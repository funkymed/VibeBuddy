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

**La seconde est produit.** vibebuddy doit pouvoir porter le buddy d'une
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
| T13 | **Vitesse d'animation** : `speed:` global et par expression, en images/seconde | **done** | **100** |
| T14 | **Mise à l'échelle pour tenir dans la fente** : plafond de largeur, visage réduit plutôt que rogné | **done** | **100** |
| T15 | Mémoïsation des mesures, calculs hissés hors du corps du `TimelineView` | **done** | **100** |
| T11 | Taille et position dérivées du slot mesuré (`PillLayout`, RFC-002) | **done** | **100** |

**Critère de sortie — atteint le 2026-08-19.**

| Point | État |
|---|---|
| Expressions distinctes pour chaque état de RFC-012 | **PASS** — six visages, six mouvements |
| **Déposer un manifeste et relancer suffit à changer de buddy** | **PASS** — tigreboite est chargé depuis `~/Library/Application Support/vibebuddy/buddies/`, rien n'est compilé |
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
`~/Library/Application Support/vibebuddy/buddies/<id>/manifest.json`, un
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

## Notes d'implémentation

Arbitrages retirés du code le 2026-08-20 lors de la coupe des commentaires. Le
code ne garde que les mesures chiffrées et les avertissements de bug ; ce qui
suit explique *pourquoi*, pas *quoi*.

### `BuddyView` (type)

**Une seule horloge, et elle peut s'arrêter.** Un unique `TimelineView`, mis en
pause dès que le budget dit `still`. L'implémentation de référence disperse à la
place dix-huit appels `withAnimation(...).repeatForever` dans ses visages, chacun
installant un `CADisplayLink` qui n'est jamais démonté — ni quand la vue quitte
l'écran, ni quand la fenêtre se cache. `withAnimation` a l'air gratuit au point
d'appel, et c'est exactement pour ça que ça s'accumule. Ici l'horloge est
visible en un seul endroit et `AnimationBudget` possède sa cadence : caché
signifie cadence zéro, et zéro signifie pas d'horloge du tout.

**Pourquoi du texte.** Un glyphe monospace à 12 pt est la seule chose que macOS
rend nettement à cette taille, parce que le hinting existe précisément pour ça.
Les deux formats remplacés — béziers, puis grille de pixels — étaient dessinés à
la main à l'échelle d'une affiche et se résolvaient en tache dans une bande de
20 pt.

### `BuddyView.fit` / `BuddyView.fitScale`

L'oreille de la pastille est plafonnée (`PillLayout.maxSlotWidth`) et la hauteur
de l'encoche est fixée par le matériel : un manifeste qui demande 40 pt doit
céder quelque part. La mise à l'échelle est la seule option qui garde un visage
un visage — rogner coupe un kaomoji en deux, et un demi-kaomoji se lit comme un
défaut de rendu, pas comme une expression. Jamais au-dessus de 1 : un visage plus
petit que sa boîte est dessiné à sa taille. C'est l'image la plus large de
l'expression *courante* qui décide, pour que l'échelle tienne toute une animation
au lieu de pulser une fois par seconde.

### `BuddyView.tier`

Une expression animée a besoin d'une horloge même quand son mouvement est
`.none` : les images avancent à leur propre cadence. Le palier doit dépasser
cette cadence — un buddy qui demande douze images par seconde sur une horloge à
huit hertz perd une image sur trois, ce qui se lit comme un bégaiement, pas comme
de la vitesse.

### `BuddyView.reservedWidth`

Réservé par expression plutôt que sur tout le buddy : l'emplacement porte déjà le
maximum global, donc tout ce qui serait plus large ici ne ferait que payer deux
fois une marge que la mise en page a déjà comptée.

### `BuddyView.interval`

Le palier est un plafond, pas une cible. Un visage dont le mouvement est `.none`
ne change que lorsque son image change ; ticker au palier réveillerait la vue
huit fois pour redessiner les mêmes glyphes — tout l'intérêt de D3 est que
personne ne dépense des réveils dont il n'a pas l'usage. Ce qui bouge vraiment a
besoin de la cadence pleine, parce que sa transformation est continue en phase.

### `BuddyView.face(phase:)`

