# RFC-015 — Le son du buddy

| | |
|---|---|
| **Status** | **todo (0 %)** — ouverte le 2026-08-21 |
| **Author** | Cyril Pereira |
| **Created** | 2026-08-21 |
| **Updated** | 2026-08-21 |
| **Phase** | 3 — Surface visible |
| **Depends on** | RFC-005 (format `.buddy`, le buddy est de la donnée) · RFC-012 (`AlertBus`, `AlertPolicy`) |
| **Related** | RFC-010 (préférences) · RFC-013 (interactions) · RFC-014 (célébration) · D3, D7 |
| **Blocks** | — |

## 1. Context & Problem

Le buddy a un visage, six expressions, un regard qui suit la souris, un rire et
une poursuite. Il n'a **aucune voix**. Or le son est ce qui fait qu'un
personnage habite un écran plutôt que de l'occuper — et c'est aussi, dans une
app visible en permanence, la chose la plus facile à rendre insupportable.

Deux précédents du dépôt cadrent la fiche avant même de commencer :

- **`VoiceAnnouncer` est off par défaut, et pour une raison mesurée** :
  `AVSpeechSynthesizer` alloue un moteur audio de plusieurs mégaoctets à la
  première utilisation (`AlertRenderers.swift`). Tout ce qui touche à l'audio
  dans cette app se juge d'abord à ce qu'il coûte quand on ne s'en sert pas.
- **Le buddy est de la donnée, pas du code** (`CLAUDE.md`, « Direction, au-delà
  du v1 »). Un manifeste `.buddy` se recharge à l'enregistrement, sans
  recompilation. Les sons doivent suivre la même règle, ou chaque nouveau son
  sera une version de l'app.

## 2. Goals / Non-goals

**Goals.** Un **paquet de sons** rechargeable à chaud, adressé par nom
d'événement, que l'utilisateur remplit lui-même. Le buddy sonne quand il finit,
quand il rate, quand il attend, quand on le clique, quand il rit. Un réglage
unique pour tout couper, et un volume.

**Non-goals.** La parole (RFC-010 a déjà `VoiceAnnouncer`). La musique de fond —
un son qui dure est un son qu'on entend deux fois. Le son en pleine session de
travail sans que rien ne se soit passé : le buddy ne parle pas tout seul.

**Interdit.**
- **Aucun moteur audio instancié tant qu'aucun son n'a joué**, et aucun maintenu
  en vie au repos. Le budget est `phys_footprint < 40 Mo` et **0 réveil**.
- **Rien qui boucle.** Un son se déclenche sur un événement, se termine, et
  n'est plus rien.
- **Off par défaut.** Le son est la chose qu'une app toujours visible peut faire
  de plus agaçant.

## 3. Proposed Solution

### Le paquet de sons

Un dossier à côté des buddies, même mécanique de rechargement à chaud
(`ProjectsWatcher` sait déjà surveiller un dossier — RFC-005 le fait pour
`buddies/`, en résolvant les liens symboliques) :

```
~/Library/Application Support/VibeBuddy/sounds/

  # ── Événements : rares, ils peuvent sonner à chaque fois ──
    finished.wav        # l'agent a terminé son tour
    failed.wav          # le tour s'est terminé en erreur
    alert.wav           # une alerte quelconque
    question.wav        # il attend une réponse
    joyful.wav          # la célébration             (RFC-014)
    laugh.wav           # on l'a secoué, ou cliqué   (RFC-013)
    poke.wav            # on a cliqué sur le buddy   (RFC-013)
    chase.wav           # la poursuite démarre       (RFC-013)

  # ── Ambiance : fréquents, ils sonnent RAREMENT (voir plus bas) ──
    glance.wav          # un regard part sur le côté
    curious.wav         # un étonnement, un coup d'œil par-dessus l'épaule
    blink.wav           # un clignement
    move.wav            # une avancée ou un recul
```

**Le nom du fichier est le contrat**, comme `idle` ou `working` le sont dans un
`.buddy`. Pas de manifeste à écrire, pas de format à apprendre : déposer
`finished.wav` suffit. Un nom inconnu est ignoré, un nom manquant ne joue rien —
un paquet incomplet doit marcher.

### Deux étages, et c'est la décision qui porte la fiche

Un regard de côté arrive **plusieurs fois par minute** : le manifeste `eve`
tient un temps de 1,6 s en `idle`, et `dart` va deux fois plus vite. Un son à
chaque mouvement n'est pas un buddy vivant, c'est un métronome — et la première
version de cette fiche dit déjà pourquoi le son au survol était écarté d'avance.

| Étage | Ce qui déclenche | Cadence |
|---|---|---|
| **Événement** | fin, échec, alerte, question, rire, célébration, poursuite | à chaque fois, sous `AlertPolicy` |
| **Ambiance** | regard de côté, étonnement, clignement, avancée | **au plus un toutes les 20 s**, et seulement une fois sur cinq |

L'étage ambiance est tiré du **même hachage que la séquence des yeux**
(RFC-005) : la décision de sonner appartient au temps lui-même, donc à phase
égale, image égale, son égal. Rien à mémoriser, aucun `Task`, aucune horloge —
et surtout, le son tombe **exactement** sur le mouvement qu'il commente, pas
une image après.

Les sons d'ambiance sont des **ticks**, pas des sons : quelques dizaines de
millisecondes, très bas. À ce volume et à cette cadence, ils passent du statut
de bruit à celui de présence — c'est tout l'objet de l'étage.

**Deux réglages, pas un** : couper l'ambiance sans couper les événements doit
être possible. C'est le premier réglage que quelqu'un cherchera.

