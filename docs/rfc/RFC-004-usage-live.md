# RFC-004 — Utilisation live : lecture Keychain et endpoint OAuth

| | |
|---|---|
| **Status** | in-progress (95 %) — module livré, refus du serveur encaissé (backoff + cache) ; reste `perfcheck A` |
| **Author** | Cyril Pereira |
| **Created** | 2026-08-19 |
| **Updated** | 2026-08-19 |
| **Phase** | 2 — Données |
| **Depends on** | RFC-001 |
| **Related** | R4, R5 |
| **Blocks** | —  (feuille du graphe) |

## 1. Context & Problem

La valeur quotidienne principale de vibebuddy est de répondre sans ouvrir de
navigateur : « où en suis-je de ma limite 5 h ? ». Le chiffre exact existe —
c'est celui de la page de facturation Claude — et il est accessible via
`api.anthropic.com/api/oauth/usage` avec le jeton OAuth que Claude Code stocke
déjà dans le trousseau.

Deux obstacles, tous deux résolus dans la référence d'une manière non évidente :

**Le trousseau.** L'item `Claude Code-credentials` a une ACL restreinte aux
binaires de confiance. Un `SecItemCopyMatching` depuis notre propre binaire
présente une identité différente et **déclenche une invite de mot de passe**. La
référence shelle vers `/usr/bin/security find-generic-password`, qui figure sur
l'ACL — parce que Claude Code a lui-même utilisé ce binaire pour écrire le jeton.
Le mécanisme est documenté sans détour en `UsageAPI.swift:45-56`.

**Le coût caché.** `UsageAggregator.swift:168-278` calcule *en plus* une
agrégation locale des tokens en lisant `String(contentsOf:)` — **chaque jsonl
entier** de la semaine écoulée — **toutes les 60 secondes** (`:60`, `:76-86`,
`:237`). Sur un corpus de 379 Mo, c'est potentiellement des centaines de Mo relus
chaque minute, pour produire une estimation que l'API donne exacte. C'est le plus
gros coût caché du projet de référence (risque R2).

## 2. Goals / Non-goals

**Goals.** Lecture du jeton, appel de l'endpoint, parsing des quatre fenêtres et
des crédits extra, backoff sur 429, cadence adaptative. Dégradation propre et
**explicite** quand la donnée est indisponible.

**Non-goals.** **Aucune agrégation locale depuis les jsonl en v1.** Cette
ambiguïté est ce qui a produit `UsageAggregator.scan()` ; elle est tranchée ici :
si l'API ne répond pas, on affiche « indisponible », jamais un chiffre estimé
présenté comme exact. Un repli local reste possible plus tard, alimenté par
l'index de RFC-009 — jamais par un scan à la demande.

**Aucun rafraîchissement de jeton.** Claude Code gère le sien et écrit dans le
trousseau ; on lit ce qui s'y trouve.

## 3. Proposed Solution

| Module | Responsabilité |
|---|---|
| `KeychainCredentialReader` | Exec `/usr/bin/security`, parse le JSON, **met le jeton en cache jusqu'à `expiresAt`**. |
| `actor UsageClient` | Requête HTTP, parsing, backoff. |
| `UsageState` | `@Observable`, MainActor. Expose `live: ClaudeUsage?` et un état d'erreur typé. |

**Repris tel quel :**

| Brique | `fichier:ligne` | Pourquoi |
|---|---|---|
| Exec `security find-generic-password -s "Claude Code-credentials" -w` | `UsageAPI.swift:107-141` | Cf. le commentaire `:45-56`. |
| Repli compte nommé → compte nul | `UsageAPI.swift:96-105` | L'entrée `-a $USER` porte les jetons rafraîchis ; l'entrée nulle date du login initial. |
| En-têtes `Authorization: Bearer` + `anthropic-beta: oauth-2025-04-20` | `UsageAPI.swift:156-157` | |
| Parsing `five_hour / seven_day / seven_day_sonnet / seven_day_opus / extra_usage` | `UsageAPI.swift:208-239` | **Chaque champ est optionnel** : un changement de schéma dégrade en « fenêtre nulle » au lieu de planter. Forme à conserver telle quelle (parade R5). |
| Double `ISO8601DateFormatter` | `UsageAPI.swift:249-258` | Le `resets_at` d'Anthropic porte des fractions de seconde. |
| Backoff 429 + `Retry-After` | `UsageAPI.swift:170-178`, `UsageAggregator.swift:93-99` | Sépare une dégradation propre d'un jeton throttlé. |
| `expiresAt` en **millisecondes** | `UsageAPI.swift:93`, divisé en `:72` | Piège classique. |

