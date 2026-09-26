# RFC-014 — L'excroissance d'alerte sous l'encoche

| | |
|---|---|
| **Status** | **in-progress (85 %)** — validée et codée le 2026-09-26 ; restent le jugement à l'œil et la mesure (T8) |
| **Author** | Cyril Pereira |
| **Created** | 2026-08-21 |
| **Updated** | 2026-09-26 |
| **Phase** | 3 — Surface visible |
| **Depends on** | RFC-012 (`AlertBus`, `SessionAlert`) · RFC-002 (fenêtre, géométrie) · RFC-005 (rastérisation des yeux) |
| **Related** | RFC-008 (saut vers le terminal) · RFC-013 (buddy interactif) · D3, D7, D8 |
| **Blocks** | — |

> **Réécrite le 2026-09-26.** La première version — un mini-panneau 320×130 avec
> un pouce et des confettis, trois secondes — est abandonnée. Elle ne traitait
> que la fin réussie, disparaissait avant qu'on la voie, et ajoutait une
> récompense là où manquait d'abord une alerte lisible.

## 1. Context & Problem

Une alerte s'affiche aujourd'hui **dans l'oreille droite de la pastille fermée** :
`NotchPanel.present(_:for:)` (`Sources/VibeBuddy/NotchPanel.swift:789`) passe la
pastille en `.speech`, y écrit un message, et la referme au bout de **4 s**.

Trois défauts :

1. **C'est laid**, de l'aveu de l'utilisateur. Un message dans une oreille
   plafonnée à 96 pt (`PillLayout.maxSlotWidth`), élargie à 168 pour l'occasion,
   collé contre le matériel.
2. **Trois événements, une seule forme.** Fin réussie, échec et attente d'une
   réponse ont le même rendu : un mot dans une oreille.
3. **Quatre secondes contredisent l'objectif n°1** — « être alerté sans
   regarder ». Qui ne regarde pas à ce moment-là ne voit rien, et c'est
   précisément le cas visé.

Accessoirement, la fermeture repose sur un `DispatchQueue.main.asyncAfter` : une
horloge hors du `WakeCoordinator`, que D3 interdit.

## 2. Goals / Non-goals

### Goals

- **G1 — Une excroissance sous l'encoche.** Un bloc qui prolonge la forme de
  l'encoche vers le bas, centré, et qui porte un **glyphe en pixels** dessiné
  comme les yeux du buddy, suivi du **nom du projet**.
- **G2 — Un glyphe par événement.** ✓ terminé · ✗ échec · ? attend une réponse.
  L'oreille droite ne porte plus aucun message.
