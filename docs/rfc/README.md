# RFC — décisions transverses, comptes, anomalies connues

Le Gantt et la liste des fiches sont dans [`GANTT.md`](GANTT.md). Les règles de
travail sont dans [`CLAUDE.md`](../../CLAUDE.md). Ce fichier garde ce qui n'a sa
place ni dans l'un ni dans l'autre : pourquoi l'ordre est celui-là, ce qui a été
tranché et quand, et ce qu'on doit encore.

## Où en est le plan

**Le v1 est complet** depuis le 2026-08-25 : onze RFC closes, 007 et 011
comprises. Ce qui reste appartient au v1.1 et au-delà : 008 à 90 %, puis 017, 014,
015, 009 et 016 · plan complet restant : 11,5-18,5 j-h. Dev solo en parallèle
d'autres projets → tabler sur un facteur calendaire ×2 à ×3.

**Livré hors RFC le 2026-09-01**, sur demande directe plutôt que sur fiche :
masquage d'une session (rien n'est supprimé sur le disque), historique par
session, chase joignable depuis les six visages, et un avis de nouvelle version
qui n'installe rien. **Le 2026-09-26** : suivi des workflows et agents en
arrière-plan, badge de délégation. Le détail et les pièges sont dans
`docs/hook.md`.

**Dette ouverte** : `make perf` scénario A est à relancer — le plancher
d'échantillonnage du pointeur est tombé, et la mesure qui l'avait fait poser
disait 1,58 réveil/s contre un budget de 2.

## Pourquoi cet ordre

**Le v1 n'a plus de chemin critique.** RFC-006 et RFC-007 sont closes depuis le
2026-08-25 : transport, installateur, contrat prouvé en réel, et les **six cas de
permission joués contre un vrai Claude Code** — `Bash`, `Edit` et
`AskUserQuestion`, autorisés et refusés. Le détournement `AskUserQuestion` tient,
et le panneau qui attend une personne coûte 0,144 réveil/s pour un budget de 2
(scénario D, `docs/perf/20260825-2158-007-D.csv`). RFC-011 a suivi le même jour :
les trois scénarios mesurés sur le bundle signé, 27 · 16 · 12 Mo pour un budget de
40, avec une réserve nommée dans la fiche — la machine n'était pas au repos
complet, et une manche du B sur cinq est montée à 70 Mo juste après une
compilation.

RFC-003 a établi que **quatre des signaux que RFC-012 devait prendre au hook sont
déjà dans le transcript** : mode de permission, fin de tour, cycle de vie des
sous-agents, échec d'outil. L'objectif n°1 du produit — alerter — est donc
atteignable **sans écrire une seule ligne dans `~/.claude/settings.json`**.

Conséquences sur l'ordre :

- **RFC-012 est passée devant RFC-006, et est close.** Alerter était l'objectif ;
  le hook n'en a jamais été le moyen.
- **Le spike « contrat de hook » s'est déplacé avec RFC-007**, seule chose qui en
  dépendait encore.
