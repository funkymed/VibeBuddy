# Audit SOLID — 2026-08-24

Mesuré contre le code du jour, pas contre les fiches. 157 fichiers, 21 682
lignes Swift dont 6 513 de tests. Les 458 tests passent.

Cet audit ne propose **aucun changement de comportement**. Tout ce qui suit se
juge à un seul critère : la suite reste verte à l'identique.

---

## Le résumé, si tu ne lis qu'un paragraphe

Le Kit (`VibeBuddyKit`) est en bon état : des types petits, une responsabilité
chacun, testés. **Le problème est concentré dans la couche AppKit**, et surtout
dans un fichier : `NotchPanel.swift`, **1 034 lignes et 98 membres**, qui est à
la fois une fenêtre, une machine à états, un moteur d'animation, un routeur de
permissions, un gestionnaire de curseur et un calculateur de géométrie.

Le second problème est l'absence quasi totale d'abstractions : **deux protocoles
dans tout le projet**. Tout le reste dépend de types concrets, ce qui rend la
plupart des chemins non testables sans lancer l'application — et c'est
exactement pourquoi cinq défauts ont dû être trouvés à la main le 2026-08-21.

---

## S — Responsabilité unique

### `NotchPanel.swift` — 1 034 lignes, 98 membres, six sections

C'est le seul endroit du dépôt où la règle « une chose par type » est violée à
cette échelle. Ses propres `// MARK:` le disent :

```
State · Diagnostics · Permissions · Sizing to what is on screen · Screens · Drag
```

Et ce qu'il pilote directement, compté par occurrences dans le fichier :

| Collaborateur | Occurrences |
|---|---|
| `hover` (`HoverProbe`) | 23 |
| `pointer` (`PointerMonitor`) | 20 |
| `host` (`ClickThroughHostView`) | 20 |
| `budget` (`AnimationBudget`) | 13 |
| `gaze` (`PointerGaze`) | 10 |
| `NSEvent`, `NSWorkspace`, `NSCursor` | 11 |
| `wake`, `metrics`, `snapPreview` | 17 |

**Quatre responsabilités séparables**, dans l'ordre où elles se détachent le
plus proprement :

1. **La machine à états** — `state`, `applyState`, le garde de réentrance, la
   borne de dix, `finishStateChange`. C'est de la logique pure : elle ne touche
   AppKit que par une fonction « pose ce cadre ». Extraite, elle devient
   **testable sans écran** — et deux des bugs les plus coûteux de la semaine
   (le panneau noir, le gel à l'ouverture des réglages) vivaient là.
2. **La géométrie** — `panelSize`, `measurePermissionHeight`, `targetFrame`,
   `hoverRect`, `pillScreenRect`. Déjà à moitié dehors (`NotchFrameSolver`,
   `PillLayout`) ; le reste peut suivre.
3. **Le routage des permissions** — `setPermission`, `answerPermission`,
   `alwaysAllowPermission`, `confirmConsent`. Il ne concerne pas une fenêtre.
4. **Le curseur et le survol** — déjà presque isolés dans `CursorZones`, mais
   `NotchPanel` garde les deux sources de survol et leur arbitrage.

### `AppCoordinator.swift` — 494 lignes, treize `on*` posés

Il tient dix-huit dépendances et câble treize callbacks. C'est un orchestrateur,
donc une certaine largeur est normale — mais il porte aussi la lecture des
drapeaux `--simulate-*`, la migration du dossier de support, l'installation des
signaux et le rechargement des buddies.

**Ce qui en sort le plus utilement** : les drapeaux de simulation (une seule
valeur lue une fois), et le câblage des callbacks, qui gagnerait à être un objet
« composition » distinct du cycle de vie de l'application.

### Les vues au-dessus de la limite

La décision **D2 plafonne une vue à 200 lignes**. Huit la dépassent :

| Lignes | Fichier |
|---|---|
| 333 | `NotchShellView.swift` |
| 240 | `Buddy/EyesFaceView.swift` |
| 223 | `ClickThroughHostView.swift` |
| 215 | `Panel/SessionRow.swift` |
| 214 | `BenchHarness.swift` |
| 205 | `Panel/PointingHandCursor.swift` |
| 205 | `Panel/Permission/PermissionPanelView.swift` |
| 204 | `Buddy/BuddyView.swift` |

Trois d'entre elles ne sont pas vraiment des vues (`ClickThroughHostView`,
`BenchHarness`, `PointingHandCursor`) — la règle ne devrait pas leur être
appliquée telle quelle, et c'est la règle qu'il faut préciser, pas le code qu'il
faut tordre.

**`NotchShellView` prend 43 paramètres.** C'est le symptôme le plus visible :
une vue qui reçoit tout ce dont ses enfants pourraient avoir besoin.

---

## O — Ouvert/fermé

**C'est le principe le mieux tenu, et c'est récent.** `VibeTheme`, `VibeButton`,
`VibeBadge`, `neonHalo` : ajouter un bouton ne demande plus de toucher aux
existants. Avant le 2026-08-23, il y avait quatre implémentations divergentes de
« un libellé qu'on clique ».

