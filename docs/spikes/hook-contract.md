# Spike — contrat de hook Claude Code

**Date** : 2026-08-20 · **Repris le** : 2026-08-21 · **Version** : Claude Code 2.1.234
puis **2.1.237** · **Bloque** : RFC-006, RFC-007

## Question

RFC-007 (interception des permissions) suppose qu'un hook `PermissionRequest`
reçoit la demande sur stdin et que sa décision est honorée. Si c'est faux, RFC-006
et RFC-007 tombent.

## Protocole

Aucune écriture dans `~/.claude/`. Claude Code accepte `--settings <fichier>`, ce
qui permet d'enregistrer des hooks dans un fichier isolé. Hook espion consignant
stdin, puis refusant avec un message reconnaissable.

Fichiers : `hook/spy.sh`, `hook/any.sh`, `hook/settings.json`.

## Résultats

### Établi

**`--settings` charge bien les hooks.** Vérifié : `SessionStart`,
`UserPromptSubmit`, `PreToolUse` et `Stop` se déclenchent tous depuis un fichier
hors de `~/.claude/`.

Charges utiles relevées, utiles à RFC-012 :

| Événement | Champs |
|---|---|
| `SessionStart` | `cwd`, `session_id`, `source`, `transcript_path` |
| `UserPromptSubmit` | + `permission_mode`, `prompt`, `prompt_id` |
| `PreToolUse` | + `tool_name`, `tool_input`, `tool_use_id`, **`effort`** |
| `Stop` | + `last_assistant_message`, `stop_hook_active`, `background_tasks`, `session_crons` |

Deux gains inattendus : **`transcript_path` est fourni directement** — plus besoin
de deviner le chemin du jsonl — et **`effort` arrive dans `PreToolUse`**, ce que
RFC-003 obtient aujourd'hui en parsant le transcript.

### Non établi

**`PermissionRequest` ne s'est jamais déclenché.** Y compris lorsqu'une permission
a été *réellement* refusée : une lecture de `/etc/hosts` hors du répertoire de
travail a été bloquée, `PreToolUse` s'est déclenché, `PermissionRequest` non.

Hypothèse la plus probable, **non vérifiée** : ce hook n'intervient que sur un
prompt **interactif**. En mode `-p` il n'y a personne à interroger, donc Claude
refuse directement sans passer par le flux de permission.

La tentative en pseudo-terminal (`script -q`) n'a pas abouti : la session démarre
(`SessionStart` se déclenche) mais le prompt n'est pas soumis — piloter une
session interactive demande un vrai terminal, pas un stdin redirigé.

### Détail de configuration relevé au passage

`~/.claude/settings.json` porte `permissions.defaultMode: auto`, ce qui explique
que la plupart des outils s'exécutent sans jamais demander. Toute vérification du
chemin de permission doit en tenir compte.

## Reprise du 2026-08-21 — la question centrale est tranchée

Version 2.1.237. Trois manches, sans main humaine.

### 1. Le hook ne part toujours pas — mais pas pour la raison supposée

`--include-hook-events` énumère **tous** les hooks qui tournent. Sur un
`claude -p` avec ce même `settings.json` :

```
SessionStart:startup · UserPromptSubmit · PreToolUse:Read · Stop     (12 hooks)
```

Aucun `PermissionRequest`, `received.jsonl` jamais créé — alors que la lecture
de `/etc/hosts` **a bien été refusée**. Mais le refus venait du contrôle « hors
du répertoire de travail », qui court-circuite avant le circuit de permission.

Seconde manche avec un `Bash`, qui passe normalement par ce circuit : la commande
**s'est exécutée**. En mode `--print`, aucune permission n'est jamais demandée —
l'outil tourne. Le hook ne peut donc pas partir, et cela **n'apprend rien** sur
son existence.

### 2. Enregistrer un hook ne prouve rien

