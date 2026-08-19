# RFC-008 — Vue sessions et saut vers le terminal hôte

| | |
|---|---|
| **Status** | todo (0 %) |
| **Author** | Cyril Pereira |
| **Created** | 2026-08-19 |
| **Updated** | 2026-08-19 |
| **Phase** | 5 — Confort |
| **Depends on** | RFC-002, RFC-003 |
| **Related** | RFC-006 (mapping PID) · R8 |
| **Blocks** | — |

## 1. Context & Problem

Avec plusieurs projets ouverts, savoir *quelle* session fait quoi demande de
parcourir ses fenêtres de terminal. La notch peut lister les sessions vivantes et
donner un moyen d'atteindre celle qu'on cherche.

Le saut vers le terminal est le point technique. Sous tmux, **la chaîne parent ne
mène pas au terminal** : le serveur tmux est détaché de son client
(`TerminalJumper.swift:34-38`). Il faut donc d'abord interroger tmux pour
sélectionner le bon volet, puis activer une application terminal. La référence y
consacre 391 lignes de bricolage empirique par émulateur — matière directement
réutilisable, mais avec deux défauts à corriger.

**Défaut 1, une contradiction interne au dépôt.** `findPIDBySessionID`
(`TerminalJumper.swift:115-156`) retrouve le PID d'une session via `lsof` sur le
jsonl. Or `ClaudeMonitor.swift:524-526` explique que claude **ferme le jsonl entre
deux écritures**, ce qui rend `lsof` non fiable. Deux parties du même projet se
contredisent.

**Défaut 2, un appariement arbitraire.** Deux sessions dans le même répertoire
reçoivent leurs PID **par ordre de tri** (`ClaudeMonitor.swift:248`,
`idx < pids.count ? pids[idx] : nil`). Et `findAllClaudePIDs` accepte
`name == "node"` (`TerminalJumper.swift:349`), ce qui attrape n'importe quel
process Node du même répertoire.

## 2. Goals / Non-goals

**Goals.** Liste des sessions vivantes ; détail d'une session sous forme de
timeline ; filtre texte ; saut vers le terminal avec sélection du volet tmux.

**Non-goals.** La collecte (RFC-003).

**Positionnement.** Cette RFC vient **après** RFC-007 : le mapping
`sessionID → PID` fourni par le hook (`HookBridge.swift:117-142`) est la seule
source fiable, et il supprime toute une classe de bugs d'appariement. La faire
avant obligerait à écrire l'heuristique, puis à la jeter.

## 3. Proposed Solution

| Module | Responsabilité |
|---|---|
| `SessionListView` / `SessionRowView` | Liste. `SessionRowView` conforme à `Equatable` pour couper les invalidations. |
| `SessionDetailView` | Timeline des événements récents. |
| `actor SessionTimelineLoader` | Tail 256 Ko + parse **avec cache**, hors du main thread. |
| `TerminalJumper` | Saut en trois étapes. |
| `TmuxPaneIndex` | Cache du mapping volet ↔ PID, invalidé au changement d'app frontmost. |

**Repris tel quel** — 391 lignes d'empirisme qu'il serait absurde de refaire :

| Brique | `fichier:ligne` | Pourquoi |
|---|---|---|
| Saut en 3 étapes : tmux → chaîne parent → repli par bundle ID | `TerminalJumper.swift:53-112` | L'ordre compte : sous tmux la chaîne parent ne mène pas au terminal. |
| `selectTmuxPane` | `TerminalJumper.swift:229-273` | Ancêtres du PID claude ∩ `pane_pid`. Le séparateur `\|` est choisi parce qu'un nom de session tmux peut contenir des espaces (`:243`). `switch-client` **avant** `select-window` si le client est attaché ailleurs (`:267-271`). |
| `findTmux()` : 4 chemins en dur puis `sh -l -c which tmux` | `TerminalJumper.swift:275-289` | Couvre Homebrew ARM/Intel et nix-darwin. |
| `runProcess` avec PATH enrichi | `TerminalJumper.swift:291-325` | Un `.app` n'hérite pas du PATH du shell. |
| Listes de terminaux par `proc_name` et par bundle ID | `TerminalJumper.swift:21-51` | Noter `"stable"` pour Warp (`:27`). |
| Parsing des événements récents | `ClaudeMonitor.swift:582-699` | Y compris un `tool_result` déguisé en entrée `user` (`:610-622`). |