**Là où il ne l'est pas** : chaque nouveau type de résumé de permission demande
un `case` dans `PermissionRequestModel.Summary`, un `case` dans le `switch` de
`PermissionPanelView`, et une vue. C'est acceptable — l'ensemble est fermé et
petit — mais c'est le même patron que RFC-016 veut casser côté agents.

---

## L — Substitution de Liskov

**Rien à signaler.** Presque aucun héritage : `NotchPanel: NSPanel` et
`ClickThroughHostView: NSView` héritent d'AppKit, sans hiérarchie propre au
projet. Le code est composé, pas dérivé. C'est un bon point et il est délibéré.

---

## I — Ségrégation des interfaces

**`NotchShellView` et ses 43 paramètres** est la violation type : chaque enfant
n'en utilise qu'une poignée, et ajouter une donnée à une carte de session oblige
à traverser toute la chaîne.

Le remède habituel — l'`Environment` de SwiftUI — a un coût que ce dépôt connaît
déjà : il invalide plus large. Le remède sobre est de **regrouper par
destinataire** : `PanelChrome`, `SessionsContent`, `PermissionContent`, chacun un
`struct` de données passé d'un bloc.

**`NotchPanel` expose sept closures `on*`**, dont trois optionnelles. Un
appelant doit savoir lesquelles poser pour que les permissions fonctionnent —
c'est un contrat implicite, non vérifié par le compilateur. Un protocole
`PermissionPresenter` rendrait l'oubli impossible.

---

## D — Inversion des dépendances

**C'est la faiblesse principale, et elle est chiffrable : deux protocoles dans
tout le projet.**

```
Sources/VibeBuddyKit/Usage/UsageClient.swift:66:     public protocol CredentialSource
Sources/VibeBuddyKit/Hook/HookSocketServer.swift:9:  public protocol HookEventSink
```

Et les deux sont bons — `HookEventSink` est précisément ce qui a permis de tester
la file de permissions sans socket. Le problème est qu'il n'y en a que deux.

Conséquences mesurables :

- **La couche app n'est pas testée.** Les 458 tests sont tous dans
  `VibeBuddyKitTests` ; `Sources/VibeBuddy/` n'a aucune cible de test. Ce n'est
  pas un oubli de discipline : ces types ne sont pas instanciables sans écran.
- **`Diagnostics` et `HoverDiagnostics` lisent `UserDefaults.standard`
  directement**, alors que `PreferencesStore` existe pour ça. La frontière fuit
  aux endroits où personne ne regarde.
- **Les façades de RFC-016 sont impossibles à écrire** sans introduire ces
  protocoles : c'est le même travail, et c'est pourquoi cet audit et la RFC
  doivent avancer ensemble.

---

## Ce que je propose, par ordre de rendement

Chaque étape est indépendante et se juge sur « les 458 tests restent verts ».

| # | Action | Rendement | Risque |
|---|---|---|---|
| 1 | **Extraire la machine à états** de `NotchPanel` en un type pur, testable sans écran | Le plus élevé — c'est là que sont nés le panneau noir et le gel | Moyen : c'est le cœur de RFC-002 |
| 2 | **Extraire le routage des permissions** de `NotchPanel` vers un `PermissionPresenter` | Élevé — rend testable ce qui a coûté cinq défauts terrain | Faible |
| 3 | **Regrouper les 43 paramètres** de `NotchShellView` en trois `struct` par destinataire | Moyen — supprime la traversée | Faible |
| 4 | **Introduire les protocoles de RFC-016** (`AgentBridge`, `TerminalBridge`) et extraire `ClaudeCodeFacade` | Élevé, et il faut le faire de toute façon | Faible si fait à comportement constant |
| 5 | **Fermer la frontière `UserDefaults`** — `Diagnostics` et `HoverDiagnostics` passent par `PreferencesStore` | Faible mais gratuit | Nul |
| 6 | **Préciser D2** : la règle vise les vues SwiftUI, pas les `NSView` ni les bancs | Nul en code, évite une fausse dette | Nul |

**Ce que je ne propose pas :**

- Découper le module buddy (`EyePose` 517, `PointerGaze` 505, `EyeRaster` 356).
  Ils sont gros mais chacun traite **un** sujet, ils sont couverts par 48 tests,
  et leur taille vient de la matière — une rastérisation analytique et une
  machine à regards, ce n'est pas de la dette.
- Introduire un conteneur d'injection. Le projet a zéro dépendance externe par
  décision ; l'injection par initialiseur suffit à ce que fait le code.
- Toucher aux vues du design system. Elles viennent d'être unifiées et le
  principe ouvert/fermé y est tenu.

---

## Le point de méthode, qui vaut plus que la liste

**La couche app n'a aucun test, et ce n'est pas réparable par de la discipline.**
Tant que `NotchPanel` mêle logique et AppKit, la seule façon de vérifier son
comportement est de lancer l'application et de regarder — ce qui a été fait le
2026-08-21 et a trouvé cinq défauts qu'aucun des 449 tests d'alors ne voyait.

L'objectif des étapes 1 et 2 n'est donc pas l'élégance. C'est de rendre
vérifiable, à froid, ce qui n'est aujourd'hui vérifiable qu'à la main.
