# RFC-012 — Détection d'état et alertes

| | |
|---|---|
| **Status** | in-progress (95 %) — chemin complet vérifié en réel ; **l'attente de réponse est détectée** |
| **Author** | Cyril Pereira |
| **Created** | 2026-08-19 |
| **Updated** | 2026-08-20 |
| **Phase** | 4 — Intégration |
| **Depends on** | RFC-003 · ~~RFC-006~~ — voir §3 |
| **Related** | RFC-005 (expression du buddy) · RFC-010 (préférences) · R11 |
| **Blocks** | — |

## 1. Context & Problem

C'est la raison d'être du produit, avec le suivi de consommation : **savoir sans
regarder que l'agent a fini, ou qu'il attend une réponse.** Le reste — la liste
des sessions, la heatmap, le saut vers le terminal — sert à investiguer une fois
qu'on a été alerté. L'alerte, elle, doit arriver sans qu'on cherche.

Le découpage initial ne traitait pas ce besoin comme un objectif. Il l'avait
dilué dans une RFC « Préférences, apparence et surfaces expressives », à côté du
choix de la couleur du buddy. Cette RFC corrige ce classement.

**Et le mécanisme était mal choisi.** L'implémentation de référence, et RFC-006
qui la recopiait, n'enregistrent que trois événements de hook —
`PermissionRequest`, `PreToolUse`, `UserPromptSubmit` — puis **déduisent** la fin
d'une session de l'absence d'écriture dans le transcript. C'est une heuristique,
avec le délai et les faux positifs qui vont avec.

Or Claude Code expose quatorze événements. Vérifié dans `~/.claude/settings.json`
le 2026-08-19 :

```
Notification, PermissionRequest, PostCompact, PostToolUse, PreCompact,
PreToolUse, SessionEnd, SessionStart, Stop, StopFailure, SubagentStart,
SubagentStop, TeammateIdle, UserPromptSubmit
```

Deux d'entre eux répondent exactement à la question posée, par événement et sans
déduction :

| Événement | Signification |
|---|---|
| **`Stop`** | l'agent a terminé son tour |
| **`Notification`** | l'agent réclame l'attention de l'utilisateur |
| `SessionStart` / `SessionEnd` | cycle de vie exact, sans inférence par mtime |
| `StopFailure` | le tour s'est terminé en erreur — à distinguer d'une fin normale |
| `SubagentStop` | fin d'un sous-agent : **ne doit pas** déclencher l'alerte de fin de tâche |

## 2. Goals / Non-goals

**Goals.** Une machine à états par session, alimentée par les événements de hook
et non par des heuristiques. Une alerte quand un tour se termine et quand
l'attention est requise. Plusieurs sessions suivies simultanément, chacune avec
son état propre. Anti-doublon et limitation de débit.

**Non-goals.**
- Le transport des hooks (RFC-006).
- Le rendu du buddy (RFC-005) — cette RFC produit l'état, RFC-005 l'exprime.
- Les préférences d'activation (RFC-010).
- **Le lien avec le mobile** — hors périmètre, mais la conception ci-dessous en
  tient compte : les alertes passent par un bus, pas par des appels directs à
  l'UI, précisément pour qu'un second consommateur puisse s'y brancher.

**Portée agent.** Claude Code uniquement, décision assumée (R11). La machine à
états est néanmoins définie en termes neutres — `AgentSession`, pas
`ClaudeSession` — pour que le jour où un second agent arrive, c'est une source
d'événements qui s'ajoute, pas un modèle à refaire.

## 3. Proposed Solution

### Machine à états

```
        SessionStart
             ↓
        ┌─ idle ─┐◄──────────────── Stop
        │        │
UserPromptSubmit │                  Notification
        ↓        │                       ↓
     working ────┴──────────────► awaiting  (attention requise)
        │                              │
        │  PermissionRequest ──────────┘
        ↓
     failed ◄── StopFailure          SessionEnd → (retirée)
```

