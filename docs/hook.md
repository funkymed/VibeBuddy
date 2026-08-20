# Reprise — notch-buddy

Point d'entrée après un effacement de contexte. À lire avant `CLAUDE.md`, qui
donne les règles ; celui-ci donne l'**état** et les **pièges**.

Dernière mise à jour : 2026-08-20 (soir).

---

## Ce qu'est le produit

App macOS native qui transforme la notch du MacBook en tableau de bord des agents
de code. Swift/SwiftPM, macOS 14+, **zéro dépendance externe**.

Objectifs, par ordre d'importance — toute fonctionnalité qui n'en sert aucun est
du confort :

1. **Être alerté sans regarder** — l'agent a terminé, ou il attend.
2. **Suivre sa consommation** réelle.
3. **Suivre plusieurs sessions** à la fois.
4. **De manière ludique**, dans la notch.

---

## État en un coup d'œil

| | |
|---|---|
| Sources | 72 fichiers, 8 926 lignes |
| Tests | 21 fichiers, **238 tests**, tous verts |
| Coût mesuré | **8,3 Mo** `phys_footprint` · **0,04 %** CPU · **0 réveil inactif** |
| Fait | RFC-001 (socle), RFC-003 (sessions) |
| En cours | 002 à 95 %, 005 à 95 %, 012 à 95 %, 004 à 90 %, 010 à 90 %, 008 à 75 % |
| **Bloqué** | **RFC-006 et RFC-007** — voir « le spike qui n'a pas tranché » |
| Reste v1 | 9-17 j-h |

Le Gantt fait foi et vit dans `CLAUDE.md`. **Il a dérivé trois fois** au cours du
développement : du code livré, des fiches à 0 %. Vérifier le code avant de croire
un pourcentage.

---

## Ce qui marche déjà

L'app détecte les sessions en **0,13 s**, affiche leur état dans l'encoche,
alerte à la fin d'un tour **et quand l'agent attend une réponse**, montre la
consommation réelle, et déploie un panneau listant les projets groupés — dont
chaque ligne vivante ramène à son onglet de terminal.

```sh
swift build -c release
.build/release/NotchBuddy          # tourne jusqu'à Ctrl-C
.build/release/NotchBuddy --info   # diagnostic complet, puis sort
.build/release/NotchBuddy --bench <mode> <secondes>
#   modes : shell · panel · pill · hidden · interaction · sessions · app
```

`--info` est l'outil de premier recours : écrans, géométrie, cadres calculés,
aimants, buddies installés, langue, parseur contre les vrais transcripts,
sessions vivantes, consommation, coût mémoire.

---

## Les quatre décisions qui structurent tout

**D3 — un seul `WakeCoordinator`.** Un `Timer` créé ailleurs est un échec de
revue. Budget : moins de 2 réveils/s au repos, **0** écran verrouillé. La
référence en a sept qui ne s'arrêtent jamais.

**D2 — `@Observable`, aucune vue au-dessus de 200 lignes.** La vue équivalente
chez Notch-Pilot fait 3 738 lignes et se réévalue en entier à chaque
`@Published`.

**D1 — une seule source de vérité par fait.** Le processus dit la *liveness*, le
transcript dit le *contenu*, le hook dirait l'*identité*. Clé primaire : le
`sessionID`, jamais le `cwd`.

**R11 — multi-agent reporté, dette assumée.** Le v1 est Claude-only par
arbitrage. Les types se nomment `AgentSession`, pas `ClaudeSession` : le
renommage a posteriori est ce qui coûte cher.

---

## Le spike qui n'a pas tranché

`docs/spikes/hook-contract.md`. **Établi :** `--settings <fichier>` charge bien
des hooks sans toucher à `~/.claude/` ; `SessionStart`, `UserPromptSubmit`,
`PreToolUse` et `Stop` se déclenchent.

**Non établi :** `PermissionRequest` ne s'est **jamais** déclenché, même quand une
permission était réellement refusée. Hypothèse non vérifiée : il n'existe que
pour un prompt interactif.

Pour conclure — demande une main humaine, une minute :

```sh
cd docs/spikes/hook/project
claude --settings ../settings.json --permission-mode manual
# puis : « Lis le fichier /etc/hosts »
# → si ça marche, le refus porte « REFUS-SPIKE-7f3a »
```