**Modifié :**
- `accessToken()` est appelé à **chaque** `fetchUsage()` (`UsageAPI.swift:153`),
  donc un `fork` de `/usr/bin/security` (15-30 ms) par requête. → cache jusqu'à
  `expiresAt`, relecture seulement sur expiration ou 401.
- Cadence : 60 s permanents (`UsageAggregator.swift:82`) → **180 s panneau fermé,
  30 s panneau ouvert, 10 s tant que `live == nil`**. Une fenêtre de 5 h ne bouge
  pas assez pour justifier 60 s en continu.
- Les douze `print(...)` de diagnostic (`UsageAPI.swift:65-68`, `:77-86`, …) →
  `os_log` avec catégorie.

**Budget.** Repos : une requête / 180 s + un exec `security` par expiration de
jeton (≈ 1/8 h) → **< 0,01 %**. Panneau ouvert : une requête / 30 s. RSS +0,5 Mo.
**C'est le seul réveil périodique inconditionnel de l'app** (cf. RFC-001, D3).

## 4. Alternatives Considered

**`SecItemCopyMatching` natif.** Écarté : invite de mot de passe à chaque lecture
(`UsageAPI.swift:45-56`). Techniquement plus propre, inutilisable en pratique.

**Rafraîchir le jeton nous-mêmes.** Écarté : deux rafraîchisseurs concurrents sur
le même refresh token, c'est la garantie d'invalider la session de l'utilisateur.

**Garder l'agrégation locale comme repli.** Écarté en v1 (cf. Non-goals, R2). Un
chiffre estimé affiché à côté d'un chiffre exact, sans distinction visuelle
forte, est pire que pas de chiffre.

**Attendre un endpoint public.** Il n'y en a pas. On assume l'instabilité, et on
la contient par un parseur tout-optionnel et un état « indisponible » explicite.

## 5. Action plan

| # | Tâche | Statut | % |
|---|---|---|---|
| T1 | Spike : le jeton est-il lisible sans invite sur cette machine ? (cf. Q1) | **done** | **100** |
| T2 | `KeychainCredentialReader` + cache jusqu'à `expiresAt` + repli de compte | **done** | **100** |
| T3 | `UsageClient` + parsing tout-optionnel + les deux formateurs ISO8601 | **done** | **100** |
| T4 | Backoff 429 honorant `Retry-After` | **done** | **100** |
| T5 | `UsageState` + états d'erreur typés (refusé / absent / expiré / réseau / throttlé) | **done** | **100** |
| T6 | Cadence adaptative branchée sur le `WakeCoordinator` | **done** | **100** |
| T7 | `protocol CredentialSource` à implémentation unique (parade R4) | **done** | **100** |
| T8 | `perfcheck.sh` A — vérifier le réveil unique à 180 s | todo | 0 |
| T9 | **Backoff exponentiel et cache de la dernière lecture** | **done** | **100** |

### T9 — l'endpoint refuse, et `Retry-After` vaut zéro

Mesuré le 2026-08-20 sur l'endpoint réel : `429`, corps
`{"type":"rate_limit_error"}`, en-tête `retry-after: 0`. Le code obéissait au
zéro et réessayait toutes les 10 s, ce qui gardait le limiteur chaud.

Le `Retry-After` est désormais un **plancher**, jamais une permission : backoff
60 s, 120, 240, plafonné à 15 min, remis à zéro par un succès. Un serveur qui
refuse en disant « réessaie tout de suite » refusera aussi le tout de suite.

