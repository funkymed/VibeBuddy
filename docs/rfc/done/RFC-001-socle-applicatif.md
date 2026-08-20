# RFC-001 — Socle applicatif, cycle de vie et budget de performance

| | |
|---|---|
| **Status** | done (100 %) |
| **Author** | Cyril Pereira |
| **Created** | 2026-08-19 |
| **Updated** | 2026-08-19 |
| **Phase** | 1 — Fondations |
| **Depends on** | — |
| **Related** | D2, D3, D5 |
| **Blocks** | RFC-002 → RFC-011 (toutes) |

## 1. Context & Problem

vibebuddy est une app macOS native qui affiche l'activité de Claude Code dans
la notch du MacBook. Sa contrainte directrice est la légèreté : elle est visible
en permanence, donc tout réveil inutile se paie en autonomie.

Le repo de référence `Notch-Pilot/` (MIT) résout le problème fonctionnel mais pas
le problème énergétique. Mesuré sur la machine cible le 2026-08-19 :

- `ClaudeMonitor.swift:555-576` lance `/usr/bin/pgrep -fl claude` **à chaque tick
  1 Hz**. Mesure : `fork`+`exec` = **11,34 ms**, soit 1,13 % d'un cœur en
  permanence — dix fois le coût du scan `libproc` qu'il double inutilement.
- Sept sources de réveil coexistent sans coordination : 1 Hz sessions
  (`ClaudeMonitor.swift:78`), 10 Hz souris (`MouseMonitor.swift:40`), 1 Hz
  Accessibility (`MouseMonitor.swift:66-72`), 60 s usage
  (`UsageAggregator.swift:82`), 30 min update (`UpdateChecker.swift:67`), 2 s
  Accessibility (`GlobalHotkeys.swift:67`), plus 18 `withAnimation(...).repeatForever`.
- **Aucun `stop()` n'est jamais appelé** (vérifié : `grep '\.stop()' *.swift` →
  vide). Les timers tournent fenêtre invisible, écran verrouillé, machine sur batterie.

Aucune de ces sources n'est individuellement scandaleuse. C'est leur accumulation
non gouvernée qui l'est, et elle est structurelle : rien dans l'architecture
n'empêche d'en ajouter une huitième.

## 2. Goals / Non-goals

**Goals.**
- Une **unique** autorité de cadencement dans l'app. Créer un `Timer` ailleurs
  est un échec de revue, pas une optimisation manquée.
- Un budget d'animation global que toute vue doit consulter avant d'animer.
- Un harnais de mesure opérationnel **avant** la première fonctionnalité, pour
  que la contrainte de légèreté soit vérifiable en continu et non constatée à la fin.
- Répondre à la question D5 : quel est le plancher de RSS d'un shell
  `NSPanel` + `NSHostingView` vide sur macOS 14 ?

**Non-goals.**
- Toute UI, toute fenêtre visible → RFC-002.
- Tout accès disque, tout réseau.
- L'onboarding (`OnboardingView.swift`, 379 l. dans la référence) : reporté sans date.

## 3. Proposed Solution

Deux cibles exécutables dans un `Package.swift` unique (`vibebuddy` et
`vibe-hook`, cf. RFC-006 et décision D4), plus un module de code partagé.

| Module | Responsabilité |
|---|---|
| `VibeBuddyApp` | `@main`, ~20 l. Miroir de `NotchPilotApp.swift:15-19` (`setActivationPolicy(.accessory)`) **sans** la branche `--hook`. |
| `AppCoordinator` | Possède le graphe d'objets. Écoute `NSWorkspace.willSleepNotification`, `didWakeNotification`, `sessionDidResignActiveNotification` — et **suspend tout** sur les deux premiers. |
| `WakeCoordinator` | **Le seul émetteur de tics de l'app.** `func schedule(_ client: WakeClient, cadence: Cadence)` avec `Cadence = .off \| .lazy(30s) \| .idle(5s) \| .active(1s)`. |
| `AnimationBudget` | `@Observable`. Expose `frameRate: Double` (0 / 8 / 30) et `allowsImplicitAnimations: Bool`. Consommé par RFC-005 et par toute vue tentée par un `repeatForever`. |
| `NotchGeometry` | `resolve()` unique. La référence calcule la géométrie **deux fois avec des règles différentes** (`AppDelegate.swift:98-112` via `NSScreen.main`, et `NotchWindow.swift:85-102` via « premier écran encoché »). |
| `PerfProbe` | `os_signpost` + une commande `--bench` qui imprime RSS/CPU après 60 s headless. |
| `scripts/perfcheck.sh` | ~60 l. de shell. Échantillonne toutes les 5 s, sort un CSV dans `docs/perf/`. |

