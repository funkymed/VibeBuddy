# RFC-007 — Interception des permissions : file, rendu, décisions

| | |
|---|---|
| **Status** | **in-progress (95 %)** — **circuit complet prouvé en réel le 2026-08-21** ; reste 5 des 6 cas et le perfcheck |
| **Author** | Cyril Pereira |
| **Created** | 2026-08-19 |
| **Updated** | 2026-08-21 |
| **Phase** | 4 — Intégration |
| **Depends on** | RFC-002, RFC-003, RFC-006 |
| **Related** | R1, R6, D6 |
| **Blocks** | — |

## 1. Context & Problem

C'est la fonction différenciante de vibebuddy : quand Claude demande
l'autorisation de lancer une commande, la notch se déploie, montre la demande
sous forme lisible, et rend la décision — sans quitter l'éditeur.

C'est aussi la fonction la plus contrainte. Elle dépend d'un protocole externe
non documenté (RFC-006), elle **écrit dans les réglages de l'utilisateur**, et
ses modes de panne sont silencieux.

Quatre pièges identifiés dans la référence, chacun corrigeant un bug réel :

- **Une file, pas un « pending » unique.** Le commentaire `HookBridge.swift:15-17`
  documente la régression : avec un seul emplacement, un burst d'appels d'outils
  parallèles fait que chaque nouvelle demande **dénie silencieusement la
  précédente**, et seule la dernière survit.
- **`AskUserQuestion` n'a pas de chemin « répondre ».** Le hook ne peut
  qu'autoriser ou refuser. La référence refuse l'outil en formulant le message de
  refus comme la réponse choisie (`HookBridge.swift:232-250`, formulation exacte
  ligne 244) ; le modèle le lit comme un résultat d'outil et poursuit. Hack
  majeur, documenté nulle part ailleurs.
- **L'utilisateur peut répondre dans le terminal.** Il faut alors retirer la
  demande de la notch (RFC-006 détecte la déconnexion du hook).
- **Une demande peut devenir obsolète.** `dismissStalePermissions`
  (`HookBridge.swift:200-220`) l'infère d'une activité jsonl plus de 2 s après la
  création de la demande.

Enfin, le coût : `NotchContentView.swift:773` fait pulser un texte via
`TimelineView(.periodic(by: 0.05))` — **20 Hz tant qu'une permission est en
attente**, c'est-à-dire pendant tout le temps où l'utilisateur réfléchit.

## 2. Goals / Non-goals

**Goals.** File FIFO ; rendu structuré selon l'outil (shell, diff, URL,
`AskUserQuestion`) ; Deny / Allow / Always-allow ; persistance dans
`permissions.allow` ; les trois mécanismes de péremption.

**Non-goals.** Le transport et le schéma de décision (RFC-006). La fenêtre (RFC-002).

**Interdit dans cette RFC :** toute animation permanente dans le panneau. Le
panneau de permission est **statique** — il s'affiche, il attend, il disparaît.

## 3. Proposed Solution

| Module | Responsabilité |
|---|---|
| `PermissionQueue` | `@Observable`, MainActor. FIFO + péremption. Implémente `HookEventSink`. |
| `PermissionRequestModel` | Parse le `tool_input` en une présentation typée. **Tronque au stockage**, pas seulement à l'affichage. |
| `PermissionPresentation` | enum `.hidden / .checking / .shown` — remplace le couple `permissionSuppressed` + `permissionChecked` (`NotchContentView.swift:154-162`) qui existe pour éviter un flash d'une frame. |
| `PermissionPanelView` + `ShellSummaryView` / `DiffSummaryView` / `URLSummaryView` / `AskQuestionView` | Vues **séparées**, chacune < 200 lignes (règle D2). |

**Repris tel quel :**

| Brique | `fichier:ligne` | Pourquoi |
|---|---|---|
| File FIFO | `HookBridge.swift:12-28` | Cf. la régression documentée `:15-17`. |
| Court-circuit always-allow avant mise en file | `HookBridge.swift:167-171` | |
| Filtrage des règles scopées `Bash(npm install:*)` | `HookBridge.swift:64-67` | On ne compare que les entrées nues à `tool_name` ; le matcher natif de Claude Code gère le reste — ne pas réimplémenter son langage de motifs. |
| **`AskUserQuestion` répondu via `deny` + `message`** | `HookBridge.swift:232-250` | Formulation exacte ligne 244. |
| Parsing tolérant des options | `HookBridge.swift:377-433` | Accepte `questions[0].options`, les clés `label`/`value`/`text`, et un simple `[String]`. |
| `handleHookDisconnect` | `HookBridge.swift:187-198` | |
| Rendu de diff rouge/vert | `NotchContentView.swift:1885-1930` | Visuel repris, code extrait en vue autonome. |

