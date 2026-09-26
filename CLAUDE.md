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
  Claude-only par arbitrage explicite ; c'est une dette assumée et suivie
  (**R11**), pas un oubli. Conséquence pratique dès maintenant : nommer les
  types en termes neutres (`AgentSession`, pas `ClaudeSession`) et isoler les
  chemins Claude derrière une constante par RFC.
- **Buddy par entreprise** — abandonné : un seul buddy, `eve`, embarqué. Le format
  `.buddy` reste pour le rechargement à chaud pendant qu'on dessine un visage.
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

| Métrique | Cible | Note |
|---|---|---|
| **`phys_footprint`** | **< 40 Mo** | la métrique mémoire budgétée (D5) |
| RSS | indicatif | compte les pages de frameworks partagées, ne pas budgéter dessus |
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
à couvrir. L'écran « À propos » ne porte pas de mention d'inspiration non plus : rien
n'étant emprunté, il n'y a rien à créditer.

## RFC, Gantt, décisions

| Fichier | Contient |
|---|---|
| [`docs/rfc/GANTT.md`](docs/rfc/GANTT.md) | Toutes les RFC : barre, %, jalon, lien vers chaque fiche |
| [`docs/rfc/README.md`](docs/rfc/README.md) | Où en est le plan, pourquoi cet ordre, phases, décisions tranchées et leur date, risques ouverts |
| `docs/hook.md` | Point de reprise : état, pièges, suite par ordre d'utilité |

## Règles d'architecture

Issues des décisions D1-D10 ; le détail et les dates sont dans `docs/rfc/README.md`.

- **D1** — un seul `actor SessionStore`. Process = liveness, jsonl = contenu, hook =
  mode et PID. Clé primaire `sessionID`, jamais le `cwd`.
- **D2** — `@Observable`, pas Combine. **Une vue SwiftUI — un `struct: View` — reste
  sous 200 lignes**, `body` et sous-vues comprises. Les `NSView`, les représentables
  et les bancs de mesure ne sont pas concernés.
- **D3** — **un seul `WakeCoordinator`.** Un `Timer` créé ailleurs est un échec de revue.
- **D4** — deux cibles exécutables : `vibebuddy` et `vibe-hook` (Foundation-only). Le
  hook ne lie jamais AppKit.
- **D5** — SwiftUI, pastille en `NSHostingView`. Mémoire budgétée en
  `phys_footprint`, pas en RSS.
- **D6** — un seul `ClaudeSettingsWriter` touche `~/.claude/settings.json` : écriture
  atomique, sauvegarde préalable, ordre préservé. Jamais d'écriture sans
  consentement de l'utilisateur.
- **D7** — pastille sans session : off par défaut, rendu statique 0 Hz si épinglée.
- **D8** — latence contractuelle : 1 s en activité, 30 s au repos.
- Signature auto-signée à CN stable ; **aucune API Accessibilité**.
- **D9** — mise à jour : signaler, jamais installer. Pas de Sparkle.
- **D10** — une seule cadence d'échantillonnage du pointeur, tous visages confondus.

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
  déplacement du fichier, ligne du Gantt (`docs/rfc/GANTT.md`). Une tâche dont la comptabilité traîne
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
  déployé 60 s, curseur en mouvement · **D** un panneau de permission qui attend
  une personne (`make perf-waiting`).
- **Une régression > 10 % sur n'importe quelle métrique bloque la clôture de la RFC.**
- **Une mesure de release se fait en trois manches, jamais en une.** Le 2026-08-25,
  le scénario B a rendu 70 puis 16 Mo à onze minutes d'écart, sur le même binaire.
  La manche isolée était la seule à suivre une compilation complète.
- Les CSV s'accumulent dans `docs/perf/`. Constater la dérive à la fin, c'est
  découvrir qu'il faut réécrire.
