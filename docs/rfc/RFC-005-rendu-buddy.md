# RFC-005 — Buddy : format de manifeste et moteur de rendu

| | |
|---|---|
| **Status** | in-progress (25 %) — manifeste et cadrage figés, moteur Swift à écrire |
| **Author** | Cyril Pereira |
| **Created** | 2026-08-19 |
| **Updated** | 2026-08-19 |
| **Phase** | 3 — Surface visible |
| **Depends on** | RFC-001, RFC-002, RFC-003 |
| **Related** | RFC-012 (produit l'état exprimé) · RFC-010 (AppearancePrefs) · R3 |
| **Blocks** | — |

## 1. Context & Problem

Le buddy est la seule chose visible en permanence. Deux exigences, de nature
différente, se rejoignent sur lui.

**La première est énergétique.** C'est le seul élément dont le coût de rendu se
paie en continu. L'implémentation de référence produit six styles animés
visuellement réussis, mais dépense son budget de façon invisible : **dix-huit**
`withAnimation(...).repeatForever` (`BuddyFace.swift` lignes 249, 252, 256, 261,
271, 411, 414, 417, 433, 436, 440, 443, 452, 455, 459, 671, 686, 1006), présents
dans **tous** les styles, chacun installant un `CADisplayLink` implicite jamais
démonté — ni quand la vue sort de l'écran, ni quand la fenêtre se masque. Aucun
`stop()` n'existe dans ce projet. S'y ajoutent jusqu'à **trois `Task`
concurrentes par buddy** (`:165-166`, `:327`, `:584`, `:729-730`, `:884-886`),
relancées à chaque `onChange(of: mode)`.

*Correction d'une lecture répandue :* le `TimelineView(.animation(1/60))` de
`BuddyFace.swift:516-517` n'est **pas** global. Il est confiné à `BarsBuddy`
(struct lignes 470→575), donc au seul style « Waves ». C'est d'ailleurs la
**bonne** approche — une horloge explicite et pausable — avec la mauvaise cadence.

**La seconde est produit.** notch-buddy doit pouvoir porter le buddy d'une
entreprise — tigreboite pour commencer. Six `struct` Swift codées en dur ne
permettent pas ça : chaque nouveau buddy serait une recompilation, une release,
et une revue de code. **Le buddy doit être de la donnée**, pas du code.

Ces deux exigences tirent dans le même sens : des renderers **sans état**,
pilotés par une horloge unique, décrits par un manifeste.

## 2. Goals / Non-goals

**Goals.** Un format de manifeste chargeable au lancement, sans recompilation.
Un moteur de rendu piloté par l'`AnimationBudget` de RFC-001. Un buddy intégré
par défaut. tigreboite comme premier manifeste externe, qui sert de test du format.

**Non-goals.**
- La logique qui *décide* de l'état : elle vient de RFC-003 et RFC-012, via une
  fonction pure.
- La pop-out d'alerte et sa politique : RFC-012.
- Un éditeur de buddy. On écrit du JSON à la main pour l'instant.
- Le chargement depuis le réseau. Fichier local uniquement — un manifeste
  téléchargé est du code exécutable qu'on n'a pas relu.

**Règle non négociable.** Quand la pastille est masquée, `frameRate = 0`. Pas
« ralenti » : zéro.

## 3. Proposed Solution

### Le manifeste

Un dossier `.buddy/` : un `manifest.json` et ses assets.

```json
{
  "schema": 1,
  "id": "tigreboite",
  "name": "Tigreboite",
  "palette": { "body": "#F5A623", "accent": "#1A1A1A", "glow": "#FFD08A" },
  "geometry": { "width": 56, "height": 32 },
  "expressions": {
    "idle":     { "layers": ["base", "eyes-open"],   "motion": "breathe" },
    "working":  { "layers": ["base", "eyes-focus"],  "motion": "pulse" },
    "awaiting": { "layers": ["base", "eyes-wide"],   "motion": "dart" },
    "finished": { "layers": ["base", "eyes-happy"],  "motion": "bounce" },
    "failed":   { "layers": ["base", "eyes-shut"],   "motion": "shake" },
    "sleeping": { "layers": ["base", "eyes-shut"],   "motion": "none" }
  },
  "layers": {
    "base":       { "shape": "path", "d": "M0,16 …", "fill": "body" },
    "eyes-open":  { "shape": "circles", "at": [[18,14],[38,14]], "r": 4, "fill": "accent" }
  }
}
```

Les états d'expression sont **ceux de la machine de RFC-012**, pas une liste
parallèle. Un manifeste qui omet une expression retombe sur `idle`.

**Formes vectorielles, pas images.** Un buddy décrit en chemins reste net à
toutes les échelles, pèse quelques kilo-octets, et se colorie par palette — un
même buddy en variante sombre sans second asset. Le format admet aussi un PNG par
couche pour les cas qu'on ne sait pas décrire, mais ce n'est pas la voie normale.

**Les mouvements (`motion`) sont un vocabulaire fermé** — `breathe`, `pulse`,
`dart`, `bounce`, `shake`, `none` — implémentés en Swift et paramétrés par le
manifeste. Un manifeste ne décrit pas *comment* animer : il choisit dans une
liste. C'est ce qui garantit que le budget d'animation tient quel que soit le
buddy chargé, et ce qui empêche un manifeste tiers de devenir un langage de
programmation.

### Modules

| Module | Responsabilité |
|---|---|
| `BuddyManifest` | `Codable`, versionné par `schema`. Validation stricte au chargement. |
| `BuddyLoader` | Charge, valide, **retombe sur le buddy intégré** si invalide. Ne plante jamais. |
| `BuddyExpression` | Miroir des états de RFC-012. |
| `MotionKind` | Le vocabulaire fermé. Chaque cas est une fonction pure `phase → transform`. |
| `BuddyRenderer` | `draw(into: GraphicsContext, manifest:, expression:, phase:)` — **sans état**. |
| `BuddyView` | **Un seul** `TimelineView`, `minimumInterval` piloté par `AnimationBudget`. |

Tout le mouvement dérive de `phase`, le temps passé par le `TimelineView`, à
l'intérieur d'un `Canvas`. Aucune animation implicite, aucune `Task`, aucun
`@State` d'animation. Le clignement se calcule depuis `phase` au lieu d'être
piloté par une boucle.

### Repris de la référence

Le travail de réglage visuel est le vrai actif du dépôt de référence, même si son
architecture ne l'est pas.

| Brique | `fichier:ligne` | Usage ici |
|---|---|---|
| Palette hex des couleurs | `BuddyFace.swift:5-60` | valeurs de départ des palettes de manifeste |
| `GhostShape`, `TriangleShape` | `:541-573`, `:710-719` | converties en chemins de manifeste |
| Rampes de couleur par mode | `:105-114`, `:168-189`, `:329-349` | modèle de la clé `palette` |
| Constantes de cadence de `runBlinkLoop` | `:120-152` | réglages des `motion`, valeurs conservées |
| Plafond de hauteur du halo en mode alerte | `:223-227`, `:264-269` | contrainte dure : la hauteur de notch est un plafond, les échelles restent entre 1,05 et 1,15 |

### Budget

| Expression | Fréquence | Coût visé |
|---|---|---|
| pastille masquée | **0 Hz, 0 réveil** | 0 |
| `sleeping` | **0 Hz** (`TimelineView` en pause) | 0 |
| `idle` | 8 Hz sur ~56×32 pt | < 0,4 % |
| `working` / `awaiting` | 30 Hz | **< 1,5 %** |
| `finished` / `failed` | impulsion, puis retour à 8 Hz | transitoire |

RSS +1 Mo. Un manifeste chargé : < 100 Ko.

## 4. Alternatives Considered

**Garder six renderers Swift codés en dur** *(le découpage initial)*. Écarté :
un buddy d'entreprise deviendrait une recompilation, et les six styles
représentent ~780 lignes qu'il faudrait de toute façon convertir au format le
jour où le besoin arrive. Autant poser le format d'abord et écrire les buddys
comme des manifestes.

**Un seul buddy générique + une couche de thème par entreprise.** Beaucoup moins
de code, et suffisant pour changer les couleurs et poser un logo. Écarté parce
que « le buddy de tigreboite » suppose une *forme* propre, pas seulement une
teinte — sinon c'est le même buddy repeint.

**Manifeste en images (PNG/APNG par expression).** Plus simple à produire pour un
graphiste, mais lourd, flou en écran non-Retina, et impossible à recolorier.
Gardé comme échappatoire par couche, pas comme voie principale.

**Manifeste scriptable (Lua, JS) pour les animations.** Écarté franchement :
c'est un moteur d'exécution tiers dans la boucle de rendu permanente d'une app
qui vise zéro réveil au repos. Le vocabulaire fermé de `motion` donne la
souplesse utile sans ce risque.

**Garder les animations implicites SwiftUI.** Écarté : c'est la dette identifiée.
Un `repeatForever` a l'air gratuit au site d'appel et ne peut plus être ni
interrogé ni arrêté une fois installé.

**`CAKeyframeAnimation` / CoreAnimation pur.** Meilleure efficacité théorique,
mais D5 a tranché : `NSPanel` + `NSHostingView` mesure 10,0 Mo de
`phys_footprint` et **0,000 réveil inactif/s**. SwiftUI n'est pas le problème.

## 5. Action plan

| # | Tâche | Statut | % |
|---|---|---|---|
| T1 | Schéma `BuddyManifest` v1 + `Codable` + validation stricte | todo | 0 |
| T2 | `BuddyLoader` + repli sur le buddy intégré (test : manifeste corrompu, champ manquant, `schema` inconnu) | todo | 0 |
| T3 | `MotionKind` : les 6 mouvements en fonctions pures `phase → transform` | todo | 0 |
| T4 | `BuddyRenderer` sans état + `BuddyView` avec le `TimelineView` unique | todo | 0 |
| T5 | Branchement sur `AnimationBudget`, y compris `frameRate = 0` si masqué | todo | 0 |
| T6 | Buddy intégré par défaut, écrit comme manifeste (pas comme cas particulier) | todo | 0 |
| T7 | **Manifeste tigreboite** — le premier client externe du format | **in-progress** | **70** |
| T8 | Mapping `BuddyExpression` ← état RFC-012, fonction pure + tests | todo | 0 |
| T9 | `perfcheck.sh` A, B, C — comparaison entre manifestes | todo | 0 |

**Critère de sortie.** Le buddy affiche des expressions distinctes pour chaque
état de RFC-012. **Déposer le manifeste tigreboite et relancer l'app suffit à
changer de buddy — aucune recompilation.** Un manifeste corrompu retombe sur le
buddy intégré sans planter ni figer. `perfcheck.sh A` avec la pastille masquée
montre **0 réveil imputable au buddy**. L'écart de coût entre deux manifestes ne
dépasse pas 10 %.

## 6. Open Questions

**~~Q1 — Quel sous-ensemble de chemins vectoriels accepter ?~~ TRANCHÉE (2026-08-19)**

**`M`, `C`, `Z`, plus `circle` et `ellipse`. Rien d'autre.** Confirmé sur le cas
réel : le buddy tigreboite complet — silhouette, corps, 11 rayures, museau,
nez/bouche — n'utilise que ces cinq primitives. Le tracer produit du Catmull-Rom
converti en cubiques, donc `L` n'apparaît même pas. Un parseur pour ce
sous-ensemble tient en une centaine de lignes.

**~~Q2 — À quoi ressemble le buddy tigreboite ?~~ TRANCHÉE (2026-08-19)**

Une tête de tigre stylisée, déjà pourvue d'yeux — le cas idéal pour un buddy.

**Il n'existe aucune source vectorielle.** `public/icons/favicon.svg` porte
l'extension mais contient un PNG en base64 dans une balise `<image>` (généré par
RealFaviconGenerator) ; recherche faite dans tout le dépôt tigreboite : deux
`.svg`, zéro `<path>`. Le buddy a donc été **reconstruit** depuis le PNG 512 px,
non par vectorisation automatique — qui aurait donné un contour impossible à
articuler — mais par **segmentation par couleur puis remesure de la géométrie** :

