# RFC-009 — Index d'activité persistant (heatmap et historique)

| | |
|---|---|
| **Status** | todo (0 %) |
| **Author** | Cyril Pereira |
| **Created** | 2026-08-19 |
| **Updated** | 2026-08-19 |
| **Phase** | 5 — Confort |
| **Depends on** | RFC-003 |
| **Related** | R2 · repli local futur de RFC-004 |
| **Blocks** | RFC-008 (heatmap) |

## 1. Context & Problem

Une bande d'activité sur 24 h, navigable jour par jour, montre quand le travail a
réellement eu lieu — souvent différent de ce qu'on croit.

**Cette RFC n'est pas une RFC de visualisation.** Formulée « heatmap », elle
reproduirait mécaniquement le défaut de la référence :
`HeatmapAggregator.swift:157-209` lit `String(contentsOf:)` — **le fichier
entier** — puis fait **deux passes complètes** sur les lignes (`:175-184` puis
`:191-209`). Le fichier complet *plus* un tableau complet de sous-chaînes sont
matérialisés en RAM. Un jsonl de projet actif dépasse couramment 50 Mo, et
chaque clic sur `‹` invalide le cache (`:76-77`) et relance un scan complet.

C'est le risque R2 : la contrainte directrice du projet manquée d'un facteur 10,
sur un corpus de 379 Mo.

Le sujet réel est donc le **stockage** : un index incrémental qui ne relit jamais
ce qu'il a déjà lu. Une fois qu'il existe, la vue est triviale, et l'index sert
aussi de repli local à RFC-004 et de source à toute statistique future.

## 2. Goals / Non-goals

**Goals.** Un index sur disque `(jour, heure, projet) → compteur`, alimenté en
append à partir des offsets déjà lus. Un backfill initial unique. La vue heatmap
24 h navigable.

**Non-goals.** Toute relecture complète d'un jsonl après le backfill. Toute
statistique de tokens (elle appartient à RFC-004, qui prend ses chiffres de l'API).

## 3. Proposed Solution

Stockage dans `~/Library/Application Support/vibebuddy/activity.sqlite` (ou un
fichier binaire compact — cf. Q1).

| Module | Responsabilité |
|---|---|
| `actor ActivityIndex` | `record(events:)`, `hours(for day: Date) -> [HourBucket]`. |
| `IndexCursorStore` | Par jsonl : `path → (inode, taille lue, mtime)`. |
| `ActivityBackfill` | Première exécution seulement, en `.utility`. |
| `HeatmapView` / `HeatmapStrip` | La vue. |

**Alimentation.** L'index consomme **les mêmes notifications FSEvents que
RFC-003** — pas un second watcher. À chaque événement, on lit ce qui a été ajouté
depuis l'offset connu, et rien d'autre.

**Repris tel quel :**

| Brique | `fichier:ligne` | Pourquoi |
|---|---|---|
| Modèle `[Int](24)` + `[[String: Int]](24)` | `HeatmapAggregator.swift:14-21` | Compte et projets par heure. |
| `viewingDate` + `advanceDay(by:)` clampé au futur | `:69-78` | |
| Rejet des scans obsolètes si le jour a changé pendant le scan | `:50-55` | |
| Pré-filtre par mtime/ctime avant d'ouvrir un fichier | `:131-142` | Bonne idée, insuffisante seule. |
| Rejet rapide `line.contains("\"timestamp\":")` avant `JSONSerialization` | `:193` | À garder dans l'indexeur. |
| `decodeProjectDirName` | `:215-219` | Repli `-Users-foo-bar` quand aucune ligne ne porte de `cwd`. |

**Écarté :** `scan(_ url:)` (`:157-209`) — c'est exactement ce que l'index
remplace. Et le cache 60 s en mémoire (`:27`, `:34-40`) devient inutile : avec un
index, la lecture d'une journée est O(24).

**Budget.** Repos : **0** — l'index n'est touché que sur un événement FSEvents
déjà émis par RFC-003. Écriture incrémentale : quelques Ko de tail parsés,
< 1 ms. Backfill initial : **une fois**, en `.utility`, ~7 s sur 379 Mo, à ne
**jamais** refaire. Lecture heatmap : < 1 ms. RSS +1 Mo (curseurs) + le cache du
moteur de stockage.

## 4. Alternatives Considered

**Garder le scan à la demande de la référence.** Écarté : c'est R2.

**Un index en mémoire seulement, reconstruit à chaque lancement.** Écarté : la
reconstruction, c'est le scan complet — le coût qu'on cherche à supprimer, payé à
chaque démarrage.

**Un fichier JSON plutôt que SQLite.** Tentant (zéro dépendance, et SQLite via
`libsqlite3` reste du C à emballer). Mais une réécriture complète du JSON à
chaque mise à jour ramène le problème d'écriture qu'on vient de résoudre en
lecture. Cf. Q1.

**Dériver la heatmap de l'index de RFC-004.** Impossible : RFC-004 prend ses
chiffres de l'API, qui ne donne pas de granularité horaire par projet.

## 5. Action plan

| # | Tâche | Statut | % |
|---|---|---|---|
| T1 | Choix du moteur de stockage (Q1) | todo | 0 |
| T2 | `IndexCursorStore` + **détection de troncature** (cf. pièges) | todo | 0 |
| T3 | `ActivityIndex` : `record` + `hours(for:)` | todo | 0 |
| T4 | Branchement sur les événements FSEvents de RFC-003 | todo | 0 |
| T5 | `ActivityBackfill` en `.utility`, exécuté une seule fois | todo | 0 |
| T6 | `HeatmapView` + navigation `‹` `›` + survol par heure | todo | 0 |
| T7 | Mesure ciblée : `/usr/bin/time -l` sur le backfill, relevé du max RSS | todo | 0 |

**Piège central.** Les jsonl sont append-only, mais Claude Code peut **réécrire**
un fichier (compaction, reprise de session). Le curseur doit stocker
`(inode, taille, mtime)` et **repartir de zéro si la taille diminue**. C'est le
seul cas de corruption d'index possible, et il est silencieux.

**Critère de sortie.** La heatmap se calcule sur un `~/.claude/projects` de plus
de 500 Mo **en moins de 2 s et sans dépasser le plancher RSS de plus de 40 Mo**
pendant le backfill. Après le backfill, ouvrir la heatmap ne lit **aucun** jsonl
en entier — vérifié par `fs_usage`.

## 6. Open Questions

**Q1 — SQLite ou fichier binaire compact ?**
SQLite via `libsqlite3` reste sans dépendance externe et donne les requêtes
gratuitement. Un format binaire maison est plus léger mais tout est à écrire.

```sh
# Ordre de grandeur du volume à indexer, pour dimensionner le choix :
find ~/.claude/projects -name '*.jsonl' | wc -l
du -sh ~/.claude/projects
/usr/bin/time -l grep -c '"timestamp"' $(find ~/.claude/projects -name '*.jsonl' | head -20) 2>&1 | tail -3
```

**Q2 — Que fait-on des jsonl supprimés ?**
Claude Code ne supprime pas ses transcripts, mais l'utilisateur peut nettoyer.
Les compteurs historiques doivent-ils survivre à la disparition du fichier
source ? Oui a priori — c'est tout l'intérêt d'un index — mais alors l'index
diverge du disque et ne peut plus être reconstruit à l'identique.

**Q3 — Le backfill doit-il être proposé ou automatique ?**
7 s de `.utility` au premier lancement, c'est peu. Mais lire l'intégralité des
transcripts sans le dire est une opération que l'utilisateur mérite de connaître.