**Modifié :**
- `dismissStalePermissions` (`:200-220`) apparie par `cwd` faute d'accord des
  `session_id` (`:207-208`). Avec le mapping PID de RFC-006, on apparie par
  `sessionID` et le `cwd` devient un repli.
- Suppression quand le terminal est déjà au premier plan
  (`NotchContentView.swift:500-508` + `TerminalJumper.swift:162-211`) : utile,
  mais l'implémentation lance `tmux list-panes -a` **à l'arrivée de chaque
  permission** (`TerminalJumper.swift:190-193`). → cache du mapping pane↔PID,
  invalidé au changement d'application frontmost. Sonde fournie par RFC-003
  (`TerminalFocusProbe`) — **ne pas dépendre de RFC-008**, ce serait un cycle.
- Le pulse à 20 Hz (`NotchContentView.swift:773`) : supprimé.

**Budget.** 0 % au repos. À l'arrivée d'une demande : un rendu de panneau
560×460, cible **< 3 % sur ~200 ms puis 0**. RSS +2 Mo transitoires — le
`tool_input` d'un `Edit` peut contenir un `new_string` volumineux, d'où la
troncature au stockage.

## 4. Alternatives Considered

**Un seul emplacement « pending » plutôt qu'une file.** Écarté : c'est le bug que
la référence a corrigé, et son commentaire le documente.

**Réimplémenter le langage de motifs de `permissions.allow`.** Écarté : Claude
Code possède son propre matcher (`Bash(npm install:*)`). Le dupliquer, c'est
garantir une divergence. On ne gère que les entrées nues et on laisse le reste
au matcher natif.

**Répondre à `AskUserQuestion` par `allow` + une réponse hors bande.** Il n'existe
pas de canal pour ça. Le détournement de `deny` + `message` est le seul chemin,
et il fonctionne parce que le modèle lit le message comme un résultat d'outil.

**Ne pas offrir « Always allow ».** Ce serait plus sûr (aucune écriture dans
`settings.json`), mais c'est la moitié de l'intérêt de la fonction. On garde,
avec les parades de R1 : sauvegarde, écriture atomique, consentement explicite.

### Ce que RFC-006 laisse exactement

Vérifié le 2026-08-21 contre le code, pas contre sa fiche :

- **`HookEventSink` existe** (`Sources/VibeBuddyKit/Hook/HookSocketServer.swift:9`),
  et le serveur l'appelle — en tir-et-oublie pour les événements non bloquants
  (`:82`), dans un groupe de tâches pour `PermissionRequest` (`:87`).
- **Rien n'instancie `HookSocketServer`.** Le transport est écrit et n'a jamais
  été démarré : aucune occurrence hors de son propre fichier dans `Sources/`.
  C'est **T0**, avant toute autre chose.
- `ClaudeSettingsWriter` et `HookInstaller` sont livrés et testés, donc T7 et T8
  écrivent à travers eux plutôt que de refaire ce chemin.

### Ce que T2 a demandé de plus que prévu

**La continuation doit être reprise par cinq chemins, pas un.** Décidée,
périmée, annulée par un raccrochage, réclamée deux fois par un panneau périmé, et
l'app qui quitte. `resume` deux fois plante ; ne jamais reprendre laisse Claude
Code attendre ses 120 s. D'où un seul `finish(_:with:)` privé, qui retire
l'entrée **avant** de reprendre — ce qui rend le deuxième appel inoffensif au
lieu de fatal.

**L'annulation vient du serveur, pas de nous.** `HookSocketServer` annule la
tâche quand le pair raccroche — c'est-à-dire quand l'utilisateur a répondu dans
le terminal, la façon **normale** dont une permission se termine. Sans
`withTaskCancellationHandler`, la file gardait une demande que plus personne
n'attendait.

**Le puits est une valeur à part, pas une conformance sur la file.**
`HookEventSink` est `Sendable` et appelé depuis le contexte du serveur ; la file
vit sur l'acteur principal avec les vues qui la lisent. `PermissionSink` est
l'unique endroit où le saut d'isolation a lieu.