**Budget imposé, inscrit dans la RFC et vérifié par `perfcheck.sh` :**

| Métrique | Seuil | Commande |
|---|---|---|
| Réveils inactifs au repos | **< 2/s** | `powermetrics --samplers tasks -n 1 \| grep VibeBuddy` |
| Réveils, écran verrouillé | **0** | idem |
| `fork`/`exec` au repos | **0** | `sample <pid> 30` puis grep `posix_spawn` |
| CPU au repos | < 0,5 % | `ps -o %cpu= -p <pid>` |
| **`phys_footprint`** | **< 40 Mo** — tranché par T1, voir Q1 | `task_info(TASK_VM_INFO)` |
| RSS | indicatif seulement (mesuré : 38,2 Mo shell+panneau) | `task_info(MACH_TASK_BASIC_INFO)` |

**La métrique qui gouverne est le nombre de réveils inactifs, pas le %CPU.** Un
process à 0,4 % de CPU avec 70 réveils/s vide une batterie et ne déclenche aucune
alerte sur un seuil exprimé en pourcentage.

## 4. Alternatives Considered

**Reprendre le graphe de dépendances à plat de la référence**
(`AppDelegate.swift:5-15` : 9 objets injectés dans une seule vue). Écarté : c'est
la cause racine du monolithe de 3 738 lignes de `NotchContentView.swift`.

**Laisser chaque module gérer son propre timer, avec une convention d'équipe.**
Écarté : c'est exactement ce qu'a fait la référence, et le résultat est sept
sources non coordonnées dont aucune ne s'arrête. Une convention non outillée ne
tient pas ; un `WakeCoordinator` obligatoire, si.

**Combine plutôt qu'Observation.** Écarté (décision D2) : l'invalidation
granulaire d'`@Observable` est précisément l'outil qui répare le défaut observé
dans la référence, où n'importe quel `@Published` réévalue tout.

**Fixer la cible RSS à 40 Mo dès maintenant.** Écarté : un shell AppKit +
`NSHostingView` vide pèse typiquement 45-60 Mo. Poser un seuil qu'on ne peut pas
tenir le rend décoratif. On mesure, puis on tranche (question ouverte Q1).

## 5. Action plan

| # | Tâche | Statut | % |
|---|---|---|---|
| T1 | **Mesurer un `NSPanel` + `NSHostingView` vide** (RSS, CPU, réveils). Livrable : [`docs/perf/2026-08-19-D5-swiftui-floor.md`](../perf/2026-08-19-D5-swiftui-floor.md). Conditionne Q1. | **done** | **100** |
| T2 | `Package.swift` deux cibles + module partagé | **done** | **100** |
| T3 | `VibeBuddyApp` + `AppCoordinator` + suspension sur `willSleep` / verrouillage | **done** | **100** |
| T4 | `WakeCoordinator` + `Cadence` + tests unitaires de cadence | **done** | **100** |
| T5 | `AnimationBudget` | **done** | **100** |
| T6 | `NotchGeometry.resolve()` unique | **done** | **100** |
| T7 | `PerfProbe` + `--bench` | **done** | **100** |
| T8 | `scripts/perfcheck.sh` + les 3 scénarios A/B/C | **done** | **100** |
| T9 | Première prise de référence, scénario A, 10 min | **done** | **100** |

**Critère de sortie — ATTEINT le 2026-08-19.**

`./scripts/perfcheck.sh A 600 001`, 120 échantillons sur 594 s, macOS 26.5 :

| Métrique | Mesuré | Budget | |
|---|---|---|---|
| `phys_footprint` crête | **10,0 Mo** | < 40 Mo | PASS |
| RSS crête | 38,0 Mo | indicatif | — |
| CPU régime établi | **0,000 %** | < 0,5 % | PASS |
| Réveils inactifs | **0,000 /s** | < 2 /s | PASS |
| `posix_spawn` au repos | **0** | 0 | PASS |