Un fichier de réglages déclarant `CeciNestPasUnEvenement` est accepté **en
silence**, sans avertissement. Claude Code ne valide pas les noms d'événements :
`PermissionRequest` dans un `settings.json` est indiscernable d'une faute de
frappe. C'est ce qui rendait la première manche ininterprétable.

### 3. Le binaire, lui, répond

`strings` sur `/Users/…/.local/share/claude/versions/2.1.237` :

| Preuve | Ce qu'elle établit |
|---|---|
| `executePermissionRequestHooks called for tool: ${e}` | la fonction existe |
| `hook_event_name:kt("PermissionRequest"), tool_name:H(), tool_input:Mn(), permission_suggestions:mt(…).optional()` | **le schéma de la charge utile**, `permission_suggestions` compris |
| `buildAllow(d, {decisionReason:{type:"hook", hookName:"PermissionRequest"}})` | une décision **`allow`** est honorée |
| `buildDeny(g.message ‖ "Permission denied by hook", …)` | une décision **`deny`** l'est aussi, avec son message |
| `{behavior:"allow", updatedInput:l, …}` | le hook peut **réécrire l'entrée** de l'outil |
| `if(a.interrupt)` sur la branche `deny` | il peut interrompre |
| `catch(s){T("PermissionRequest hook fai…")}` | un hook qui échoue **ne bloque pas** |
| « a plan_token requires a one-time project approval, which is not available in subagent or **PermissionRequest-hook sessions** » | le produit nomme ces sessions dans ses propres messages |

**La prémisse de RFC-007 tient.** Un hook `PermissionRequest` reçoit la demande,
et sa décision est honorée — `allow` comme `deny`.

### Ce qui reste

Une manche interactive, une minute, pour voir le hook partir en vrai. Elle ne
conditionne plus la faisabilité : elle confirme un contrat déjà lisible dans le
binaire.

Elle a eu lieu le 2026-08-21 et a réussi. Le harnais espion qui l'a portée a
été supprimé le 2026-08-25, le contrat étant établi ; celui de RFC-007 vit
dans `docs/spikes/rfc007/`.

Choisir un outil qui **demande vraiment** — un `Bash`, pas une lecture hors du
répertoire, qui est refusée en amont par un autre contrôle.

## Conséquence

**RFC-006 et RFC-007 sont faisables.** Le contrat que RFC-007 suppose est écrit
dans le binaire : un hook `PermissionRequest` reçoit `tool_name`, `tool_input` et
`permission_suggestions`, et sa décision est honorée — `allow`, `deny`, avec
réécriture de l'entrée et interruption. C'est la question qui bloquait 8 à
12 jours-homme.

Ce spike avait conclu à l'indétermination, et il avait raison de le faire : ce
qu'il observait ne permettait pas de trancher. Ce qui manquait n'était pas une
manche de plus au même endroit, c'était **de cesser d'interroger le comportement
pour interroger le produit** — `--include-hook-events` pour savoir ce qui part
vraiment, un nom d'événement bidon pour savoir si l'enregistrement prouve quelque
chose, puis `strings` sur le binaire.

Trois enseignements que la première manche ne pouvait pas donner :

1. **Un `settings.json` accepté ne veut rien dire.** Les noms d'événements ne
   sont pas validés.
2. **`--print` ne demande jamais de permission.** Un `Bash` s'y exécute
   directement. Toute manche non interactive était condamnée d'avance.
3. **Un refus n'est pas l'autre.** Lire hors du répertoire de travail est refusé
   par un contrôle en amont qui court-circuite le circuit de permission — c'est
   très probablement ce que mesurait la manche d'origine.

Reste une confirmation d'une minute, décrite plus haut. Elle ne conditionne plus
rien : elle vérifie qu'un contrat lisible dans le binaire se comporte comme il
est écrit.

Ce qui **ne** dépendait **pas** de cette réponse, et n'en dépend toujours pas :
RFC-012 (alertes) tire ses quatre signaux du transcript, comme RFC-003 l'a
établi. Le cœur du produit tient quoi qu'il arrive.
