# Découpage RFC — notch-buddy

Document de travail issu de deux analyses croisées du repo de référence
`Notch-Pilot/` (MIT, 23 fichiers Swift, 10 510 lignes). Sert de base à la
rédaction des RFC. **Ce n'est pas une RFC** : pas d'en-tête de statut, pas de
comptabilité Gantt.

Toutes les références `fichier:ligne` pointent vers `Notch-Pilot/Sources/NotchPilot/`
sauf mention contraire.

---

## 1. Mesures de référence

Faites le 2026-08-19 sur la machine cible (corpus : 546 jsonl, 379 Mo).

| Mesure | Valeur | Verdict |
|---|---|---|
| `proc_listpids` + `proc_name` + `proc_pidpath`, 617 process | 1,06 ms | 0,11 % d'un cœur à 1 Hz — négligeable |
| Scan récursif `~/.claude/projects` | ~7 ms, cache chaud | négligeable |
| **`fork`+`exec` de `/usr/bin/pgrep`** | **11,34 ms** | **1,13 % d'un cœur à 1 Hz — 10× le scan libproc** |

Le polling n'est pas cher par ses syscalls. Il est cher par ses `fork`/`exec`
et par ses réveils.

## 2. Sources de coût réelles dans la référence

| # | Source | `fichier:ligne` | Nature |
|---|---|---|---|
| C1 | `pgrep -fl claude` à chaque tick 1 Hz | `ClaudeMonitor.swift:555-576` | `fork`+`exec`/s pour une chaîne de sous-titre déjà calculable depuis `liveClaudeCwdCounts()` |
| C2 | 18 `withAnimation(...).repeatForever` | `BuddyFace.swift` 249, 252, 256, 261, 271, 411, 414, 417, 433, 436, 440, 443, 452, 455, 459, 671, 686, 1006 | présents dans **tous** les styles ; chacun installe un `CADisplayLink` implicite jamais arrêté |
| C3 | `TimelineView(.animation(1/60))` | `BuddyFace.swift:516-517` | **uniquement `BarsBuddy`** (struct 470→575), donc seulement si style = Waves |
| C4 | `TimelineView(.periodic(by: 0.05))` = 20 Hz | `NotchContentView.swift:773` | actif tant qu'une permission est en attente |
| C5 | `Timer` 10 Hz souris + requête AX inter-process à 1 Hz | `MouseMonitor.swift:40`, `:66-72` | l'IPC Accessibility coûte plus que `proc_listpids` |
| C6 | `String(contentsOf:)` fichier entier, tous les jsonl de la semaine, **toutes les 60 s** | `UsageAggregator.swift:237` (boucle `:60`, `:76-86`) | le plus gros coût caché du projet |
| C7 | `String(contentsOf:)` + **double passe** sur les lignes | `HeatmapAggregator.swift:165`, `:175-184`, `:191-209` | relancé à chaque clic sur `‹` (`:76-77`) |
| C8 | `recentEvents()` — tail 256 Ko **sans cache**, appelé **depuis un body de vue** | `ClaudeMonitor.swift:582-699` + `NotchContentView.swift:1183` | relit le disque à chaque invalidation |
| C9 | **Aucun `stop()` n'est jamais appelé** | vérifié : `grep '\.stop()' *.swift` → vide | les timers tournent fenêtre invisible et écran verrouillé |

**Corrigé par rapport à une lecture rapide** : ce n'est pas « le buddy tourne à
60 fps ». C3 est confiné à un style. Le coût permanent est C2 + C9.

## 3. Ce qui est borné, et ce qui ne l'est pas

`ClaudeMonitor` lit correctement : `readTail` 64 Ko (`:470-482`) + cache mtime
(`:274-280`) + parse borné à 50 lignes en remontant (`:296`).

Les deux autres lecteurs ne sont **pas** bornés : C6 et C7 ci-dessus. Le bon
patron existe déjà dans le dépôt et n'a pas été réutilisé.

---

