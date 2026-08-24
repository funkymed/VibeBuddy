# RFC-006 — Pont hook Claude Code : binaire dédié et socket Unix

| | |
|---|---|
| **Status** | **in-progress (96 %)** — transport, installateur et contrat **prouvé en réel** ; reste **T11 seule**, un défaut d'affamement de fils trouvé le 2026-08-21 et non corrigé |
| **Author** | Cyril Pereira |
| **Created** | 2026-08-19 |
| **Updated** | 2026-08-21 (soir) |
| **Phase** | 4 — Intégration |
| **Depends on** | RFC-001 |
| **Related** | RFC-003 (ModeUpdate, mapping PID) · **RFC-012 (consomme Stop/Notification)** · D4, D6, R1, R6 |
| **Blocks** | RFC-007, RFC-011, RFC-012 |

## 1. Context & Problem

Claude Code peut déléguer ses demandes de permission à un programme externe via
un hook déclaré dans `~/.claude/settings.json`. C'est ce qui rend possible
l'interception des permissions dans la notch (RFC-007). Le hook est un exécutable
lancé par Claude Code à chaque événement, qui reçoit un JSON sur stdin et répond
sur stdout ; pour `PermissionRequest` il **bloque** Claude jusqu'à sa réponse.

Trois contraintes rendent ce pont délicat, toutes documentées dans la référence :

**Le schéma de réponse est strict et casse en silence.** Commentaire de l'auteur
en `HookClient.swift:157-160` : tout champ de premier niveau en trop (par exemple
`"decision": "block"`) fait que Claude Code **invalide la réponse et retombe sur
son interface habituelle**. Aucune erreur n'est produite. L'utilisateur voit le
prompt normal et conclut que l'app est cassée.

**Le hook peut être tué pendant qu'il attend.** Si l'utilisateur répond dans le
terminal, Claude Code tue le process du hook. Sans détection, la notch reste
bloquée sur un prompt mort. La référence détecte le `POLLHUP` / `recv MSG_PEEK == 0`
(`SocketServer.swift:164-195`).

**Le coût de démarrage se paie à chaque appel d'outil.** La référence a supprimé
sa dépendance à Node en faisant du binaire principal son propre hook via
`--hook` (`NotchPilotApp.swift:11-13`) — vrai gain. Mais ce binaire **lie AppKit**
(`import AppKit`, ligne 1) : dyld charge AppKit **avant** que `main()` teste
l'argument, à chaque `PreToolUse`, donc à chaque appel d'outil de chaque session.

## 2. Goals / Non-goals

**Goals.** Installation idempotente et **non destructrice** du hook ; un
exécutable dédié Foundation-only ; le protocole ligne-JSON sur socket Unix ; et
**le schéma de décision, qui appartient au transport** — pas à l'UI.

**Événements enregistrés.** L'implémentation de référence n'en déclare que trois
(`HookInstaller.swift:14`) et **déduit** le reste de l'inactivité du transcript.
Claude Code en expose quatorze — vérifié dans `~/.claude/settings.json` le
2026-08-19. On enregistre :

| Événement | Bloquant | Pour qui |
|---|---|---|
| `PermissionRequest` | **oui** | RFC-007 |
| `Notification` | non | RFC-012 — l'agent réclame l'attention |
| `Stop` | non | RFC-012 — l'agent a terminé son tour |
| `StopFailure` | non | RFC-012 — tour terminé en erreur |
| `SessionStart` / `SessionEnd` | non | RFC-003 — cycle de vie exact, sans inférence par mtime |
| `SubagentStop` | non | RFC-012 — pour être explicitement **ignoré** (voir sa §3) |
| `PreToolUse` / `UserPromptSubmit` | non | RFC-003 — `permission_mode` courant |

Un seul de ces événements bloque. Tous les autres sont en tir-et-oublie, donc
leur coût est le démarrage du binaire — d'où la contrainte des 8 ms.

**Non-goals.** Le rendu et la décision de permission (RFC-007).

**Frontière assumée.** Si le schéma `hookSpecificOutput` était connu à la fois du
transport et de l'UI, l'un des deux finirait par y ajouter un champ — exactement
le mode de panne que documente `HookClient.swift:157-160`. Il vit ici, et
seulement ici.

## 3. Proposed Solution

Deux cibles exécutables dans le même `Package.swift` (décision D4) :
`vibebuddy` (AppKit/SwiftUI) et **`vibe-hook` (dépendances : `Foundation`,
`Darwin` — `import AppKit` interdit)**, avec un fichier `HookProtocol.swift`
partagé par les deux.