**Ne pas engager RFC-006/007 avant cette réponse** : 8 à 12 j-h suspendus à une
hypothèse. Le cœur du produit n'en dépend pas.

---

## Les pièges, chèrement acquis

**Le format des transcripts contient plus qu'on ne croit.** Quatre signaux que
les fiches croyaient réservés aux hooks y sont nativement : `permission-mode`,
`system/turn_duration` (fin de tour), `started`/`result` (sous-agents),
`is_error` sur `tool_result`. **Trois ont été trouvés par le compteur d'entrées
non reconnues** — la parade au risque R9, qui s'est payée dès sa première
exécution. Ne pas la supprimer.

**`proc_pidinfo` ne franchit pas un processus setuid.** La chaîne parent d'un
agent dans iTerm2 passe par `login`, setuid root. Utiliser
`sysctl(KERN_PROC_PID)`. La référence porte cet angle mort.

**`eventPaths` de FSEvents est un `char **`**, pas un `CFArray`, sauf si
`kFSEventStreamCreateFlagUseCFTypes` est posé. Le lire à l'envers crashe dans
`objc_msgSend`. Couvert par `ProjectsWatcherTests`.

**FSEvents surveille où sont les octets, pas où est le lien.** Les buddies sont
liés symboliquement depuis `assets/` ; le veilleur résout les liens.

**`NSWindow.Level.floating` (3) est SOUS `.statusBar` (25).** La fenêtre de
réglages s'ouvrait sous la pastille qui l'avait ouverte.

**Un banc dont la closure ne fait rien ne mesure rien.** Une mesure a annoncé
0,036 réveil/s pour une cadence à 10 Hz ; le vrai chiffre était 6,3. Le banc
enregistrait une closure vide.

**`--bench sessions` n'instancie pas `AppCoordinator`.** Utiliser `--bench app`
pour tout ce qui touche au buddy, aux réglages ou au rechargement à chaud.

**Un seul chemin de rendu du buddy : `BuddyView`.** L'aperçu des réglages
dessinait le même buddy en `Text` brut — donc un aperçu de quelque chose que
l'app n'affiche jamais, ni pixelisé ni éclairé. Tout passe désormais par
`BuddyView`, avec un `AnimationBudget` laissé à `.still` dans les réglages :
même rendu, aucune horloge. Ne pas réintroduire un second dessin « juste pour
l'aperçu ».

**La fenêtre de contexte n'est pas dans le transcript.** Chaque entrée assistant
dit `"model":"claude-opus-5"` et rien d'autre ; le `[1m]` qui choisit la fenêtre
d'un million vit dans `~/.claude/settings.json` (`"model": "opus[1m]"`). Déduire
la fenêtre des jetons donnait 71 % là où Claude Code affichait 14 % — même
nombre de jetons, dénominateur cinq fois trop petit. `ContextWindowResolver` lit
les réglages (utilisateur, projet, local, plus `env.ANTHROPIC_MODEL`) ; le seuil
des 200k reste en filet, pour ce que les réglages ne voient pas (`/model` tapé en
cours de session).

**`@Observable` change la sémantique de `didSet`.** La macro transforme une
propriété stockée en propriété calculée autour du registrar : s'assigner à
soi-même depuis son propre `didSet` **ré-entre dans le setter** au lieu d'être
ignoré comme sur une propriété stockée ordinaire. Un bornage écrit dans `didSet`
a récursé jusqu'à épuiser la pile et a tué le runner de tests entier avec un
SIGSEGV, sans nom de test pour l'accuser. Borner dans une propriété calculée.

**Les préférences sont trois modèles, pas un.** `AppearancePrefs`, `LayoutPrefs`,
`NotificationPrefs`, un seul `PreferencesStore` derrière, écritures coalescées
(60 changements → 1 écriture, sous test). Le découpage est par *qui observe
quoi* : un changement de couleur du buddy ne doit pas invalider ce qui regarde la
position de la fenêtre.

**Les modifications de buddy vivent dans `UserDefaults`, pas dans le `.buddy`.**
Arbitrage du 2026-08-20. Deux sources de vérité, donc **une seule fonction** les
réconcilie — `BuddyOverrides.apply(to:)` — et `BuddyExportWriter` aplatit le tout
en `.buddy` autonome pour qu'une retouche puisse encore se partager.