## 4. Découpage retenu — 11 RFC

Corrigé après analyse. Divergences par rapport au découpage initial en 10 :
RFC-001 scindée, RFC-008 recadrée en RFC de stockage, RFC-009 requalifiée,
auto-update sorti du périmètre.

| RFC | Titre | Ce qu'elle contient |
|---|---|---|
| 001 | Socle applicatif, cycle de vie, budget de performance | cibles SwiftPM, `AppCoordinator`, `WakeCoordinator`, `AnimationBudget`, `PerfProbe`. **Aucune UI.** |
| 001b | Fenêtre notch : NSPanel, click-through, drag/snap, multi-écran | `NotchPanel`, `NotchFrameSolver` (pur, testable), `ClickThroughHostView`, `HoverProbe` |
| 002 | Collecte de sessions : source de vérité unique | `actor SessionStore`, `ProjectsWatcher` (FSEvents), `JSONLTailReader`, `TranscriptParser`, `ToolActionClassifier` |
| 003 | Utilisation live : Keychain + endpoint OAuth | `KeychainCredentialReader`, `UsageClient`, `UsageState`. **Feuille du graphe.** |
| 004 | Rendu du buddy : cadenceur unique et budget d'animation | `BuddyRenderer` (protocole), 6 renderers sans état, **un seul** `TimelineView` piloté par `AnimationBudget` |
| 005 | Pont hook Claude Code : binaire dédié + socket Unix | 2ᵉ cible SwiftPM Foundation-only, `HookProtocol` partagé, `HookInstaller`, `HookSocketServer` |
| 006 | Interception des permissions : file, rendu, décisions | `PermissionQueue`, `PermissionRequestModel`, vues séparées shell/diff/URL/AskUserQuestion |
| 007 | Vue sessions et saut vers le terminal hôte | `SessionListView`, `SessionTimelineLoader` (actor + cache), `TerminalJumper`, `TmuxPaneIndex` |
| 008 | Index d'activité persistant (heatmap + historique) | `ActivityIndex` (actor), `IndexCursorStore`, `ActivityBackfill`, `HeatmapView` |
| 009 | Préférences, apparence et surfaces expressives | prefs scindées en 3 `@Observable`, `PreferencesStore` + migrations, `SpeechPresenter`, `VoiceAnnouncer` |
| 010 | Build, empaquetage, signature, distribution | `build.sh`, `generate-icon.swift`, `Info.plist`, DMG, workflow release, cask |

### Pourquoi ces écarts

- **001 → 001 + 001b.** `NotchWindow.swift` fait 825 lignes de géométrie
  multi-écran non triviale. Ce n'est pas un sous-chapitre du socle. Et le budget
  perf n'est pas un chapitre : c'est un livrable mesurable qui conditionne la suite.
- **008 recadrée.** Formulée « heatmap », elle reproduit le scan complet de C7.
  Formulée « index incrémental », elle sert aussi de repli local à 003 et de
  source à toute statistique future.
- **009 requalifiée.** `BuddyPreferences.swift` (459 l.) + le sélecteur
  d'apparence (`NotchContentView.swift:2778-3470`, ~700 l.) = ~1 200 lignes que
  le découpage initial n'attribuait à personne. Les notifications et la voix
  (175 l. au total) y sont repliées — trop maigres pour une RFC.
- **Auto-update sorti.** `UpdateChecker.swift` (372 l.) télécharge, monte,
  recopie dans `/Applications`, **se re-signe** (`:255-272`) et se relance via
  un script shell (`:278-305`). Risque disproportionné pour un utilitaire de
  notch ; Homebrew fait mieux.
- **Onboarding reporté.** `OnboardingView.swift` (379 l.) — animation d'intro,
  zéro fonction. Sans propriétaire dans le découpage initial.

### Graphe de dépendances — aucun cycle