```swift
enum HookEvent {
  case permissionRequest(PermissionPayload)
  case modeUpdate(cwd: String, mode: String, sessionID: String)
}
enum HookDecision { case allow; case deny(message: String) }
protocol HookEventSink { func handle(_ e: HookEvent) async -> HookDecision? }
```

RFC-007 implémente `HookEventSink`. RFC-003 consomme `modeUpdate` et le mapping
`sessionID → PID`.

**Repris tel quel :**

| Brique | `fichier:ligne` | Pourquoi |
|---|---|---|
| Serveur AF_UNIX complet | `SocketServer.swift:56-134` | Y compris `chmod(path, 0o600)` (`:93`) — canal privé — et l'`unlink` du socket résiduel (`:64`). |
| `getsockopt(LOCAL_PEERPID)` | `SocketServer.swift:146-150` | Seul moyen de remonter au PID de `claude` depuis la connexion. |
| Détection `POLLHUP` / `recv MSG_PEEK == 0` | `SocketServer.swift:164-195` | **Seul moyen de savoir que l'utilisateur a répondu dans le terminal.** Sémantique à conserver ; réimplémentée en `DispatchSource` plutôt qu'en boucle de sémaphore à 500 ms. |
| Client + `SO_RCVTIMEO` 120 s | `HookClient.swift:111-119` | |
| **Schéma exact de la réponse** | `HookClient.swift:157-175` | `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}` — rien de plus. |
| `exit(0)` sur entrée malformée ou app absente | `HookClient.swift:26-29`, `:95`, `:113` | **Ne jamais bloquer Claude Code.** |
| Remontée de la chaîne parent hook → shell → claude | `HookBridge.swift:117-142` | Double critère nom **et** chemin `/claude/versions/` (`:130-139`), car le binaire est versionné. Borne de 8 sauts. |
| Rôle de `PreToolUse` / `UserPromptSubmit` | `HookClient.swift:36-39` | Servent **uniquement** à apprendre le `permission_mode` courant, absent du jsonl entre deux prompts. C'est ce qui rend un Shift+Tab visible immédiatement. |

**Modifié :**
- Filtrage des entrées obsolètes (`HookInstaller.swift:68-91`) : la logique est
  bonne, mais l'heuristique `cmd.hasSuffix(" --hook")` (`:78`) n'a plus de sens
  avec un binaire séparé → marqueur explicite dans l'entrée.
- **Écriture de `settings.json` (parade R1, la plus importante de la RFC).** La
  référence relit tout, re-sérialise avec `[.prettyPrinted, .sortedKeys]` et fait
  `data.write(to:)` (`HookInstaller.swift:114-120`) : non atomique, et **réordonne
  intégralement le fichier de l'utilisateur** à chaque lancement. Remplacé par un
  `ClaudeSettingsWriter` unique (décision D6) : sauvegarde horodatée avant la
  première écriture, `replaceItemAt` atomique, **pas de `.sortedKeys`**, relecture
  avant chaque mutation, aucun cache long — l'utilisateur édite ce fichier à la main.

**Budget.** App : socket en `accept` bloquant → **0 % / 0 réveil** au repos. Par
événement : un `fork`/`exec` du hook, cible **< 8 ms** (Foundation-only) contre
40-60 ms attendus si AppKit est lié. RSS app +0,3 Mo.

## 4. Alternatives Considered

**Binaire dual-mode via `--hook`, comme la référence.** Écarté (D4) : le coût de
chargement d'AppKit est payé à chaque appel d'outil de chaque session. On garde
les deux vrais avantages de leur choix — pas de dépendance Node, version du hook
toujours synchrone avec l'app — sans le coût.

**Un script shell ou Node comme hook.** Écarté : c'est ce que la référence a
elle-même abandonné (`HookInstaller.swift:8-11`), et pour de bonnes raisons —
dépendance externe, et dérive de version entre le script installé et l'app.

**Ne pas installer de hook du tout, tout déduire des jsonl.** Écarté : les
demandes de permission ne sont pas observables dans le transcript au moment où
elles se posent, et le `permission_mode` n'y figure pas entre deux prompts.

**Écriture atomique sans sauvegarde.** Insuffisant : l'atomicité protège d'un
crash en cours d'écriture, pas d'une écriture logiquement fausse. La sauvegarde
horodatée est ce qui rend l'erreur réparable.

## 5. Action plan