Trois ombres empilées plutôt qu'une : une seule ombre large se lit comme un flou,
tandis qu'un halo serré et vif par-dessus un halo large et sourd se lit comme
quelque chose qui émet de la lumière. La plus serrée est la même couleur à pleine
force — c'est elle qui fait paraître les traits plus épais et plus chauds qu'ils
ne sont. Les ombres sont bon marché ici : une poignée de glyphes, donc le flou
s'applique à quelques points et non à un bitmap.

### `PixelGrid` (BuddyView.swift)

**Grille, pas scanlines.** La première version ne traçait que des lignes
horizontales. C'est un tube cathodique — et ça se lisait exactement comme ça : des
rayures. Un afficheur à pixels est une *matrice*, donc la séparation doit courir
dans les deux sens ou l'œil n'assemble jamais les cellules en carrés.

**Masquée sur les glyphes.** Régler toute la pastille ne ferait que zébrer le
fond noir derrière le visage. Masquer sur le contenu fait chevaucher la grille
aux glyphes allumés, là où une vraie matrice montre sa structure.

**`lineWidth`** — un quart du pas garde la cellule nettement plus grande que sa
bordure ; au-delà d'environ un tiers, la grille cesse d'être une séparation et
devient le sujet.

### `PixelatedText` (type)

**Pourquoi ce détour par un bitmap.** Rien dans SwiftUI ne quantifie le texte.
`Canvas` rasterise *après* sa transformation, donc agrandir à l'intérieur produit
des glyphes lisses à la résolution finale ; `.drawingGroup()` rasterise à
l'échelle native. Les deux donnent un visage lisse plus gros, pas un visage plus
carré.

**Et pourquoi c'est quand même bon marché.** Rasteriser à chaque image serait du
gaspillage : le bitmap est mis en cache et reconstruit seulement quand le texte,
la couleur ou la taille changent — au plus une fois par seconde, puisque c'est la
cadence de l'animation. Le mouvement par-dessus (échelle, décalage) s'applique à
l'image en cache et ne coûte rien. Teinter le bitmap plutôt que d'y cuire la
couleur signifie qu'un changement de couleur ne coûte aucune rasterisation.

### `PillLayout` (type)

La pastille est centrée à l'écran et l'encoche aussi, ce qui rend la mise en page
naïve fausse dès que les oreilles diffèrent en largeur : centrer la *pastille*
décale l'emplacement du milieu de la moitié de la différence. Le correctif est de
décaler l'ensemble de `(droite - gauche) / 2`, ce que renvoie
`notchAlignmentOffset`.

**Pourquoi les largeurs sont mesurées plutôt que déclarées.** L'implémentation de
référence code en dur 56 pt pour son buddy et 84 pour son affichage de
consommation. Ça marche jusqu'à ce qu'un buddy ait un visage de cinq caractères,
ou qu'une taille de police change dans un manifeste — le contenu déborde alors
d'un emplacement dimensionné pour autre chose. Ici chaque emplacement est mesuré
sur ce qu'il contient réellement.

### `PillLayout.slotPadding`

Ramené de 10 à 6 quand les oreilles sont devenues symétriques : la symétrie
complète la plus étroite jusqu'à la plus large, donc la marge est désormais payée
deux fois du côté qui n'a rien à montrer. Six points dégagent encore l'encoche —
les glyphes n'atteignent jamais le bord — et la pastille cesse de paraître
gonflée.

### `PillLayout.maxSlotWidth`

Sans plafond, la pastille est définie par son contenu : un manifeste avec un long
visage à 40 pt — que l'éditeur d'expressions rend trivial à produire — fait une
pastille plus large que l'encoche de l'écran et transforme le tableau de bord en
bandeau. Au-delà, c'est le *buddy* qui cède, réduit à l'emplacement qu'on lui
donne (`BuddyView`, `fit:`).

### `PillLayout.resolve` — oreilles égales

Mesurer chaque oreille sur son propre contenu rendait la pastille bancale — un
buddy de quatre glyphes à gauche, `×2` à droite — et le correctif était alors de
décaler toute la pastille pour que son trou tombe encore sur l'encoche
(`notchAlignmentOffset`). Ça marche géométriquement et ça a l'air faux : l'encoche
est symétrique, et une forme qui dépasse davantage d'un côté se lit comme mal
alignée même quand elle est exactement alignée. Des oreilles égales coûtent
quelques points de largeur du côté le plus étroit et achètent une forme
symétrique par construction — l'offset vaut alors zéro, il n'est pas corrigé.

