# VibeBuddy

App macOS native qui transforme la notch du MacBook en tableau de bord de ses
agents de code. Swift / SwiftPM, macOS 14+, **zéro dépendance externe**
(stdlib + frameworks Apple).

## Objectifs produit

Par ordre d'importance. Toute fonctionnalité qui ne sert aucun de ces objectifs
est du confort, et se juge comme tel.

1. **Être alerté sans regarder** — quand l'agent a terminé, et quand il attend
   une réponse. C'est la raison d'être. → [RFC-012](docs/rfc/done/RFC-012-detection-etat-alertes.md)
2. **Suivre sa consommation** — le vrai % de limite, pas une estimation.
   → [RFC-004](docs/rfc/done/RFC-004-usage-live.md)
3. **Suivre plusieurs sessions à la fois**, chacune avec son état propre.
   → [RFC-003](docs/rfc/done/RFC-003-collecte-sessions.md)
4. **De manière ludique, dans la notch** — le buddy est le porteur de l'état.
   → [RFC-005](docs/rfc/done/RFC-005-rendu-buddy.md)

### Direction, au-delà du v1

- **Multi-agent** — Claude, Codex, Copilot, opencode et suivants. Le v1 est
  Claude-only par arbitrage explicite du 2026-08-19 ; c'est une dette assumée et
  suivie (**R11**), pas un oubli. Conséquence pratique dès maintenant : nommer les
  types en termes neutres (`AgentSession`, pas `ClaudeSession`) et isoler les
  chemins Claude derrière une constante par RFC.
- **Buddy par entreprise** — le buddy est de la *donnée*, pas du code : un
  manifeste chargé au lancement, sans recompilation. **tigreboite** est le premier
  manifeste externe et sert de test du format.
- **Lien avec le mobile** — pas de RFC encore, mais la conception en tient compte :
  les alertes passent par un bus (`AlertBus`, RFC-012) et non par des appels
  directs à l'UI, précisément pour qu'un second consommateur puisse s'y brancher.

## Output Constraints

- Réponses courtes. Livrer le résultat, pas le commentaire.
- Analyses longues → écrire dans un fichier markdown, pas dans la réponse.
- Questions de clarification → `AskUserQuestion`, jamais un mur de questions.

## Contrainte directrice

**La légèreté prime sur les fonctionnalités.** L'app est visible en permanence :
tout réveil inutile se paie en autonomie.

| Métrique | Cible | Statut |
|---|---|---|
| **`phys_footprint`** | **< 40 Mo** | mesuré **10,6 Mo** (shell + panneau vide) — [D5 tranchée](docs/perf/2026-08-19-D5-swiftui-floor.md) |
| RSS | indicatif | mesuré 38,2 Mo — compte les pages de frameworks partagées, ne pas budgéter dessus |
| CPU au repos | < 0,5 % | |
| CPU en activité | < 3 % | |
| Réveils inactifs au repos | **< 2/s** | métrique gouvernante |
| `fork`/`exec` au repos | **0** | non négociable |

**La métrique qui gouverne est le nombre de réveils inactifs, pas le %CPU.** Un
process à 0,4 % de CPU avec 70 réveils/s vide une batterie sans déclencher aucun
seuil exprimé en pourcentage.

Toute proposition technique se juge d'abord à son coût au repos.

## Mesures de référence

Faites le 2026-08-19 sur la machine cible (corpus : 546 jsonl, 379 Mo, 617 process).
**Ne pas les réutiliser sans les remesurer** — cf. « Verify before assert ».

| Mesure | Valeur |
|---|---|
| `proc_listpids` + `proc_name` + `proc_pidpath`, 617 process | 1,06 ms → 0,11 % d'un cœur à 1 Hz |
| Scan récursif `~/.claude/projects` | ~7 ms, cache chaud |
| **`fork`+`exec` de `/usr/bin/pgrep`** | **11,34 ms → 1,13 % d'un cœur à 1 Hz** |

Le polling n'est pas cher par ses syscalls. Il est cher par ses `fork`/`exec` et
par ses réveils.

## Origine

L'idée vient de **Notch-Pilot**, et **VibeIsland** a inspiré la suite.

**Aucune ligne n'en est reprise.** Réécriture intégrale, pas un fork. Ce qui a
été gardé, ce sont des *constats* : une valeur de drapeau et la raison qui la
justifie, un ordre d'opérations qui ne marche que dans ce sens, un séparateur
choisi parce qu'un nom de session tmux peut contenir des espaces. Neuf fiches
portent une section « Repris tel quel » qui les recense — le titre date de
l'époque où l'emprunt était envisagé ; ce que ces tableaux contiennent est de
l'empirisme, et leur colonne `fichier:ligne` désigne le dépôt de référence, pas
le nôtre.