```
001  Socle / WakeCoordinator / AnimationBudget
 ├── 001b Fenêtre notch
 ├── 002  SessionStore ──┬── 004, 006, 007, 008
 ├── 003  Usage API      │   (feuille — parallélisable dès que 001 est posée)
 ├── 005  Hook + IPC ────┴── 002 (ModeUpdate, mapping PID), 006 (transport)
 ├── 009  Prefs ──────────── 001b (layout), 004 (apparence)
 └── 008  ActivityIndex ──── 007
```

Chemin critique : **001 → 005 → 006**.

**Cycle latent à interdire.** RFC-006 a besoin de « le terminal est-il au premier
plan ? » (`NotchContentView.swift:503`), qui vit dans RFC-007. Ne pas créer
006 → 007 : extraire `TerminalFocusProbe` dans RFC-002 (qui possède déjà
`ProcessLookup` et les PID), puis 006 → 002 et 007 → 002.

**Frontière 005/006.** Le schéma de décision (`HookClient.swift:157-175`)
appartient au **transport** (005), pas à l'UI. S'il reste dans 006, deux endroits
connaîtront la forme `hookSpecificOutput` et l'un des deux finira par ajouter un
champ de trop — exactement le mode de panne que documente le commentaire `:157-160`.

---

## 5. Décisions d'architecture à trancher avant la première ligne