**Le saut vers l'onglet s'apparie sur le tty, jamais sur un titre.**
`ProcessLookup.tty(of:)` (`sysctl` → `e_tdev` → `devname`) donne `/dev/ttys004` ;
iTerm2 et Terminal publient `tty` en lecture sur leur `session` / `tab`. C'est
une égalité, pas une heuristique — les titres sont écrits par le shell et deux
agents du même projet partagent leur `cwd`. Sous tmux le tty est celui du volet,
donc aucune session de l'émulateur ne le porte : le repli active l'app **sans**
choisir d'onglet, plutôt que d'en choisir un faux.

**L'attente de réponse est dans le transcript, elle aussi.** `AskUserQuestion`
et `ExitPlanMode` s'écrivent en `tool_use` avec un `id` ; la réponse revient en
`tool_result` portant le même `tool_use_id`. Un usage sans résultat derrière lui
est un agent à l'arrêt — cinquième signal que les fiches croyaient réservé au
hook. La liste des outils-questions est **fermée** (`QuestionTools.names`) :
dans le fichier, un `Bash` qui tourne et une question sans réponse sont
indiscernables, et déduire d'un délai ferait de chaque commande lente une fausse
alerte. `awaiting` n'est donc plus une face morte — c'est ce qui la produit.

---

## Le format `.buddy`

Fichiers dans `~/Library/Application Support/notch-buddy/buddies/`, **liés** vers
`assets/buddies/`. Rechargés à l'enregistrement, sans relance ni recompilation —
recompiler ne sert à rien, ces fichiers vivent hors du binaire.

```
size: 15                      # défaut, surchargeable par expression
speed: 1                      # images par seconde, défaut 1, bornes 0,05–30

idle (yellow #FFBB00) 17 3    # couleur, puis taille, puis vitesse — positionnel
(ᵕ • ᴗ •)                     # une image par ligne
(„• ֊ •„)
                              # ligne vide = fin de section
```

`idle` est la seule expression obligatoire ; les autres y retombent.

**La vitesse est un débit, pas un délai** — plus grand veut dire plus rapide, et
le moteur prend l'inverse dans `BuddyManifest.secondsPerFrame(for:)`. Une valeur
hors bornes est **refusée et signalée**, jamais ramenée dans les bornes : un
fichier qui demande 200 images/s est une faute, et en dessiner 30 sans rien dire
la cache. Au-dessus de 8 img/s le palier d'animation passe à `lively`, sinon
l'horloge à 8 Hz mangerait une image sur deux.

Trois formats ont été écrits avant celui-ci — béziers, puis grille de pixels.
Les deux marchaient à taille d'affiche et perdaient leur sens à 20 pt. **Ne pas y
revenir** sans lire RFC-005 §4, qui dit pourquoi avec les mesures.

---

## Ce qu'il ne faut pas faire

- **Jamais commiter, pousser, ni créer de branche.** L'utilisateur gère son git.
- **Ne rien afficher de faux.** Le panneau n'a ni heatmap ni « always allowed »
  parce que RFC-009 et RFC-007 n'existent pas. Un chiffre de remplacement dans
  un produit dont l'argument est de montrer le *vrai* nombre est la pire chose
  à livrer.
- **Ne pas écrire dans `~/.claude/settings.json`.** Le spike passe par
  `--settings`. Quand RFC-006 arrivera, R1 impose sauvegarde, écriture atomique,
  et consentement affichant le diff.
- **Ne pas annoncer un pourcentage sans vérifier le code.** Grep bilingue
  `Status|Statut`.

---

## La suite, par ordre d'utilité

1. **Faire trancher le spike hook** — une minute d'interaction humaine, débloque
   ou annule 8-12 j-h.
2. **RFC-010** (90 %) — livrée le 2026-08-20 : fenêtre segmentée à sept sections,
   éditeur complet des expressions du buddy, trois modèles de préférences, voix
   et haptique. Reste le **login item**, écrit mais invérifiable tant que l'app
   n'est pas un bundle — il attend RFC-011 — et les vérifications à l'usage.
3. **RFC-011** — empaquetage. L'app n'est pas installable aujourd'hui.
4. Vérifications terrain en attente : écran externe (RFC-002), trois sessions
   simultanées (RFC-012), scénario C curseur en mouvement (RFC-005).
