# Analyse — « Refonte UI premium » et la maquette

Lecture du 2026-08-22, contre le code à l'instant, pas contre les fiches.

## Périmètre — arbitrage du 2026-08-22

**Rien de ce qui touche au buddy ne se fait.** Ni halo d'état, ni glow autour de
lui, ni animation nouvelle, ni retouche du visage ou de ses expressions. Il reste
exactement ce que RFC-005 et RFC-013 ont livré, et son siège dans le header reste
réservé comme aujourd'hui.

Sont donc hors périmètre : la section 4 en entier, la phrase de la direction
artistique qui fait du buddy « la principale source de lumière », le buddy dans
la liste des porteurs de glow (section 3), sa ligne dans la sémantique d'état
(section 16), et « le Buddy peut avoir les animations les plus expressives »
(section 21).

**Ce que cet arbitrage change vraiment.** Le seul glow que je jugeais tenable
sans nouvelle mesure était le halo du buddy — un seul, prévu par le format
`.buddy`, sur un élément qui porte déjà son horloge. Il tombe. Ce qui reste est
le glow sur les boutons, les anneaux et les cartes : c'est-à-dire la partie qui
n'a **jamais** été mesurée sur ce produit, appliquée à des vues qui, elles, sont
statiques aujourd'hui.

Autrement dit, retirer le buddy du périmètre **augmente** le risque de la
section 3 au lieu de le réduire. La contrepartie est nette : plus aucun risque de
régression sur le visage, qui est ce qui coûte le plus cher à réparer.

## Ce que le document a de juste

**Il ne demande rien d'inventé.** C'est sa qualité principale et elle n'allait
pas de soi : chaque donnée de la maquette existe déjà dans `AgentSession` —
`73 %` est `contextFraction`, `high` est `effort`, `auto`/`default` est
`permissionMode`, `opus 5` est `model`, `depuis 6h46` se calcule depuis
`startedAt`, les pastilles de consommation sont `UsageBar`. Aucun chiffre de
remplacement, ce qui est la faute que ce dépôt refuse en premier.

**Le buddy est protégé explicitement**, avec la bonne raison : c'est un élément
d'interface vivant, pas un hero. Le document interdit de le remplacer. C'est
exactement l'arbitrage de RFC-005 et RFC-013.

**Le design system est à moitié écrit.** Le document parle de le « créer » ; il
existe déjà, sous d'autres noms, et il porte ses raisons :

| Le document demande | Existe déjà |
|---|---|
| `VibeColors` | `PanelInk` — six niveaux qui ont remplacé 22 valeurs d'opacité |
| couleurs d'état | `SessionStateStyle` — une table, pas des couleurs en ligne |
| couleurs sémantiques du panneau | `PermissionInk` — rouge/vert à 0,85, saturés ils vibrent sur le noir |
| `VibeSpacing` / métriques | `PanelMetrics`, `PillLayout` |
| surface et bordure | `PanelInk.surface` / `.stroke` |

Le travail réel est donc de **compléter et renommer**, pas de créer. Un
`DesignSystem/` neuf à côté de ceux-là ferait deux tables de couleurs, ce que
`PanelInk` existe précisément pour éviter.

## Les trois conflits durs

### 1. Le glow, contre trois mesures déjà payées

Le document demande inner glow **et** outer glow sur les boutons, les anneaux,
le buddy, plus un halo d'état. Ce dépôt a mesuré ce que ça coûte :

| Ce qui a été essayé | Coût mesuré | Après correction |
|---|---|---|
| Trois ombres empilées sur le visage | **38 Mo, 5,4 réveils/s** | une seule : 23 Mo, 0,2 |
| Trois dégradés dans un corps de vue qui dépend de la phase | **127 Mo** | sortis de la phase : 37 |
| `ImageRenderer` pour douze glyphes | **101 Mo** contre 40 de budget | `NSBitmapImageRep` : 21 |

Le budget est **40 Mo de `phys_footprint`**, l'app en mesure 15. Un glow par
composant est la troisième version de la même faute : un pipeline de rendu qu'on
n'a pas demandé. Ce n'est pas un refus du glow — c'en est le prix, et il se paie
en le mesurant à chaque étape, pas à la fin.

**Ce qui est tenable, le buddy étant hors périmètre :** un glow **statique** sur
l'action principale, et rien d'autre tant qu'un `make perf` n'a pas dit ce que ça
coûte. Ce qui ne l'est pas sans mesure : un glow sur chaque carte de session et
chaque anneau — c'est-à-dire sur les éléments les plus nombreux de l'écran.

### 2. « Le glow peut respirer » — l'animation permanente

C'est exactement ce que RFC-007 interdit dans sa section 2, et pour une raison
qui a un nom : la référence faisait pulser un texte à 20 Hz **pendant tout le
temps où l'utilisateur réfléchit à une permission**. Le moment le plus cher à
animer est celui où rien ne se passe.