### Ce que T3 a demandé de plus que prévu

**Les trois péremptions devaient être événementielles, pas seulement bon
marché.** Le critère de sortie dit **0 réveil pendant qu'une demande attend**,
ce qui interdit de sonder quoi que ce soit. Chacune roule donc sur un événement
que la machine allait livrer de toute façon :

| Péremption | Portée par |
|---|---|
| L'utilisateur a répondu dans le terminal | le pair raccroche ; le serveur le met en course contre le puits et annule — déjà là depuis T2 |
| Claude est passé à autre chose | le transcript est écrit ; `SessionCoordinator.onChange`, lui-même piloté par `ProjectsWatcher` (RFC-003) |
| Le terminal est déjà devant | `NSWorkspace.didActivateApplicationNotification` |

**Le délai de grâce n'est pas une supposition sur le comportement.** L'appel
d'outil est écrit dans le transcript **avant** que la permission soit demandée,
donc toute entrée postérieure appartient à ce qui a suivi. Les deux secondes sont
une marge contre la dérive d'horloge, pas une estimation.

**Parcourir une file qui se vide en même temps.** `expireStale` et
`expireIfHostIsFrontmost` retirent des entrées pendant qu'elles les parcourent :
d'où `models`, une copie. Un test périme les cinq d'un coup.

### Ce que T4-T6 ont laissé derrière

Deux défauts connus, tous deux vérifiés dans le code, aucun bloquant :

- **`PermissionRequestModel.cut(to:)` écrit sa mention de troncature en
  français, dans le Kit** (`PermissionRequestModel.swift`, `truncationMark`).
  Un utilisateur en anglais lira « caractères de plus ». La corriger demande de
  faire descendre `Strings` dans le parseur — une décision de conception, pas
  une retouche, et seize tests s'appuient sur la chaîne actuelle.
- **`URLSummaryView.host(of:)` prend un chemin relatif nu pour un hôte.**
  `.read("README.md")` s'affiche sous la légende « DOMAINE ». Sans conséquence
  si Claude Code passe toujours des chemins absolus — non vérifié.

**Rien n'a jamais été vu à l'écran.** Aucune de ces six vues n'est instanciée :
seule la compilation prouve quelque chose. C'est ce que le câblage doit lever.

### T9 est sans objet, vérifié le 2026-08-21

La fiche redoutait un `tmux list-panes -a` à l'arrivée de chaque permission
(`TerminalJumper.swift:190-193` dans la référence) et demandait un cache. Notre
chemin de péremption n'y passe pas : il appelle
`TerminalFocusProbe.isHostingTerminalFrontmost`, qui remonte la chaîne parent
par `sysctl` et n'exécute **aucun processus** — `grep 'list-panes\|Process()'`
sur ce fichier ne rend rien. Le `tmux` coûteux appartient au *saut* vers
l'onglet, qui est RFC-008 T6 et n'est pas écrit. La tâche est retirée plutôt que
faite : un cache pour un appel qui n'a pas lieu est du code que personne
n'exerce.

### Ce que T7 et T8 ont demandé de plus que prévu

**On n'écrit pas le document qu'on a montré.** `commit` refait la mutation en
relisant le fichier, au lieu d'écrire le `after` calculé pour le diff. Entre
l'affichage et la confirmation, l'utilisateur a pu éditer son fichier — écrire
une valeur calculée sur une copie plus ancienne est un retour en arrière
silencieux, exactement ce que la relecture de D6 existe pour empêcher.

**La suggestion de Claude Code passe avant le nom de l'outil.**
`Bash(npm test:*)` est ce qui a été demandé ; `Bash` est tous les `Bash` pour
toujours. Le nom nu reste le repli, et il ne doit jamais être le choix préféré.

**Écrire d'abord, répondre ensuite.** Un `allow` qui atteindrait Claude Code
avant que la règle soit sur le disque serait accordé une fois et redemandé au
suivant — ce qui se lit comme un bouton qui ne marche pas.

**Le consentement est un état du panneau, pas une fenêtre.** Un `NSPanel` qui
n'est jamais fenêtre clé ne peut pas héberger de modale correctement, et une
seconde fenêtre au-dessus de l'encoche est une seconde chose à congédier.

**`TextDiff` a déménagé dans le Kit.** L'installateur de hook le montrait déjà
pour la même raison ; deux résumés du même changement qui se contredisent est
pire qu'un seul.