| État | Origine | Ce que voit l'utilisateur |
|---|---|---|
| `idle` | `SessionStart`, `Stop` | rien, ou le buddy au repos |
| `working` | `UserPromptSubmit`, `PreToolUse` | buddy actif |
| `awaiting` | `Notification`, `PermissionRequest` | **alerte attention** |
| `finished` | `Stop` après un `working` | **alerte fin de tour** |
| `failed` | `StopFailure` | alerte fin, marquée en erreur |

`SubagentStop` ne provoque **aucune** transition : un sous-agent qui se termine
n'est pas la fin du travail, et confondre les deux produirait une alerte à chaque
délégation.

### Modules

| Module | Responsabilité |
|---|---|
| `SessionStateMachine` | **Pure**, testable : `(état, événement) → (état, [Alert])`. |
| `AlertBus` | Publie les alertes. Un `AsyncStream`, pas un appel direct à l'UI — c'est le point d'accroche du futur relais mobile. |
| `AlertPolicy` | Anti-doublon, limitation de débit, fenêtre de silence. |
| `AlertPresenter` | Consomme le bus : pop-out de la notch, son, voix. |

### Politique d'alerte

Trois garde-fous, tous issus de défauts observés dans l'implémentation de référence :

- **Anti-doublon** sur `(sessionID, type, minute)`. La référence bucket déjà sa
  clé à la minute (`NotchContentView.swift:545-548`) pour ne pas fusionner deux
  fins successives de la même session — même besoin ici, raison inverse.
- **Limitation de débit** : au plus une alerte visuelle toutes les 12 s, valeur
  reprise de `SpeechController.swift:40-131`.
- **Silence si le terminal est déjà au premier plan.** Si l'utilisateur regarde
  la session concernée, l'alerte est du bruit. Sonde fournie par RFC-003
  (`TerminalFocusProbe`).

### Budget

**0 réveil ajouté.** Tout est piloté par des événements de hook entrants ; aucune
horloge n'est créée. L'alerte visuelle emprunte le cadenceur de RFC-005 pendant
sa durée d'affichage, puis rend la main à `AnimationBudget.still`.

## 4. Alternatives Considered

**Déduire la fin d'une session de l'inactivité du transcript.** C'est ce que fait
la référence, et c'est ce qui a motivé cette RFC. Latence de plusieurs secondes,
faux positifs quand le modèle réfléchit longtemps, et incapacité à distinguer
« terminé » de « en attente ». `Stop` et `Notification` donnent la réponse
directement.

**Utiliser les notifications système (`UNUserNotificationCenter`).** Écarté pour
le v1 : ça demande une autorisation, ça empile dans le centre de notifications, et
ça double une UI qu'on a déjà sous les yeux. La notch *est* la surface. À rouvrir
avec le relais mobile.

**Alerter aussi sur `PostToolUse`.** Trop bavard : un tour normal en produit des
dizaines.

**Appeler l'UI directement au lieu de passer par un bus.** Plus simple d'un
fichier, mais le relais mobile annoncé devient alors une modification de chaque
site d'appel. Le bus coûte ~40 lignes maintenant.

## 5. Action plan

| # | Tâche | Statut | % |
|---|---|---|---|
| T1 | ~~Étendre RFC-006 aux événements de hook~~ — **annulée**, les signaux sont dans le transcript | **n/a** | — |
| T2 | `SessionStateMachine` pure + tests de toutes les transitions | **done** | **100** |
| T3 | Test explicite : `SubagentStop` ne déclenche aucune alerte | **done** | **100** |
| T4 | `AlertBus` (`AsyncStream`) | **done** | **100** |
| T5 | `AlertPolicy` : dédup, débit, silence si terminal au premier plan | **done** | **100** |
| T6 | `AlertPresenter` : pop-out de la notch | **done** | **100** |
| T9 | Compteur de sessions vivantes dans la pastille | **done** | **100** |
| T7 | Suivi simultané de N sessions, chacune son état | **done** | **100** |
| T8 | `perfcheck.sh` B — vérifier que rien n'ajoute de réveil | **done** | **100** |
| T10 | **Attente de réponse** : `tool_use` de question sans `tool_result` → `.awaiting` + `needsAttention` | **done** | **100** |

### T10 — le cinquième signal, encore dans le transcript