| Partie | Mesure | Reconstruction |
|---|---|---|
| yeux | circularité **0,94**, r = 38,0, ±100,6 de l'axe, y = 246,2 | `circle` paramétrique |
| reflets | r = 10,0, décalage (+6,5 ; −12,4) depuis l'œil | `circle` paramétrique |
| museau | 158×112 en (255,6 ; 333,3) | `ellipse` |
| silhouette | — | chemin, 53 points |
| corps | — | chemin, 103 points |
| rayures | 11 marques, en paires symétriques | chemins |
| nez + bouche | 118×78 | chemin, 46 points |

Palette exacte : corps `#FE9C19` (45 %), contour `#332921` (25 %), museau
`#F8F0E8` (4 %).

Le fait que les yeux soient de **vrais cercles** est ce qui rend tout le reste
possible : un œil à 200 points de polygone ne peut pas cligner.

Livrables : `assets/buddies/tigreboite/manifest.json` (13,6 Ko),
`parts.json`, `tiger.svg`, `expressions-preview.png`. Outils reproductibles dans
`tools/` (`analyze_tiger.py`, `trace_paths.py`, `build_tiger_buddy.py`,
`emit_svg.py`).

**Reste à faire pour clore T7** : le moteur de rendu Swift. La maquette actuelle
est en Python + SVG, elle valide le format et les expressions, pas le rendu
embarqué.