Conséquence pratique : l'app ne porte pas de notice MIT, parce qu'elle n'a rien
à couvrir. L'écran « À propos » dit *Inspired by Notch-Pilot & VibeIsland*.

## Liste des RFC

| RFC | Titre | Statut | % | Jalon | Charge |
|---|---|---|---|---|---|
| — | [Spike](docs/spikes/keychain-oauth-usage.md) keychain + oauth-usage — débloquait RFC-004 | **done** | **100 %** | v1 | ✔ |
| — | [Spike](docs/spikes/hook-contract.md) contrat de hook — **prouvé en réel le 2026-08-21** | **done** | **100 %** | v1 | ✔ |
| [001](docs/rfc/done/RFC-001-socle-applicatif.md) | Socle applicatif, cycle de vie, budget de performance | **done** | **100 %** | v1 | ✔ |
| [002](docs/rfc/RFC-002-fenetre-notch.md) | Fenêtre notch : NSPanel, click-through, multi-écran | **in-progress** | **95 %** | v1 | 4-6 j |
| [003](docs/rfc/done/RFC-003-collecte-sessions.md) | Collecte de sessions : source de vérité unique | **done** | **100 %** | v1 | ✔ |
| [004](docs/rfc/done/RFC-004-usage-live.md) | Utilisation live : Keychain + endpoint OAuth | **done** | **100 %** | v1 | ✔ |
| [005](docs/rfc/done/RFC-005-rendu-buddy.md) | Buddy : visage, format `.buddy`, rendu | **done** | **100 %** | v1 | ✔ |
| [006](docs/rfc/RFC-006-pont-hook.md) | Pont hook Claude Code : binaire dédié + socket Unix | **in-progress** | **95 %** | v1 | 0,5 j |
| [007](docs/rfc/RFC-007-interception-permissions.md) | Interception des permissions : file, rendu, décisions | **in-progress** | **95 %** | v1 | 0,5 j |
| [008](docs/rfc/RFC-008-vue-sessions.md) | Vue sessions et saut vers le terminal hôte | **in-progress** | **80 %** | v1.1 | 1-2 j |
| [009](docs/rfc/RFC-009-index-activite.md) | Index d'activité persistant (heatmap et historique) | todo | 0 % | v1.2 | 3-4 j |
| [010](docs/rfc/done/RFC-010-preferences-apparence.md) | Préférences, réglages segmentés et **aperçu de buddy** | **done** | **100 %** | v1 | ✔ |
| [011](docs/rfc/RFC-011-build-distribution.md) | Build, empaquetage, signature, distribution | **in-progress** | **95 %** | v1 | 0,5 j |
| [012](docs/rfc/done/RFC-012-detection-etat-alertes.md) | **Détection d'état et alertes** — depuis le transcript, sans hook | **done** | **100 %** | v1 | ✔ |
| [013](docs/rfc/done/RFC-013-buddy-interactif.md) | **Buddy interactif** — regard, chasse, rire, icône | **done** | **100 %** | v1 | ✔ |
| [014](docs/rfc/RFC-014-celebration-fin-de-tache.md) | **Célébration de fin de tâche** — mini-panneau, pouce, confettis | todo | 0 % | v1.1 | 1-2 j |
| [015](docs/rfc/RFC-015-son-du-buddy.md) | **Le son du buddy** — paquet de sons rechargeable à chaud | todo | 0 % | v1.1 | 1-2 j |

**Reste pour le v1 : 1,5-4,5 j-h** (001, 003, 005 et **012** faites ; 002, 004 et
**006** à 95 %, 010 et **013** à 90 % ; spike keychain fait) · plan complet restant : 15,5-24 j-h. Dev solo en parallèle d'autres projets →
tabler sur un facteur calendaire ×2 à ×3.

## Gantt

Barre = 20 caractères = 100 %. █ fait · ░ restant.
Ordre = ordre de réalisation, pas ordre de numérotation.