L'objectif n°1 nomme deux choses : « a terminé » **et** « attend une réponse ».
Seule la première était détectée ; la seconde était rangée derrière RFC-006 avec
les permissions.

Elle n'en avait pas besoin. Mesuré sur un vrai transcript : `AskUserQuestion`
apparaît comme un `tool_use` avec un `id`, et la réponse revient en `tool_result`
portant le même `tool_use_id`. Entre les deux, **rien n'est écrit** — et c'est
exactement la fenêtre à détecter. `ExitPlanMode` a la même forme : l'agent
s'arrête jusqu'à l'approbation du plan.

La liste des outils-questions est **fermée** (`QuestionTools.names`). Dans le
fichier, un `Bash` qui tourne encore et une question sans réponse sont
indiscernables — tous deux « un usage sans résultat ». Seuls des outils qui
*sont* des questions par définition peuvent être lus comme une attente ; déduire
d'un délai transformerait chaque commande lente en fausse alerte.

Ce qui reste derrière RFC-006 : la demande de **permission** en cours. Elle est
résolue interactivement et n'est écrite qu'une fois terminée — rien dans le
fichier ne dit qu'elle a lieu pendant qu'elle a lieu.

Vérification sur le transcript de la session qui a écrit ce code, tronqué juste
après la question puis juste après la réponse :

```
PROBE pending.jsonl  awaiting= true  question= Quel système de rendu unique garder pour le buddy ?
PROBE answered.jsonl awaiting= false question= —
```

**Critère de sortie — atteint le 2026-08-19, sauf l'alerte d'attente.**

| Point | État |
|---|---|
| Une fin de tour produit exactement une alerte attribuée | **PASS** — vérifié en réel : `★ ALERTE notch finished` |
| Trois sessions simultanées → trois états reconnus, une interruption | **PASS** — test d'intégration |
| Un sous-agent qui finit n'alerte pas | **PASS** — test dédié |
| Silence si le terminal concerné est au premier plan | **PASS** — test dédié |
| Aucun réveil ajouté | **PASS** — 0,000 réveil inactif/s, CPU 0,000 %, 8,0 Mo |
| Alerte `needsAttention` sur permission en attente | **reporté à RFC-007** — voir ci-dessous |

### Ce que le transcript donne, et ce qu'il ne donne pas

RFC-003 a établi que la fin de tour (`system/turn_duration`), l'échec d'outil
(`is_error`), le cycle de vie des sous-agents (`started`/`result`) et le mode de
permission sont **tous dans le transcript**. Cette RFC ne dépend donc plus de
RFC-006, et l'objectif n°1 du produit est atteint sans écrire une ligne dans
`~/.claude/settings.json`.

**Une chose n'y est pas** : « bloqué sur une demande de permission ». Le prompt
est interactif et résolu avant que quoi que ce soit ne s'écrive. `needsAttention`
est déclaré dans le type et n'est jamais produit — il arrivera avec RFC-007.

Cela dit, la fin de tour *est* déjà « il attend ton retour » : après un
`turn_duration`, l'entrée suivante est un `user` dans la majorité des cas
observés. Les deux objectifs énoncés — « a terminé » et « attend une réponse » —
sont donc couverts pour le cas courant.

### Le bug que seul un test d'intégration pouvait trouver

Le premier test bout en bout a échoué immédiatement, et pour une bonne raison.

Le parseur scanne du plus récent au plus ancien. Il rencontrait donc
`turn_duration`, **puis** le `tool_use` du tour qui venait de s'achever — lequel
remettait `action = .shell`. La machine à états concluait « en cours » sur une
session terminée : **l'alerte ne pouvait jamais partir.** Une fois la frontière
de tour franchie en remontant, tout ce qui est plus ancien est de l'histoire.

Ce défaut est invérifiable à la main, et pas par manque de rigueur : la
vérification manuelle échoue deux fois d'affilée **pour de bonnes raisons**. La
session qui observe est elle-même occupée à exécuter le test, donc jamais
terminée ; et son terminal est au premier plan, donc la politique supprime
correctement ce qui aurait pu partir. Les deux comportements sont justes, et
ensemble ils rendent l'observation impossible.

