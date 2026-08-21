# RFC-013 — Buddy interactif : regard, chasse, rire

| | |
|---|---|
| **Status** | **done (100 %)** — livré, jugé à l'œil et mesuré le 2026-08-21 |
| **Author** | Cyril Pereira |
| **Created** | 2026-08-21 |
| **Updated** | 2026-08-21 (soir) |
| **Phase** | 3 — Surface visible |
| **Depends on** | RFC-005 (format `.buddy`, rastérisation) · RFC-002 (fenêtre, survol) |
| **Related** | RFC-010 (préférences retirées) · RFC-011 (icône) · D3, D7 |
| **Blocks** | — |

> Fiche écrite **après** le code, le 2026-08-21. C'est une dette assumée, pas un
> usage : la fonctionnalité est née d'une conversation en aller-retour, chaque
> geste répondant à ce que l'écran venait de montrer. Elle est ici parce que le
> Gantt doit contenir toutes les RFC, et parce que les arbitrages ci-dessous se
> reperdraient sinon.

## 1. Context & Problem

Le buddy est le porteur de l'état (objectif produit n°4), mais il ne **répondait
à rien**. Son visage jouait une séquence tirée d'un hachage de l'indice du temps
— parfaitement lisible, et parfaitement indifférent à ce que fait l'utilisateur.

Or l'app est visible en permanence, dans l'encoche, à trente centimètres des
yeux. Un objet qui vit là et ne réagit jamais cesse d'être regardé. C'est du
confort au sens de la première section de `CLAUDE.md` — et le confort se juge
comme tel : il ne doit rien coûter au repos.

**La contrainte qui gouverne : le suivi du pointeur est le pire cas possible pour
le budget de réveils.** `HoverProbe` porte la mesure : `NSEvent.mouseLocation`
est un aller-retour au serveur de fenêtres, et le sonder à 10 Hz a mesuré
**6,3 réveils/s** contre un budget de 2. Suivre un regard demande trois fois
cette cadence.

## 2. Goals / Non-goals

**Goals.** Un buddy qui suit le pointeur du regard, s'étonne, se laisse
distraire, et rit quand on le secoue ou qu'on le clique — **à zéro réveil au
repos**. Un vocabulaire fermé d'humeurs, comme les formes et les regards du
format `.buddy`.

**Non-goals.** Le son. Les raccourcis clavier (aucune API Accessibilité en v1).
Un buddy qui réagit au contenu des sessions — c'est RFC-012, et elle est faite.

## 3. Proposed Solution

### Le coût d'abord

**Un moniteur d'événements, jamais un sondage.** `NSEvent.addGlobalMonitorForEvents`
plus son pendant local, muets tant que la souris ne bouge pas. Le coût s'inverse :
zéro au repos — le cas pour lequel le budget est écrit — et il ne se paie que
pendant que l'utilisateur bouge déjà sa souris, donc que la machine est déjà
réveillée. Plafonné à 30 Hz, au-delà duquel le travail est jeté.

Aucune permission Accessibilité : elle n'est requise que pour les moniteurs
**clavier**. La règle « aucune API AX en v1 » tient.

**Aucune horloge nouvelle** (décision D3). L'humeur est lue par `BuddyView` sur
le `TimelineView` qu'il fait déjà tourner. D'où la restriction : seuls les
visages qui portent déjà une horloge réagissent — `sleeping` n'en a pas par
construction, et un regard qu'aucune horloge ne dessine est un regard immobile.

### Les humeurs

`PointerMood`, vocabulaire fermé :

| Humeur | Déclencheur | Rendu |
|---|---|---|
| `resting` | rien | le cycle du manifeste, intact |
| `startled` | 0,35 s de mouvement délibéré | yeux écarquillés, penché en avant, **le regard s'arrête** |
| `following` | après l'étonnement | suit le pointeur, arrivée amortie, frémissement de 4 % |
| `chasing` | une **secousse** | rose `#FF5FA2`, yeux de `finished`, à sa portée tout de suite |
| `amused` | clic, ou secousse pendant une chasse | `^^`, trois sauts |