```
── EN COURS ──
#   RFC      Titre                                          Avancement            %    Reste   Jalon
1   RFC-002  Fenêtre notch (NSPanel, click-through)          ███████████████████░  95 %   0,5 j  v1
2   —        Spike keychain + oauth-usage                    ████████████████████ 100 %   ✔      v1
3   —        Spike contrat de hook ← **prouvé en réel**      ████████████████████ 100 %   ✔      v1
4   RFC-006  Pont hook + socket Unix                         ███████████████████░  95 %   0,5 j  v1
5   RFC-007  Interception des permissions ← prouvée en réel  ███████████████████░  95 %   0,5 j  v1
6   RFC-011  Build, signature, distribution                  ███████████████████░  95 %   0,5 j  v1
7   RFC-008  Vue sessions + saut terminal/tmux               ████████████████░░░░  80 %   1-2 j  v1.1
8   RFC-014  Célébration de fin de tâche                     ░░░░░░░░░░░░░░░░░░░░   0 %   1-2 j  v1.1
9   RFC-015  Le son du buddy (paquet rechargeable)           ░░░░░░░░░░░░░░░░░░░░   0 %   1-2 j  v1.1
10  RFC-009  Index d'activité (heatmap + historique)         ░░░░░░░░░░░░░░░░░░░░   0 %   3-4 j  v1.2

── DONE ──
—   RFC-010  Réglages segmentés + aperçu de buddy            ████████████████████ 100 %   —      v1
—   RFC-013  Buddy interactif (regard, chasse, rire)         ████████████████████ 100 %   —      v1
—   RFC-004  Utilisation live (Keychain + OAuth)             ████████████████████ 100 %   —      v1
—   RFC-012  Détection d'état et alertes  ← objectif n°1     ████████████████████ 100 %   —      v1
—   RFC-005  Buddy : visage, format .buddy, rendu            ████████████████████ 100 %   —      v1
—   RFC-001  Socle applicatif, budget de performance         ████████████████████ 100 %   —      v1
—   RFC-003  Collecte de sessions (source de vérité unique)  ████████████████████ 100 %   —      v1
```

**Chemin critique : 007.** RFC-006 est à 95 % — transport, installateur et
désinstallation livrés, il ne reste que la confirmation d'une minute du spike.
RFC-007 est désormais le seul gros morceau du v1.

RFC-003 a établi que **quatre des signaux que RFC-012 devait prendre au hook sont
déjà dans le transcript** : mode de permission, fin de tour, cycle de vie des
sous-agents, échec d'outil. L'objectif n°1 du produit — alerter — est donc
atteignable **sans écrire une seule ligne dans `~/.claude/settings.json`**.

Conséquences sur l'ordre :

- **RFC-012 est passée devant RFC-006, et est close.** Alerter était l'objectif ;
  le hook n'en a jamais été le moyen.
- **Le spike « contrat de hook » se déplace avec RFC-007**, seule chose qui en
  dépende encore. S'il échoue, l'interception des permissions tombe — plus le
  cœur du produit.
