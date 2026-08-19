# RFC-005 — Buddy : format de manifeste et rendu

| | |
|---|---|
| **Status** | in-progress (95 %) — format texte animé livré, reste le scénario C |
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

### Le format : six chaînes

```json
{
  "schema": 3, "kind": "ascii",
  "id": "tigreboite", "name": "Tigreboite",
  "colour": "#FE9C19", "fontSize": 13,
  "expressions": {
    "sleeping": { "face": "=--=", "motion": "none" },
    "idle":     { "face": "=^^=", "motion": "breathe" },
    "working":  { "face": "=OO=", "motion": "pulse" },
    "awaiting": { "face": "=??=", "motion": "dart" },
    "finished": { "face": "=**=", "motion": "bounce", "colour": "#7CE38B" },
    "failed":   { "face": "=xx=", "motion": "shake",  "colour": "#FF6B6B" }
  }
}
```

Les états d'expression sont **ceux de la machine de RFC-012**, pas une liste
parallèle. Une expression absente retombe sur `idle`, donc un manifeste
décrivant un seul visage est légal et complet.

### Modules

| Module | Responsabilité |
|---|---|
| `BuddyManifest` | `Decodable`, versionné par `schema`, validation stricte au chargement |
| `BuddyLoader` | Charge, valide, **retombe sur le buddy intégré** si invalide. Ne plante jamais. |
| `BuddyExpression` | Miroir des états de RFC-012, plus le mapping en une fonction pure |
| `MotionKind` | Vocabulaire fermé de six mouvements, **fonctions pures** `phase → transform` |
| `BuddyView` | **Une** `TimelineView`, cadence pilotée par `AnimationBudget` |

Le buddy ne connaît pas sa position ni sa taille : il occupe l'oreille gauche
d'un `PillLayout` (RFC-002), dont la largeur est **mesurée depuis son propre
visage**. Un manifeste qui passe `fontSize` de 13 à 20 élargit son slot sans que
personne n'édite de constante — c'est la divergence assumée avec la référence,
qui code 56 pt en dur.

### Les mouvements restent un vocabulaire fermé

Un manifeste **choisit** un mouvement, il n'en décrit jamais. C'est ce qui rend
le format sûr — un fichier tiers ne devient pas un évaluateur d'expressions dans
la boucle de rendu — et ce qui permet de garantir le budget d'animation **pour
n'importe quel buddy**, puisque chaque mouvement est une fonction bornée de la
phase.

Chaque mouvement déclare aussi la cadence dont il a besoin : un souffle à
0,28 Hz est indiscernable à 8 fps ou à 60, un rebond ne l'est pas. La vue prend
**le minimum** entre ce que le mouvement demande et ce que le budget autorise.

### Le halo

Trois ombres empilées, pas une. Une ombre large se lit comme un flou ; un halo
serré et vif par-dessus un halo large et faible se lit comme quelque chose qui
*émet*. La plus serrée reprend la couleur à pleine intensité — c'est elle qui
fait paraître les traits plus épais et plus chauds qu'ils ne sont.

Le coût est négligeable sur quatre glyphes et ne l'aurait pas été sur les 900
cellules du format précédent.

### Budget

| Expression | Cadence | Mesuré |
|---|---|---|
| pastille masquée | **0 Hz, 0 réveil** | — |
| `sleeping` | **0 Hz** (`TimelineView` en pause) | — |
| `idle` (breathe) | 8 Hz | **0,000 réveil inactif/s · 0,000 % CPU** |
| `working` (pulse) | 8 Hz | idem |
| `finished` / `failed` | 30 Hz, transitoire | impulsion, retour à 8 Hz |

App complète — sessions, buddy et compteur : **8,3 Mo de `phys_footprint`,
0,042 % de CPU, 0,000 réveil inactif/s.**

## 4. Alternatives Considered

Trois formats ont été écrits et mesurés, dans cet ordre. Les deux premiers
fonctionnaient à taille d'affiche et perdaient leur sens à la taille réelle.

### Béziers avec gréement d'œil — écarté

