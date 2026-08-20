# RFC-007 — Interception des permissions : file, rendu, décisions

| | |
|---|---|
| **Status** | todo (0 %) |
| **Author** | Cyril Pereira |
| **Created** | 2026-08-19 |
| **Updated** | 2026-08-19 |
| **Phase** | 4 — Intégration |
| **Depends on** | RFC-002, RFC-003, RFC-006 |
| **Related** | R1, R6, D6 |
| **Blocks** | — |

## 1. Context & Problem

C'est la fonction différenciante de vibebuddy : quand Claude demande
l'autorisation de lancer une commande, la notch se déploie, montre la demande
sous forme lisible, et rend la décision — sans quitter l'éditeur.

C'est aussi la fonction la plus contrainte. Elle dépend d'un protocole externe
non documenté (RFC-006), elle **écrit dans les réglages de l'utilisateur**, et
ses modes de panne sont silencieux.

Quatre pièges identifiés dans la référence, chacun corrigeant un bug réel :

- **Une file, pas un « pending » unique.** Le commentaire `HookBridge.swift:15-17`
  documente la régression : avec un seul emplacement, un burst d'appels d'outils
  parallèles fait que chaque nouvelle demande **dénie silencieusement la
  précédente**, et seule la dernière survit.
- **`AskUserQuestion` n'a pas de chemin « répondre ».** Le hook ne peut
  qu'autoriser ou refuser. La référence refuse l'outil en formulant le message de
  refus comme la réponse choisie (`HookBridge.swift:232-250`, formulation exacte
  ligne 244) ; le modèle le lit comme un résultat d'outil et poursuit. Hack
  majeur, documenté nulle part ailleurs.
- **L'utilisateur peut répondre dans le terminal.** Il faut alors retirer la
  demande de la notch (RFC-006 détecte la déconnexion du hook).
- **Une demande peut devenir obsolète.** `dismissStalePermissions`
  (`HookBridge.swift:200-220`) l'infère d'une activité jsonl plus de 2 s après la
  création de la demande.

Enfin, le coût : `NotchContentView.swift:773` fait pulser un texte via
`TimelineView(.periodic(by: 0.05))` — **20 Hz tant qu'une permission est en
attente**, c'est-à-dire pendant tout le temps où l'utilisateur réfléchit.

## 2. Goals / Non-goals

**Goals.** File FIFO ; rendu structuré selon l'outil (shell, diff, URL,
`AskUserQuestion`) ; Deny / Allow / Always-allow ; persistance dans
`permissions.allow` ; les trois mécanismes de péremption.

**Non-goals.** Le transport et le schéma de décision (RFC-006). La fenêtre (RFC-002).

**Interdit dans cette RFC :** toute animation permanente dans le panneau. Le
panneau de permission est **statique** — il s'affiche, il attend, il disparaît.

## 3. Proposed Solution

| Module | Responsabilité |
|---|---|
| `PermissionQueue` | `@Observable`, MainActor. FIFO + péremption. Implémente `HookEventSink`. |
| `PermissionRequestModel` | Parse le `tool_input` en une présentation typée. **Tronque au stockage**, pas seulement à l'affichage. |
| `PermissionPresentation` | enum `.hidden / .checking / .shown` — remplace le couple `permissionSuppressed` + `permissionChecked` (`NotchContentView.swift:154-162`) qui existe pour éviter un flash d'une frame. |
| `PermissionPanelView` + `ShellSummaryView` / `DiffSummaryView` / `URLSummaryView` / `AskQuestionView` | Vues **séparées**, chacune < 200 lignes (règle D2). |

**Repris tel quel :**

| Brique | `fichier:ligne` | Pourquoi |
|---|---|---|
| File FIFO | `HookBridge.swift:12-28` | Cf. la régression documentée `:15-17`. |
| Court-circuit always-allow avant mise en file | `HookBridge.swift:167-171` | |
| Filtrage des règles scopées `Bash(npm install:*)` | `HookBridge.swift:64-67` | On ne compare que les entrées nues à `tool_name` ; le matcher natif de Claude Code gère le reste — ne pas réimplémenter son langage de motifs. |
| **`AskUserQuestion` répondu via `deny` + `message`** | `HookBridge.swift:232-250` | Formulation exacte ligne 244. |
| Parsing tolérant des options | `HookBridge.swift:377-433` | Accepte `questions[0].options`, les clés `label`/`value`/`text`, et un simple `[String]`. |
| `handleHookDisconnect` | `HookBridge.swift:187-198` | |
| Rendu de diff rouge/vert | `NotchContentView.swift:1885-1930` | Visuel repris, code extrait en vue autonome. |

**Modifié :**
- `dismissStalePermissions` (`:200-220`) apparie par `cwd` faute d'accord des
  `session_id` (`:207-208`). Avec le mapping PID de RFC-006, on apparie par
  `sessionID` et le `cwd` devient un repli.