**Le regard est une zone, pas un vecteur.** Neuf zones lues sur l'écran :

| | gauche (< ⅓) | centre | droite (> ⅔) |
|---|---|---|---|
| haut, < 25 % | par-dessus l'épaule | vers le haut | par-dessus l'épaule |
| milieu | à gauche | droit devant | à droite |
| bas, > 50 % | en bas à gauche | en bas | en bas à droite |

La rastérisation quantifie déjà le regard en cellules entières — `EyeRaster` note
que « le regard est à l'une de cinq places ». Lui donner une direction continue
n'achète qu'une valeur qui arrondit vers la même cellule sur un tiers de l'écran.
En bandes, la règle se dit, et le visage se lit : on peut voir où le buddy croit
qu'on est.

Le regard par-dessus l'épaule reprend **exactement** les proportions de
`EyeBeat.overLeft` (0,75 de côté, 0,8 vers le haut, `roll` complet) : un coup
d'œil au curseur et un coup d'œil au hasard sont le même geste.

### Ce qu'une secousse est

Rapide, répétée **et** large — les trois : 5 virages, chacun après au moins
24 pt de course, dans une fenêtre de 0,6 s. La première version demandait trois
virages sans amplitude : viser un bouton et le dépasser en fait deux ou trois, et
le buddy riait de quelqu'un qui se sert de sa souris.

### Un seul chemin par comportement

- Le rire a plusieurs entrées — clic dans la pastille, clic dans le panneau,
  secousse pendant une chasse — et **une seule fonction**, `amuse(at:)`.
- Le clic a deux chemins de détection, parce que deux choses différentes
  possèdent le clic selon l'état : repliée, la fenêtre l'absorbe et
  `NotchPanel.mouseUp` l'attrape ; dépliée, SwiftUI possède le hit-testing et la
  fenêtre n'en entend jamais parler. Les deux appellent `amuse()`, et l'appeler
  deux fois revient à l'appeler une fois.

### Ce que la fonctionnalité a emporté avec elle

- **Deux préférences supprimées** — le grain des pixels et la taille du buddy.
  Fixées à 3 et 100 %, jugées à l'œil. Une préférence dont on connaît la bonne
  valeur est un moyen de se tromper.
- **`BuddyManifest.scaled(_:)` supprimée.** Elle multipliait la planche et les
  poses : à une autre taille, le visage tombe sur un autre nombre de cellules, et
  les yeux changeaient de **forme** au lieu de changer de taille.
- **L'icône de l'app** est devenue le regard du buddy : un rond bleu et un carré
  vert, rasterisés par la même règle que le visage.

## 4. Alternatives Considered

**Sonder `NSEvent.mouseLocation` sur le tick existant.** Écarté : c'est
précisément ce que `HoverProbe` a mesuré à 6,3 réveils/s, et il faudrait trois
fois sa cadence.

**Ne réagir que quand le pointeur survole la pastille.** Gratuit — les événements
sont déjà livrés — mais la pastille fait 68 pt de large : le buddy ne verrait
jamais venir personne.

**Un vecteur de direction continu.** Écarté, voir « le regard est une zone ».

**Re-mettre le manifeste à l'échelle pour la chasse.** Écarté pour la raison qui
a tué `scaled(_:)` : les cellules changent, donc la forme change.

**Le mode chase réservé à `working`.** C'était la première version. Deux sens
pour un même geste selon le visage porté est un geste que personne ne peut
prévoir. La secousse veut dire la même chose partout.

## 5. Action plan