**Formats acceptés : `wav`, `aiff`, `caf`, `m4a`, `mp3`.** Recommandé : WAV ou
CAF courts. Un MP3 se décode avant de sortir, ce qui met un délai entre
l'événement et le son — et un son en retard sur ce qu'il commente est pire que
pas de son.

### Ce qui joue, et ce que ça coûte

`NSSound` plutôt qu'`AVAudioEngine` : pas de graphe à monter, pas de moteur à
tenir en vie, et il libère ses ressources quand le son se termine. Le coût à
mesurer est celui de la **première** lecture — c'est là que le daemon audio du
système se réveille — et le retour à zéro après.

**Un son n'est jamais joué sans passer par `AlertPolicy`.** Elle dédoublonne
déjà (fenêtre de 60 s) et impose un écart minimum de 12 s entre deux alertes ;
la même barrière protège les oreilles. Trois sessions qui finissent ensemble
font **un** son, pas trois.

**Le silence hérite de `quietWhenFrontmost`.** Si le terminal de la session est
déjà devant, l'utilisateur regarde — il n'a pas besoin qu'on le lui dise tout
haut.

### Les réglages

Deux, dans la section Notifications qui existe déjà :

| Réglage | Défaut |
|---|---|
| `sound` — les événements | **off** |
| `soundAmbience` — regards, clignements, mouvements | **off**, et grisé tant que `sound` est off |
| `soundVolume` | 0,6 |

Pas de réglage par événement. Le découpage par genre existe déjà
(`onFinished`, `onFailed`, `onNeedsAttention`) et le son s'y plie : couper les
alertes d'échec coupe aussi leur son. Un second tableau de cases à cocher pour
la même chose serait deux endroits où se contredire.

## 4. Alternatives Considered

**Embarquer les sons dans le bundle.** Écarté pour la raison qui a fait sortir
la police de l'icône : le dépôt n'a aucun asset binaire, et surtout chaque
nouveau son deviendrait une version de l'app. Un paquet dans Application Support
se remplit sans recompiler.

**Un manifeste `.sounds` qui déclare les liaisons.** Écarté : le nom du fichier
dit déjà tout, et un format de plus est une chose de plus à apprendre pour
déposer un `wav`.

**`AVAudioEngine` avec un graphe pré-monté.** Le plus rapide à déclencher, et le
plus cher au repos — un graphe vivant est exactement ce que la contrainte
directrice interdit. À reconsidérer **seulement** si la mesure montre une
latence perceptible avec `NSSound`.

**`NSSound(named:)` sur les sons système.** Gratuit et instantané, mais ce sont
les sons de tout le monde : le buddy sonnerait comme une alerte de Finder.

**Un son au survol.** Écarté d'avance : le survol arrive des dizaines de fois
par jour, et un son entendu dix fois par jour est un son qu'on désactive.

## 5. Action plan

| # | Tâche | Statut | % |
|---|---|---|---|
| T1 | `SoundPack` : lecture du dossier, correspondance nom → fichier, formats acceptés | todo | 0 |
| T2 | `BuddyVoice` : jouer, couper, volume ; **rien d'instancié avant le premier son** | todo | 0 |
| T3 | Rechargement à chaud du dossier, sur le veilleur existant | todo | 0 |
| T4 | Branchement sur `AlertBus` : `finished`, `failed`, `awaiting`, via `AlertPolicy` | todo | 0 |
| T5 | Branchement sur les interactions de RFC-013 : `poke`, `laugh`, `chase` | todo | 0 |
| T5b | **Étage ambiance** : `glance`, `curious`, `blink`, `move`, tirés du hachage des temps | todo | 0 |
| T6 | Réglages `sound` et `soundVolume` dans la section Notifications | todo | 0 |
| T7 | `--play <nom>` pour entendre un son du paquet sans provoquer l'événement | todo | 0 |
| T8 | Un paquet d'exemple documenté dans `assets/sounds/README.md` (le mode d'emploi, pas les fichiers) | todo | 0 |
| T9 | `perfcheck` A : **0 réveil et retour au budget mémoire** une fois le son fini | todo | 0 |

**Critère de sortie.** Déposer un `finished.wav` dans le dossier le rend audible
**sans relancer l'app**. Trois sessions qui finissent en même temps font un seul
son. Son coupé : `perfcheck A` identique à la mesure d'avant la RFC — aucun
moteur audio n'a jamais été construit. Son actif puis silence de dix minutes :
retour à **0 réveil**.

## 6. Open Questions

**Q1 — Un son doit-il accompagner un mouvement plutôt qu'un événement ?**
**Tranchée le 2026-08-21 : oui, mais dans un étage à part.** Voir « Deux
étages » — au plus un son d'ambiance toutes les 20 s, une fois sur cinq, tiré du
hachage des temps. Ce qui reste à trancher **à l'oreille** est la cadence : un
sur cinq et 20 s sont un point de départ, pas une mesure.

**Q2 — Faut-il varier ?** Deux ou trois `finished-1.wav`, `finished-2.wav` tirés
au hasard usent moins vite qu'un seul son entendu vingt fois par jour. Coût :
une convention de nommage de plus.

**Q3 — Le volume suit-il celui du système ou est-il indépendant ?**
`NSSound.volume` est relatif au volume de sortie. Un réglage indépendant permet
un buddy discret sur une machine forte ; c'est aussi un réglage de plus.

```sh
# Entendre un son du paquet sans attendre l'événement (T7)
.build/release/VibeBuddy --play finished

# Le chiffre qui décide : rien ne doit survivre au son
scripts/perfcheck.sh A 600
```
