# RFC-016 — Deux ponts : `AgentBridge` et `TerminalBridge`

| | |
|---|---|
| **Status** | **todo (0 %)** — ouverte le 2026-08-24 |
| **Author** | Cyril Pereira |
| **Created** | 2026-08-24 |
| **Updated** | 2026-08-24 |
| **Phase** | 7 — Ouverture |
| **Depends on** | RFC-003 (collecte), RFC-006 (transport socket), RFC-008 (saut vers l'onglet) |
| **Related** | R9 (le format des transcripts n'est pas un contrat), **R11** |
| **Blocks** | — |

## 1. Context & Problem

Le produit dit deux choses qu'il ne tient pas encore.

`CLAUDE.md` annonce le multi-agent comme direction — « Claude, Codex, Copilot,
opencode et suivants » — et présente le v1 Claude-only comme « une dette assumée
et suivie (**R11**) ». Et le panneau promet de ramener l'utilisateur à sa session
en un clic, quel que soit son terminal.

**Vérifié contre le code le 2026-08-24, ni l'un ni l'autre n'est vrai.**

### Côté agents

Un point d'extension existe, et il est bien placé :

```swift
/// One case today, so adding Codex is a new case, not a hunt for hard-coded paths (R11).
public enum AgentProvider: String, Sendable, Equatable, CaseIterable {
    case claudeCode
}
```

`AgentSession.provider` porte la valeur, `ProcessLookup.matches(pid:provider:)`
fait un `switch` dessus. Le nommage neutre a été tenu partout : `AgentSession`,
jamais `ClaudeSession`.

Mais la promesse « un nouveau case » ne vaut que pour la **détection de
processus**. Tout le reste est Claude-only en dur, dans **quatorze fichiers** :

| Ce qui est spécifique à Claude Code | Où |
|---|---|
| `~/.claude/projects`, format des `.jsonl` | `SessionStore`, `SessionCoordinator` |
| Fenêtre de contexte lue dans les réglages Claude | `ContextWindowResolver` (4 occurrences) |
| `settings.json`, installation du hook, `permissions.allow` | `ClaudeSettingsWriter`, `HookInstaller`, `PermissionRules` |
| Keychain et endpoint OAuth Anthropic | tout le module d'usage (RFC-004) |

Et **R11 n'est pas dans le tableau des risques de `CLAUDE.md`** : la prose le
cite deux fois, l'index s'arrête à R10. Un risque qu'on dit suivre et qui n'est
pas dans la liste n'est pas suivi.

### Côté terminaux

| Terminal | Détection de la session | Retour à l'onglet exact |
|---|---|---|
| iTerm2, Terminal.app | ✔ chaîne parent par `sysctl` | ✔ AppleScript apparié sur le **tty** |
| Ghostty, kitty, Alacritty, WezTerm, Warp | ✔ | ✘ activation de l'app seulement |
| n'importe lequel **sous tmux** | ✔ | ✘ le tty est celui du volet |

`TerminalJumper.scriptable` contient trois chaînes — `iTerm2`, `iTerm`,
`Terminal` — et son propre commentaire dit déjà pourquoi les autres tombent :
ils n'embarquent aucun dictionnaire de script.

**Le cas tmux est le plus fréquent et le pire.** Il échoue pour les deux
terminaux pourtant supportés : sous tmux, le tty de l'agent est celui du volet,
donc aucune session iTerm2 ne le porte, l'appariement échoue et le repli active
l'application sans choisir d'onglet. C'est déjà écrit dans RFC-008 T6/T7, à 0 %.

### Ce que la découverte du 2026-08-24 change

`opencode` est installé sur la machine, et il expose **une API de plugins**.
Open Island s'en sert déjà :

```
~/.config/opencode/plugins/open-island.js
// Bridges OpenCode events to the Open Island desktop app via Unix socket.
```

C'est notre modèle exactement : un plugin pousse les événements de l'agent vers
une socket Unix. Le mécanisme n'est donc pas à inventer, il est à observer — et
il est vérifiable ici, tout de suite, sans réseau ni supposition.

### Ce que la lecture d'open-vibe-island a rendu — 2026-08-24

Le dépôt est sur cette machine. **Aucune ligne n'en est reprise**, même règle que
pour Notch-Pilot : ce qui suit est de l'empirisme et des chiffres.

**L'ampleur, d'abord.** 147 fichiers Swift, 54 900 lignes, contre 14 990 ici. Dix
agents supportés, et **aucune abstraction commune** — un jeu de fichiers par
agent, dupliqué :

| Agent | Fichiers | Lignes |
|---|---|---|
| Claude | 9 | 3 056 |
| Codex | 6 | 4 222 |
| Cursor | 5 | 864 |
| Gemini | 3 | 876 |
| OpenCode | 3 | 757 |
| Kimi | 2 | 553 |

Plus un `BridgeServer.swift` de **102 Ko** et un `CodexSessionTracking.swift` de
61 Ko. C'est l'argument le plus concret en faveur du protocole : dix agents à ce
régime, c'est dix fois la surface à maintenir, et le dixième arrive quand le
premier a déjà dérivé.

**Le réglage par agent est un tri-état, pas un booléen.** C'est le constat le
plus directement réutilisable :

```swift
public enum AgentHookIntent: String, Codable, Sendable, CaseIterable {
    case untouched
    case installed
    case uninstalled
}
```

`untouched` (jamais vu) et `uninstalled` (refusé) ne sont pas la même chose : un
booléen force soit à réinstaller ce que l'utilisateur a retiré, soit à ne jamais
rien proposer. Leur commentaire est explicite — « the startup flow must honour
`uninstalled` and never silently reinstall ».

S'y ajoute une **migration depuis l'état du disque** au premier lancement : pour
chaque agent, on regarde si le hook est réellement là, et on en déduit
l'intention. Sans quoi un utilisateur de longue date se voit proposer un
onboarding pour ce qu'il utilise déjà.

**Ghostty est scriptable, et notre code dit le contraire.**
`TerminalJumper.scriptable` porte ce commentaire : « Ghostty, kitty and
Alacritty ship no scripting dictionary and must fall back to activation. » Or
ils font bien `tell application "Ghostty"` et lisent `terminals`, `id`,
`working directory`, `name`. **À vérifier avant de s'en servir**, mais la
phrase est à corriger dans les deux cas.

Nuance qui compte pour nous : Ghostty expose un `working directory`, **pas un
tty**. L'appariement se ferait donc sur le répertoire — exactement ce que
RFC-003 refuse, parce que deux agents du même projet le partagent. Ghostty n'est
pas « impossible », il est *ambigu*, ce qui est une décision, pas un blocage.

**Les autres terminaux, et par quel canal :**

| Terminal | Canal | Chez nous aujourd'hui |
|---|---|---|
| iTerm2, Terminal.app | AppleScript, apparié sur le **tty** | ✔ |
| Ghostty | AppleScript, apparié sur le **cwd** | ✘ (dit non scriptable) |
| WezTerm, Kaku (`fun.tw93.kaku`) | CLI `wezterm cli` | ✘ |
| **Warp** | **lecture SQLite** — `WarpSQLiteReader.swift`, 23,8 Ko | ✘ |
| tmux | CLI `tmux list-panes`, chemin résolu à l'exécution | ✘ (RFC-008 T6/T7) |

Warp répond à la Q4 de cette fiche : le canal existe, mais lire la base d'une
autre application est un contrat encore moins tenu qu'un format de transcript
(R9). 23,8 Ko pour un seul terminal donne le prix.

**Un détail d'AppleScript qui vaut d'être noté** : leurs scripts renvoient des
enregistrements séparés par les caractères ASCII 30 et 31 (*record separator* et
*unit separator*) plutôt que par des virgules ou des retours à la ligne. Un titre
d'onglet peut contenir n'importe quoi ; ces deux octets, non.

**Et le point où nous divergeons, délibérément.** Leur coordinateur résout les
cibles de saut **à chaque tick de surveillance (~2 s)** dès qu'une session est
vivante — AppleScript, `tmux list-panes`, `ps`/`lsof`, en tâche détachée mais en
continu. Notre budget l'interdit : un `fork`+`exec` coûte **11,34 ms**, soit
1,13 % d'un cœur à 1 Hz, et le contrat dit **zéro `fork` au repos**.

Cette lecture ne remet donc pas en cause notre choix — elle le chiffre. Ce qu'ils
paient en permanence, nous le paierons au clic.

## 2. Goals / Non-goals

**Goals.**

- Un contrat `AgentBridge` : ce qu'un agent doit fournir pour apparaître dans la
  notch, et ce qu'il peut ne pas fournir.
- Un contrat `TerminalBridge` : ce qu'un terminal doit savoir faire pour qu'un
  clic ramène à l'endroit exact.
- **opencode** comme deuxième agent réel, par plugin.
- **tmux** comme premier pont terminal réel, parce qu'il casse déjà les deux
  terminaux supportés.
- R11 inscrit au tableau des risques.

**Non-goals.**

- Porter l'**interception des permissions** (RFC-007) sur un second agent. Elle
  dépend d'un contrat de hook propre à Claude Code, prouvé à la dure ; la refaire
  ailleurs est un projet à part.
- Porter la **consommation** (RFC-004). Le Keychain et l'endpoint `oauth/usage`
  sont Anthropic ; un autre agent n'a pas d'équivalent, et afficher un chiffre
  approché serait pire que ne rien afficher.
- Un réglage « agent actif ». Tous les agents visibles sont visibles ensemble.

## 3. Proposed Solution

**Stratégie pour le contrat, façade pour l'intégration.** Arbitrage du
2026-08-24. Les deux mots recouvrent deux besoins distincts, et les confondre est
ce qui produit un `BridgeServer.swift` de 102 Ko.

- La **stratégie** est ce que l'application connaît : un protocole étroit,
  interchangeable, que le reste du code appelle sans savoir qui répond.
- La **façade** est ce qu'une intégration cache derrière : un installeur, un
  lecteur de transcript, un analyseur, un client de socket, des chemins, des
  formats. Rien de tout cela ne remonte.

Le test qui sépare les deux : **si le reste de l'application peut le nommer, ce
n'est pas dans la façade.** `SessionStore` ne doit jamais lire le mot `claude`.

### Deux familles de ponts, et la distinction est la seule qui compte

| Famille | L'agent | Exemples | Ce qu'on obtient |
|---|---|---|---|
| **Poussé** | nous parle | Claude Code (hook), opencode (plugin) | fin de tour, attente, mode, identité — à la seconde |
| **Observé** | ne sait pas qu'on existe | tout le reste | processus vivants, `cwd`, dates de fichiers |

Le transport est déjà écrit et générique : `HookSocketServer`, une ligne JSON par
sens (RFC-006). Il ne lui manque qu'un champ `agent` dans l'enveloppe, et un nom
qui ne dise plus « hook ».

### Les stratégies

```swift
/// Ce que l'application sait d'un agent. Rien de plus.
protocol AgentBridge: Sendable {
    var identifier: AgentIdentifier { get }
    /// Processus vivants, groupés par cwd normalisé. Jamais de fork (RFC-003).
    func liveSessions() -> [String: [pid_t]]
    /// Ce que l'agent raconte de lui-même, s'il raconte quelque chose.
    func enrich(_ session: inout AgentSession)
}

/// Ce que l'application sait d'un terminal.
protocol TerminalBridge: Sendable {
    /// Sans lancer un seul processus — voir « Le coût » plus bas.
    func canReveal(_ session: AgentSession) -> Bool
    func reveal(_ session: AgentSession) -> TerminalJumper.Outcome
}
```

**Le minimum pour apparaître est délibérément bas** : un processus identifiable
et un `cwd`. C'est ce que `ProcessLookup` sait déjà faire pour n'importe quel
exécutable, et ça suffit à dessiner une ligne dans le panneau.

**Tout le reste est facultatif, et l'UI doit savoir l'afficher absent.** C'est la
contrainte la plus structurante de cette RFC : un agent sans fenêtre de contexte
n'a pas d'anneau, un agent sans mode de permission n'a pas de badge. Le panneau
ne montre jamais un chiffre qu'il n'a pas — règle du dépôt, et la raison d'être
du produit.

### Les façades

Une par intégration, et **une seule** : c'est le point d'entrée unique de tout ce
qui est spécifique à un agent ou à un terminal.

```
AgentBridge (stratégie)
  ├── ClaudeCodeFacade      ← extraite de l'existant, sans changement de comportement
  │     └── cache : transcripts jsonl · settings.json · hook · Keychain OAuth
  └── OpenCodeFacade
        └── cache : plugin JS · socket · registre de sessions

TerminalBridge (stratégie)
  ├── TmuxFacade            ← cache : chemin de tmux, list-panes, select-pane, index
  ├── AppleScriptFacade     ← cache : les scripts iTerm2 et Terminal.app, l'appariement tty
  └── CommandFacade         ← cache : wezterm cli, kitty @
```

Chaque façade porte **quatre** responsabilités et n'en expose aucune :

1. **Découvrir** — reconnaître ses processus, ses fichiers, son application.
2. **Installer** — écrire le hook ou le plugin, avec les parades de R1
   (relecture, sauvegarde horodatée, écriture atomique) ; savoir aussi se
   désinstaller.
3. **Interpréter** — transcript, événement de socket, sortie de commande, en
   `AgentSession` ou en cible de saut.
4. **Se déclarer indisponible** — l'application n'est pas installée, le binaire
   manque, l'utilisateur a refusé le pont.

Le quatrième point est celui qu'on oublie. Une façade qui ne sait pas dire « pas
moi » oblige l'appelant à la connaître, et la stratégie ne sert plus à rien.

### Les briques, et c'est là que se gagne le prochain pont

**Une façade ne part pas de zéro. C'est tout l'intérêt de l'exercice.** Sans ce
socle, la deuxième intégration réécrit la première et la troisième réécrit les
deux — c'est très exactement l'état d'open-vibe-island, où Codex pèse 4 222
lignes et Claude 3 056 sans partager une ligne.

Une nouvelle façade doit se réduire à **ce qui lui est propre** : ses chemins,
son format, le nom de son binaire. Tout le reste est déjà écrit, testé, et
mesuré.

| Brique partagée | Existe déjà | Ce qu'elle évite d'écrire |
|---|---|---|
| `ProcessLookup` — pids, `cwd`, `tty`, chaîne parent par `sysctl` | ✔ RFC-003 | la découverte, et le piège `proc_pidinfo` qui ne franchit pas un `setuid` |
| `ManagedConfigWriter` — relecture, sauvegarde horodatée, `replaceItemAt`, ordre préservé | ✔ sous le nom `ClaudeSettingsWriter` | la parade R1 en entier, et `OrderedJSON` avec son analyseur écrit à la main |
| Transport socket + enveloppe une-ligne-JSON | ✔ RFC-006 | le protocole, `SO_NOSIGPIPE`, la détection de raccrochage, le drainage |
| `JSONLTailReader` + compteur d'entrées non reconnues | ✔ RFC-003 | la lecture incrémentale, et la parade R9 qui a trouvé quatre signaux |
| `SessionDisplayState`, `AlertPolicy`, `AlertBus` | ✔ RFC-012 | la machine d'état, l'anti-doublon, le routage des alertes |
| `AppleScriptRunner` avec séparateurs ASCII 30/31 | à extraire (T6) | l'échappement, et les titres d'onglet qui contiennent n'importe quoi |
| `CommandRunner` — résolution de chemin, PATH enrichi, sortie bornée | à extraire (T7) | le `fork`/`exec` fait correctement, une seule fois |
| `FrontmostInvalidatedIndex` | à écrire (T7) | le cache et son invalidation, la seule qui observe un fait |

**Le critère d'acceptation d'une nouvelle façade est donc chiffrable** : si
brancher un agent supplémentaire demande plus de **deux cents lignes**, c'est
qu'une brique manque au socle et qu'il faut l'extraire plutôt que la recopier.
`ClaudeCodeFacade` sera le mètre étalon — elle est la plus fournie des trois
(hook bloquant, permissions, usage OAuth), et ce qu'elle fait de générique doit
descendre d'un cran avant que `OpenCodeFacade` soit écrite.

C'est l'ordre de T2 puis T4 : extraire d'abord contre l'existant, à comportement
inchangé et suite verte, **puis** écrire la seconde façade. L'inverse — écrire
opencode d'abord et généraliser après — produit deux implémentations et une
abstraction qui ressemble à la dernière écrite.

### Le registre

```swift
/// Interroge les stratégies dans l'ordre, s'arrête à la première qui répond.
struct BridgeRegistry {
    let agents: [any AgentBridge]
    let terminals: [any TerminalBridge]
}
```

**Ordre du plus précis au plus grossier** pour les terminaux — tmux avant
l'émulateur, l'émulateur avant l'activation nue. Le repli final reste ce qu'il
est aujourd'hui : activer l'application sans choisir d'onglet, ce qui vaut mieux
que d'en choisir un faux.

### Les réglages, et ce qui demande un consentement

Un tri-état par pont, repris comme constat d'open-vibe-island :

```swift
enum BridgeIntent: String, Codable, Sendable { case untouched, installed, uninstalled }
```

**Recommandation sur Q5 — le tri-état porte sur l'installation, jamais sur
l'observation.** Regarder la table des processus ne demande aucun consentement :
c'est ce que fait `ps`, et l'app le fait déjà pour Claude Code sans rien
installer. Écrire un fichier chez l'utilisateur en demande un, toujours.

Donc, par agent :

| | Observation | Pont installé |
|---|---|---|
| Ce qu'on obtient | processus, `cwd`, « en cours » | fin de tour, attente, mode |
| Ce qu'on écrit | **rien** | `settings.json` ou un plugin |
| Réglage | toujours actif | tri-état, `untouched` par défaut |

Un agent jamais vu est donc **visible** et **muet** : la ligne existe, l'alerte
non — et l'écran de réglages dit ce qu'installer le pont ajouterait. C'est
l'inverse du silence, qui laisse croire que l'agent n'est pas supporté.

**La migration au premier lancement** est reprise telle quelle : lire ce qui est
réellement sur le disque et en déduire l'intention, sinon un utilisateur de
longue date se voit proposer d'installer ce qu'il a déjà.

### Le coût, qui décide de la forme

`TerminalJumper` porte déjà l'avertissement : la référence lançait
`tmux list-panes -a` **à l'arrivée de chaque permission**, et un `fork`+`exec`
coûte **11,34 ms**, soit 1,13 % d'un cœur à 1 Hz — la mesure la plus chère du
dépôt. Le budget dit **zéro `fork` au repos**, et open-vibe-island paie ce prix
toutes les deux secondes.

D'où deux règles non négociables, portées par la **stratégie** et non laissées à
la discrétion des façades :

- **`liveSessions()` ne lance aucun processus.** `proc_listpids` et `sysctl`
  suffisent, mesurés à 1,06 ms pour 617 processus.
- **`canReveal` ne lance aucun processus.** Il répond depuis un index construit
  au premier clic et invalidé au changement d'application frontmost — ce que
  RFC-008 T7 décrit déjà.

### Le tick permanent — mesuré puis écarté, 2026-08-24

La question a été posée : adopter leur modèle, qui résout les cibles de saut à
chaque tour de surveillance (~2 s), si cela simplifie. Mesuré sur la machine
cible avant de répondre :

| | Coût |
|---|---|
| `fork`+`exec` nu (`/usr/bin/true`) | **1,4 ms** |
| **un `osascript` trivial** | **32,1 ms** (médiane sur 10 essais) |
| `pgrep` | 11,34 ms (mesure du 2026-08-19) |

Leur tour de surveillance fait au minimum **deux** `osascript` — disponibilité
Ghostty, disponibilité Terminal — plus `tmux list-panes`, plus `ps`/`lsof`.
Soit **64 ms toutes les deux secondes, c'est-à-dire 3,2 % d'un cœur en
permanence**, pour zéro pixel dessiné.

Le budget de ce projet est de **0,5 % au repos** et **3 % en activité**. Leur
modèle dépasse donc à lui seul le budget d'*activité*, en étant au repos. Et la
mesure du 2026-08-23 place le scénario A à 0,000 % de CPU et 0,261 réveil/s :
il n'y a pas de marge à dépenser, il y a un ordre de grandeur à préserver.

**Ce n'est pas un arbitrage entre confort et pureté.** C'est un facteur qui
ferait sortir l'application de son propre contrat, et le contrat est l'argument
de vente : « la légèreté prime sur les fonctionnalités ».

### Ce qu'on retient quand même : le préchauffage sur événement

Le tick permanent achète une seule chose de valeur — **pas de latence au clic**,
parce que l'inventaire est déjà là. On peut l'obtenir sans le payer en continu,
en construisant l'index sur des signaux que la machine livre de toute façon :

| Signal | Déjà écouté | Ce qu'il déclenche |
|---|---|---|
| Le panneau se déploie | ✔ `applyState` | construire l'index : l'utilisateur ne peut cliquer que maintenant |
| L'application frontmost change | ✔ RFC-007 T3 | invalider l'index |
| Une permission arrive | ✔ `PermissionQueue` | préchauffer, le saut est probable |

Le panneau n'est ouvert que quelques secondes à la fois, et c'est **exactement**
la fenêtre où un clic est possible. Le coût suit donc l'attention de
l'utilisateur au lieu de courir en permanence — et au repos, panneau fermé,
il reste nul.

C'est la même logique que les trois péremptions de RFC-007, qui roulent toutes
sur un événement que la machine allait livrer de toute façon.

## 4. Alternatives Considered

**Un protocole seul, sans façades.** C'est-à-dire : `ClaudeCodeBridge` conforme
à `AgentBridge` et contenant tout. Écarté le 2026-08-24, et open-vibe-island
montre où ça mène — leurs neuf fichiers Claude et six fichiers Codex n'ont aucun
point d'entrée commun, si bien que `ProcessMonitoringCoordinator` doit connaître
chacun. Un protocole sans façade déplace le désordre d'un cran, il ne le
supprime pas.

**Un `enum` de plus au lieu d'un protocole.** `AgentProvider` en a déjà un et il
a bien vieilli pour la détection. Mais un `switch` par fait — chemins,
transcripts, usage, permissions — étale un agent sur quatorze fichiers, ce qui
est exactement l'état actuel. Le protocole existe pour que le second agent soit
un fichier, pas une chasse.

**Tout lire depuis les fichiers, sans plugin ni hook.** Écarté : le format des
transcripts n'est pas un contrat (R9), et il l'est encore moins chez les autres.
Le hook Claude Code a coûté deux heures d'épreuve terrain pour être prouvé ; le
plugin opencode existe déjà et pousse ce qu'il sait.

**Réutiliser le plugin d'Open Island.** Écarté : c'est le pont d'un autre
produit, vers une autre socket. On lit son mécanisme, on n'emprunte pas son code
— même règle que pour Notch-Pilot.

**Attendre un second agent réel avant d'abstraire.** C'est l'argument le plus
sérieux contre cette RFC, et il aurait gagné il y a une semaine. Il perd
aujourd'hui parce qu'un second agent est **installé sur la machine** et que son
mécanisme est vérifiable sans rien supposer.

## 5. Action plan

| # | Tâche | Statut | % |
|---|---|---|---|
| T0 | **R11 au tableau des risques** de `CLAUDE.md` — la prose le cite, l'index l'ignore | **done** | **100** — fait le 2026-08-24, avec R12 pour les terminaux |
| T0b | **Réglages : un tri-état par pont** — `untouched` / `installed` / `uninstalled`, plus la migration depuis l'état réel du disque au premier lancement | todo | 0 |
| T0c | Vérifier que **Ghostty est scriptable** et corriger le commentaire de `TerminalJumper.scriptable`, qui affirme le contraire | todo | 0 |
| T1 | Spike **opencode** : quels événements le plugin peut pousser, quel format, quelle identité de session. Sortie brute archivée dans `docs/spikes/` | todo | 0 |
| T2 | `AgentBridge` (stratégie) + `ClaudeCodeFacade` extraite de l'existant, **sans changement de comportement** — les 458 tests restent verts à l'identique, c'est le seul critère | todo | 0 |
| T2b | `BridgeRegistry` : ordre d'interrogation, repli, et le « pas moi » d'une façade indisponible | todo | 0 |
| T2c | **Descendre les briques génériques d'un cran** — `ManagedConfigWriter`, `JSONLTailReader`, `AppleScriptRunner`, `CommandRunner`. Fait *avant* la seconde façade, sans quoi l'abstraction ressemble à la dernière intégration écrite | todo | 0 |
| T3 | Champ `agent` dans l'enveloppe socket ; `HookSocketServer` renommé pour ce qu'il est devenu | todo | 0 |
| T4 | `OpenCodeFacade` + plugin `vibebuddy.js`, installé par une commande explicite comme le hook | todo | 0 |
| T5 | **L'UI sait afficher l'absence** : pas d'anneau sans fenêtre de contexte, pas de badge sans mode, pas de consommation | todo | 0 |
| T6 | `TerminalBridge` (stratégie) + `AppleScriptFacade` (extraction de l'existant) | todo | 0 |
| T7 | `TmuxFacade` — reprend RFC-008 T6/T7, index invalidé au frontmost, **zéro `fork` avant le clic** | todo | 0 |
| T8 | `CommandFacade` (kitty, WezTerm), chacune conditionnée à la présence de son binaire | todo | 0 |
| T8b | **Préchauffage de l'index** au déploiement du panneau, invalidation au frontmost — au lieu d'un tick permanent, mesuré à 3,2 % d'un cœur | todo | 0 |
| T9 | `perfcheck` A et C avant/après T7 : le budget dit **0 `fork` au repos** | todo | 0 |

**Critère de sortie.** Une session opencode et une session Claude Code sont
visibles **en même temps** dans le panneau, chacune avec son état propre, et la
ligne opencode n'affiche aucun chiffre qu'elle n'a pas. Un clic sur une session
tournant dans un volet tmux ramène **au volet**, cinq fois de suite. `perfcheck`
scénario A : zéro `fork` au repos, inchangé.

**Et un critère de forme, qui vaut autant** : `OpenCodeFacade` tient en moins de
deux cents lignes. Au-delà, une brique manque au socle — la conclusion est de
l'extraire, jamais de recopier.

## 6. Open Questions

**Q1 — Que fait le panneau d'un agent qu'il ne sait qu'observer ?**
Une ligne avec un nom, un `cwd` et « en cours » est-elle utile, ou trompeuse ?
L'objectif n°1 est d'alerter à la fin d'un tour ; sans signal poussé, on ne sait
pas dire qu'un tour est fini.

```sh
# Ce que l'observation seule donne aujourd'hui, pour n'importe quel binaire :
pgrep -x opencode | while read pid; do lsof -a -p "$pid" -d cwd -Fn | tail -1; done
```

**Q2 — Le plugin opencode s'installe-t-il comme le hook ?**
`HookInstaller` écrit dans `~/.claude/settings.json` avec toutes les parades de
R1 : relecture, sauvegarde horodatée, écriture atomique, ordre préservé. Un
plugin est un **fichier déposé** dans `~/.config/opencode/plugins/`, ce qui est
plus simple — mais faut-il l'écraser s'il existe déjà ?

```sh
ls -la ~/.config/opencode/plugins/
cat ~/.config/opencode/opencode.jsonc
```

**Q3 — Deux agents dans le même `cwd`.** RFC-003 a fait du `sessionID` la clé
primaire précisément pour ça, et `cwd` est déjà un repli qui a coûté un bug
(RFC-007, défaut n°1). Un agent observé n'a **pas** de `sessionID`. Que devient
la clé ?

**Q4 — Faut-il un pont pour Warp ? — répondu le 2026-08-24, et la réponse est
« pas maintenant ».** Le canal existe : open-vibe-island lit sa base **SQLite**
(`WarpSQLiteReader.swift`, 23,8 Ko pour ce seul terminal). Mais lire la base
d'une autre application est un contrat encore moins tenu qu'un format de
transcript, qui est déjà le risque R9. À rouvrir si quelqu'un le demande.

**Q5 — Le tri-état porte-t-il sur le pont ou sur l'agent ? — tranchée le
2026-08-24 par recommandation, l'utilisateur n'ayant pas d'avis arrêté.**

Il porte sur **l'installation du pont**, et l'observation reste toujours active.
Lire la table des processus ne demande aucun consentement — c'est ce que fait
`ps`, et l'app le fait déjà. Écrire un fichier chez l'utilisateur en demande un,
toujours. Voir « Les réglages » en section 3.

À rouvrir si l'usage dit le contraire : le signe serait un utilisateur surpris de
voir une ligne pour un agent dont il n'a rien installé.

```sh
# Ce qui est écrit sur le disque de l'utilisateur, par pont :
ls -la ~/.claude/settings.json ~/.config/opencode/plugins/
```