- **RFC-006 et RFC-007 restent indissociables** (RFC-006 seule ne produit rien
  d'observable), et forment un bloc *optionnel* plutôt qu'un passage obligé.
- **RFC-017 passe devant 014 et 015** (2026-09-26) : sans elle, ce bloc optionnel
  n'est installable par personne qui n'a pas de terminal ouvert sur le dépôt.

RFC-004 reste une feuille du graphe, parallélisable à tout moment.

## Phases

| Phase | RFC | Critère de sortie |
|---|---|---|
| 0 — Preuves | spikes | Scripts jetables archivés dans `docs/spikes/` **avec leur sortie brute** et la date. Le spike hook ne conditionne plus que RFC-006/007 — s'il échoue, le cœur du produit tient quand même. |
| 1 — Fondations | 001, 002 | Panneau qui se déploie au survol ; un clic dans la zone transparente atteint l'horloge de la barre de menus ; `perfcheck A` : 0 `posix_spawn`, < 2 réveils/s. |
| 2 — Données | 003 ✔, 004 | **003 : atteint** — détection en 0,13 s, 0 `posix_spawn`, 0,055 % CPU, 8,2 Mo. Le critère « 0 `proc_listpids` » a été amendé : la mort d'un processus n'émet aucun événement filesystem, l'exiger revenait à exiger de ne jamais la remarquer. **004 :** le % 5 h identique à la page de facturation. |
| 3 — Surface visible | 005 | Modes distincts pour édition / shell / lecture / danger. Pastille masquée → 0 réveil imputable au buddy. |
| 4 — Intégration | 006, 007 | Bash, Edit et AskUserQuestion autorisés **et** refusés depuis la notch (6 cas). Tuer l'app pendant une attente ne bloque pas Claude > 120 s. Test golden-file en CI. |
| 5 — Confort | 010, puis 008, 017, 009 | Une fin de session → **exactement une** notification sur 10 essais. Deux sessions dans le même cwd → le bon volet tmux, 5 fois de suite. Hook installé et retiré sans terminal. |
| 6 — Livraison | 011 | DMG installé sur un **second compte macOS** se lance. `codesign --verify --strict --deep` passe. |

## Décisions structurantes

Le détail et les alternatives vivent dans la RFC qui applique chaque décision. Les
règles qui en découlent sont rappelées dans `CLAUDE.md`.

| # | Décision | Statut |
|---|---|---|
| D1 | `actor SessionStore` unique. Process = liveness, jsonl = contenu, hook = mode et PID. Clé primaire `sessionID`. | tranchée |
| D2 | `@Observable` (Observation) plutôt que Combine. **Une vue SwiftUI — un `struct: View` — reste sous 200 lignes**, `body` et sous-vues comprises. Les `NSView`, les représentables et les bancs de mesure ne sont pas concernés. | tranchée |
| D3 | **Un seul `WakeCoordinator`.** Un `Timer` créé ailleurs est un échec de revue. | tranchée |
| D4 | Deux cibles exécutables : `vibebuddy` et `vibe-hook` (Foundation-only). Le hook ne lie jamais AppKit. | tranchée |
| D5 | **SwiftUI retenu**, pastille en `NSHostingView`. Budget mesuré en `phys_footprint`, pas en RSS. Mesuré 10,6 Mo (shell + panneau vide), [D5](../perf/2026-08-19-D5-swiftui-floor.md). | tranchée 2026-08-19 |
| D6 | Un `ClaudeSettingsWriter` unique, écriture atomique, sauvegarde préalable, sans `.sortedKeys`. | tranchée |
| D7 | Pastille visible sans session : **off par défaut**, rendu statique 0 Hz si épinglée. | tranchée |
| D8 | Latence contractuelle : 1 s en activité, 30 s au repos. | tranchée |
| — | Signature **auto-signée à CN stable**, et **aucune API Accessibilité en v1** (pas de raccourcis globaux, pas de détection plein-écran par AX). | tranchée |
| D9 | **Mise à jour : signaler, jamais installer.** Une requête GitHub par jour, montée sur le `WakeCoordinator`. Pas de Sparkle — dépendance externe. Aucun téléchargement — l'app n'est pas notarisée, un binaire qu'elle irait chercher arriverait en quarantaine. Le canal reste `brew upgrade`. | tranchée 2026-09-01 |
| D10 | **Une seule cadence d'échantillonnage du pointeur**, tous visages confondus. Le plancher dormant de 12 Hz cachait la secousse, qui tourne à 5-8 Hz. Le déclencheur du chase doit être identique partout. | tranchée 2026-09-01 |
| — | **Multi-agent reporté** : v1 Claude-only par arbitrage explicite du 2026-08-19 (R11). | tranchée |
| — | **Buddy par entreprise abandonné** le 2026-08-25 : un seul buddy, `eve`. Le format `.buddy` reste pour le rechargement à chaud. | tranchée |

### D2 — la dette qu'elle laisse

Un seul fichier dépasse encore 200 lignes sans relever de D2 :
`Sources/VibeBuddy/BenchHarness.swift` (225, un banc de mesure).

Remesuré le 2026-09-01 (`wc -l` pour le fichier, étendue de la déclaration pour
la vue) — dette reconnue, pas règle tacitement violée :

| Fichier | Lignes | Plus grosse vue | Dépasse D2 |
|---|---|---|---|
| `NotchShellView.swift` | 320 | `NotchShellView` **316** (l. 5-320) | **oui**, ×1,6 |
| `Panel/SessionRow.swift` | 187 | `SessionRow` 180 | non |
| `Buddy/EyesFaceView.swift` | 185 | `EyesFaceView` 95, `FaceScreen` 87 | non — 4 types dans le fichier |
| `Panel/Permission/PermissionPanelView.swift` | 166 | `PermissionPanelView` 152 | non |
| `Buddy/BuddyView.swift` | 170 | `BuddyView` 128 | non — 2 `extension Color` en fin de fichier |

**Une seule vue est en infraction.** `NotchShellView` est la dette qui reste : à
découper au prochain passage sur le shell.

## Risques ouverts

Chaque risque est traité dans la RFC en regard ; ce tableau est l'index.

| # | Risque | RFC |
|---|---|---|
| R1 | Écriture destructrice dans `~/.claude/settings.json` (non atomique + réordonne le fichier) | 006, 007, 017 |
| R2 | Scan des jsonl en `String(contentsOf:)` → budget mémoire ×10 | 004, 009 |
| R3 | CPU au repos non nul par construction | 001, 003, 005 |
| R4 | Le hack Keychain dépend d'un détail d'implémentation d'Anthropic | 004 |
| R5 | L'endpoint `oauth/usage` n'est pas public (en-tête beta daté) | 004 |
| R6 | Schéma `PermissionRequest` strict, casse **en silence** | 007 |
| R7 | Signature ad-hoc, friction Gatekeeper | 011 |
| R8 | Détection de session fragile (appariement PID par ordre de tri) | 003, 008 |
| R9 | Le format des jsonl n'est pas un contrat | 003, 004, 009 |
| R10 | Dérive calendaire — **chaque RFC se termine sur un binaire lançable** | transverse |
| R11 | **Multi-agent reporté** — v1 Claude-only. Cité en prose, absent de cet index jusqu'au 2026-08-24 : un risque qu'on dit suivre et qui n'est pas listé n'est pas suivi | 016 |
| R12 | **Retour à l'onglet limité à deux terminaux**, et cassé sous tmux — c'est-à-dire le cas courant | 008, 016 |
| R13 | **Hook absent sans que rien ne le dise** : les panneaux de permission ne viennent jamais, et l'app a l'air de marcher | 017 |
