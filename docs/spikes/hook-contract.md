# Spike — contrat de hook Claude Code

**Date** : 2026-08-20 · **Version** : Claude Code 2.1.234 · **Bloque** : RFC-006, RFC-007

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

## Conséquence

**Le sort de RFC-006 et RFC-007 reste indéterminé.** Ce spike devait trancher, il
ne l'a pas fait — et le reconnaître vaut mieux que de bâtir 8 à 12 jours-homme sur
une hypothèse.

Ce qu'il faut pour conclure, et qui demande une main humaine :

```sh
cd docs/spikes/hook/project
claude --settings ../settings.json --permission-mode manual
# puis, dans la session : « Lis le fichier /etc/hosts »
# → si le hook fonctionne, Claude annonce un refus portant « REFUS-SPIKE-7f3a »
#   et hook/received.jsonl contient la demande.
```

Ce qui **ne** dépend **pas** de cette réponse : RFC-012 (alertes) tire ses quatre
signaux du transcript, comme RFC-003 l'a établi. Le cœur du produit tient quoi
qu'il arrive.
