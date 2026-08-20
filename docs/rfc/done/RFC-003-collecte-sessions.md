# RFC-003 — Collecte de sessions : source de vérité unique

| | |
|---|---|
| **Status** | done (100 %) |
| **Author** | Cyril Pereira |
| **Created** | 2026-08-19 |
| **Updated** | 2026-08-19 |
| **Phase** | 2 — Données |
| **Depends on** | RFC-001 |
| **Related** | RFC-006 (ModeUpdate, mapping PID) · D1, D8 |
| **Blocks** | RFC-005, RFC-007, RFC-008, RFC-009 |

## 1. Context & Problem

Savoir ce que fait Claude Code exige de croiser trois sources de fraîcheur
différente : quels process `claude` tournent (liveness), ce que dit le dernier
enregistrement du transcript (contenu), et quel mode de permission est actif
(seul le hook le connaît entre deux prompts).

La référence a **trois sources de vérité qui se contredisent** :
`ClaudeMonitor.sessions` (jsonl + libproc), `HookBridge.sessionPIDs` (chaîne
parent du socket), `HookBridge.liveModes` (indexé par `cwd`, pas par session).
D'où des appariements par `cwd` faute de mieux (`HookBridge.swift:207-209`), et
un `lsof` qui **contredit un commentaire du même dépôt** :
`TerminalJumper.swift:143` s'appuie sur `lsof` pour retrouver le PID d'une
session, alors que `ClaudeMonitor.swift:524-526` explique que claude **ferme le
jsonl entre deux écritures**, ce qui rend `lsof` non fiable.

Deuxième problème, celui du coût. `ClaudeMonitor.swift:78` déclenche à 1 Hz un
parcours complet de `~/.claude/projects` **plus** un `fork`+`exec` de `pgrep`
(`:555-576`) dont l'information est déjà produite par `liveClaudeCwdCounts()`
dans le même `refresh()`. Mesuré : 11,34 ms par `fork`, contre 1,06 ms pour le
scan `libproc` complet de 617 process.

## 2. Goals / Non-goals

**Goals.** Un acteur unique produisant `[SessionSnapshot]`. Clé primaire =
`sessionID` (nom du jsonl) ; `cwd` en index secondaire uniquement. Déclenchement
par FSEvents pour le contenu, par cadence paresseuse pour la liveness. Latence
contractuelle : **1 s en activité, 30 s au repos** (décision D8).

**Non-goals.** Toute agrégation historique (RFC-009). Toute UI. Le transport du
hook (RFC-006).

**Cadrage explicite.** « Event-driven » est un vœu, pas un design : **la sortie
d'un process n'émet aucun événement filesystem**. Le scan process reste
périodique, mais paresseux — 30 s au repos, 2 s en activité. La RFC s'énonce donc
« une source de vérité unique fusionnant trois flux de fraîcheur différente ».

## 3. Proposed Solution

```swift
struct SessionSnapshot: Sendable, Equatable {
  let id: String            // = nom du jsonl, clé primaire
  let cwd: String           // normalisé, index secondaire
  let projectName, model: String
  let startedAt, lastActivity: Date
  let status: ShortStatus
  let action: ToolAction
  let contextTokens, contextWindow: Int
  let claudePID: pid_t?
}
```

| Module | Responsabilité |
|---|---|
| `actor SessionStore` | La source de vérité. Publie via `AsyncStream<[SessionSnapshot]>`. |
| `ProcessLookup` | enum sans état, wrappers `libproc`. |
| `ProjectsWatcher` | `FSEventStreamCreate` sur `~/.claude/projects`, latence 1 s, coalescé. |
| `JSONLTailReader` | tail borné + cache mtime. |
| `TranscriptParser` | **pur, testable** : `Data → ParsedTail`. |
| `ToolActionClassifier` | **pur**. |
| `TerminalFocusProbe` | « le terminal hôte est-il au premier plan ? » — placé **ici** et non dans RFC-008, pour éviter un cycle RFC-007 → RFC-008. |

**Repris tel quel** — la partie la plus rentable du dépôt de référence :