- Suppression quand le terminal est déjà au premier plan
  (`NotchContentView.swift:500-508` + `TerminalJumper.swift:162-211`) : utile,
  mais l'implémentation lance `tmux list-panes -a` **à l'arrivée de chaque
  permission** (`TerminalJumper.swift:190-193`). → cache du mapping pane↔PID,
  invalidé au changement d'application frontmost. Sonde fournie par RFC-003
  (`TerminalFocusProbe`) — **ne pas dépendre de RFC-008**, ce serait un cycle.
- Le pulse à 20 Hz (`NotchContentView.swift:773`) : supprimé.

**Budget.** 0 % au repos. À l'arrivée d'une demande : un rendu de panneau
560×460, cible **< 3 % sur ~200 ms puis 0**. RSS +2 Mo transitoires — le
`tool_input` d'un `Edit` peut contenir un `new_string` volumineux, d'où la
troncature au stockage.

## 4. Alternatives Considered

**Un seul emplacement « pending » plutôt qu'une file.** Écarté : c'est le bug que
la référence a corrigé, et son commentaire le documente.

**Réimplémenter le langage de motifs de `permissions.allow`.** Écarté : Claude
Code possède son propre matcher (`Bash(npm install:*)`). Le dupliquer, c'est
garantir une divergence. On ne gère que les entrées nues et on laisse le reste
au matcher natif.

**Répondre à `AskUserQuestion` par `allow` + une réponse hors bande.** Il n'existe
pas de canal pour ça. Le détournement de `deny` + `message` est le seul chemin,
et il fonctionne parce que le modèle lit le message comme un résultat d'outil.

**Ne pas offrir « Always allow ».** Ce serait plus sûr (aucune écriture dans
`settings.json`), mais c'est la moitié de l'intérêt de la fonction. On garde,
avec les parades de R1 : sauvegarde, écriture atomique, consentement explicite.

## 5. Action plan

| # | Tâche | Statut | % |
|---|---|---|---|
| T1 | `PermissionRequestModel` + parsing par outil + troncature au stockage | todo | 0 |
| T2 | `PermissionQueue` FIFO + court-circuit always-allow | todo | 0 |
| T3 | Les 3 péremptions : déconnexion, obsolescence jsonl, terminal au premier plan | todo | 0 |
| T4 | `PermissionPanelView` + `ShellSummaryView` | todo | 0 |
| T5 | `DiffSummaryView` (rouge/vert) et `URLSummaryView` | todo | 0 |
| T6 | `AskQuestionView` + le détournement `deny` + `message` | todo | 0 |
| T7 | Écriture de `permissions.allow` via le `ClaudeSettingsWriter` de RFC-006 | todo | 0 |
| T8 | **Écran de consentement au premier lancement, affichant le diff exact** (parade R1) | todo | 0 |
| T9 | Cache du mapping pane↔PID pour la sonde de premier plan | todo | 0 |
| T10 | Test du cycle de vie de la file (cf. Q3) | todo | 0 |

**Critère de sortie.** Un `Bash`, un `Edit` et un `AskUserQuestion` sont chacun
autorisés **et** refusés depuis la notch — six cas, et le terminal reprend la main
correctement dans les six. « Always allow » écrit dans `settings.json` après
consentement explicite, et Claude Code honore la règle à la session suivante.
`perfcheck.sh` montre **0 réveil** pendant qu'une demande attend.

## 6. Open Questions

**Q1 — Que fait la notch si l'app démarre alors qu'une demande est déjà en cours ?**
Le hook attend sur un socket qui n'existait pas. Il sortira sur `exit(0)`
(RFC-006) et Claude retombera sur son interface — acceptable, mais à vérifier.

**Q2 — Combien de demandes empilées affiche-t-on ?**
La référence montre un compteur « N en attente ». Au-delà de 3 ou 4, la file
signale plutôt que quelque chose ne va pas.

**Q3 — Le cycle de vie de la closure de réponse est-il testable ?**
`PendingPermission.respond` est une closure `@Sendable` retenue qui **maintient
la connexion socket ouverte** (`HookBridge.swift:349`). Toute fuite bloque Claude
Code jusqu'au timeout. C'est l'invariant le plus important de la RFC.

```sh
# Vérifier qu'aucun descripteur ne fuit après un cycle de 20 demandes :
lsof -p $(pgrep -x NotchBuddy) | grep -c unix
# Relever avant / après, l'écart doit être nul.
```

**Q4 — Faut-il journaliser les décisions ?**
Un journal local des allow/deny aide à diagnostiquer R6 (réponse rejetée en
silence) et rassure sur ce que l'app a autorisé. Mais c'est un fichier de plus
qui trace l'activité de l'utilisateur.