| # | Tâche | Statut | % |
|---|---|---|---|
| T1 | Spike : un hook trivial reçoit-il un `PermissionRequest` et sa décision est-elle honorée ? (Q1) | **done** | **100** — **observé en réel le 2026-08-21** : émis, reçu, décidé à la souris, honoré |
| T2 | Deuxième cible `vibe-hook` + `HookProtocol.swift` partagé + garde-fou anti-`import AppKit` | **done** | **100** |
| T3 | `HookSocketServer` (actor) : bind, `chmod 0600`, accept, ligne-JSON | **done** | **100** |
| T4 | Détection de déconnexion du pair en `DispatchSource` | **done** | **100** |
| T5 | Client : stdin → socket → stdout, `SO_RCVTIMEO`, `exit(0)` sur tout imprévu | **done** | **100** |
| T6 | **Test golden-file** : réponse attendue **octet à octet**, plus une assertion qui interdit tout champ de trop (parade R6) | **done** | **100** |
| T7 | `ClaudeSettingsWriter` : sauvegarde, atomique, **ordre préservé** (parade R1, D6) | **done** | **100** |
| T8 | `HookInstaller` idempotent + nettoyage des entrées obsolètes | **done** | **100** |
| T9 | `vibebuddy --uninstall-hook` | **done** | **100** |
| T10 | Mesure du temps de démarrage du hook (valide D4) | **done** | **100** — **3,2 ms** de médiane, cible 8 |
| T11 | **Perte d'un événement tir-et-oublie** — 1 sur 6 → **1 sur 14** ; une cause trouvée et corrigée, une seconde isolée mais pas résolue | **in-progress** | **60** |

### Ce que T8 et T9 ont demandé de plus que prévu

**Le marqueur ne suffit pas seul.** La fiche disait « marqueur explicite dans
l'entrée », en remplacement de l'heuristique `cmd.hasSuffix(" --hook")` de la
référence. Nécessaire, mais une entrée dont le marqueur a été effacé à la main
reste la nôtre — et si on ne la reconnaît plus, `--uninstall-hook` la laisse
derrière lui. `HookInstaller.isOurs` teste donc le marqueur **ou**, à défaut, le
nom de l'exécutable.

**Une entrée se remplace sur place.** Ajouter un groupe à chaque installation la
déplaçait en fin de fichier au premier passage et la dupliquait à tous les
suivants. `placed(_:in:)` réécrit la première entrée à nous là où elle est.

**L'écriture est un geste consenti, pas un effet de bord du lancement.** L'app
n'écrit rien au démarrage : `vibebuddy --install-hook` et `--uninstall-hook`
affichent le **diff** du fichier et attendent un oui. `--yes` saute la question,
`--settings <chemin>` vise un autre fichier — nécessaire parce que
`NSHomeDirectory()` ignore `$HOME`, donc sans ce drapeau il n'existe aucun moyen
de répéter la manœuvre ailleurs que sur le vrai `~/.claude/settings.json`.

**La mise en forme n'est pas préservée, l'ordre l'est.** Un objet que
l'utilisateur avait écrit sur une ligne revient développé, une clé par ligne.
C'est l'ordre que D6 protège ; la mise en page, non.

**Ce que la sauvegarde protège vraiment.** `backedUpThisRun` était un drapeau
global : deux fichiers de réglages écrits dans la même exécution se volaient la
sauvegarde, et seul le premier en avait une. Une sauvegarde par **fichier** et
par exécution — c'est ce que la règle voulait dire.

### Ce que T7 a demandé de plus que prévu

La fiche disait « sans `.sortedKeys` ». Ça ne suffit pas : **sans elle,
`JSONSerialization` rend un ordre arbitraire**, pas celui de l'utilisateur.
`.sortedKeys` rend le brassage *stable*, elle ne l'empêche pas. Or le fichier
visé fait onze kilo-octets écrits à la main, avec `$schema` délibérément en tête.

D'où `OrderedJSON` : un modèle qui retient l'ordre des clés, et un analyseur et
un sérialiseur à la main. Deux bénéfices que le détour paie :

- **Une clé remplacée reste à sa place** — elle ne migre pas en fin de fichier.
- **Les nombres gardent leur texte d'origine.** `JSONSerialization` transforme
  `1.0` en `1` et perd des chiffres sur un grand entier ; le littéral est
  conservé tel quel.

Le fichier réel de l'utilisateur sert de fixture : le test le lit s'il existe,
le re-sérialise, et vérifie que l'ordre des vingt-cinq clés racine est intact.

### Défaut ouvert — la lecture bloque un fil, trouvé le 2026-08-21

