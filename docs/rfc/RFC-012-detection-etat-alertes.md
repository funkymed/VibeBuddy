# RFC-012 — Détection d'état et alertes

| | |
|---|---|
| **Status** | todo (0 %) |
| **Author** | Cyril Pereira |
| **Created** | 2026-08-19 |
| **Updated** | 2026-08-19 |
| **Phase** | 4 — Intégration |
| **Depends on** | RFC-003, RFC-006 |
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
| T1 | Étendre RFC-006 aux événements `Stop`, `StopFailure`, `Notification`, `SessionStart`, `SessionEnd`, `SubagentStop` | todo | 0 |
| T2 | `SessionStateMachine` pure + tests de toutes les transitions | todo | 0 |
| T3 | Test explicite : `SubagentStop` ne déclenche aucune alerte | todo | 0 |
| T4 | `AlertBus` (`AsyncStream`) | todo | 0 |
| T5 | `AlertPolicy` : dédup, débit, silence si terminal au premier plan | todo | 0 |
| T6 | `AlertPresenter` : pop-out de la notch | todo | 0 |
| T7 | Suivi simultané de N sessions, chacune son état | todo | 0 |
| T8 | `perfcheck.sh` B — vérifier que rien n'ajoute de réveil | todo | 0 |

**Critère de sortie.** Sur **trois** sessions Claude simultanées dans trois
projets : chaque fin de tour produit **exactement une** alerte, attribuée à la
bonne session, sur dix essais. Une demande de permission produit une alerte
`awaiting` distincte de l'alerte de fin. Un `SubagentStop` n'en produit aucune.
Aucune alerte quand le terminal concerné est déjà au premier plan.
`perfcheck.sh B` inchangé par rapport à RFC-003.

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