- **RFC-006 et RFC-007 restent indissociables** (RFC-006 seule ne produit rien
  d'observable), mais forment désormais un bloc *optionnel* plutôt qu'un passage
  obligé.

RFC-004 reste une feuille du graphe, parallélisable à tout moment.

## Phases

| Phase | RFC | Critère de sortie |
|---|---|---|
| 0 — Preuves | spikes | Scripts jetables archivés dans `docs/spikes/` **avec leur sortie brute** et la date. Le spike hook ne conditionne plus que RFC-006/007 — s'il échoue, le cœur du produit tient quand même. |
| 1 — Fondations | 001, 002 | Panneau qui se déploie au survol ; un clic dans la zone transparente atteint l'horloge de la barre de menus ; `perfcheck A` : 0 `posix_spawn`, < 2 réveils/s. |
| 2 — Données | 003 ✔, 004 | **003 : atteint** — détection en 0,13 s, 0 `posix_spawn`, 0,055 % CPU, 8,2 Mo. Le critère « 0 `proc_listpids` » a été amendé : la mort d'un processus n'émet aucun événement filesystem, l'exiger revenait à exiger de ne jamais la remarquer. **004 :** le % 5 h identique à la page de facturation. |
| 3 — Surface visible | 005 | Modes distincts pour édition / shell / lecture / danger. Pastille masquée → 0 réveil imputable au buddy. |
| 4 — Intégration | 006, 007 | Bash, Edit et AskUserQuestion autorisés **et** refusés depuis la notch (6 cas). Tuer l'app pendant une attente ne bloque pas Claude > 120 s. Test golden-file en CI. |
| 5 — Confort | 010, puis 008, 009 | Une fin de session → **exactement une** notification sur 10 essais. Deux sessions dans le même cwd → le bon volet tmux, 5 fois de suite. |
| 6 — Livraison | 011 | DMG installé sur un **second compte macOS** se lance. `codesign --verify --strict --deep` passe. |

## Décisions structurantes

Le détail et les alternatives vivent dans la RFC qui applique chaque décision.

| # | Décision | Statut |
|---|---|---|
| D1 | `actor SessionStore` unique. Process = liveness, jsonl = contenu, hook = mode et PID. Clé primaire `sessionID`. | tranchée |
| D2 | `@Observable` (Observation) plutôt que Combine. **Aucune vue ne dépasse 200 lignes.** | tranchée |
| D3 | **Un seul `WakeCoordinator`.** Un `Timer` créé ailleurs est un échec de revue. | tranchée |
| D4 | Deux cibles exécutables : `vibebuddy` et `vibe-hook` (Foundation-only). Le hook ne lie jamais AppKit. | tranchée |
| D5 | **SwiftUI retenu**, pastille en `NSHostingView`. Budget mesuré en `phys_footprint`, pas en RSS. | tranchée 2026-08-19 |
| D6 | Un `ClaudeSettingsWriter` unique, écriture atomique, sauvegarde préalable, sans `.sortedKeys`. | tranchée |
| D7 | Pastille visible sans session : **off par défaut**, rendu statique 0 Hz si épinglée. | tranchée |
| D8 | Latence contractuelle : 1 s en activité, 30 s au repos. | tranchée |
| — | Signature **auto-signée à CN stable**, et **aucune API Accessibilité en v1** (pas de raccourcis globaux, pas de détection plein-écran par AX). | tranchée |

## Risques ouverts

Chaque risque est traité dans la RFC en regard ; ce tableau est l'index.

| # | Risque | RFC |
|---|---|---|
| R1 | Écriture destructrice dans `~/.claude/settings.json` (non atomique + réordonne le fichier) | 006, 007 |
| R2 | Scan des jsonl en `String(contentsOf:)` → budget mémoire ×10 | 004, 009 |
| R3 | CPU au repos non nul par construction | 001, 003, 005 |
| R4 | Le hack Keychain dépend d'un détail d'implémentation d'Anthropic | 004 |
| R5 | L'endpoint `oauth/usage` n'est pas public (en-tête beta daté) | 004 |
| R6 | Schéma `PermissionRequest` strict, casse **en silence** | 007 |
| R7 | Signature ad-hoc, friction Gatekeeper | 011 |
| R8 | Détection de session fragile (appariement PID par ordre de tri) | 003, 008 |
| R9 | Le format des jsonl n'est pas un contrat | 003, 004, 009 |
| R10 | Dérive calendaire — **chaque RFC se termine sur un binaire lançable** | transverse |

## Conventions

### Général
- Anglais pour le code (noms, commentaires), français pour l'UI et les RFC.
- Branches : `feat/rfc-XXX`.
- **Ne jamais commiter, ni pousser, ni créer de branche.** L'utilisateur gère
  entièrement son git, y compris `git init`.

### RFC
- Utiliser la skill `rfc`. Six sections canoniques, en-tête avec `Status`,
  `Author`, `Created`, `Updated`, `Phase`, `Depends on`, `Related`, `Blocks`.
- RFC terminée → `docs/rfc/done/`, annulée → `docs/rfc/archive/`.
- **Les trois gestes dans le même tour que le code** : statut de la fiche,
  déplacement du fichier, ligne du Gantt. Une tâche dont la comptabilité traîne
  compte comme non terminée.
- Le Gantt liste **toutes** les RFC. Une RFC sous `── DONE ──` a son fichier dans
  `docs/rfc/done/` — les deux ne divergent jamais.
- Ne jamais se fier à l'en-tête `Status` d'une fiche : vérifier contre le code.
  Grep bilingue `Status|Statut`.

### Verify before assert
- Ne rien affirmer sans l'avoir vérifié à l'instant, avec `file:line`.
- Interdits : reprendre un chiffre mesuré plus tôt dans la conversation, conclure
  d'un `grep` vide qu'une chose n'existe pas, déduire d'un en-tête qu'un travail
  est fait.
- Quand un sous-agent contredit le brief avec des preuves, il a probablement
  raison — vérifier, pas insister.

### Performance
- `scripts/perfcheck.sh <scenario> <durée>` après **chaque** RFC. Scénarios :
  **A** repos 10 min sur batterie · **B** 3 sessions actives 5 min · **C** panneau
  déployé 60 s, curseur en mouvement.
- **Une régression > 10 % sur n'importe quelle métrique bloque la clôture de la RFC.**
- Les CSV s'accumulent dans `docs/perf/`. Constater la dérive à la fin, c'est
  découvrir qu'il faut réécrire.
