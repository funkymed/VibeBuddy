# RFC-014 — Célébration de fin de tâche

| | |
|---|---|
| **Status** | **todo (0 %)** — ouverte le 2026-08-21 |
| **Author** | Cyril Pereira |
| **Created** | 2026-08-21 |
| **Updated** | 2026-08-21 |
| **Phase** | 3 — Surface visible |
| **Depends on** | RFC-012 (`AlertBus`, `SessionAlert`) · RFC-002 (fenêtre, géométrie) |
| **Related** | RFC-008 (saut vers le terminal) · RFC-013 (buddy interactif) · D3, D8 |
| **Blocks** | — |

## 1. Context & Problem

**Être alerté sans regarder est l'objectif produit n°1**, et RFC-012 l'a atteint :
la fin d'un tour est détectée depuis le transcript, `AlertBus` la diffuse,
`AlertPolicy` la dédoublonne, et la pastille s'élargit quelques secondes avec un
texte dans l'oreille droite — « notch terminé ».

Ce qui manque n'est pas la détection, c'est la **récompense**. Une fin de tâche
est le seul moment agréable du cycle : l'agent a fini, l'utilisateur peut y
retourner. Aujourd'hui elle a exactement le même rendu qu'un échec ou qu'une
question en attente — un mot dans une oreille de 89 pt. Trois événements très
différents, une seule forme.

Et ce moment est le plus regardé de tous : c'est celui où l'utilisateur revient
vers l'écran.

## 2. Goals / Non-goals

**Goals.** Un mini-panneau qui descend de l'encoche à la fin d'une tâche : un
pouce en l'air, le nom de la session, quelques confettis, trois secondes, et il
s'en va. Un clic dedans ramène à l'onglet de terminal.

**Non-goals.** Le son (RFC-010 a déjà la voix, et elle est off par défaut).
Changer la détection (RFC-012 la fait). Célébrer autre chose qu'une fin réussie
— un échec ne se fête pas, et une question en attente n'est pas terminée.

**Interdit.** Toute horloge qui survit à la célébration. La pastille au repos
doit revenir à **0 réveil**, exactement comme avant.

## 3. Proposed Solution

### Arbitrages du 2026-08-21

| Question | Tranché | Pourquoi |
|---|---|---|
| La forme | **mini-panneau 320×130** | Le panneau plein (560×460) est démesuré pour un pouce ; l'oreille élargie d'aujourd'hui est ce qu'on cherche justement à dépasser |
| Les confettis | **suggérés, ~8 formes, 0,8 s** | Huit formes redessinées ne coûtent rien de mesurable. Trente auraient demandé un budget que la fiche aurait dû défendre |
| La sortie | **3 s, puis fermeture ; cliquable** | Un clic saute vers l'onglet (RFC-008 le fait déjà). Rester jusqu'au survol laisserait le panneau des minutes à l'écran quand personne ne regarde |

### Ce qui se branche où

| Brique | Rôle |
|---|---|
| `SessionAlert.Kind.finished` | Le seul genre qui déclenche. `failed` et `needsAttention` gardent l'oreille élargie d'aujourd'hui |
| Nouvel état `PanelState.celebration` | Une taille de plus, pas un mécanisme de plus : `NotchPanel` sait déjà animer entre deux tailles |
| `CelebrationView` | Le pouce, le message, les confettis. Sous 200 lignes (D2) |
| `ConfettiView` | Les huit formes. Séparée pour que le reste de la vue ne se réévalue pas avec elles |

**Le mouvement sans horloge qui traîne.** La règle du projet est D3 : un seul
`WakeCoordinator`, aucun `Timer` ailleurs. Les confettis et le rebond du pouce
sortent d'un `TimelineView(.animation)` **borné par sa propre fin** : passé
0,8 s, la vue rend une image fixe et la vue entière disparaît à 3 s. Les
positions viennent d'un hachage de l'indice de la particule — même technique que
les yeux du buddy (RFC-005), donc rien à mémoriser, aucun `Task`.

**Le pouce est un emoji, pas un dessin.** `NSAttributedString` dans un
`NSBitmapImageRep`, comme le buddy pixelisé : `ImageRenderer` a déjà coûté 80 Mo
à ce projet pour dessiner une douzaine de glyphes, et un `Text("👍")` de 48 pt
dans une vue qui se réévalue à 30 Hz est le même piège avec un autre nom.

**La fenêtre ne grandit pas pour les confettis.** Ils sont dessinés **dans** le
mini-panneau, jamais au-delà : une fenêtre plus grande que sa forme est une
fenêtre qui mange les clics de ce qu'il y a derrière.

## 4. Alternatives Considered

**Une notification système (`UNUserNotificationCenter`).** Écartée : elle
demande une autorisation, elle s'empile dans le centre de notifications, et elle
apparaît dans le coin — pas là où l'utilisateur regarde. Le produit existe
précisément pour ne pas passer par là.

**Réutiliser le panneau plein.** Aucune géométrie neuve à tenir, mais 560×460
pour trois mots est une réponse disproportionnée, et le panneau porte déjà la
liste des sessions : deux contenus dans une forme qu'on ouvre par survol.

**Trente confettis en vraies particules.** Écartée à l'arbitrage : le coût
aurait dû être défendu au perfcheck pour un gain que huit formes donnent déjà.

**Célébrer aussi les échecs, en rouge.** Écartée : un échec demande d'agir, pas
de fêter. Il garde l'oreille élargie, qui est une alerte et non une récompense.

## 5. Action plan

| # | Tâche | Statut | % |
|---|---|---|---|
| T1 | `PanelState.celebration` + sa taille dans `NotchPanel` | todo | 0 |
| T2 | `CelebrationView` : pouce, message, nom de session | todo | 0 |
| T3 | `ConfettiView` : huit formes, hachées, bornées à 0,8 s | todo | 0 |
| T4 | Branchement sur `SessionAlert.Kind.finished` uniquement | todo | 0 |
| T5 | Fermeture à 3 s, et clic → saut vers l'onglet (RFC-008) | todo | 0 |
| T6 | `--simulate-celebration`, pour la juger à l'œil sans attendre une vraie fin | todo | 0 |
| T7 | `perfcheck` A : **0 réveil** une fois la célébration passée | todo | 0 |

**Critère de sortie.** Une fin de session → **exactement une** célébration sur
dix essais (le critère de RFC-012, hérité). Trois secondes après, `perfcheck A`
mesure **0 réveil** : rien ne survit à la fête. Un clic dedans ouvre le bon
onglet de terminal, cinq fois de suite.

## 6. Open Questions

**Q1 — Que se passe-t-il si deux sessions finissent en même temps ?**
`AlertPolicy` dédoublonne déjà, mais deux sessions distinctes sont deux alertes
légitimes. Une file comme celle des permissions, ou une seule célébration qui
dit « 2 tâches terminées » ?

**Q2 — La célébration doit-elle respecter « silence si le terminal est au
premier plan » ?** `AlertPolicy` le fait pour les alertes : l'utilisateur regarde
déjà. Une récompense est peut-être l'exception — il vient de voir la tâche finir,
et la fête est pour lui.

```sh
# Juger à l'œil, sans attendre une vraie fin de tâche (T6)
.build/release/VibeBuddy --simulate-celebration

# Le chiffre qui décide : rien ne doit survivre à la fête
scripts/perfcheck.sh A 600
```