`HookSocketServer.read` poste un `HookSocket.readLine` **bloquant** sur la file
globale, un fil par connexion ouverte. Tout le reste de ce fichier est
événementiel (`DispatchSource` sur l'écoute, `DispatchSource` sur le
raccrochage) ; ce point ne l'est pas.

Mesuré : la suite `Hook: the socket, end to end` échouait environ **une fois sur
six** en parallèle, **zéro fois sur dix** en isolé. L'un de ses tests tient un
puits endormi 30 s ; six serveurs à la fois affament le pool de fils, et un
événement qui n'est jamais ordonnancé ressemble exactement à un événement perdu.

La suite est sérialisée pour arrêter la fausse alerte. Le défaut reste : Claude
Code lance ses hooks **par rafales** — le commentaire d'`acceptOne` le dit — donc
l'affamement est atteignable en production, pas seulement ici.

**Une première tentative de correctif a empiré les choses, et c'est le plus
utile qu'on ait appris.** Remplacer la lecture bloquante par un
`DispatchSource` a fait passer l'échec de **1 sur 6 à 3 sur 8**, et le chemin
qui cassait n'était plus le même : la réponse d'un `PermissionRequest`
n'arrivait plus du tout.

La raison : le chemin bloquant utilise **déjà** un `DispatchSource` par
connexion — le veilleur de raccrochage. Lire depuis une source en ajoute une
**seconde sur le même descripteur**, créée pendant que la première est encore en
train de s'annuler. L'annulation d'une source est asynchrone, et les deux se
marchent dessus.

**Deuxième tentative, le 2026-08-21 également : une seule source par connexion,
portant la lecture puis le raccrochage.** Écrite, compilée, tests unitaires
verts. Résultat en parallèle : **3 échecs sur 8**, pire que les 1 sur 6 de
départ. Retour arrière, remesuré à **0 sur 8** avec la suite sérialisée.

**Ce que les deux tentatives ont éliminé** — et c'est tout ce qu'on sait :

- Ce n'est **pas** l'affamement de fils. La seconde version ne parquait plus
  aucun fil et échouait davantage.
- Ce n'est **pas** deux sources sur le même descripteur. La seconde version n'en
  avait qu'une.
- Ce n'est **pas** la limite de 5 s du client de test. Portée à 20 s, l'échec
  demeure.