**Modifié :**
- `findPIDBySessionID` via `lsof` (`:115-156`) : **supprimé**. Le mapping du hook
  est exact ; le `cwd` sert de repli.
- `findAllClaudePIDs` acceptant `node` (`:349`) : unifié sur le filtre de
  `ClaudeMonitor.swift:531-542` (nom exact `claude`, ou chemin contenant
  `/claude/versions/`).
- `recentEvents()` appelé **depuis un `body` de vue**
  (`NotchContentView.swift:1183`) : déplacé dans une `.task(id:)` avec cache.
  Aujourd'hui, chaque invalidation relit 256 Ko de disque sur le main thread.
- `sessionRowContent` (`NotchContentView.swift:3483-3560`) : extrait en
  `SessionRowView` conforme à `Equatable`.

**Budget.** 0 % panneau fermé. Panneau ouvert : rendu de ≤ 8 lignes, aucune
animation. Le saut coûte 3 à 4 `fork`/`exec` tmux **au clic uniquement**. Le
détail : un tail 256 Ko + parse, **une fois par ouverture**, en tâche détachée
(~5 ms hors main thread). RSS +2 Mo panneau ouvert, restitués à la fermeture.

## 4. Alternatives Considered

**`lsof` pour l'appariement.** Écarté : contredit par le dépôt lui-même.

**AppleScript pour activer le terminal.** Écarté : demande l'autorisation
d'automatisation, et ne résout pas le problème du volet tmux.
`NSRunningApplication.activate()` suffit une fois le volet sélectionné.

**Faire RFC-008 avant RFC-007.** Écarté : sans le mapping PID du hook, il faut
écrire une heuristique d'appariement qu'on jettera. Voir R8.

**Ne pas faire le saut du tout, se contenter de la liste.** Défendable — `⌘Tab`
couvre le cas simple. Mais avec plusieurs sessions dans plusieurs volets tmux,
c'est précisément le cas simple qui n'existe plus.

## 5. Action plan

| # | Tâche | Statut | % |
|---|---|---|---|
| T1 | `SessionListView` + `SessionRowView` `Equatable` | todo | 0 |
| T2 | Filtre texte | todo | 0 |
| T3 | `SessionTimelineLoader` (actor + cache), hors `body` | todo | 0 |
| T4 | `SessionDetailView` | todo | 0 |
| T5 | `TerminalJumper` : chaîne parent + repli bundle ID | todo | 0 |
| T6 | `selectTmuxPane` + `findTmux` + PATH enrichi | todo | 0 |
| T7 | `TmuxPaneIndex` avec invalidation sur changement de frontmost | todo | 0 |
| T8 | Unification du filtre de process claude (suppression du cas `node`) | todo | 0 |

**Critère de sortie.** Avec **deux** sessions Claude dans le **même** répertoire,
cliquer sur chaque ligne active le bon volet tmux — **cinq fois de suite sans
erreur**. Le panneau fermé ne coûte rien.

## 6. Open Questions

**Q1 — Quels émulateurs vérifier réellement ?** La liste de la référence en
couvre onze, mais seuls ceux effectivement installés peuvent être testés.

```sh
# Ce qui tourne réellement ici, pour cadrer la liste à tester :
ps -Ao comm= | grep -Ei 'term|alacritty|ghostty|kitty|wezterm|warp|hyper|rio|tabby' | sort -u
tmux -V 2>/dev/null || echo "tmux absent"
```

**Q2 — Le détail de session est-il utile, ou redondant avec le terminal ?**
435 lignes dans la référence pour afficher ce qui est déjà à l'écran. Candidat au
report si le calendrier dérape.

**Q3 — Combien de sessions afficher ?** La référence plafonne à 8
(`NotchContentView.swift:1358`). Au-delà, faut-il paginer ou tronquer ?