La dernière bonne lecture est mise en cache (`UsageCache`) et réaffichée au
lancement avec son âge dès qu'il dépasse deux minutes. Elle est jetée au-delà de
5 h : une fenêtre de 5 h qui s'est réinitialisée n'est pas vieille, elle est
fausse.

**Critère de sortie — atteint sauf la comparaison visuelle.**

| Point | État |
|---|---|
| Jeton lu sans invite | **PASS** |
| Endpoint répond 200 | **PASS** — 0,32 s |
| Parseur tolérant aux fenêtres inconnues | **PASS** — vérifié sur la réponse réelle |
| Une fenêtre absente affiche « indisponible », jamais 0 % | **PASS** — test dédié |
| Backoff honorant `Retry-After` | **PASS** — code + test |
| Cadence adaptative, un seul réveil périodique | **PASS** — 180/30/10 s |
| Chiffre identique à la page de facturation | **non vérifié** — demande une capture côte à côte |

**Rendu ajouté hors périmètre initial** : la section consommation au pied du
panneau, deux jauges en points plutôt qu'en barres. À cette largeur, le
remplissage d'une barre entre 15 % et 25 % fait quelques pixels ; un point rempli
se compte d'un coup d'œil. L'arrondi est au supérieur — 4 % rendrait une jauge
vide, ce qui se lit « pas commencé » plutôt que « à peine commencé ».

### Ancien critère
Le pourcentage 5 h affiché est **identique au chiffre de la
page de facturation Claude**, vérifié par capture d'écran côte à côte. Couper le
réseau affiche un état « indisponible » explicite, **jamais un chiffre périmé
sans marque**. Vingt requêtes forcées déclenchent un back-off qui honore
`Retry-After`.

## 6. Open Questions

**~~Q1 — Le jeton est-il lisible sans invite ?~~ TRANCHÉE (2026-08-19)**

**Oui.** `security find-generic-password -s "Claude Code-credentials" -a $USER -w`
rend le jeton **sans aucune invite de trousseau**, et le champ `expiresAt` est
bien en millisecondes. Le mécanisme décrit dans la référence tient.

**~~Q2 — L'endpoint répond-il encore, et avec quel schéma ?~~ TRANCHÉE**

**HTTP 200 en 0,32 s.** Relevé le 2026-08-19 : session 5 h à 16 %, semaine à 5 %.

Et le schéma **a déjà changé** depuis la référence. La réponse contient des
fenêtres sous des noms de code que ce code n'a jamais vus — `tangelo`,
`nimbus_quill`, `omelette_promotional`, `cinder_cove`, `iguana_necktie` — la
plupart nulles. C'est la confirmation directe du risque R5 : le parseur
tout-optionnel n'est pas une précaution théorique, il est **déjà nécessaire**.

Les valeurs réelles sont conservées dans les fixtures de test, y compris les clés
inconnues, pour que la tolérance soit vérifiée et pas seulement affirmée.

### Ancienne Q1, pour mémoire
C'était l'hypothèse qui pouvait annuler cette RFC à elle seule (risque R4).

```sh
/usr/bin/security find-generic-password -s "Claude Code-credentials" -a "$USER" -w \
  | python3 -c 'import json,sys,datetime as d; o=json.load(sys.stdin)["claudeAiOauth"]; print("expire:", d.datetime.fromtimestamp(o["expiresAt"]/1000))'
# Doit rendre une date sans afficher la moindre invite de trousseau.
```

**Q2 — L'endpoint répond-il encore, et avec quel schéma ? (spike)**

```sh
TOKEN=$(/usr/bin/security find-generic-password -s "Claude Code-credentials" -a "$USER" -w \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["claudeAiOauth"]["accessToken"])')
curl -s -D- -o /tmp/usage.json \
  -H "Authorization: Bearer $TOKEN" -H "anthropic-beta: oauth-2025-04-20" \
  https://api.anthropic.com/api/oauth/usage | head -1
python3 -m json.tool /tmp/usage.json | head -40
```

**Q3 — Que montre la pastille quand le jeton est expiré et que Claude Code ne
tourne pas pour le rafraîchir ?** Cas fréquent au réveil de la machine. « — »
neutre, ou une marque d'obsolescence sur le dernier chiffre connu ?
