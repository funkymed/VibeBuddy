# Spike — trousseau et endpoint `oauth/usage`

**Date d'origine** : 2026-08-19 · **Rejouée le** : 2026-08-21 · **Débloquait** : RFC-004

> **Fiche reconstruite après coup.** Le spike a été mené le 2026-08-19 et son
> résultat est passé directement dans `Sources/VibeBuddyKit/Usage/`, sans être
> archivé — ce que le critère de sortie de la Phase 0 exige pourtant. Ce qui suit
> est établi en rejouant les mêmes gestes le 2026-08-21 et en les confrontant au
> code livré. Les sorties ci-dessous sont **de la rejouée**, pas de la session
> d'origine ; les mesures de 2026-08-19 (0,32 s de réponse) sont citées comme
> telles, depuis les commentaires du code.

## Question

RFC-004 promet « le vrai % de limite, pas une estimation », c'est-à-dire le
chiffre qu'affiche la page de facturation d'Anthropic. Deux inconnues :

1. Peut-on **lire le jeton OAuth** que Claude Code range dans le trousseau, sans
   déclencher de dialogue de mot de passe et sans le lui voler ?
2. L'endpoint `oauth/usage` **existe-t-il**, et que rend-il ?

Si l'une des deux tombe, RFC-004 se rabat sur une estimation par comptage de
jetons — et le deuxième objectif du produit perd son argument.

## Protocole

Aucune écriture nulle part. Lecture seule du trousseau, un appel HTTP.

```sh
security find-generic-password -s "Claude Code-credentials" -a "$(whoami)" -w
curl -s https://api.anthropic.com/api/oauth/usage \
  -H "Authorization: Bearer <jeton>" \
  -H "anthropic-beta: oauth-2025-04-20"
```

## Résultats

### Établi — la lecture du trousseau, mais par un seul chemin

`/usr/bin/security` rend la main **sans aucun dialogue**. Structure obtenue le
2026-08-21, valeurs secrètes non imprimées :

```
clés racine       : ['claudeAiOauth', 'mcpOAuth']
clés claudeAiOauth: ['accessToken', 'expiresAt', 'rateLimitTier',
                     'refreshToken', 'refreshTokenExpiresAt',
                     'scopes', 'subscriptionType']
expiresAt         : 1787267207326 -> 2026-08-21T01:06:47
accessToken       : < 108 caractères, non imprimé >
```

**Le résultat central du spike est négatif, et c'est lui qui a dicté le code.**
`SecItemCopyMatching` — la façon normale de lire un trousseau depuis une app —
**déclenche une invite de mot de passe**. `/usr/bin/security` non. La raison est
l'ACL de l'entrée : elle liste le binaire qui a écrit le jeton, et Claude Code
l'a écrit *via* `/usr/bin/security`. Ce chemin est donc déjà de confiance ;
le nôtre ne l'est pas.

D'où `KeychainCredentials` qui **fait tourner un processus** (`UsageClient.swift:80`)
au lieu d'appeler l'API Security. C'est un `fork`/`exec`, et le budget de
performance en interdit un seul au repos — d'où le cache de jeton jusqu'à son
expiration (`:19`), pour que la dépense ait lieu une fois par heure et non à
chaque rafraîchissement.

Deux entrées coexistent : une portée au compte et une sans compte. C'est
**celle portée au compte qui contient les jetons rafraîchis**, donc elle est lue
en premier (`:74`).

`expiresAt` est en **millisecondes** depuis l'époque, pas en secondes (`:97`).

### Établi — l'endpoint répond

Réponse 200. Mesurée à **0,32 s** le 2026-08-19 (relevé dans
`UsageClient.swift:8`). Le 2026-08-21, l'app entière — détection de sessions,
parsing des transcripts, appel réseau compris — sort en **376 ms** :

```
── consommation Claude ──
  session (5 h)  24.0 %  reset 01:59
  semaine (7 j)  15.0 %  reset 23 août, 21:59
```

Chiffres identiques à ceux de la page de facturation : le critère de sortie de la
Phase 2 est atteint.

### Établi — la forme de la réponse, et son instabilité

La charge utile porte **des fenêtres que cette version n'a jamais vues**
(`tangelo`, `cinder_cove`), la plupart à `null` (`ClaudeUsage.swift:5-7`).
Conséquences codées :

- **Toute fenêtre est optionnelle**, et une fenêtre absente s'affiche
  « indisponible », **jamais zéro** : 0 % ressemble à une bonne nouvelle.
- Les clés inconnues sont **ignorées, pas rejetées** (`:40`) — ce n'est pas un
  contrat public.
- `resets_at` s'écrit `2026-08-19T22:20:00.226366+00:00` : secondes
  fractionnaires, et un décalage plutôt qu'un `Z`. **Les deux orthographes
  existent**, les deux sont acceptées (`:60-66`).

### Non établi — la durée de vie du montage

L'en-tête beta est daté (`oauth-2025-04-20`) et l'endpoint n'est pas public.
C'est le risque **R5**, et le spike ne peut pas le lever : il constate seulement
qu'à cette date, ça répond.

L'ACL du trousseau est un détail d'implémentation d'Anthropic — risque **R4**.
D'où la couture `CredentialSource` (`:66`), que les tests ne franchissent jamais.

## Conséquence

RFC-004 est faisable telle qu'écrite, et livrée à 95 %. Trois règles en sortent,
toutes appliquées :

1. **Ne jamais rafraîchir le jeton.** Claude Code en est propriétaire ; un
   rafraîchisseur concurrent le déconnecte (`UsageClient.swift:10`).
2. **Honorer `Retry-After`** sur 429 : marteler un limiteur de débit fait
   bloquer un jeton (`ClaudeUsage.swift:71`).
3. **401 vide le cache de jeton** et se signale comme « pas d'identifiants »,
   sans réessai.