**~~Q3bis — Quel cadrage dans la pastille ?~~ TRANCHÉE (2026-08-19) — cadrage serré sur le visage**

`viewBox = [0, 164, 512, 324]`, ratio **1,58:1**. Largeur pleine et menton
conservés, **seules les oreilles sont rognées**.

Deux essais ont été écartés par la mesure, pas par le goût :

- **Forcer le ratio 1,75:1 de la pastille** coupe le menton ou les oreilles selon
  où on centre. Une pastille large et un visage carré sont incompatibles si on
  veut garder toute la tête.
- **Cadrage carré** coupe les joues et les moustaches : la tête fait **510×453**,
  elle n'est pas carrée. Un carré centré sur l'axe perd les bords latéraux, qui
  portent les moustaches — un signe distinctif du logo.

Les cadrages intermédiaires (1,28:1 et 1,43:1) laissent des **moignons de rayures
coupés** au bord supérieur, qui se lisent comme un défaut de rendu. 1,58:1 coupe
au-dessus des yeux sans laisser de moignon.

**Le buddy ne remplit pas la pastille.** Il occupe ~56×35 pt (minimum 48×30) dans
une pastille de ~56×32 à 220×38 selon l'encoche ; le reste de la largeur porte le
statut. C'est ce qui résout la tension de ratio : on n'étire pas le visage, on
lui donne sa place.