| Brique | `fichier:ligne` | Pourquoi c'est non évident |
|---|---|---|
| `ProcessLookup` complet | `ProcessLookup.swift:11-73` | macOS n'a pas de `/proc` ; `proc_listpids` / `proc_pidinfo` sont la seule voie. |
| `normalize()` | `ProcessLookup.swift:77-82` | `/private` doit être strippé pour que le `cwd` de `libproc` et celui du jsonl se comparent. |
| **`liveClaudeCwdCounts()`** | `ClaudeMonitor.swift:518-553` | **Règle métier centrale** : un jsonl fraîchement écrit par une session *terminée* paraît vivant pendant des minutes. Le `cwd` du process est la seule vérité. |
| Filtre de capacité par cwd | `ClaudeMonitor.swift:210-251` | N jsonl gardés = N process vivants dans ce cwd. |
| `readTail(64 Ko)` + cache mtime + parse borné à 50 lignes | `:470-482`, `:274-280`, `:296` | Le seul lecteur correct du dépôt — les deux autres (RFC-004, RFC-009) lisent des fichiers entiers. |
| Cache sticky du contexte + fenêtre 1M | `:59-70`, `:176-185`, `:226-232` | Sans lui, l'anneau de contexte clignote dès que le tail tombe sur une entrée sans bloc `usage`. |
| Heuristiques de danger | `:399-468` | Notamment `:456-465`, qui vérifie le caractère suivant pour ne pas flaguer `rm -rf .build`. |

**Écarté :** le `Timer` 1 Hz (`:78`) ; `countClaudeProcesses()` via `pgrep`
(`:555-576`) ; `decodeProjectName` (`:265-269`, mort et lossy) ; `recentEvents()`
(`:582-699`) qui part en RFC-008 **et sort de tout `body` de vue** — il est
aujourd'hui appelé depuis `NotchContentView.swift:1183`, donc relit 256 Ko de
disque à chaque invalidation, sans cache.

**Budget.** Repos, aucune session : FSEvents dormant, scan process toutes les
30 s → 1,06 ms / 30 s = **0,0035 % d'un cœur**. Activité : FSEvents coalescé 1 s
+ scan process 2 s → ~0,1 %. RSS +2 à 3 Mo (cache mtime ~550 entrées + un buffer
de tail réutilisé). **0 réveil hors FSEvents au repos.**

## 4. Alternatives Considered

**Garder le `Timer` 1 Hz de la référence.** Écarté : c'est la source de coût n°1
avec le `fork` de `pgrep`, et rien ne justifie 1 Hz au repos.

**Tout event-driven, y compris la liveness.** Impossible : la mort d'un process
n'émet aucun événement filesystem. On pourrait s'abonner à
`NSWorkspace.didTerminateApplicationNotification`, mais `claude` est un process
CLI, pas une application au sens AppKit. Le scan périodique paresseux est le
compromis honnête.

**`lsof` pour associer un jsonl à un PID.** Écarté : contredit par
`ClaudeMonitor.swift:524-526` (claude ferme le fichier entre deux écritures). Le
mapping par le hook (RFC-006) est exact ; en attendant, le `cwd` suffit.

**Un `ObservableObject` sur le MainActor plutôt qu'un acteur.** Écarté (D2) : le
scan et le parse doivent sortir du main thread, et l'acteur donne l'exclusion
mutuelle sur les trois caches sans verrou explicite.

## 5. Action plan

| # | Tâche | Statut | % |
|---|---|---|---|
| T1 | `ProcessLookup` (reprise) + tests de `normalize()` | todo | 0 |
| T2 | `TranscriptParser` pur + fixtures jsonl versionnées | **done** | **100** |
| T3 | `ToolActionClassifier` pur + tests des heuristiques de danger | **done** | **100** |
| T4 | `JSONLTailReader` (tail 64 Ko + cache mtime + éviction) | **done** | **100** |
| T5 | `ProjectsWatcher` FSEvents, coalescence 1 s | **done** | **100** |
| T6 | `actor SessionStore` + fusion des trois flux + caches sticky | **done** | **100** |
| T7 | `TerminalFocusProbe` | **done** | **100** |
| T8 | Compteur d'entrées non interprétées, exposé en diagnostic (parade R9) | **done** | **100** |
| T9 | `perfcheck.sh` A et B + la mesure ciblée du critère de sortie | **done** | **100** |

**Critère de sortie — amendé le 2026-08-19.**

Le critère d'origine exigeait « zéro `posix_spawn` **et zéro `proc_listpids`** »
au repos. **La seconde moitié était fausse**, et pour la raison que cette même
fiche énonce plus haut : la mort d'un processus n'émet aucun événement
filesystem. Exiger zéro scan de processus, c'est exiger de ne jamais remarquer
qu'une session s'est terminée. Le critère est donc :