- **G3 — Reste jusqu'à être vu.** Le bloc tient jusqu'au survol de l'encoche (qui
  ouvre le panneau : c'est « vu ») ou jusqu'au clic sur le bloc (qui ramène à
  l'onglet de terminal de la session). Aucune minuterie.
- **G4 — Plusieurs événements, un bloc.** Le plus urgent s'affiche, suivi d'un
  compteur : « ✗ podcaster +1 ». Priorité : attente > échec > terminé.
- **G5 — La couleur du visage.** Chaque glyphe prend la teinte que le `.buddy`
  donne à l'état correspondant (`finished`, `failed`, `awaiting`).

### Non-goals

- **Changer le visage.** Le buddy continue d'exprimer l'état agrégé de toutes les
  sessions ; le bloc dit l'événement. Ce ne sont pas les mêmes informations.
- **Le son** — RFC-015.
- **Changer la détection** — RFC-012.
- **Remplacer le panneau de permission.** Une demande de permission ouvre déjà le
  panneau ; le bloc « ? » couvre l'attente lue dans le transcript
  (`AskUserQuestion`, `ExitPlanMode`) quand aucun panneau n'est ouvert.

**Interdit.** Toute horloge qui survit à l'apparition. Un bloc affiché est une
image fixe : **0 réveil** au repos, bloc visible ou non.

## 3. Proposed Solution

### Arbitrages du 2026-09-26

| Question | Tranché | Pourquoi |
|---|---|---|
| Périmètre | **les trois événements**, un glyphe chacun | Déplacer la seule fin réussie laissait l'échec et l'attente dans l'oreille qu'on veut quitter |
| Contenu | **glyphe + nom du projet** | Avec plusieurs sessions, « laquelle ? » est la question utile ; un glyphe seul ne la tranche pas |
| Durée | **jusqu'au survol ou au clic** | Objectif n°1 : l'alerte attend l'utilisateur, pas l'inverse |
| Plusieurs | **le plus urgent + compteur** | Un glyphe par session élargit le bloc au-delà de l'encoche en deux événements |
| Interaction | **survol = vu, clic = terminal** | Le survol ouvre déjà le panneau ; le clic réutilise le saut de RFC-008 |
| Couleur | **celle du visage pour l'état** | Le bloc et le buddy parlent la même langue ; pas de second code couleur |
| Visage | **inchangé** | Il dit l'agrégat, le bloc dit l'événement |

### 3.1 Forme

```
 ┌──────────── encoche ────────────┐
 └────────┬───────────────┬────────┘
          │ ✓ notch       │           ← excroissance, même noir, coins du bas arrondis
          └───────────────┘
```

Un nouvel état `PanelState.alert`, frère de `.pill` : la fenêtre descend de la
hauteur du bloc (≈ 26 pt), la forme de `NotchShellView` gagne une languette
centrée sous l'encoche. La largeur suit le texte, bornée entre la largeur du
glyphe seul et celle de l'encoche physique. **Le haut reste noir sur la hauteur
exacte de l'encoche** — même règle que le panneau (`docs/hook.md`).

La zone cliquable de la fenêtre se limite à la languette : le reste reste
click-through (RFC-002).

### 3.2 Le glyphe : le rendu des yeux, pas dans les yeux

Le glyphe vit **dans l'excroissance**, et les yeux ne changent pas. Ce qui est
partagé, c'est le **rendu** : la même rastérisation analytique — chaque cellule
allumée entière ou pas du tout, trois intensités, le même grain, le même halo — et
le même chemin en `Shape` (le `Canvas` a coûté 95 Mo, `docs/hook.md`).

Les trois glyphes forment un catalogue à part, `AlertGlyph` (`check`, `cross`,
`question`), et **n'entrent pas dans `EyeShape`** : ils ne doivent pas devenir des
formes d'yeux qu'un `.buddy` pourrait choisir. Ils appellent le rastériseur des
yeux sur leur propre contour. Image fixe : `AnimationBudget` à `.still` pour le
bloc.

La forme `x` d'`EyeShape` peut servir de modèle au tracé de `cross` (Q2).

### 3.3 La file et la priorité

`AlertStack` (Kit, testable sans écran) : reçoit les `SessionAlert` du bus,
garde **une entrée par session** (la plus récente), et expose `head` (la plus
urgente selon attente > échec > terminé, puis la plus récente) et `count`.

- Une session qui reprend (nouveau tour) retire son entrée : l'alerte est
  périmée.
- Le survol vide toute la pile. Le clic vide l'entrée affichée et saute au
  terminal ; s'il en reste, le bloc montre la suivante.

### 3.4 Couleurs

Lues dans le manifeste du buddy : `finished`, `failed`, `awaiting`. Chez `eve`,
`finished` et `awaiting` partagent le même bleu (`#5AB8FF`) : **seul le glyphe les
distingue**, ce qui est voulu — la couleur dit « regarde », la forme dit quoi.

### 3.5 Ce qui disparaît

- Le message de l'oreille droite, `PillLayout.maxMessageSlotWidth` et la largeur
  élargie à 168 pt.
- L'état `.speech` et son `asyncAfter` de 4 s — une horloge de moins hors du
  `WakeCoordinator`.

L'icône de mise à jour de la pastille (D9) n'est pas concernée.

## 4. Alternatives Considered

| Alternative | Pourquoi non |
|---|---|
| **Pouce + confettis, 3 s** (première version) | Une récompense là où manquait une alerte ; ne couvre que la fin ; disparaît avant d'être vue |
| **Glyphe seul** | Plus sobre, mais ne dit pas quelle session ; il faudrait ouvrir le panneau à chaque fois |
| **Un glyphe par session côte à côte** | Le bloc déborde l'encoche dès deux événements |
| **Les yeux deviennent des coches** | Joli, mais confond l'état agrégé (le visage) et l'événement (le bloc), et n'a pas de place pour le nom |
| **Notification système** | Autorisation, centre de notifications, coin de l'écran — le produit existe pour ne pas passer par là |
| **Garder 4 s** | Contraire à l'objectif n°1 |

## 5. Action plan

| # | Tâche | Statut | % |
|---|---|---|---|
| T1 | `AlertGlyph` (`check`, `cross`, `question`), hors d'`EyeShape`, dessinés comme les yeux — `Sources/VibeBuddyKit/Buddy/AlertGlyph.swift`, tests de forme | done | 100 |
| T2 | `AlertStack` (Kit) : une entrée par session, priorité, compteur, péremption à la reprise — `Sources/VibeBuddyKit/Alerts/AlertStack.swift`, 6 tests | done | 100 |
| T3 | La languette : **fenêtre à part** (`AlertTongueWindow`) plutôt qu'un `PanelState.alert`, voir « Écarts » | done | 100 |
| T4 | `AlertTongueView` : glyphe + nom + « +N », couleur du manifeste — 64 lignes | done | 100 |
| T5 | Survol → panneau ouvert → pile vidée ; clic → saut au terminal et entrée suivante | done | 100 |
| T6 | Retrait de l'oreille-message, de `.speech`, de `maxMessageSlotWidth` et de l'`asyncAfter` de 4 s | done | 100 |
| T7 | `--simulate-alert <finished\|failed\|awaiting> [n]`, `make simulate-alert kind=… n=…` ; `--simulate-finished` reste un alias | done | 100 |
| T8 | `perfcheck` A avec un bloc affiché : **0 réveil** imputable | todo | 0 |

### Écarts avec la fiche validée

- **Une fenêtre à part, pas un état du panneau.** La hauteur de la fenêtre de la
  pastille sert à trois mesures — la bande de survol, le siège du buddy, la cible du
  clic sur le visage — et sa zone de clic couvre toute sa hauteur : grandir pour la
  languette aurait déplacé les trois et fait absorber une bande large comme la
  pastille sous la barre des menus. `AlertTongueWindow` n'absorbe que la languette ;
  la pastille n'a pas changé.
- **Des bitmaps, pas des contours.** Six cellules de haut : un trait analytique
  tombait d'un côté ou de l'autre d'un centre de cellule et la coche sortait en
  tache. Ce qui est partagé avec les yeux est le rendu — cellules, dégradé, halo.
- **Pas de curseur main sur la languette.** macOS ne laisse poser le curseur qu'à
  l'application au premier plan ; la pastille ne l'obtient qu'en devenant key, ce
  qu'une languette posée sur la fenêtre d'une autre app ne doit pas faire.

**Charge estimée : 1,5-2 j.**

**Critère de sortie.** Une fin de session → **exactement un** bloc sur dix essais.
Bloc affiché pendant 10 min sans personne : `perfcheck A` ne mesure aucun réveil de
plus que sans bloc. Deux sessions qui finissent → « ✓ notch +1 », et un échec qui
arrive ensuite prend la tête. Un clic sur le bloc ouvre le bon onglet, cinq fois
de suite.

## 6. Open Questions

| # | Question | Proposition |
|---|---|---|
| Q1 | « Silence si le terminal est au premier plan » (`AlertPolicy`) s'applique-t-il au bloc ? | Oui pour « terminé » : vous regardez déjà. Non pour « échec » et « attente » : un bloc qui attend coûte zéro. |
| Q2 | `cross` reprend-il le tracé de la forme `x` des yeux, ou un trait plus épais pour la lisibilité à 26 pt ? | À juger au pixel avec T7. |
| Q3 | Pastille masquée (D7, sans session) : un bloc peut-il apparaître seul ? | Non : sans session vivante, pas d'événement. Mais une session qui finit *puis meurt* peut laisser un bloc : le garder jusqu'au survol. |
| Q4 | Écran externe sans encoche (RFC-002) : où va la languette ? | Sous la pastille simulée, même géométrie. À vérifier avec le test d'écran externe reporté. |

```sh
# Juger à l'œil, pile comprise (T7)
.build/release/VibeBuddy --simulate-alert failed 2

# Le chiffre qui décide : un bloc affiché ne coûte rien
scripts/perfcheck.sh A 600
```
