# RFC-008 — Vue sessions et saut vers le terminal hôte

| | |
|---|---|
| **Status** | in-progress (75 %) — liste, groupement, scroll et **saut hors tmux** livrés ; tmux et détail à écrire |
| **Author** | Cyril Pereira |
| **Created** | 2026-08-19 |
| **Updated** | 2026-08-20 |
| **Phase** | 5 — Confort · la liste est arrivée avec le panneau de RFC-002 |
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

**AppleScript pour activer le terminal.** ~~Écarté~~ — **repris le 2026-08-20**,
et l'argument d'origine était à moitié faux. Vrai pour tmux :
`NSRunningApplication.activate()` suffit une fois le volet sélectionné. Faux pour
l'onglet : hors tmux, le dictionnaire de scripting est la **seule** API qui cible
un onglet, et il publie `tty` en lecture (`sdef /Applications/iTerm.app`,
`<property name="tty">` sur `session`). L'appariement devient donc une égalité
sur le pty — pas un titre, pas un `cwd`, pas un ordre de tri. Le prix est
l'autorisation d'automatisation, demandée une fois, au premier clic.

**Apparier sur le titre de l'onglet ou le `cwd`.** Écarté : les titres sont
écrits par le shell, le prompt et les programmes, et deux agents dans le même
projet partagent leur `cwd`. C'est exactement R8 sous un autre nom.

**Faire RFC-008 avant RFC-007.** Écarté : sans le mapping PID du hook, il faut
écrire une heuristique d'appariement qu'on jettera. Voir R8.

**Ne pas faire le saut du tout, se contenter de la liste.** Défendable — `⌘Tab`
couvre le cas simple. Mais avec plusieurs sessions dans plusieurs volets tmux,
c'est précisément le cas simple qui n'existe plus.

## 5. Action plan

| # | Tâche | Statut | % |
|---|---|---|---|
| T1 | `SessionListView` + `SessionRowView` `Equatable` | **done** | **100** |
| T2 | Filtre texte | **done** | **100** |
| T9 | Groupement par répertoire + défilement de la liste | **done** | **100** |
| T3 | `SessionTimelineLoader` (actor + cache), hors `body` | todo | 0 |
| T4 | `SessionDetailView` | todo | 0 |
| T5 | `TerminalJumper` : tty + chaîne parent + repli activation | **done** | **100** |
| T5b | Ligne cliquable, message de résultat, i18n | **done** | **100** |
| T6 | `selectTmuxPane` + `findTmux` + PATH enrichi | todo | 0 |
| T7 | `TmuxPaneIndex` avec invalidation sur changement de frontmost | todo | 0 |
| T8 | Unification du filtre de process claude (suppression du cas `node`) | todo | 0 |

**Critère de sortie.** Avec **deux** sessions Claude dans le **même** répertoire,
cliquer sur chaque ligne active le bon volet tmux — **cinq fois de suite sans
erreur**. Le panneau fermé ne coûte rien.

### Le groupement, trouvé à l'usage

Claude Code ne supprime jamais un transcript, et un projet en accumule : cinq
exécutions dans le même dossier produisent cinq lignes, quatre terminées.
Affichées à plat, **la session qui tourne se retrouve enterrée sous son propre
historique** — l'inverse de ce à quoi sert un tableau de bord. Constaté sur une
capture après une après-midi de travail.

Le regroupement se fait par **répertoire de travail**, pas par identifiant de
session : ce que l'utilisateur appelle « ma session notch » est le dossier, et
les identifiants changent à chaque relance.

Un badge `×5` n'apparaît que s'il y a de l'historique — un `×1` sur chaque ligne
serait du bruit déguisé en information.

La règle verrouillée par un test : **une session terminée ne masque jamais une
session vivante**, même plus récente qu'elle.

La liste défile, l'en-tête et la consommation restent fixes. Sans ça la liste
poussait les deux hors du panneau, et une après-midi suffisait à perdre les
lectures pour lesquelles le panneau existe.

Effet de bord corrigé au passage : la règle d'ordonnancement était écrite **deux
fois**, dans la vue et dans le tri. Elle vit désormais uniquement dans
`SessionGroup`.

### Livré en avance, avec le panneau déployé

La liste est arrivée en construisant le contenu du panneau de RFC-002 : les
données de RFC-003 étaient déjà là, et un panneau vide n'avait pas d'intérêt.

Trois écarts avec la référence, mesurés ou raisonnés :

- **`SessionRow` est `Equatable`.** Le panneau se redessine à chaque instantané
  de session ; sans ça les six lignes se reconstruisent quand une seule change.
  Leur ligne est inlinée dans une vue de 3 738 lignes, ce qui invalide tout le
  panneau à la moindre mise à jour.
- **Un anneau de contexte plutôt qu'un pourcentage.** Un nombre demande une
  unité et un dénominateur ; un anneau n'en demande aucun. Orange à 70 %, rouge
  à 90 %.
- **Le champ de filtre n'apparaît qu'au-delà de trois sessions.** Une boîte de
  recherche au-dessus de deux lignes est du mobilier.

**Ce qui est absent est absent, pas maquetté.** Le pourcentage de consommation
(RFC-004), la heatmap (RFC-009) et la liste des outils toujours autorisés
(RFC-007) ne figurent pas dans le panneau. Un chiffre de remplacement dans un
produit dont l'argument est de montrer le *vrai* nombre serait la pire chose à
livrer — et une fois posé, on oublie qu'il est faux.

Coût mesuré du panneau construit : **8,3 Mo, 0,038 % de CPU, 0,000 réveil
inactif/s.**

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
