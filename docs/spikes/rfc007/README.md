# RFC-007 — les quatre cas qui restent

Prêt à jouer. Ce dossier tient le nécessaire : un fichier de réglages où
`vibe-hook` est le **seul** hook `PermissionRequest`, en `defaultMode: manual`,
et un projet jetable avec un fichier à modifier.

Deux cas sur six ont été prouvés le 2026-08-21 — `Bash` autorisé et refusé.
Restent `Edit` dans les deux sens, et `AskUserQuestion` dans les deux sens.

## Le piège qui annule la manche avant qu'elle commence

**`permissions.defaultMode: "auto"` dans `~/.claude/settings.json` l'emporte sur
tout `--settings` et tout `--permission-mode`.** Il y est en ce moment. Tant
qu'il y est, rien ne demande jamais, et les quatre cas rendent un faux négatif.

```sh
# Avant : remettre le fichier utilisateur en manuel.
#   "permissions": { "defaultMode": "manual", … }
# Après : le rendre à "auto".
```

C'est la seule modification à faire dans le fichier utilisateur, et elle est à
la main : `ClaudeSettingsWriter` n'est pas là pour changer un mode.

## Lancer

```sh
make build-release                       # vibe-hook doit être à jour
make stop                                # une seule instance, cf. défaut #2
make run-release &                       # l'app qui écoute

cd docs/spikes/rfc007/project
claude --settings ../settings.json --permission-mode manual
```

## Les quatre cas

| # | Ce qu'on tape | Ce qu'on attend dans l'encoche | Ce qu'on attend dans le terminal |
|---|---|---|---|
| 3 | « Remplace REMPLACER-MOI par BONJOUR dans cible.txt » puis **Autoriser** | un diff rouge/vert, la ligne 2 seule | le fichier est modifié, l'agent continue |
| 4 | idem, puis **Refuser** | le panneau disparaît | l'agent dit le refus et **ne réessaie pas autrement** |
| 5 | « Pose-moi une question à choix multiples sur X » puis **cliquer une option** | les options, une par ligne, sous la question | l'agent poursuit **avec l'option choisie**, sans redemander |
| 6 | idem, puis **Refuser** | le panneau disparaît | l'agent demande ce que veut l'utilisateur, il ne devine pas |

Le cas 5 est le seul qui n'a jamais tourné. Il repose sur le détournement
`deny` + message (`QuestionAnswer.denyMessage(for:)`), et sur un fait lu dans le
binaire 2.1.239 : `AskUserQuestion` déclare `requiresUserInteraction()`, donc
Claude Code **jette** tout `allow` venu d'un hook pour cet outil et retombe sur
son propre sélecteur. C'est pourquoi le bouton s'appelle « Répondre dans le
terminal » sur une question, et pourquoi « Toujours autoriser » n'y est pas.

Ce qu'il faut regarder dans le terminal au cas 5 : que l'agent **enchaîne** sur
l'option choisie. S'il repose la question ou s'excuse d'avoir été refusé, le
détournement ne passe pas et le libellé du message est à revoir — c'est le seul
endroit où le produit dépend de la façon dont un modèle lit une phrase.

## Ce qui n'est pas dans ces quatre cas

- **« Toujours autoriser » honoré à la session suivante** — sur un `Bash`, pas
  sur une question. Écrire la règle, quitter, relancer, refaire le même appel :
  rien ne doit s'afficher.
- **`make perf` pendant une attente** — le critère de sortie demande 0 réveil
  pendant que le panneau attend une personne.

## Après

Rendre `~/.claude/settings.json` à `"defaultMode": "auto"`. Le dossier de ce
spike peut rester : il ne touche rien tant qu'on ne le passe pas en `--settings`.