| Point | Cible | Mesuré |
|---|---|---|
| `posix_spawn` au repos | **0** | **0** — aucun `Process()`, `popen` ni `pgrep` dans le code |
| `proc_listpids` | borné à la cadence paresseuse, jamais à 1 Hz | conforme (`.lazy`, 30 s) |
| Réveils inactifs | < 2/s | **0,000/s** |
| CPU au repos | < 0,5 % | **0,055 %** |
| `phys_footprint` | < 40 Mo | **8,2 Mo** — sous le plancher de RFC-001 |
| Latence de détection | < 1 s | **0,13 s** |
| Latence de fraîcheur | 1 s en activité, 30 s au repos | contractuel, cf. D8 |

Le gain réel sur la référence n'est pas la suppression du scan de processus —
il coûte 1,06 ms — mais celle du `fork`+`exec` de `pgrep` qui l'accompagnait à
chaque tick, mesuré à **11,34 ms**, soit dix fois plus.

### Latence de détection : 0,13 s

Mesurée le 2026-08-19 **depuis l'intérieur de l'app en marche**, avec quatre
sessions vivantes, en lançant un `claude` dans un projet neuf :

```
  + notch-latency-test détectée 0.13 s après sa dernière écriture
```

L'écart est calculé contre le `mtime` du transcript, pas contre une horloge que
le harnais contrôle : c'est le seul chiffre qui décrive l'app plutôt que la
mesure.

**Une première tentative avait donné 2,23 s, et ce chiffre était faux.** Le
harnais relançait `--info` toutes les 250 ms ; chaque appel crée un
`SessionStore` neuf, sans FSEvents, précédé d'un démarrage de processus. Il
mesurait le harnais et le lancement de `claude`, pas la détection. Refait
correctement, c'est 0,13 s — bien sous la seconde contractuelle.

La détection de **fin** de session est visible dans la même trace : `4 vivantes`
→ `3` → `2` à mesure que les processus se terminent, par le sondage paresseux.

### Un crash, et le test qui manquait

Le passage à un rafraîchissement incrémental a introduit un crash immédiat sous
trafic FSEvents réel : `eventPaths` n'est un `CFArray` **que si**
`kFSEventStreamCreateFlagUseCFTypes` est posé, et il ne l'était pas. Le callback
bit-castait donc un `char **` en `NSArray` avant de lui envoyer un message
Objective-C — un pointeur arbitraire déréférencé dans `objc_msgSend`.

Ce n'est pas une erreur que le compilateur peut voir, et aucun test unitaire ne
l'aurait attrapée : elle n'existe qu'une fois un vrai événement arrivé. D'où
`ProjectsWatcherTests`, qui monte un flux réel sur un dossier temporaire et
écrit dedans. Son assertion utile n'est pas « les chemins sont bons » mais
**« le callback s'exécute »**.

### Quatre signaux qui n'ont pas besoin du hook

Le format réel a été relevé sur Claude Code 2.1.234, pas repris de la référence.
Il contient, nativement, quatre choses que RFC-006 et RFC-012 croyaient devoir
prendre à des événements de hook :

| Signal | Où | Ce que la référence en fait |
|---|---|---|
| mode de permission | entrées `permission-mode`, **plus** un champ inline sur user/assistant | l'obtient de `PreToolUse` |
| fin de tour | `system` / `turn_duration`, avec `durationMs` | la **déduit** de l'inactivité du transcript |
| cycle de vie des sous-agents | `started` / `result`, clés par `agentId` | attend `SubagentStop` |
| échec d'un outil | `is_error` sur les blocs `tool_result` | — |

**Trois de ces quatre ont été trouvés par le compteur d'entrées non reconnues**,
c'est-à-dire par la parade au risque R9, dès sa première exécution sur données
réelles. C'est le meilleur argument possible pour cette parade : sans elle, ces
types auraient été ignorés en silence.

Conséquence : RFC-003 **ne dépend plus de RFC-006**, et RFC-012 non plus pour
l'essentiel. Le hook ne reste indispensable qu'à l'interception des permissions
(RFC-007) — la partie la plus lourde et la moins portable.

### Deux défauts de la référence, trouvés en la reprenant