Une alerte prend l'oreille droite à la place du compteur : les deux disent la
même sorte de chose, et les empiler ferait grandir la pastille deux fois.

### `PillLayout.measure`

Mesuré via AppKit plutôt qu'estimé au nombre de caractères : une police monospace
a quand même des chasses propres à chaque fonte, et deviner produit un
emplacement soit rogné soit rembourré de quelques points sur toute machine ayant
un défaut différent.

### `BuddyFile` (type) — pourquoi pas JSON

Un buddy est une poignée de kaomoji. En JSON ils arrivent en échappements
`"\u{1D5D3}"` et en guillemets qui semblent déséquilibrés, et en éditer un revient
à compter des antislashs. Le format est ce que quelqu'un écrit quand on lui
demande de décrire un buddy sur une serviette en papier — d'où il vient
littéralement :

```
font: Menlo
size: 14
speed: 2          # images par seconde ; 1 par défaut

sleeping (blue #00BBFF)
ᓚ₍⑅^- .-^₎ -ᶻ 𝗓 𐰁
ᓚ₍⑅^- .-^₎ -𐰁 ᶻ 𝗓

working (green #55FF55) 17 4
(ᵕ • ᴗ •)
```

Une image par ligne, une seconde par image par défaut. Une ligne vide termine une
section. Le nom de couleur devant l'hexa est ignoré — il est là pour l'humain.

Les deux nombres de l'en-tête d'expression sont **positionnels** — taille
d'abord, vitesse ensuite — donc une expression qui ne veut qu'une autre vitesse
énonce quand même sa taille. Des suffixes nommés étaient l'alternative et
transforment un format de serviette en petit langage ; un en-tête avec deux
nombres se lit encore à voix haute.

Un `font` absent signifie la police système, ce qui est le bon défaut : elle
compose les replis glyphe par glyphe, et aucune famille installée seule ne couvre
les écritures rares dont ces visages sont faits.

Une valeur hors bornes tombe dans le rapport « ligne non comprise » plutôt que
d'être bornée : un fichier qui demande 200 images par seconde est une erreur, et
en dessiner silencieusement 30 la cache jusqu'à ce que quelqu'un se demande
pourquoi le buddy l'ignore. La vitesse accepte une décimale parce que « une demi-
image par seconde » se demande vraiment ; la taille non, parce qu'une taille de
corps fractionnaire ne se demande pas.

### `BuddyFile` — `MotionKind.default(for:)`

Ces visages s'animent en changeant d'image, donc le mouvement par-dessus est
volontairement retenu : un visage qui rebondit *et* défile se lit comme cassé,
pas comme vivant.

### `BuddyManifest` (type) — comment on en est arrivé là

Ça a commencé en chemins de Bézier avec un rig d'yeux, puis c'est devenu une
grille de pixels. Les deux marchaient à taille d'affiche et perdaient leur sens à
la taille qui compte. Le buddy se rend dans une bande d'environ 20 pt de haut : à
cette échelle une courbe fait trois pixels gris antialiasés, et une grille 38×24
affichée à 0,5 pt par cellule fait un pixel physique par cellule — techniquement
net, pratiquement une tache. Le texte est la seule chose que macOS rend bien à
11 pt, parce que c'est *à ça* que sert le hinting.

`=^^=` est aussi lisible dans le manifeste, diffable en revue, et tapable par
quiconque veut un buddy. Le format pixel demandait une chaîne hexa de 900
cellules et un outil pour l'écrire.

Le coût est réel et mérite d'être nommé : pas de dégradés, pas de contrôle au
pixel, et le visage dépend de la police installée. Accepté.

### `BuddyManifest.framesPerSecond` et les surcharges d'expression

Exprimé en cadence plutôt qu'en délai pour que « plus grand » veuille dire « plus
rapide », ce qu'attend quelqu'un qui écrit `speed: 4` dans un fichier texte. Le
moteur de rendu veut l'inverse et le calcule en un seul endroit.