| # | Tâche | Statut | % |
|---|---|---|---|
| T1 | `PointerGazeState` : machine à humeurs pure, testée sans run loop ni serveur de fenêtres | **done** | **100** |
| T2 | `PointerMonitor` : moniteurs global et local, plafond 30 Hz, zéro réveil au repos | **done** | **100** |
| T3 | Les neuf zones de regard, bandes lues sur l'écran porteur | **done** | **100** |
| T4 | Étonnement puis suivi, avec le délai avant de capter | **done** | **100** |
| T5 | Détection de secousse : rapide, répétée **et** large | **done** | **100** |
| T6 | Mode chase : rose, yeux de `finished`, transition de couleur montante et descendante | **done** | **100** |
| T7 | Rire : `^^`, clic et secousse en chasse, un seul `amuse(at:)` | **done** | **100** |
| T8 | `EyeRaster.drawableRadius` — un œil rond de quatre cellules est un losange | **done** | **100** |
| T9 | Icône de l'app tirée du regard | **done** | **100** |
| T10 | `perfcheck` A et C : vérifier le **zéro réveil au repos** et le coût pendant une chasse | **done** | **100** |
| T11 | Jugement à l'œil : vivacité de la chasse, durée du rire, teinte | **done** | **100** — jugé et ajusté en séance le 2026-08-21 |

**Critère de sortie.** `perfcheck A` inchangé par rapport à la mesure d'avant la
RFC — **0 réveil, 0 `fork`** — pointeur immobile. Scénario C avec la souris en
mouvement : la régression reste sous 10 %.

### Les mesures de clôture, 2026-08-21

| Scénario | Fichier | Durée | Footprint | CPU | Réveils | `fork` |
|---|---|---|---|---|---|---|
| **A** repos | `20260821-2148-013-A.csv` | 465 s | 15,0 Mo | 0,000 % | **0,000 /s** | 0 |
| **C** interaction | `20260821-2146-013-C.csv` | 84 s | 11,0 Mo | 0,000 % | 0,000 /s | — |

**Le pari du moniteur d'événements est tenu** : suivre le pointeur, chasser et
rire n'ajoutent **rien** au repos. C'était la condition posée en §3 — un
sondage aurait coûté les 6,3 réveils/s que `HoverProbe` a mesurés à 10 Hz.

Le run A s'est arrêté à 465 s au lieu de 600. Il est retenu parce que son
verdict **concorde** avec les deux autres mesures de la même soirée — 594 s à
0,249/s pour RFC-004, et le scénario C à 0,000/s — au lieu de les contredire
comme les runs jetés plus tôt (0,000 puis 4,475 sur des durées tronquées).

### Ce que le jugement à l'œil a changé, en séance

Rien de ce qui suit n'était dans la fiche d'origine ; tout vient de regarder
l'écran et de corriger :

- **Grain 3 et taille 100 %**, tranchés à l'œil, puis les deux réglages
  **supprimés** — une préférence dont on connaît la bonne valeur est un moyen de
  se tromper.
- **Le losange** : un œil rond de quatre cellules *est* un losange, d'où
  `EyeRaster.drawableRadius`.
- **La secousse durcie** — 3 virages devenaient 5, plus une amplitude de 24 pt :
  le buddy riait de quelqu'un qui vise un bouton.
- **La chasse** prend les yeux de `finished` et une transition de couleur, parce
  qu'un œil plissé qui poursuit une souris lit comme de l'agacement.
- **Le buddy voyageur** : une seule instance qui glisse entre ses deux sièges,
  au lieu de disparaître huit images à l'ouverture du panneau.

## 6. Open Questions

**Q1 — Un clic doit-il réveiller un buddy endormi ?** Aujourd'hui `sleeping` ne
réagit à rien, parce qu'il ne porte aucune horloge (c'est ce qui tient le
scénario A à zéro). Lui en donner une le temps d'un rire est faisable ; le coût
est un réveil par clic, pas plus.

**Q2 — Le chase doit-il survivre à un changement d'expression ?** Si une session
se termine pendant une poursuite, l'expression passe à `finished` et la chasse
continue — c'est ce que fait le code, ça n'a pas été jugé à l'écran.

```sh
# Voir les six visages et la séquence de leurs temps
VIBEBUDDY_FACE=idle .build/release/VibeBuddy --info

# Mesurer le repos, pointeur immobile : le chiffre qui décide
scripts/perfcheck.sh A 600
```