Données : [`docs/perf/20260819-1515-001-A.csv`](../perf/20260819-1515-001-A.csv).
`swift build` propre en Swift 6 mode strict, `swift test` 25/25.

Ces chiffres deviennent le plancher de référence de toutes les RFC suivantes.
Une régression de plus de 10 % sur l'une d'elles bloque la clôture de la RFC en
cours.

## 6. Open Questions

**~~Q1 — Le plancher de RSS impose-t-il d'abandonner SwiftUI pour la pill ?~~ TRANCHÉE (2026-08-19)**

**Non. SwiftUI est retenu, la pastille reste en `NSHostingView`.**

Mesuré sur macOS 26.5, `VibeBuddy --bench`, 60 s, échantillonné depuis
l'intérieur du process :

| Mode | RSS crête | `phys_footprint` crête | Réveils inactifs |
|---|---|---|---|
| `shell` (aucune fenêtre) | 31,4 Mo | 6,7 Mo | 0,000 /s |
| `panel` (`NSPanel` + `NSHostingView` vide) | **38,2 Mo** | **10,6 Mo** | 0,000 /s |

La prédiction de 45-60 Mo pour un shell `NSHostingView` est démentie : 38,2 Mo,
**sous** la cible. L'option « pastille en `CALayer` » perd sa justification et
n'est pas retenue — deux paradigmes de rendu à maintenir pour rien.

**Conséquence : le budget se mesure désormais en `phys_footprint`, plus en RSS.**
Le RSS compte les pages de frameworks partagées avec tous les autres processus de
la machine ; les facturer à vibebuddy revient à lui imputer AppKit autant de
fois qu'il y a d'apps qui l'utilisent. `phys_footprint` est ce que macOS impute
réellement. La marge réelle passe de 1,8 Mo (intenable) à 29,4 Mo.

Détail et données brutes : [`docs/perf/2026-08-19-D5-swiftui-floor.md`](../perf/2026-08-19-D5-swiftui-floor.md).

**Q2 — `Cadence.idle` à 5 s est-il utile, ou deux niveaux suffisent-ils ?**
Trois cadences se justifient si la latence perçue le demande ; sinon `.lazy` et
`.active` suffisent et simplifient le coordinateur.

```sh
# Instrumenter les transitions de cadence sur une session de travail réelle :
log stream --predicate 'subsystem == "fr.funkylab.vibebuddy" AND category == "wake"' --style compact
```

**Q3 — Faut-il suspendre aussi sur `NSWorkspace.screensDidSleepNotification` ?**
Écran éteint mais machine active : cas fréquent en déport de session.

## Notes d'implémentation

Arbitrages déplacés depuis les commentaires du code lors du dégraissage du
2026-08-20. Le code garde une ligne de renvoi vers cette section.

### `WakeCoordinator.swift` — `WakeCoordinator`

L'implémentation de référence fait tourner sept sources de réveil indépendantes —
sondage des sessions à 1 Hz, sondage de la souris à 10 Hz, requêtes Accessibilité
à 1 Hz, rafraîchissement de la consommation à 60 s, vérification de mise à jour
toutes les 30 min, sondage des raccourcis à 2 s, plus dix-huit animations
`repeatForever` — et n'appelle `stop()` sur aucune. Elles continuent de se
déclencher fenêtre masquée, écran verrouillé, et sur batterie. Aucune n'est
déraisonnable prise seule ; l'accumulation l'est, et rien dans cette architecture
n'empêche d'en ajouter une huitième.

D'où : une seule horloge, un seul propriétaire, un seul endroit à auditer. Un
`Timer` créé ailleurs dans ce dépôt est un échec de revue, pas une optimisation
manquée.

