# Gantt — VibeBuddy

Toutes les RFC, terminées comme en cours. Une ligne sous `── DONE ──` a son
fichier dans `done/` ; les deux ne divergent jamais.

Barre = 20 caractères = 100 %. █ fait · ░ restant.
Ordre = ordre de réalisation, pas ordre de numérotation.

```
── EN COURS ──
#   RFC      Titre                                          Avancement            %    Reste    Jalon
7   RFC-008  Vue sessions + saut terminal/tmux               ██████████████████░░  90 %   0,5-1 j  v1.1
8   RFC-017  Installer le hook depuis les réglages           ██████████████████░░  90 %   0,5 j    v1.1
9   RFC-014  Célébration de fin de tâche                     ░░░░░░░░░░░░░░░░░░░░   0 %   1-2 j    v1.1
10  RFC-015  Le son du buddy (paquet rechargeable)           ░░░░░░░░░░░░░░░░░░░░   0 %   1-2 j    v1.1
11  RFC-009  Index d'activité (heatmap + historique)         ░░░░░░░░░░░░░░░░░░░░   0 %   3-4 j    v1.2
12  RFC-016  Ponts agents et terminaux (opencode, tmux)      ░░░░░░░░░░░░░░░░░░░░   0 %   4-6 j    v1.2

── DONE ──
—   Spike    Keychain + oauth-usage                          ████████████████████ 100 %            v1
—   Spike    Contrat de hook                                 ████████████████████ 100 %            v1
—   RFC-011  Build, signature, distribution                  ████████████████████ 100 %            v1
—   RFC-007  Interception des permissions                    ████████████████████ 100 %            v1
—   RFC-006  Pont hook + socket Unix                         ████████████████████ 100 %            v1
—   RFC-002  Fenêtre notch (NSPanel, click-through)          ████████████████████ 100 %            v1
—   RFC-010  Réglages segmentés + aperçu de buddy            ████████████████████ 100 %            v1
—   RFC-013  Buddy interactif (regard, chasse, rire)         ████████████████████ 100 %            v1
—   RFC-004  Utilisation live (Keychain + OAuth)             ████████████████████ 100 %            v1
—   RFC-012  Détection d'état et alertes                     ████████████████████ 100 %            v1
—   RFC-005  Buddy : visage, format .buddy, rendu            ████████████████████ 100 %            v1
—   RFC-001  Socle applicatif, budget de performance         ████████████████████ 100 %            v1
—   RFC-003  Collecte de sessions (source de vérité unique)  ████████████████████ 100 %            v1
```

## Fiches

| RFC | Titre | Jalon |
|---|---|---|
| [Spike](../spikes/keychain-oauth-usage.md) | Keychain + oauth-usage | v1 |
| [Spike](../spikes/hook-contract.md) | Contrat de hook | v1 |
| [001](done/RFC-001-socle-applicatif.md) | Socle applicatif, cycle de vie, budget de performance | v1 |
| [002](done/RFC-002-fenetre-notch.md) | Fenêtre notch : NSPanel, click-through, multi-écran | v1 |
| [003](done/RFC-003-collecte-sessions.md) | Collecte de sessions : source de vérité unique | v1 |
| [004](done/RFC-004-usage-live.md) | Utilisation live : Keychain + endpoint OAuth | v1 |
| [005](done/RFC-005-rendu-buddy.md) | Buddy : visage, format `.buddy`, rendu | v1 |
| [006](done/RFC-006-pont-hook.md) | Pont hook Claude Code : binaire dédié + socket Unix | v1 |
| [007](done/RFC-007-interception-permissions.md) | Interception des permissions : file, rendu, décisions | v1 |
| [008](RFC-008-vue-sessions.md) | Vue sessions et saut vers le terminal hôte | v1.1 |
| [009](RFC-009-index-activite.md) | Index d'activité persistant (heatmap et historique) | v1.2 |
| [010](done/RFC-010-preferences-apparence.md) | Préférences, réglages segmentés et aperçu de buddy | v1 |
| [011](done/RFC-011-build-distribution.md) | Build, empaquetage, signature, distribution | v1 |
| [012](done/RFC-012-detection-etat-alertes.md) | Détection d'état et alertes, depuis le transcript | v1 |
| [013](done/RFC-013-buddy-interactif.md) | Buddy interactif : regard, chasse, rire, icône | v1 |
| [014](RFC-014-celebration-fin-de-tache.md) | Célébration de fin de tâche : mini-panneau, pouce, confettis | v1.1 |
| [015](RFC-015-son-du-buddy.md) | Le son du buddy : paquet de sons rechargeable à chaud | v1.1 |
| [016](RFC-016-ponts-agents-terminaux.md) | Ponts agents et terminaux : `AgentBridge`, `TerminalBridge` | v1.2 |
| [017](RFC-017-hook-depuis-reglages.md) | Installer le hook depuis les réglages | v1.1 |