- L'échec est **toujours le même** : `a permission request gets its decision
  back`, la réponse n'arrive jamais. Jamais en isolé (0 sur 10).

La cause reste **inconnue**. Ce qui est acquis, c'est que le chemin bloquant
d'origine est le plus fiable des trois essayés, et qu'il a servi une dizaine de
permissions réelles dans la soirée sans en perdre une. Une prochaine tentative
devrait commencer par instrumenter le serveur — quel appel rend quoi, dans
quel ordre — plutôt que par proposer une architecture.

**Critère de sortie.** Le test golden-file passe. Tuer l'app pendant qu'une
permission est en attente **ne bloque pas Claude Code plus de 120 s**.
`--uninstall-hook` retire exactement nos entrées, vérifié par `diff` contre la
sauvegarde. Le hook démarre en moins de 8 ms.

### T11, le 2026-08-23 — ce qui est trouvé, ce qui reste

**Une cause sur deux est réglée, et ce n'était pas le socket.** Les tests
dormaient 300 ms fixes avant d'affirmer. Un événement en tir-et-oublie est
traité de façon asynchrone : sur une machine chargée ce budget ne suffit pas
toujours, et le taux d'échec suivait la charge — ce qui, vu de l'extérieur,
ressemble exactement à « instable sous charge parallèle ». Remplacé par une
attente **sur la condition** avec échéance (`waitUntil`). Effet secondaire
mesuré : la suite passe de 1,14 s à **0,63 s**, parce que les 500 ms d'attente
fixe étaient payés à chaque exécution même quand tout allait bien.

**Ce qui reste, et c'est une donnée neuve.** Avec l'attente conditionnelle, il
subsiste **1 échec sur 14** où l'événement n'arrive *jamais* — cinq secondes ne
suffisent pas davantage que trois cents millisecondes. La trace du serveur
(`VIBEBUDDY_HOOK_TRACE=1`) montre le mode de panne exact :

```
hooksrv: accept → fd 5
(plus rien : aucun « read fd 5 »)
```

Le serveur accepte la connexion, puis `readLine` ne rend jamais la main. Le
client, lui, a réussi son `connect` **et** son `write` — `send` rend `""`, sans
quoi la première assertion tomberait. Des octets sont donc écrits sur une
connexion établie, et jamais lus.

**Heisenbug confirmé** : avec la trace active, 22 exécutions consécutives sans
un seul échec ; sans elle, 1 sur 14. L'écriture sur `stderr` déplace assez le
minutage pour faire disparaître le cas.

**Éliminé aujourd'hui** : l'écriture partielle côté client (`write` boucle
jusqu'au bout et rend `false` sinon) ; la famine du pool coopératif (`read`
tourne sur `DispatchQueue.global`, pas sur le pool Swift) ; la collision de
chemins (`temporarySocket` tire un UUID) ; l'ordre lecture/raccrochage (le
raccrochage n'est consulté que pour les événements bloquants).

**Livré en attendant** : `HookSocket.setReadTimeout` sur chaque descripteur
accepté, dix secondes. Ça ne rend pas l'événement, mais un descripteur et un fil
GCD immobilisés pour la vie du processus sont une fuite, et une app dont la
première règle est de ne jamais bloquer ne peut pas se le permettre.

**La prochaine piste**, dans l'ordre : instrumenter côté **client** dans le même
run (quel `fd`, combien d'octets `send` a réellement écrits, à quel instant)
pour savoir si les octets partent vers le descripteur que le serveur a accepté.
La trace serveur seule ne peut pas répondre.

## 6. Open Questions

**Q1 — Le contrat de hook fonctionne-t-il ?** *Spike fait le 2026-08-20, sans conclusion.*

**Établi** — `--settings <fichier>` charge bien des hooks, sans rien écrire dans
`~/.claude/`. `SessionStart`, `UserPromptSubmit`, `PreToolUse` et `Stop` se
déclenchent tous, avec des charges utiles complètes.

Deux gains inattendus pour d'autres RFC :

- **`transcript_path` est fourni** sur chaque événement — plus besoin de déduire
  le chemin du jsonl (RFC-003).
- **`effort` arrive dans `PreToolUse`** — RFC-003 le parse aujourd'hui depuis le
  transcript.

**Non établi** — `PermissionRequest` ne s'est **jamais** déclenché, y compris
lorsqu'une permission a été réellement refusée (lecture de `/etc/hosts` hors du
répertoire de travail : `PreToolUse` part, `PermissionRequest` non).

Hypothèse **non vérifiée** : ce hook n'intervient que sur un prompt interactif,
absent en mode `-p`. La tentative en pseudo-terminal n'a pas abouti — piloter une
session interactive demande un vrai terminal.

**Conséquence : RFC-006 et RFC-007 restent bloquées**, soit 8 à 12 jours-homme
qu'il vaut mieux ne pas engager sur une hypothèse. Le cœur du produit ne dépend
pas de cette réponse : RFC-012 tire ses quatre signaux du transcript.

Ce qu'il faut pour conclure, et qui demande une main humaine :

```sh
cd docs/spikes/hook/project
claude --settings ../settings.json --permission-mode manual
# puis : « Lis le fichier /etc/hosts »
# → si le hook fonctionne, le refus porte « REFUS-SPIKE-7f3a »
```

```sh
mkdir -p /tmp/hookspike && cat > /tmp/hookspike/h.sh <<'SH'
#!/bin/sh
cat > /tmp/hookspike/in.json
printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"spike"}}}'
SH
chmod +x /tmp/hookspike/h.sh
# Déclarer /tmp/hookspike/h.sh comme hook PermissionRequest dans une COPIE de
# settings.json, lancer une session claude, demander une commande shell,
# puis vérifier que le refus « spike » remonte bien :
cat /tmp/hookspike/in.json | python3 -m json.tool
```

**Q2 — Quel marqueur identifie nos entrées dans `settings.json` ?**
Un champ conventionnel dans l'objet du hook survit-il au parseur de Claude Code,
ou faut-il se rabattre sur le chemin du binaire ?

**Q3 — Faut-il un verrou inter-process sur `settings.json` ?**
Claude Code écrit dans ce fichier lui aussi. `replaceItemAt` protège d'une
écriture partielle, pas d'un « dernier écrivain gagne ». Un `flock` sur un fichier
voisin est peu coûteux — reste à savoir si Claude Code le respecterait.

**Q4 — Le timeout de 120 s est-il le bon ?** C'est la valeur de la référence
(`HookClient.swift:19`). Trop court, une vraie réflexion de l'utilisateur est
interrompue ; trop long, un bug de vibebuddy paralyse Claude Code deux minutes.