| # | Question | Recommandation |
|---|---|---|
| **D1** | Source de vérité d'une session ? La référence en a **trois** qui se contredisent : `ClaudeMonitor.sessions`, `HookBridge.sessionPIDs`, `HookBridge.liveModes` (indexé par cwd, pas par session). Un `lsof` contredit même un commentaire du dépôt (`TerminalJumper.swift:143` vs `ClaudeMonitor.swift:524-526`). | `actor SessionStore` unique. Le process = vérité de *liveness*, le jsonl = vérité de *contenu*, le hook = vérité de *mode et d'identité PID*. Clé primaire `sessionID` (nom du jsonl) ; `cwd` en index secondaire. |
| **D2** | Un acteur ou N `ObservableObject` ? Aujourd'hui 8 `@ObservedObject` + 1 `@EnvironmentObject` dans **une struct de 3 647 lignes** (`NotchContentView.swift:4-3650`). | Acteur en amont + `@Observable` (Observation, macOS 14) plutôt que Combine. Vues feuilles conformes à `Equatable`. **Règle mécanique : aucune vue ne dépasse 200 lignes.** |
| **D3** | Combien de timers l'app a-t-elle le droit d'avoir ? Aujourd'hui : 1 Hz + fork, 10 Hz, 1 Hz AX, 60 s, 30 min, 2 s, 18 `repeatForever`, 2 `TimelineView`. Aucun ne s'arrête. | **Un seul** `WakeCoordinator`. Budget : **2 réveils/s max au repos, 0 écran verrouillé**. Un `Timer` créé hors du coordinateur = échec de revue. Seul réveil périodique inconditionnel accepté : l'appel usage (180 s). |
| **D4** | Hook : binaire dual-mode ou exécutable séparé ? Le binaire de la référence lie AppKit (`NotchPilotApp.swift:1`) ; dyld le charge **avant** que `main()` teste `--hook`, à chaque `PreToolUse`, donc à chaque appel d'outil de chaque session. | **Deux cibles** dans le même `Package.swift` + `HookProtocol.swift` partagé. On garde le gain (pas de Node, version synchrone), on supprime le coût. À valider par un `time` comparatif. |
| **D5** | ~~SwiftUI ou AppKit pour la pill ?~~ **TRANCHÉE 2026-08-19.** L'hypothèse « 45-60 Mo pour un shell vide, donc 40 Mo hors d'atteinte » est **démentie par la mesure**. | **SwiftUI retenu.** `NSPanel` + `NSHostingView` vide = **38,2 Mo RSS / 10,6 Mo `phys_footprint`** (shell seul : 31,4 / 6,7), 0,000 réveil inactif/s. L'option `CALayer` est abandonnée. **Le budget se mesure en `phys_footprint`** : le RSS compte les pages de frameworks partagées avec toute la machine. Données : [`docs/perf/2026-08-19-D5-swiftui-floor.md`](../perf/2026-08-19-D5-swiftui-floor.md). |
| **D6** | `permissions.allow` : source partagée ou miroir interne ? Deux écrivains indépendants et non atomiques (`HookInstaller.swift:52-124`, `HookBridge.swift:311-332`), sans détection de modification concurrente. | `ClaudeSettingsWriter` unique, écriture atomique (`replaceItemAt`), relecture avant chaque mutation, **jamais** de cache long (l'utilisateur édite ce fichier à la main). Garder le filtre des règles scopées (`HookBridge.swift:64-67`). |
| **D7** | Que fait la notch sans session vivante ? `alwaysVisible` est à `true` par défaut (`BuddyPreferences.swift:399`) → pill affichée → `TimelineView` en pause mais **pas** les `repeatForever`, plus une boucle de peek toutes les 28-75 s (`NotchContentView.swift:620`) qui rallume tout. | Défaut à `false`. En mode épinglé : 0 Hz strict, rendu statique unique. Le peek aléatoire coûte des réveils permanents pour 1,6 s de plaisir — derrière une préférence, off par défaut. |
| **D8** | Que devient la latence de 1 s ? | L'assumer comme contrat dans 002 : **1 s en activité, 30 s au repos**. Sans contrat écrit, quelqu'un remettra un timer 1 Hz au premier bug de fraîcheur. |

**« Event-driven » est un vœu, pas un design** : la sortie d'un process n'émet
aucun événement filesystem. Il faut assumer un scan process périodique, mais
paresseux (30 s au repos, 2 s en activité). Formuler 002 comme « une source de
vérité unique fusionnant trois flux de fraîcheur différente ».

---

## 6. Carte de réemprunt

Ce qui est repris **tel quel** — les briques les plus rentables du dépôt.

| Brique | `fichier:ligne` | Pourquoi c'est non évident |
|---|---|---|
| `ProcessLookup` complet + `normalize()` | `ProcessLookup.swift:11-82` | macOS n'a pas de `/proc` ; `/private` doit être strippé pour comparer cwd libproc et cwd jsonl |
| `liveClaudeCwdCounts()` | `ClaudeMonitor.swift:518-553` | **Règle métier centrale** : un jsonl fraîchement écrit par une session *terminée* paraît vivant. Le fd cwd du process est la seule vérité. |
| `readTail` 64 Ko + cache mtime + parse borné à 50 lignes | `:470-482`, `:274-280`, `:296` | le seul lecteur correct du dépôt |
| Cache sticky contexte + fenêtre 1M | `:59-70`, `:176-185`, `:226-232` | sans lui l'anneau clignote quand le tail tombe sur une entrée sans bloc `usage` |
| Heuristiques de danger + vérif du caractère suivant | `:399-468`, `:456-465` | évite de flaguer `rm -rf .build` |
| Lecture Keychain via `/usr/bin/security` | `UsageAPI.swift:107-141` (+ commentaire `:45-56`) | `SecItemCopyMatching` depuis notre binaire déclenche une invite : l'ACL de l'item ne liste que les binaires de confiance, dont `/usr/bin/security` — parce que Claude Code a lui-même utilisé ce binaire pour l'écrire |
| Repli compte nommé → compte nul | `UsageAPI.swift:96-105` | l'entrée `-a $USER` porte les jetons rafraîchis, l'entrée nulle date du login initial |
| Double `ISO8601DateFormatter` | `UsageAPI.swift:249-258` | le `resets_at` d'Anthropic a des fractions de seconde |
| Backoff 429 + `Retry-After` | `UsageAPI.swift:170-178` | sépare une dégradation propre d'un token throttlé |
| Socket AF_UNIX + `chmod 0600` + unlink résiduel | `SocketServer.swift:56-134` | |
| `getsockopt(LOCAL_PEERPID)` | `SocketServer.swift:146-150` | seul moyen de remonter au PID de `claude` |
| Détection `POLLHUP` / `recv MSG_PEEK == 0` | `SocketServer.swift:164-195` | **seul moyen de savoir que l'utilisateur a répondu dans le terminal** (Claude Code tue alors le hook). Sans ça la notch reste bloquée sur un prompt mort. |
| **Schéma strict de réponse `PermissionRequest`** | `HookClient.swift:157-175` | tout champ de premier niveau en trop → Claude Code **invalide la réponse et retombe sur son TUI, sans erreur** |
| `exit(0)` sur entrée malformée / app absente | `HookClient.swift:26-29`, `:95`, `:113` | ne jamais bloquer Claude |
| File FIFO des permissions | `HookBridge.swift:12-28` | le commentaire `:15-17` documente la régression : un seul « pending » déniait silencieusement le précédent en burst parallèle |
| **AskUserQuestion répondu via `deny` + `message`** | `HookBridge.swift:232-250` | hack majeur, non documenté ailleurs : le hook n'a pas de chemin « répondre », donc on refuse l'outil et on formule le message comme la réponse ; le modèle le lit comme un résultat d'outil |
| Saut terminal en 3 étapes + `selectTmuxPane` | `TerminalJumper.swift:53-112`, `:229-273` | sous tmux la chaîne parent ne mène **pas** au terminal (serveur détaché), d'où « tmux d'abord » ; `switch-client` avant `select-window` si le client est ailleurs |
| `findTmux()` 4 chemins + `sh -l -c which` | `TerminalJumper.swift:275-289` | couvre Homebrew ARM/Intel et nix-darwin |
| `runProcess` avec PATH enrichi | `TerminalJumper.swift:291-325` | un `.app` n'hérite pas du PATH du shell |
| `canBecomeKey = false` | `NotchWindow.swift:206-215` | contrainte structurante : interdit `keyboardShortcut`, impose les hotkeys globaux (donc AX) |
| `ClickThroughHostingView` / `hitTest` | `NotchWindow.swift:671-727` | en mode silhouette la fenêtre reste large de 560 pt alors que la pill est étroite |
| `resolveScreen(savedID:)` | `NotchWindow.swift:231-240` | `NSScreen.main` suit le focus clavier et fait basculer la silhouette |
| Certificat auto-signé à CN stable | `scripts/build.sh:108-137` | la signature ad-hoc régénère l'identité à chaque build et **révoque les autorisations Accessibility** |
| `NSSupportsAutomaticGraphicsSwitching` | `scripts/build.sh:102` | compte pour le budget énergie |

Ce qui est **écarté** :

| Brique | `fichier:ligne` | Motif |
|---|---|---|
| `countClaudeProcesses()` via `pgrep` | `ClaudeMonitor.swift:555-576` | `fork`/s mesuré à 11,34 ms, pour une info déjà dans `liveClaudeCwdCounts()` |
| `Timer` 1 Hz | `ClaudeMonitor.swift:78` | remplacé par FSEvents + cadence paresseuse |
| Les 18 `repeatForever` | `BuddyFace.swift` (18 sites) | `CADisplayLink` implicites jamais arrêtés, y compris hors écran |
| Les 6 `@State …Task` par buddy | `BuddyFace.swift:165-166`, `:327`, `:584`, `:729-730`, `:884-886` | jusqu'à 3 `Task` concurrentes par buddy, relancées à chaque `onChange(of: mode)` |
| `UsageAggregator.scan()` | `UsageAggregator.swift:168-278` | lecture intégrale de chaque jsonl de la semaine, toutes les 60 s, pour des chiffres que l'API donne exacts |
| `HeatmapAggregator.scan(_:)` | `HeatmapAggregator.swift:157-209` | remplacé par l'index incrémental |
| `findPIDBySessionID` via `lsof` | `TerminalJumper.swift:115-156` | claude **ferme le jsonl entre deux écritures** (`ClaudeMonitor.swift:524-526`) — code contradictoire dans le dépôt |
| `findAllClaudePIDs` acceptant `name == "node"` | `TerminalJumper.swift:349` | faux positifs massifs ; unifier sur le filtre de `ClaudeMonitor.swift:531-542` |
| Binaire dual-mode `--hook` | `NotchPilotApp.swift:11-13` | lie AppKit ; dyld le charge à chaque appel d'outil |
| Classe unique de 20 préférences | `BuddyPreferences.swift:147-458` | un `@Published` de couleur invalide ce qui observe la position ; cause du filtrage manuel de publishers (`NotchWindow.swift:177-192`) et de `suppressPrefsReposition` |
| `decodeProjectName` | `ClaudeMonitor.swift:265-269` | mort (jamais appelé) et lossy |
| `UpdateChecker` | fichier entier (372 l.) | l'app se recopie dans `/Applications` et **se re-signe** |
| `OnboardingView` / `OnboardingWindow` | 432 l. | reporté sans date |

---

## 7. Registre des risques

Trié par capacité à tuer le projet.

### R1 — Écriture destructrice dans `~/.claude/settings.json` — RFC-005/006
Probabilité **certaine** (l'écriture a lieu à chaque lancement) · impact **fatal en réputation**.

`HookInstaller.swift:114-120` relit tout le fichier, le re-sérialise avec
`[.prettyPrinted, .sortedKeys]` et fait `data.write(to:)` : écriture **non
atomique** qui **réordonne intégralement le fichier de l'utilisateur**. Idem pour
`permissions.allow` (`HookBridge.swift:326-331`). Deux dégâts : une écriture
concurrente de Claude Code écrase la configuration (dernier écrivain gagne) ; un
fichier maintenu à la main est ré-ordonné à chaque lancement, produisant un diff
monstrueux dans des dotfiles versionnés.

**Parade.** Sauvegarde horodatée avant la première écriture, jamais écrasée ·
`.atomic` · supprimer `.sortedKeys`, ou patcher le JSON textuellement sans
re-sérialiser · **écran de consentement affichant le diff exact avant d'écrire** ·
`--uninstall-hook` vérifié par `diff` contre la sauvegarde.

### R2 — Budget mémoire pulvérisé par le scan des jsonl — RFC-003/008
Probabilité **certaine** chez un utilisateur intensif · impact : **la contrainte
directrice manquée d'un facteur 10**.

C6 et C7 ci-dessus : fichier entier **plus** un tableau complet de sous-chaînes
matérialisés en RAM. Un jsonl de projet actif dépasse couramment 50 Mo.

**Parade.** Lecture par blocs de 64 Ko découpés sur `\n` — **le patron existe
déjà dans le dépôt** (`ClaudeMonitor.readTail:470-482`) · index incrémental
persisté (offset + agrégats par fichier) · scan hors du process d'UI.

### R3 — CPU au repos non nul par construction — RFC-001/002/004
Probabilité **certaine si on recopie l'architecture** · impact : **la raison
d'être du projet**.

Sources : C1, C2, C4, C5, C9.

**Parade.** FSEvents à la place du `Timer` 1 Hz · `NSTrackingArea` à la place du
poll souris · `proc_listpids` uniquement en réaction à un événement ·
`frameRate = 0` quand la pill est masquée · **interdiction absolue de `Process()`
dans une boucle périodique**. Mesure à la fin de **chaque** RFC.

### R4 — Le hack Keychain repose sur un détail d'implémentation d'Anthropic — RFC-003
Probabilité **moyenne-haute sur 12 mois** · impact fatal pour 003 seule.

`UsageAPI.swift:46-61` documente le mécanisme sans détour. Toute version de
Claude Code qui passerait à `SecItemAdd` depuis son propre binaire casse ça **en
silence**.

**Parade.** Spike jour 1 · isoler derrière un protocole `CredentialSource` à
implémentation unique · un échec de lecture ne bloque jamais l'UI · journaliser
distinctement « refusé » et « absent ».

### R5 — L'endpoint `oauth/usage` n'est pas public — RFC-003
Probabilité **haute** · impact : la fonction phare devient vide.

`UsageAPI.swift:43` code en dur l'URL, avec un en-tête **daté**
`anthropic-beta: oauth-2025-04-20` (`:157`) — instable par construction.

**Parade.** Le parseur de la référence est déjà bien formé : chaque champ est
optionnel (`:208-239`), donc un changement de schéma dégrade en « fenêtre nulle »
plutôt qu'en crash — **reprendre cette forme telle quelle**. Y ajouter un état
« données indisponibles » explicite, **jamais un chiffre inventé**.

### R6 — Le schéma de réponse `PermissionRequest` casse en silence — RFC-006
Probabilité **haute pendant le développement** · impact : 006 inutilisable, et le
diagnostic est invisible.

`HookClient.swift:157-160`, commentaire de l'auteur : tout champ de premier
niveau en trop fait que Claude Code invalide la réponse et retombe sur son TUI.
L'échec ne produit **aucune erreur** : l'utilisateur voit le prompt habituel et
conclut que l'app est cassée.

**Parade.** **Test golden-file** (fixture stdin → sortie attendue octet à octet)
en CI · journal local quand le hook sort sans décision · **conserver les deux
timeouts de 120 s** (`HookClient.swift:19`, `SocketServer.swift:168`) : c'est ce
qui empêche un bug de notch-buddy de devenir « Claude Code est bloqué ».

### R7 — Signature ad-hoc, Gatekeeper, permissions révoquées à chaque update — RFC-010
Probabilité **certaine** · impact : friction d'installation + régression à chaque release.

`scripts/build.sh:118-135` fabrique un certificat auto-signé, **avec un repli en
signature ad-hoc ligne 135**. Aucune notarisation (vérifié : `notary` absent de
`build.sh` et de `make-dmg.sh`). Le cask contourne en désactivant la protection
de l'OS à la place de l'utilisateur : `xattr -dr com.apple.quarantine`
(`release.yml:124-126`). Conséquence documentée par le dépôt lui-même
(`GlobalHotkeys.swift:35-37`) : la permission Accessibilité est révoquée à
**chaque** mise à jour.

**Parade.** Notariser (compte Apple 99 $/an, `notarytool submit --wait` +
`stapler staple`, ~1 j) — le risque disparaît entièrement. À défaut : certificat
auto-signé à CN stable hors dépôt et **supprimer le repli ad-hoc** (le repli
*est* le bug). Et **n'utiliser aucune API exigeant l'Accessibilité en v1** :
ni raccourcis globaux, ni détection plein-écran par AX — ce qui allège 001b de
~250 lignes au passage.

### R8 — Détection de session fragile — RFC-002/007
Probabilité moyenne · impact : mauvaise session affichée, saut vers le mauvais terminal.

`ClaudeMonitor.swift:528-553` apparie par nom de process et par `cwd`. Trois
failles : deux sessions dans le même `cwd` reçoivent leurs PID **par ordre de
tri** (`:248`) — appariement arbitraire ; `TerminalJumper.swift:349` matche aussi
`node` ; la normalisation `/private` est une heuristique.

**Parade.** En v1, **afficher un compteur de sessions sans prétendre les
identifier individuellement** — supprime le risque à coût nul. Ensuite, résoudre
le PID par le hook (`HookBridge.swift:120-142`), seule source fiable — d'où 007
**après** 006.

### R9 — Le format des jsonl n'est pas un contrat — RFC-002/003/008
Probabilité moyenne-haute sur 12 mois · impact : dégradation muette.

Clés non documentées : `type`, `message.usage.cache_read_input_tokens`,
`permissionMode`, `cwd`, `timestamp` (`ClaudeMonitor.swift:300-384`).

**Parade.** Un parseur qui **compte** les entrées non interprétées et expose ce
compteur dans un panneau de diagnostic · fixtures jsonl versionnées en test ·
aucun `fatalError`.

### R11 — Dette multi-agent assumée — RFC-003 / 004 / 006 / 007
Probabilité **certaine** (l'objectif produit est explicite) · impact : **quatre
RFC à retoucher après implémentation**.

Le produit vise à suivre Claude, Codex, Copilot, opencode et consorts. Le v1 est
délibérément Claude-only (arbitrage du 2026-08-19), ce qui câble en dur, à chaque
étage : `~/.claude/projects` (RFC-003), `proc_name == "claude"` (RFC-003), le
point d'accès OAuth d'Anthropic (RFC-004), le protocole de hook de Claude Code
(RFC-006, RFC-007).

Les agents n'exposent pas les mêmes choses : Claude Code offre hooks + transcripts
+ API de quota ; les autres offrent beaucoup moins, voire rien. Une abstraction
honnête devra donc raisonner en **niveaux de capacité** — présence / activité /
attente / consommation — et l'UI devra dégrader par agent.

**Parade, à appliquer pendant le v1 pour que la dette reste petite :**
(1) nommer les types en termes neutres dès maintenant — `AgentSession`, pas
`ClaudeSession` ; `AgentProvider`, pas `ClaudeMonitor` — le renommage a posteriori
est ce qui coûte cher ;
(2) isoler les chemins et identifiants Claude derrière **une** constante par RFC,
jamais dispersés ;
(3) ne jamais faire dépendre l'UI d'une capacité sans passer par un test de
capacité explicite, même quand il n'existe qu'un seul agent et qu'il répond
toujours oui.

### R10 — Dérive calendaire (développeur seul) — transverse
**Parade.** Règle dure : **chaque RFC se termine sur un binaire lançable.** Aucune
RFC ne laisse l'app cassée entre deux sessions de travail. C'est pourquoi 005
(qui seule ne produit rien d'observable) est collée à 006.

---

## 8. Protocole de vérification de la légèreté

Outil à écrire pendant RFC-001 (~60 lignes de shell) :
`scripts/perfcheck.sh <scenario> <durée>`, échantillonnage toutes les 5 s,
sortie CSV dans `docs/perf/<date>-<rfc>-<scenario>.csv`.

| Métrique | Commande | Seuil |
|---|---|---|
| RSS | `ps -o rss= -p <pid>` (Ko) | max < 40 960 — **à réviser après D5** |
| CPU | `ps -o %cpu= -p <pid>` | moyenne < 0,5 % repos / < 3 % activité |
| Réveils inactifs | `powermetrics --samplers tasks -n 1 \| grep NotchBuddy` | < 5/s repos, < 30/s activité |
| `fork`/`exec` | `sample <pid> 30` puis grep `posix_spawn` | **0 au repos** |

**La métrique qui compte est le nombre de réveils inactifs, pas le %CPU.** Un
%CPU de 0,4 % avec 70 réveils/s vide une batterie et ne déclenche aucune alerte
sur un seuil en pourcentage.

Trois scénarios fixes : **A** repos 10 min, aucune session, panneau replié, sur
batterie · **B** activité 5 min, 3 sessions dans 3 projets · **C** panneau
déployé 60 s, curseur en mouvement continu.

Cadence : première prise **fin de 001, scénario A** — elle devient la référence
(le RSS d'une fenêtre vide est le plancher incompressible). Puis les trois
scénarios à la fin de **chaque** RFC ; **une régression > 10 % sur n'importe
quelle métrique bloque la clôture**. Deux points de contrôle renforcés :
**fin de 002**, un `sample` de 30 s au repos doit montrer **zéro** `posix_spawn`
et **zéro** `proc_listpids` (preuve que l'event-driven a remplacé le polling) ;
**fin de 003 puis 008**, `/usr/bin/time -l` sur le scan seul contre un corpus
> 500 Mo, relevé du *maximum resident set size* (attrape R2).