### Arbitrages du 2026-08-21

**Ordre : le socle d'abord, les vues ensuite.** T1-T3 entièrement testés sans
UI, puis les quatre vues. Rien n'est observable avant le quatrième jour ; en
échange, ce qu'on dessine repose sur un socle déjà éprouvé. La tranche verticale
« un `Bash` de bout en bout d'abord » a été écartée à l'usage.

**Une seule demande à l'écran, plus un compteur** (répond à Q2). La demande en
tête occupe le panneau, un « +N en attente » discret dit le reste. Au-delà de
trois ou quatre, une file signale surtout que quelque chose ne va pas — l'afficher
en entier, c'est dessiner le symptôme.

**Aucune trace sur disque** (répond à Q4). Les décisions vivent en mémoire le
temps de la session. Le prix est assumé : un refus que Claude Code rejette en
silence (R6) reste difficile à diagnostiquer, et c'est le test golden-file de
RFC-006 qui tient ce risque, pas un journal.

## 5. Action plan

| # | Tâche | Statut | % |
|---|---|---|---|
| **T0** | **Démarrer `HookSocketServer` dans l'app** — écrit par RFC-006, jamais instancié | **done** | **100** — `HookService.swift`, puits sans avis jusqu'à T2 |
| T1 | `PermissionRequestModel` + parsing par outil + troncature au stockage | **done** | **100** — 16 tests |
| T2 | `PermissionQueue` FIFO + court-circuit always-allow | **done** | **100** — 13 tests, branchée dans `HookService` |
| T3 | Les 3 péremptions : déconnexion, obsolescence jsonl, terminal au premier plan | **done** | **100** — 9 tests, aucune horloge ajoutée |
| T4 | `PermissionPanelView` + `ShellSummaryView` | **done** | **100** |
| T5 | `DiffSummaryView` (rouge/vert) et `URLSummaryView` | **done** | **100** |
| T6 | `AskQuestionView` + le détournement `deny` + `message` | **done** | **100** — jamais vu à l'écran, rien ne l'instancie encore |
| T7 | Écriture de `permissions.allow` via le `ClaudeSettingsWriter` de RFC-006 | **done** | **100** — `PermissionRules`, 12 tests |
| T8 | **Écran de consentement affichant le diff exact** (parade R1) | **done** | **100** — un état du panneau, pas une fenêtre |
| T9 | ~~Cache du mapping pane↔PID~~ — **sans objet**, voir ci-dessous | **n/a** | — |
| T10 | Test du cycle de vie de la file (cf. Q3) | **done** | **100** — 20 cycles, 5 sorties, 0 descripteur fuité |
| T11 | Compteur « +N en attente » dans le panneau | **done** | **100** |

**Critère de sortie.** Un `Bash`, un `Edit` et un `AskUserQuestion` sont chacun
autorisés **et** refusés depuis la notch — six cas, et le terminal reprend la main
correctement dans les six. « Always allow » écrit dans `settings.json` après
consentement explicite, et Claude Code honore la règle à la session suivante.
`perfcheck.sh` montre **0 réveil** pendant qu'une demande attend.

### L'épreuve du 2026-08-21 — ce qu'elle a coûté et ce qu'elle a rendu

**Le circuit complet a fonctionné** : `PermissionRequest` émis par Claude Code
2.1.238 → reçu par l'app → mis en file → panneau affiché dans l'encoche →
décision prise à la souris → **honorée par Claude Code**, sans toucher au
terminal. C'est le cas 1 sur 6.

Il a fallu deux heures pour y arriver, et **trois défauts qu'aucun des 467 tests
ne voyait** :