D'où deux coutures introduites délibérément : une racine de projet temporaire, et
une **source de liveness injectable** dans `SessionStore`. Ce n'est pas de la
souplesse gratuite — sans elles, ce chemin n'aurait pu être exercé qu'à la main,
c'est-à-dire jamais.

### La surface : trois éléments, trois poids

La pastille porte désormais l'état sous trois formes, hiérarchisées
délibérément :

| Élément | Place | Poids visuel |
|---|---|---|
| **Le buddy** | oreille gauche | couleur pleine, halo vif — il porte l'état et doit accrocher l'œil |
| **Le compteur `×N`** | oreille droite | blanc à 72 %, halo léger — une information qu'on va chercher |
| **L'alerte** | oreille droite, **à la place** du compteur, 4 s | pastille de couleur + nom du projet |

Les trois occupent les slots de `PillLayout` (RFC-002), pas des `overlay`
décalés à la main. **L'alerte remplace le compteur au lieu de s'y ajouter** :
les deux disent la même sorte de chose, et les empiler ferait grandir la
pastille deux fois pour un seul événement.

Le milieu reste vide : c'est le trou matériel, et tout ce qu'on y dessine est
invisible par construction.

Le compteur est **caché à zéro** plutôt qu'affiché `×0` — une absence se dit
mieux par le silence, et une pastille vide est déjà l'information. Il ne
déclenche un redessin que si le nombre change, pas à chaque instantané : avec un
rafraîchissement toutes les 2 s en activité, reconstruire la vue pour un chiffre
identique serait du gaspillage pur.

La couleur porte le sens avant la forme : `=**=` en vert, `=xx=` en rouge. Au
coin de l'œil, la teinte arrive avant qu'on ait lu le visage.

### La règle qui structure la conception

**Une alerte appartient à une transition, jamais à un état.** Un test vérifie que
dix rafraîchissements d'une session terminée produisent exactement une alerte.
Sans cette règle, chaque relecture du transcript renotifierait — et l'app en relit
un à chaque événement FSEvents.

Cinq tests ne vérifient que des **silences**, parce que ce sont les défauts qui
font désinstaller ce genre d'outil : sous-agent en vol, outil encore actif,
session morte, terminal au premier plan, rafale simultanée. Et les alertes
supprimées sont conservées **avec leur motif** : un système de notification qui
jette des choses en silence est impossible à auditer.

## 6. Open Questions

**Q1 — Quelle charge utile portent réellement `Stop` et `Notification` ?**
À capturer avant d'écrire la machine à états : les champs disponibles décident si
on peut attribuer l'alerte à la bonne session sans passer par le `cwd`.

```sh
# Enregistrer un hook espion sur une COPIE de settings.json, puis lire ce qui tombe :
mkdir -p /tmp/nb-hookspy && cat > /tmp/nb-hookspy/spy.sh <<'SH'
#!/bin/sh
{ printf '%s ' "$(date +%H:%M:%S)"; cat; echo; } >> /tmp/nb-hookspy/events.jsonl
SH
chmod +x /tmp/nb-hookspy/spy.sh
# … enregistrer spy.sh sur Stop / Notification / SessionStart / SessionEnd,
# faire tourner une session, puis :
python3 -c "
import json,sys
for l in open('/tmp/nb-hookspy/events.jsonl'):
    t,_,j = l.partition(' ')
    try: d=json.loads(j); print(t, d.get('hook_event_name'), sorted(d))
    except: pass"
```

**Q2 — `Notification` est-il émis pour autre chose que l'attente d'une réponse ?**
S'il sert aussi à des messages informatifs, il faut filtrer sur sa charge utile,
sinon l'alerte « attention requise » criera pour rien.

**Q3 — Que fait l'alerte quand plusieurs sessions finissent en même temps ?**
Une alerte par session risque la rafale. Grouper (« 3 sessions terminées ») ou
sérialiser avec la limitation de débit ?

**Q4 — L'alerte doit-elle persister jusqu'à acquittement ?**
Un pop-out de 3 s manqué pendant qu'on est ailleurs, c'est une alerte perdue.
Une marque persistante sur la pastille jusqu'au prochain regard serait plus
fiable — mais c'est un état de plus à gérer.
