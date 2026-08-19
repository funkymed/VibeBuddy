# RFC-003 — Collecte de sessions : source de vérité unique

| | |
|---|---|
| **Status** | todo (0 %) |
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
| T2 | `TranscriptParser` pur + fixtures jsonl versionnées | todo | 0 |
| T3 | `ToolActionClassifier` pur + tests des heuristiques de danger | todo | 0 |
| T4 | `JSONLTailReader` (tail 64 Ko + cache mtime + éviction) | todo | 0 |
| T5 | `ProjectsWatcher` FSEvents, coalescence 1 s | todo | 0 |
| T6 | `actor SessionStore` + fusion des trois flux + caches sticky | todo | 0 |
| T7 | `TerminalFocusProbe` | todo | 0 |
| T8 | Compteur d'entrées non interprétées, exposé en diagnostic (parade R9) | todo | 0 |
| T9 | `perfcheck.sh` A et B + la mesure ciblée du critère de sortie | todo | 0 |

**Critère de sortie.** Lancer `claude` dans un projet change l'état publié en
**moins d'une seconde**. Et surtout : `sample` sur le process pendant les 30 s qui
précèdent ce lancement montre **zéro `posix_spawn` et zéro `proc_listpids`** —
c'est la preuve que l'event-driven a bien remplacé le polling. `perfcheck.sh B`
(3 sessions actives) reste sous 3 % de CPU.

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