| # | Défaut | Symptôme | Correctif |
|---|---|---|---|
| 1 | Repli par `cwd` dans la péremption | une demande mourait en 3,6 s parce qu'une **autre** session travaillait dans le même dossier — le cas normal | appariement par `sessionID` seul ; `cwd` uniquement si une seule session peut être désignée |
| 3bis | *(les deux ne faisaient qu'un)* | ensemble, 1 et 3 rendaient le panneau invisible dans **tous** les cas réels : soit un voisin le tuait, soit il se tuait lui-même | — |
| 2 | Deux instances de l'app | la seconde vole le socket, la première écoute un inode mort et affiche sa pastille — invisible | **non corrigé**, noté en RFC-011 |
| 3 | Péremption à 2 s | la session écrit son `tool_use` juste avant de demander : la demande **périmait son propre panneau** deux secondes après l'avoir ouvert | 60 s — la péremption est un filet, le raccrochage est le mécanisme |
| 4 | Péremption « terminal au premier plan » | fermait le panneau avant qu'on l'atteigne : l'utilisateur **est** dans son terminal quand l'agent demande, c'est là qu'il vient de taper | retirée. Vraie d'une alerte, fausse d'une permission |
| 5 | Refus sans message | `deny(message: "")` : le modèle reçoit un refus sans raison et **réessaie autrement**, en boucle | message explicite, dans les deux langues |

**La fausse accusation, qui vaut d'être écrite.** Pendant deux heures les hooks
voisins — rtk, vibe-island, Notch Pilot — ont été suspectés de manger
l'événement, parce que le seul essai qui a marché était celui fait avec un
fichier de réglages minimal. C'était une coïncidence de calendrier : cet essai
tombait juste après le correctif de la péremption. Vérifié ensuite avec les
quatre hooks présents, **le panneau s'ouvre normalement**. rtk n'y était pour
rien — il rend même service, en réécrivant `ls` en `rtk ls`, une commande que
Claude Code ne reconnaît pas comme inoffensive et pour laquelle il demande donc
toujours. C'est un générateur de cas de test.

**Trois fausses pistes, chacune instructive :**

- Claude Code n'a **jamais** demandé pour un `echo` : les commandes jugées
  inoffensives sont auto-approuvées. Il faut du réseau (`curl`) pour être sûr
  d'un prompt.
- `permissions.defaultMode: "auto"` dans le fichier **utilisateur** l'emporte sur
  tout ce qu'on passe en `--settings` et en `--permission-mode`. Rien ne demande
  jamais tant qu'il est là.
- Écrire hors du répertoire de travail est refusé **en amont**, sans passer par
  le circuit de permission — le piège que `docs/hook.md` documentait déjà et dans
  lequel je suis retombé.

**Ce qui a été prouvé** : `Bash` **autorisé** (un `curl`, un `ls`, un `echo`) et
`Bash` **refusé** (cinq appels de suite, tous rendus au modèle avec leur
message). Deux cas sur six, dans les deux sens, avec les quatre hooks de
l'utilisateur en place.

**Ce qui reste à éprouver** : `Edit` autorisé et refusé, `AskUserQuestion`
autorisé et refusé — ce dernier est le plus fragile, puisqu'il repose sur le
détournement `deny` + `message` que rien n'a encore exercé. Puis « toujours
autoriser » honoré à la session suivante, et `perfcheck A` pendant une attente.

**La leçon de la soirée, en une phrase :** les trois péremptions venaient de la
référence, où elles protégeaient contre des *alertes* redondantes. Une permission
n'est pas une alerte — elle attend une personne, et tout ce qui la retire avant
qu'elle réponde est un bug, jamais une optimisation. Il n'en reste qu'une, le
raccrochage du pair : la seule qui **observe** un fait au lieu d'en supposer un.

## 6. Open Questions

**Q1 — Que fait la notch si l'app démarre alors qu'une demande est déjà en cours ?**
Le hook attend sur un socket qui n'existait pas. Il sortira sur `exit(0)`
(RFC-006) et Claude retombera sur son interface — acceptable, mais à vérifier.

**Q2 — Combien de demandes empilées affiche-t-on ?** **Tranchée le 2026-08-21 :**
une seule à l'écran, plus un compteur « +N en attente ».

**Q3 — Le cycle de vie de la closure de réponse est-il testable ?**
`PendingPermission.respond` est une closure `@Sendable` retenue qui **maintient
la connexion socket ouverte** (`HookBridge.swift:349`). Toute fuite bloque Claude
Code jusqu'au timeout. C'est l'invariant le plus important de la RFC.

```sh
# Vérifier qu'aucun descripteur ne fuit après un cycle de 20 demandes :
lsof -p $(pgrep -x VibeBuddy) | grep -c unix
# Relever avant / après, l'écart doit être nul.
```

**Q4 — Faut-il journaliser les décisions ?** **Tranchée le 2026-08-21 : non.**
Rien sur disque. Un journal aiderait à diagnostiquer R6, mais c'est un fichier de
plus qui trace l'activité de l'utilisateur, et le golden-file de RFC-006 couvre
déjà le mode de panne.