La métrique gouvernante du projet est le **nombre de réveils inactifs**, pas le
%CPU : 0,4 % de CPU avec 70 réveils/s vide une batterie sans franchir aucun
seuil. Un glow qui respire est une horloge permanente, et D3 dit qu'il n'y a
qu'un `WakeCoordinator` — un `Timer` créé ailleurs est un échec de revue.

**Ce qui est tenable :** une transition **au changement d'état**, courte, qui
s'arrête. Pas de respiration.

### 3. La maquette empile ce que le panneau montre en alternance

L'image montre, dans une seule fenêtre : autorisation **+** deux cartes de
session **+** consommation. Aujourd'hui c'est exclusif — une demande occupe le
panneau, les sessions occupent le panneau, jamais les deux.

Empilé, ce panneau mesure ~900 pt de haut. Le plafond actuel est **460**, et il
n'est pas arbitraire : c'est ce qui tient sous une encoche. La maquette contredit
donc la section 22 du document lui-même (« espace extrêmement compact », « ne
jamais considérer l'écran comme une fenêtre desktop »).

**C'est la décision la plus lourde du document, et elle est fonctionnelle, pas
esthétique.** Trois issues :

1. **Garder l'alternance** — la maquette sert de référence de style, pas de
   structure.
2. **Empiler et scroller** — un seul panneau à 460 dont le corps défile. Le
   mécanisme existe depuis aujourd'hui.
3. **Empiler et grandir** — abandonner le plafond. À écarter : le panneau
   couvrirait la moitié de l'écran pendant qu'on répond à une question.

## Les incohérences internes du document

- **Section 2 contre section 16.** `working #55FF55` (vert) d'un côté ;
  « Running : accent bleu/cyan » de l'autre. Le code dit vert
  (`SessionStateStyle`). Il faut une seule table, et elle existe.
- **`sleeping` et `awaiting` reçoivent la même couleur** (`#00BBFF`), alors que
  ce sont les deux états qu'il importe le plus de distinguer : l'un dort, l'autre
  **attend une réponse** — c'est l'objectif n°1 du produit.
- **`idle → orange` (section 4) contre `finished → orange` (section 2).** Deux
  états, une couleur. Le manifeste `eve` donne déjà `idle` en ambre.
- **`ViewThatFits` recommandé** : il instancie chaque variante pour choisir. À
  n'employer qu'en connaissance de ce coût.
- **`.black` déconseillé** : sur ce produit c'est faux. Le panneau est dessiné
  dans le **trou physique** de la dalle. Le noir n'y est pas une couleur de
  fond, c'est l'absence d'écran, et c'est ce qui fait que la fenêtre disparaît
  dans l'encoche. `#050608` sur les bords de l'encoche se verrait.

## Ce qui manque au document

- **Le contraste.** `PanelInk.tertiary` est à 0,35 d'opacité ; le document veut
  des informations « plus discrètes » encore. Il n'y a aucun seuil énoncé.
- **`accessibilityDisplayShouldReduceMotion`**, déjà respecté par le code, n'est
  pas mentionné alors que la section 21 ajoute des animations.
- **D2 — aucune vue au-dessus de 200 lignes.** La refonte ajoute des composants ;
  la règle existe pour que ça reste vrai. `NotchShellView` est déjà à 274.
- **Ce que le panneau ne doit pas afficher.** La règle du dépôt est qu'un panneau
  ne montre que ce qui est vrai : pas de heatmap tant que RFC-009 n'existe pas.

## Recommandation

**Faire l'ordre du document, pas son ampleur.** Ses douze étapes (section 26)
sont justes ; ce qui doit changer est le critère d'arrêt de chacune.

1. **Tokens d'abord** — étendre `PanelInk` en `VibeTheme` sans créer de seconde
   table. Renommage et complétion, un seul endroit par fait.
2. **Palette d'états — trancher les trois contradictions ci-dessus**, dans
   `SessionStateStyle`, avant de toucher une seule vue.
3. **Composants** — `VibeBadge`, `VibeActionButton`, `VibeUsageMeter`,
   `VibeSessionCard`. C'est la partie la plus sûre et la plus rentable : elle ne
   coûte rien au repos et supprime des valeurs dispersées.
4. **Glow, en dernier, et mesuré** — `make perf` scénario A **avant et après**.
   Une régression de plus de 10 % sur n'importe quelle métrique bloque, c'est la
   règle du dépôt. Le buddy étant hors périmètre, commencer par **un seul**
   élément — l'action principale du panneau de permission — et mesurer avant
   d'en équiper un deuxième.
5. **La structure empilée** — à trancher explicitement, en connaissance du
   plafond de 460.

**À ne pas faire :** la réécriture des vues en une passe. Cinq défauts trouvés
le 2026-08-21 en pilotant un vrai Claude Code étaient invisibles aux 458 tests ;
une refonte simultanée de toutes les vues rend ce genre de bug impossible à
attribuer.