**`proc_pidinfo` ne franchit pas un processus setuid.** La chaîne parent d'un
agent lancé dans iTerm2 est `claude → zsh → login → iTermServer → iTerm2`, et
`login` est setuid root : `proc_pidinfo(PROC_PIDTBSDINFO)` n'y répond pas. La
marche s'arrête deux sauts avant le terminal, **à chaque fois**, pour toute
session lancée depuis un shell de login. Corrigé en lisant le ppid par
`sysctl(KERN_PROC_PID)`, qui n'est pas soumis aux privilèges — c'est ce que fait
`ps`. Même repli ajouté à `name(of:)`, pour la même raison. La référence utilise
`proc_pidinfo` et porte donc cet angle mort.

**Le motif `"curl | sh"` ne matche aucune vraie commande**, puisqu'une vraie
commande a une URL entre les deux. Remplacé par un examen des deux moitiés de
part et d'autre du tuyau.

### Ce que le sujet de l'outil apporte

Chaque outil range son argument sous une clé différente — `command`,
`file_path`, `pattern`, `url`, `query`, `questions[0].question` — et il n'y en a
aucune de commune. Les extraire dans cet ordre de priorité est ce qui transforme
« édition » en « édition de `NotchPanel.swift` ». Repris de la référence, qui
avait déjà résolu ce point.

## 6. Open Questions

**Q1 — Quelle latence FSEvents ?** 1 s coalescé est le point de départ. Trop bas,
on réveille à chaque écriture de token ; trop haut, la pastille traîne.

```sh
# Compter les événements FS générés par une minute de session Claude réelle :
sudo fs_usage -w -f filesys | grep -c '\.claude/projects' &
sleep 60; kill %1
```

**Q2 — Le cache mtime doit-il être borné en taille ?**
`ClaudeMonitor.swift:253-257` évince sur `livePaths`, ce qui suffit tant que le
nombre de sessions vivantes est petit. À vérifier sur le corpus réel.

```sh
find ~/.claude/projects -name '*.jsonl' -newermt '-15 minutes' | wc -l
```

**Q3 — `contextWindow` : garder l'inférence sticky à 190k ?**
La règle de la référence (`:59-70`) pin la fenêtre à 1M dès qu'une session
dépasse 190k tokens. Heuristique, mais aucune autre source ne donne l'info.

## Notes d'implémentation

Pavés d'arbitrage déplacés depuis le code lors de la coupe des commentaires
(2026-08-20). Le code garde à leur place une ligne de renvoi vers cette section.

### `SessionStore.swift` / `actor SessionStore` — pourquoi un seul propriétaire

L'implémentation de référence en tient trois, et ils se contredisent : des
sessions dérivées des transcripts et de `libproc`, des PID dérivés du pair
socket d'un hook, et des modes de permission indexés par répertoire de travail
plutôt que par session. Le résultat est un appariement sur `cwd` faute de mieux,
et un appel `lsof` qui contredit un commentaire ailleurs dans le même dépôt.

Ici il y a un propriétaire et trois *entrées*, chacune faisant autorité sur
exactement une chose :

- **le processus** est la vérité sur la vivacité,
- **le transcript** est la vérité sur le contenu, le mode et la progression,
- **le hook**, quand RFC-006 arrivera, est la vérité sur l'identité — un PID lié
  à un identifiant de session plutôt que déduit d'un répertoire partagé.

La clé primaire est l'identifiant de session. `cwd` est un index secondaire, rien
de plus.

« Événementiel » est une description, pas une conception : les changements de
transcript arrivent par FSEvents, mais la mort d'un processus n'émet **aucun
événement filesystem**. La vivacité reste donc un sondage — paresseux, 30 s au
repos et 2 s en activité, plutôt que le 1 Hz plat avec un `fork` dedans de la
référence.

### `SessionStore.swift` / `liveness` — pourquoi la vivacité est injectable

L'alternative est intestable. La vivacité vient de vrais processus, et aucun test
ne peut faire apparaître un agent tournant dans un répertoire temporaire — sans
cette couture, le chemin d'alerte ne pourrait être exercé qu'à la main, depuis
une session par définition occupée à exécuter le test.

### `TranscriptParser.swift` / `TranscriptParser` — ce que le format contient

Observé sur Claude Code 2.1.234, pas repris de l'implémentation de référence, qui
est antérieure à plusieurs de ces types et les manque :

| type | porte |
|---|---|
| `user` / `assistant` | messages, `usage`, blocs `tool_use` |
| `permission-mode` | `permissionMode` — **le mode est dans le transcript** |
| `system` / `turn_duration` | le tour est terminé, avec `durationMs` |
| `system` / `stop_hook_summary` | un hook Stop s'est exécuté |
| `started` / `result` | cycle de vie des sous-agents, clé `agentId` |
| `attachment`, `file-history-snapshot`, `file-history-delta`, `last-prompt`, `mode`, `queue-operation` | connus, inutilisés |