Chemins vectoriels `M`/`C`/`Z` plus un gréement paramétrique : rayon d'œil,
décalage du regard, courbure. Reconstruit depuis le logo tigreboite par
segmentation couleur et remesure de la géométrie — les yeux se sont révélés être
de **vrais cercles** (circularité 0,94, rayon 38, à ±100,6 de l'axe).

Écarté à l'usage : **une courbe rendue dans 20 pt est trois pixels gris
anticrénelés.** Coûts annexes : 13,9 Ko de manifeste, et un parseur de tracés
qui était une frontière de confiance à durcir.

### Grille de pixels — écarté

Un buddy devient une grille d'indices de palette. D'abord dérivée du vectoriel
par sous-échantillonnage, ce qui a échoué de façon mesurable : **à 28×18
cellules, la zone de l'œil fait trois cellules de côté**, et six réglages de
gréement s'y quantifient en marques identiques. En ajustant les paramètres,
`idle` et `working` se sont retrouvés à **2 cellules d'écart sur 504**.

Le pixel art se dessine, il ne se sous-échantillonne pas. Réécrit à la main —
d'abord des sprites d'yeux 4×3, puis un visage complet à 38×24, à la densité
d'une référence fournie. La paire la plus proche est passée de 8 à 112 cellules.

Écarté quand même : **38×24 affiché à 0,5 pt par cellule fait un pixel physique
par cellule** — techniquement net, pratiquement une bavure. Et l'écrire
demandait 900 caractères hexadécimaux et onze scripts Python pour les produire.

### Texte — retenu

Un glyphe monospace à 13 pt est la seule chose que macOS rend correctement à
cette taille, **parce que c'est exactement ce à quoi sert le hinting**.

Bénéfices annexes qui pèsent : `=^^=` se lit dans le manifeste, se relit dans
une revue, et se tape par quiconque veut son buddy. Le manifeste passe de 13,9 Ko
à 700 octets, et tout l'outillage d'authoring disparaît.

Le coût est réel et mérite d'être nommé : **pas de dégradés, pas de contrôle au
pixel, et le visage dépend de la police monospace installée.** Assumé.

### Retirer la silhouette — retenu au passage

Découvert pendant l'étape pixel et conservé : une tête de tigre dépensait la
majorité de ses cellules en un contour qui ne change jamais. Le visage seul —
deux yeux, une bouche — est aussi **large et bas comme la pastille**, là où une
tête est ronde.

## 5. Action plan

| # | Tâche | Statut | % |
|---|---|---|---|
| T1 | Schéma `BuddyManifest` v3 + `Codable` + validation stricte | **done** | **100** |
| T2 | `BuddyLoader` + repli sur le buddy intégré (manifeste absent, JSON illisible, schéma inconnu, visage vide, largeurs inégales, couleur invalide) | **done** | **100** |
| T3 | `MotionKind` : les 6 mouvements en fonctions pures `phase → transform` | **done** | **100** |
| T4 | `BuddyView` avec le `TimelineView` unique + halo | **done** | **100** |
| T5 | Branchement sur `AnimationBudget`, y compris `frameRate = 0` si masqué | **done** | **100** |
| T6 | Buddy intégré par défaut, écrit **comme manifeste** | **done** | **100** |
| T7 | **Manifeste tigreboite** — premier client externe du format | **done** | **100** |
| T8 | Mapping `BuddyExpression` ← état RFC-012, fonction pure + tests | **done** | **100** |
| T9 | `perfcheck.sh` A et B | **done** | **100** |
| T12 | Animation par images, rechargement à chaud, taille et couleur par expression | **done** | **100** |
| T10 | `perfcheck.sh` C (curseur en mouvement, panneau déployé) | todo | 0 |
| T11 | Taille et position dérivées du slot mesuré (`PillLayout`, RFC-002) | **done** | **100** |

**Critère de sortie — atteint le 2026-08-19.**

| Point | État |
|---|---|
| Expressions distinctes pour chaque état de RFC-012 | **PASS** — six visages, six mouvements |
| **Déposer un manifeste et relancer suffit à changer de buddy** | **PASS** — tigreboite est chargé depuis `~/Library/Application Support/notch-buddy/buddies/`, rien n'est compilé |
| Un manifeste corrompu retombe sur le buddy intégré sans planter | **PASS** — six modes de défaillance testés |
| Pastille masquée → 0 réveil imputable au buddy | **PASS** — 0,000 réveil inactif/s |
| Coût de l'app complète | **PASS** — 8,3 Mo, 0,042 % CPU |

### La validation qui compte

Elle refuse deux visages de **largeurs différentes**. Sans elle, la pastille se
redimensionnerait à chaque changement d'état — ce qui se lit comme une interface
qui tremble, pas comme un buddy qui s'exprime. C'est la contrainte que le format
texte introduit et que les deux formats précédents n'avaient pas.

## 6. Open Questions

Les questions Q1 (sous-ensemble de tracés), Q2 (à quoi ressemble le buddy) et
Q5 (six mouvements suffisent-ils) **n'ont plus d'objet** : elles portaient sur le
format vectoriel, puis pixel. Leur trace reste en §4, parce que c'est en y
répondant qu'on a découvert pourquoi ces formats ne tenaient pas.

**Q3 — Où vivent les manifestes ?** *Tranchée* :
`~/Library/Application Support/notch-buddy/buddies/<id>/manifest.json`, un
dossier par buddy, découverts au lancement.

**Q4 — Faut-il verrouiller un buddy par politique d'entreprise ?**
Si tigreboite déploie l'app à son équipe, veut-elle imposer le buddy ou le
proposer par défaut ? Ça change le modèle de préférences de RFC-010.

**Q6 — La dépendance à la police monospace installée est-elle acceptable ?**
`=^^=` rendu en SF Mono et en Menlo n'ont pas le même équilibre. Faut-il
embarquer une police, ou accepter la variation ?

```sh
# Voir le visage dans les polices monospace disponibles :
fc-list : family | grep -i mono | sort -u | head -20
```

**Q7 — Le halo doit-il être réglable ?**
Trois ombres codées en dur aujourd'hui. Sur un fond clair — pastille flottante
hors encoche — le halo pourrait être de trop.