Validé **à la taille réelle**, pas à 256 px : les six expressions restent
distinctes à 56×35 pt, et `awaiting` — celle qui doit attirer l'œil — est la plus
marquée. Seule réserve consignée : les fentes de `sleeping` deviennent presque
invisibles à cette taille. C'est l'effet voulu, mais à revalider sur écran réel
plutôt qu'en agrandissement.

**Q3 — Où vivent les manifestes ?**
`~/Library/Application Support/notch-buddy/buddies/<id>/` a ma préférence. Un
dossier par buddy, découvert au lancement.

**Q4 — Faut-il verrouiller un buddy par politique d'entreprise ?**
Si tigreboite déploie l'app à son équipe, veut-elle que le buddy soit imposé, ou
juste proposé par défaut ? Ça change le modèle de préférences de RFC-010.

**~~Q5 — Six mouvements suffisent-ils ?~~ TRANCHÉE (2026-08-19), avec une correction du format**

Les six mouvements suffisent. **Mais le gréement de l'œil, non.**

La première maquette ne pilotait l'œil que par une échelle verticale `sy`. Résultat
mesurable à l'œil : `finished` (« clin d'œil satisfait ») et `sleeping`
(« endormi ») s'écrasaient tous deux en la même fente plate, et `failed` était
indiscernable de `awaiting`. **Une mise à l'échelle ne peut pas exprimer une
forme.**

Correction apportée au format : un paramètre **`curve`** par expression.
`0` rend un disque plein ; `+1` un arc vers le haut (œil rieur) ; `−1` un arc vers
le bas (abattu). Les six expressions sont alors nettement distinctes —
vérifié visuellement, voir `expressions-preview.png`.

Enseignement à garder pour tout futur manifeste : **un vocabulaire fermé a besoin
d'un bouton de forme, pas seulement d'un bouton de taille.**