Trois d'entre eux comptent, et tous trois sont des choses que la référence
obtient d'événements de hook dont aucun n'est nécessaire : `permission-mode`,
`turn_duration`, et le couple `started`/`result` qui suit les sous-agents.

Les deux derniers n'étaient pas dans cette liste au moment de l'écrire. Ils sont
apparus parce que les types non reconnus sont *comptés* plutôt qu'ignorés — la
parade au risque R9 se payant dès son premier passage.

### `TranscriptParser.swift` / `ParsedTail.awaitingQuestion`

Lu depuis un bloc `tool_use` dont l'outil pose une question et dont l'id n'a
aucun `tool_result` correspondant plus récent. **C'est dans le transcript**, tout
comme le mode de permission et la frontière de tour avant lui — le hook n'a
jamais été nécessaire pour ça. Ce pour quoi le hook reste nécessaire, c'est une
demande de *permission* en attente, qui se résout interactivement et n'est écrite
qu'une fois terminée.

### `JSONLTailReader.swift` / `JSONLTailReader` — une valeur, pas un acteur

C'était un acteur. Cela forçait `SessionStore` — lui-même un acteur — soit à
l'attendre au milieu d'un rafraîchissement, produisant un instantané assemblé à
partir de plusieurs instants, soit à tenir un second cache. Il tenait un second
cache, et il y avait alors deux caches pour un seul travail.

Une structure possédée par `SessionStore` hérite gratuitement de l'isolation de
cet acteur, et un rafraîchissement lit un moment cohérent.

### `ContextWindowResolver.swift` / `ContextWindowResolver`

La fenêtre ne peut pas être lue là où les tokens sont lus. C'est un fait sur la
*configuration*, et ce fichier est le seul endroit qui y répond — D1 s'applique à
la fenêtre autant qu'au reste.

Coût : trois `stat` par résolution, et une analyse seulement quand l'un des
fichiers a réellement changé. Rien ne tourne au repos : le store demande pendant
qu'il parcourt déjà les transcripts.

### `TerminalFocusProbe.swift` / `TerminalFocusProbe` — où il vit, et pourquoi

Il appartient à RFC-003, pas à la vue sessions qui le veut aussi. Le placer avec
la vue ferait dépendre la RFC permissions de la RFC sessions, ce qui est un cycle
de dépendances en puissance. Il est ici parce que ce module possède déjà
`ProcessLookup` et les PID.

Il existe pour que RFC-007 puisse rester silencieuse : interrompre quelqu'un avec
une demande de permission dans la notch alors que le terminal qui la pose est
juste devant lui, c'est du bruit.

### `SessionGroup.swift` / `SessionGroup` — pourquoi grouper

Claude Code ne supprime jamais un transcript, et un projet en accumule : cinq
lancements dans le même répertoire produisent cinq entrées, dont quatre
terminées. Affichées à plat, une seule après-midi de travail enterre la session
réellement en cours sous son propre historique — l'inverse de ce à quoi sert un
tableau de bord.

Grouper par répertoire de travail est la bonne clé plutôt que par identifiant de
session : ce que l'utilisateur pense être « ma session notch », c'est le
répertoire, et les identifiants changent à chaque redémarrage.

La préférence de *ne pas* grouper passe quand même par `SessionGroup`, plutôt que
la vue ne se dote d'un second chemin pour les sessions nues : les badges de la
ligne, son égalité et son saut lisent tous un groupe, et deux formes pour la même
ligne, c'est ainsi qu'une liste finit avec deux comportements.

### `TerminalJumper.swift` / `TerminalJumper` — tmux, et le coût

Sous tmux, le terminal de contrôle de l'agent est le pty du volet, pas celui de
l'émulateur : aucune session iTerm2 ne le porte et l'appariement échoue. Le repli
active alors l'application sans sélectionner d'onglet, ce qui est honnête — c'est
ce que `⌘Tab` aurait fait — plutôt que d'en sélectionner un mauvais. Demander à
tmux coûte trois sous-processus au moment du clic : c'est RFC-008 T6.

Coût : rien au repos. Sur un clic : un `sysctl`, un parcours de chaîne parente et
un Apple Event. L'événement réclame la permission d'automatisation, que macOS
demande une fois, et seulement la première fois qu'on clique sur une ligne.