Le minuteur est programmé avec une marge généreuse (25 % de l'intervalle), ce qui
laisse le noyau fusionner nos réveils avec ceux déjà programmés sur le système.
Un réveil fusionné est presque gratuit ; un réveil isolé est ce qui vide une
batterie. En veille ou écran verrouillé, le minuteur est *annulé*, pas ralenti :
à ce moment-là le budget est de zéro réveil, pas de peu.

### `Cadence.swift` — `Cadence`

Volontairement un ensemble fermé de quatre valeurs. Les intervalles arbitraires
sont la façon dont une app finit avec sept minuteurs non coordonnés — l'état de
l'implémentation de référence. Si un sous-système a besoin d'autre chose que ces
quatre valeurs, c'est une conversation de conception, pas un paramètre.

### `AnimationBudget.swift` — `AnimationBudget`

L'implémentation de référence dépense son budget d'animation sans le voir :
dix-huit appels `withAnimation(...).repeatForever` répartis dans
`BuddyFace.swift`, chacun installant un `CADisplayLink` implicite qui n'est jamais
démonté — ni quand la vue sort de l'écran, ni quand la fenêtre se masque.
`withAnimation` a l'air gratuit au point d'appel, et c'est exactement pour ça que
ça s'accumule.

Ici le mouvement a un seul cadran, et il est observable. Une vue qui veut animer
demande ce qu'elle a le droit de dépenser ; quand la réponse est `0`, elle dessine
une image fixe et n'installe aucune horloge.

### `PreferencesStore.swift` — `PreferencesStore`

**Pourquoi pas `@AppStorage`.** `@AppStorage` n'a aucun chemin de migration.
L'implémentation de référence en a eu besoin dès qu'elle a changé la façon de
stocker une position de fenêtre, et l'a écrit à la main
(`BuddyPreferences.swift:79-91`) ; un store incapable de versionner ses propres
clés se contente de reporter ce travail sur la première personne qui le heurte.

**Écritures fusionnées.** La référence écrit dans `UserDefaults` depuis le
`didSet` de vingt propriétés (`NotchWindow.swift:505-507`), c'est-à-dire une
écriture synchrone **par image** pendant le déplacement d'une fenêtre. Ici un
changement marque une clé sale et programme un seul vidage ; une rafale de
changements se réduit à une écriture.

### `NotchFrameSolver.swift` — `NotchFrameSolver`

Pur et sans type AppKit au-delà de `CGRect`, pour que chaque règle de
positionnement — bornage, aimantation, règle d'affleurement sur écran à encoche —
soit testable sans écran branché. Dans l'implémentation de référence cette
arithmétique vit à l'intérieur de la sous-classe `NSPanel`, et c'est pour ça que
ses cas limites ont été corrigés avec des drapeaux plutôt qu'avec des tests.

### `PanelMetrics.swift` — `PanelTiming.contentRevealFraction`

Fraction de l'animation d'ouverture qui doit s'écouler avant que le contenu du
panneau soit révélé (0,62).

Les insérer dès le début paraît faux pour une raison qui mérite d'être nommée :
la forme est encore à la hauteur de la pastille, donc une mise en page pleine
taille apparaît dans quelque chose de bien trop petit pour elle, puis le cadre
rattrape. Attendre que la croissance soit presque finie fait arriver le contenu
dans un espace qui le contient déjà.

À la fermeture, le contenu est retiré *d'abord*, avant que le cadre rétrécisse :
laisser un panneau mis en page se faire écraser dans une pastille se lit comme un
effondrement, pas comme une fermeture.

### `LayoutPrefs.swift` — `LayoutPrefs.showPillWithoutSession`

D7 dit que ce réglage doit être à *off* par défaut. Il est à **on** ici, et c'est
une divergence délibérée plutôt qu'un oubli : l'app a toujours affiché la
pastille, et la faire disparaître silencieusement à la mise à jour se lirait comme
un plantage plutôt que comme un nouveau défaut. Le réglage existe ; le défaut
bougera le jour où l'app sera livrée à quelqu'un qui n'a jamais vu l'ancien
comportement.

### `Strings.swift` — `Strings`

**Pourquoi une `struct` plutôt que des fichiers `.strings`.** Une clé manquante
dans un `.strings` est un raté à l'exécution : l'app affiche la clé brute, ou
bascule silencieusement dans une autre langue, et personne ne le remarque avant
un utilisateur. Ici chaque langue est une instance de la même structure, donc
**ajouter une chaîne sans la traduire ne compile pas**.

Le compromis est réel : ce n'est pas un fichier qu'un traducteur peut éditer. À
deux langues dans un outil personnel, c'est le bon sens de l'échange ; le jour où
une troisième arrive avec quelqu'un d'autre pour l'écrire, le catalogue peut
passer en `.strings` sans que les sites d'appel changent.
