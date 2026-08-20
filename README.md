# vibebuddy

App macOS native qui transforme la notch du MacBook en tableau de bord de ses
agents de code. Swift, SwiftPM, macOS 14 minimum, aucune dépendance externe :
la stdlib et les frameworks Apple, rien d'autre.

## Ce que ça fait

Par ordre d'importance. Une fonctionnalité qui ne sert aucun de ces points est du
confort, et se juge comme tel.

1. Alerter sans qu'on regarde : quand l'agent a terminé, et quand il attend une
   réponse. Les deux se lisent dans le transcript, sans passer par un hook.
2. Montrer la consommation réelle, c'est-à-dire le pourcentage des limites 5 h et
   7 j tel qu'Anthropic le renvoie, pas une estimation à partir des jetons.
3. Suivre plusieurs sessions, chacune avec son état propre, groupées par projet.
   Un clic sur une ligne vivante ramène son onglet de terminal.
4. Le faire de façon ludique : un *buddy* animé porte l'état dans la notch.

## Installer et lancer

L'app n'est pas encore empaquetée, elle se lance depuis le dépôt. RFC-011 s'en
occupe.

```sh
swift build -c release
.build/release/VibeBuddy              # tourne jusqu'à Ctrl-C ou au bouton power
```

Les buddies vivent hors du binaire, dans
`~/Library/Application Support/vibebuddy/buddies/`. Pour éditer ceux du dépôt
en place :

```sh
mkdir -p ~/Library/Application\ Support/vibebuddy/buddies
ln -s "$PWD/assets/buddies/emoji.buddy" ~/Library/Application\ Support/vibebuddy/buddies/
```

Ils sont rechargés à l'enregistrement du fichier, sans relance ni recompilation.

## Diagnostic et mesure

`--info` est l'outil de premier recours : écrans, géométrie, cadres calculés,
budgets de réveil et d'animation, buddies installés avec leur cadence, langue,
parseur confronté aux vrais transcripts, sessions vivantes avec leur tty,
consommation, coût mémoire.

```sh
.build/release/VibeBuddy --info
.build/release/VibeBuddy --hover                  # zones de survol contre pixels réellement peints
.build/release/VibeBuddy --bench <mode> <secondes>
#   modes : shell · panel · pill · hidden · interaction · sessions · app
scripts/perfcheck.sh <scénario> <durée>            # A repos · B 3 sessions · C panneau ouvert
```

## Le format `.buddy`

Un buddy est de la donnée, pas du code : un fichier texte, éditable à la main ou
depuis les réglages de l'app.

```
font: Menlo                   # optionnel, système par défaut
size: 15                      # taille par défaut
speed: 1                      # images par seconde, 1 par défaut

idle (yellow #FFBB00) 17 3    # couleur, puis taille, puis vitesse (positionnel)
(ᵕ • ᴗ •)                     # une image par ligne
(„• ֊ •„)
                              # une ligne vide termine la section
```

Six expressions : `sleeping`, `idle`, `working`, `awaiting`, `finished`,
`failed`. Seule `idle` est obligatoire, les autres y retombent. Le mot de couleur
avant le code hexadécimal est décoratif, seul le `#RRGGBB` compte.

Deux formats ont précédé celui-ci, des béziers puis une grille de pixels. Ils
marchaient à taille d'affiche et perdaient leur sens à 20 pt.

## La contrainte qui gouverne

La légèreté prime sur les fonctionnalités. L'app est visible en permanence, donc
tout réveil inutile se paie en autonomie.

| Métrique | Cible | Mesuré |
|---|---|---|
| `phys_footprint` | < 40 Mo | 11,8 Mo (`--bench pill 10`) |
| Réveils inactifs au repos | < 2/s | 0,000/s (idem) |
| CPU au repos | < 0,5 % | 0,016 % (idem) |
| `fork`/`exec` au repos | 0 | 0 |

Mesures du 2026-08-20 sur la machine de développement, pastille affichée et
panneau fermé. À remesurer plutôt qu'à recopier, c'est la règle du dépôt.

Le nombre de réveils gouverne, pas le pourcentage de CPU : un process à 0,4 % de
CPU avec 70 réveils par seconde vide une batterie sans franchir aucun seuil
exprimé en pourcentage. D'où une seule horloge dans toute l'app
(`WakeCoordinator`), et un budget d'animation qui peut tomber à zéro image par
seconde.

## Tests

```sh
swift test        # 254 tests, 50 suites
```

Ils portent sur ce qui casse en silence : le parseur de transcripts, la machine à
états des alertes, la géométrie de la notch, le format `.buddy`, la fenêtre de
contexte, le calque d'édition des buddies et l'appariement des terminaux.

## Documentation

| Fichier | Contenu |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | Les règles : objectifs produit, décisions structurantes, Gantt, conventions |
| [`docs/hook.md`](docs/hook.md) | L'état réel et les pièges chèrement acquis, à lire en premier |
| [`docs/rfc/`](docs/rfc/) | Une RFC par sujet, avec son plan d'action et ses pourcentages |
| [`docs/perf/`](docs/perf/) | Les mesures, en CSV, datées |

## Inspiration

Inspiré par Notch-Pilot & VibeIsland sur la mécanique de récolte des données de Claude et son intégration en Swift.

Ce n'est pas un fork, mais une interprétation différente et libre.