Les surcharges par expression existent parce que ces visages diffèrent énormément
en densité : un chat qui dort en traînant des `zzz` et un clignement de quatre
glyphes ne veulent ni la même taille de corps pour peser pareil à l'écran, ni la
même cadence — un `zzz` qui s'éloigne veut être plus lent que le buddy auquel il
appartient, pas seulement plus court.

### `BuddyManifest.validate` — plus de contrôle de largeur

Il existait pour empêcher la pastille de changer de taille entre états, et c'était
la bonne règle pour des visages de quatre caractères. Ces expressions sont des
animations de largeurs très différentes, donc des largeurs égales ne sont plus ni
atteignables ni souhaitables. La mise en page résout le problème à la place, en
mesurant une fois l'image la plus large de toutes les expressions.

### `BuddyManifest.candidateFrames` — coût

Mesurer environ vingt-cinq chaînes courtes quand la mise en page se résout, ce qui
arrive sur un changement de géométrie ou d'état, pas à chaque image.

### `BuddyManifest.minimumFrameRate` / `maximumFrameRate`

Le plancher est une image toutes les vingt secondes — en dessous, une animation
est indiscernable d'un visage fixe et ne coûte qu'une horloge. Le plafond est le
palier `lively` : demander plus serait une cadence que le budget refuse de
dessiner, donc le fichier promettrait ce que le rendu ignore en silence.

### `BuiltInBuddy` (BuddyLoader.swift)

Écrit comme un manifeste plutôt que comme un cas particulier, pour que le format
soit exercé par le chemin par défaut à chaque lancement. Un format que seuls des
tiers utilisent est un format qui casse en silence.

### `BuddyOverrides` (type) — deux sources de vérité

D1 demande une source de vérité unique par fait, et cette couche l'enfreint
sciemment : ce à quoi ressemble un buddy vient maintenant d'un fichier *et* de
cette couche. L'arbitrage (2026-08-20) l'a accepté en échange de ne jamais écrire
dans un fichier que l'utilisateur maintient à la main — R1 est le même risque un
dossier plus loin.

L'atténuation est que la règle de précédence vit dans `apply(to:)` et nulle part
ailleurs. Aucune vue, aucun chargeur, aucun moteur de rendu n'a le droit de la
re-dériver.

L'échappatoire est `BuddyExportWriter`, qui aplatit couche et fichier en un
`.buddy` autonome. Sans lui une édition ne pourrait jamais être partagée, ce qui
fermerait en douce la direction « un buddy par entreprise » ; avec lui, le partage
devient délibéré au lieu d'impossible.

### `BuddyExportWriter` (type et `write`)

C'est le contrepoids au stockage des éditions dans les préférences. Ce qu'il écrit
est le fichier que l'éditeur *aurait* écrit : couche et fichier déjà fusionnés,
plus rien à réconcilier.

`overwrite` est explicite parce que la destination évidente d'un export est le
fichier d'où vient le buddy — et remplacer silencieusement un fichier écrit à la
main est exactement ce que la couche de préférences existe pour éviter.

### `MotionKind` (type) — vocabulaire fermé

Un manifeste **choisit** un mouvement ; il n'en décrit jamais un. C'est la ligne
qui garde ceci sûr et bon marché :

- **Sûr** — un manifeste est un fichier sur le disque. Lui laisser porter un
  script mettrait un évaluateur d'expressions tiers dans la boucle de rendu d'une
  app dont toute la prémisse est zéro réveil au repos.
- **Bon marché** — le budget d'animation est garantissable pour *n'importe quel*
  buddy, parce que chaque mouvement ici est une fonction pure de la phase, bornée
  par construction.

Les amplitudes restent petites délibérément : la hauteur de l'encoche est un
plafond dur, et un buddy qui déborde est rogné plutôt qu'expressif.

Le vocabulaire : `none` immobile (`sleeping`), `breathe` montée et descente lente,
`pulse` battement plus vif et plus fort, `dart` petits sauts du regard (deux
fréquences pour ne pas se lire comme un métronome), `bounce` ressort court amorti
pour les arrivées, `shake` frisson latéral bref amorti pour les échecs.
