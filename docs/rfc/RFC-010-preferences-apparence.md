# RFC-010 — Préférences, réglages segmentés et éditeur de buddy

| | |
|---|---|
| **Status** | in-progress (90 %) — modèle, fenêtre segmentée et éditeur de buddy livrés ; reste le login item (bloqué par RFC-011) et les vérifications terrain |
| **Author** | Cyril Pereira |
| **Created** | 2026-08-19 |
| **Updated** | 2026-08-20 |
| **Phase** | 5 — Confort |
| **Depends on** | RFC-001 |
| **Related** | D2 · D7 · consommée par RFC-002, RFC-005 et RFC-012 · format `.buddy` défini en RFC-005 |
| **Blocks** | — |

## 1. Context & Problem

Cette RFC n'existait pas dans le découpage initial. Elle couvre pourtant
~1 200 lignes de la référence : `BuddyPreferences.swift` (459 l.) et le sélecteur
d'apparence (`NotchContentView.swift:2778-3470`, ~700 l.). Sans propriétaire, ce
volume se serait redistribué dans les autres RFC — c'est-à-dire nulle part.

Elle est aussi la RFC qui, mal faite, **recrée mécaniquement le monolithe**. La
référence met vingt préférences hétérogènes dans une seule classe
(`BuddyPreferences.swift:147-458`) : couleur du buddy, position de fenêtre,
démarrage au login, toggles de voix. Conséquence directe — un `@Published` de
couleur invalide tout ce qui observe la position. C'est pourquoi `NotchWindow`
doit filtrer manuellement quatre publishers (`NotchWindow.swift:177-192`) et
inventer un drapeau `suppressPrefsReposition` (`:494-509`) pour ne pas déclencher
une animation par écriture pendant un drag.

Second défaut : `didSet { UserDefaults.set }` sur chacune des vingt propriétés,
donc une écriture synchrone sur le main thread **à chaque frame de drag**
(`NotchWindow.swift:505-507`).

On y replie les notifications de fin de session et les annonces vocales :
`SpeechController` (132 l.) et `VoiceAnnouncer` (43 l.) ne pèsent pas une RFC.

### Élargissement du 2026-08-20 : la fenêtre est un formulaire, et le buddy n'est pas éditable

Ce qui est livré tient en un `Form` de deux sections — langue, buddy — sur une
seule page (`SettingsWindow.swift:93-160`). Deux limites, constatées à l'usage :

**Rien n'est segmenté.** Tout ce que les RFC en cours vont ajouter — démarrage au
login, alertes par événement, voix, saut vers le terminal, consommation,
diagnostics — arrive dans ce même formulaire. Un formulaire de vingt lignes
hétérogènes est la version UI du monolithe que §1 reproche au modèle : on n'y
trouve rien, et chaque ajout dégrade ce qui existait.

**Le buddy se choisit, il ne s'édite pas.** Le sélecteur liste les manifestes
installés et affiche un aperçu ; changer un visage demande d'ouvrir un fichier
texte dans un éditeur, à un emplacement que la fenêtre se contente d'ouvrir
(`SettingsWindow.swift:170-178`). C'est cohérent avec « le buddy est de la
donnée », et c'est hostile pour quiconque veut juste changer une frimousse.

## 2. Goals / Non-goals

**Goals.** Un modèle de préférences typé, **scindé en trois surfaces
d'invalidation distinctes**, avec migrations. L'UI de réglages. Les annonces
vocales et le retour haptique, comme *rendus* d'alerte.

**Déplacé en RFC-012.** La détection d'état et la politique d'alerte — quand
alerter, sur quel événement, avec quelle déduplication — ne sont plus ici. C'est
l'objectif n°1 du produit, pas un réglage à côté du choix de la couleur du buddy.
Cette RFC ne garde que les *préférences* d'alerte (activer/désactiver par
événement) et les surfaces de rendu qu'elle pilote.

**Ajoutés le 2026-08-20.** Une fenêtre de réglages **segmentée** — barre latérale,
une section par sujet, chaque section une vue autonome — et un **éditeur complet
des expressions du buddy** : images, couleur, taille, vitesse, mouvement, plus la
création et la duplication d'un buddy.

**Non-goals.** La géométrie de fenêtre (RFC-002 consomme `LayoutPrefs`). Le rendu
du buddy (RFC-005 consomme `AppearancePrefs`) — l'éditeur produit de la donnée,
il ne dessine pas. Le format `.buddy` lui-même (RFC-005) : l'éditeur en est un
client, il ne l'étend pas.

## 3. Proposed Solution

**Trois `@Observable` distincts**, c'est le point structurant :

| Modèle | Contenu | Consommé par |
|---|---|---|
| `AppearancePrefs` | style, couleur, taille | RFC-005 |
| `LayoutPrefs` | position, ancrage, épinglage | RFC-002 |
| `NotificationPrefs` | toggles voix / speech / haptique par événement | cette RFC |

Plus `PreferencesStore` (UserDefaults + migrations + **écritures coalescées**),
`SpeechPresenter`, `VoiceAnnouncer`, et `SettingsView` découpée en sous-vues de
moins de 200 lignes chacune (règle D2).

**Repris tel quel :**

| Brique | `fichier:ligne` | Pourquoi |
|---|---|---|
| Schéma de clés + valeurs par défaut | `BuddyPreferences.swift:370-389`, `:391-458` | Structure reprise, clés renommées. |
| Migration `LegacyNotchPosition` → fraction | `:79-91`, `:406-416` | Bon patron de migration, à généraliser dans `PreferencesStore`. |
| `applyStartAtLogin` via `SMAppService` | `:240-257`, `:453-457` | Le commentaire `:453-456` explique que `didSet` ne se déclenche pas depuis `init` : il faut pousser l'état manuellement au premier lancement, sinon le réglage ment. |
| `voiceAllows` / `speechAllows` par événement | `:276-286`, `:226-234` | |
| `SpeechController` : dédup + limite de débit 12 s + auto-clear | `SpeechController.swift:40-131` | Logique conservée. |
| `VoiceAnnouncer` + debounce 4 s | `VoiceAnnouncer.swift:18-38` | |
| Haptique `.levelChange` / `.drawCompleted` | `NotchContentView.swift:480-485` | |
| Clé de dédup bucketée à la minute | `NotchContentView.swift:545-548` | Évite de fusionner deux fins successives de la même session. |

**Modifié :**
- La classe unique → trois modèles (raison ci-dessus).
- `didSet` synchrone → écritures coalescées.
- `SpeechController` pilote des `withAnimation` en interne (`:114`, `:126`) :
  retiré. Un contrôleur ne décide pas de l'animation.
- `VoiceAnnouncer` est un `static let shared` instancié au lancement
  (`VoiceAnnouncer.swift:10`). Or `AVSpeechSynthesizer` alloue un moteur audio
  (~4-6 Mo) à la première utilisation. → **instanciation paresseuse**, d'autant
  que la voix est off par défaut (`BuddyPreferences.swift:398`).

**Budget.** 0 % au repos. RSS +1 Mo, +4-6 Mo **seulement** si la voix est
activée et utilisée au moins une fois.

### La fenêtre segmentée

Une barre latérale à gauche, une section à droite, une seule section visible à la
fois. Sept sections, choisies sur ce qui existe **ou** ce qu'une RFC en cours va
livrer — pas sur une arborescence inventée d'avance :

| Section | Contenu | Vient de |
|---|---|---|
| Général | langue, démarrage au login, délai de survol | RFC-010 |
| Buddy | choix, **éditeur d'expressions**, dossier | RFC-005 · cette RFC |
| Notifications | activation par événement, voix, haptique | RFC-012 · cette RFC |
| Sessions | groupement, saut vers le terminal, tmux | RFC-008 |
| Consommation | fenêtres suivies, rafraîchissement | RFC-004 |
| Avancé | diagnostics (`--info` dans la fenêtre), réinitialisation | RFC-001 |
| À propos | version, buddy actif, crédits MIT Notch-Pilot | RFC-011 |

Trois règles de construction :

- **Une section = un fichier = une vue < 200 lignes** (D2). La section est
  l'unité de découpage ; si une section dépasse, elle se scinde en sous-vues,
  jamais en un fichier plus gros.
- **Une section vide ne s'affiche pas.** Tant que RFC-004 n'expose aucun réglage,
  la section « Consommation » n'existe pas dans la barre. Une section qui
  n'offre rien est pire qu'absente : elle promet.
- **Aucun réglage sans effet.** Interdiction de préparer l'UI d'une préférence
  que le code ne lit pas encore — même règle que le panneau, qui n'affiche ni
  heatmap ni « always allowed » parce que RFC-009 et RFC-007 n'existent pas.

### L'éditeur de buddy, et le calque qu'il écrit

**Arbitré le 2026-08-20 : l'éditeur n'écrit pas dans le `.buddy`.** Les
modifications vivent dans un calque de préférences, et le fichier reste lu tel
quel.

Ce que ça coûte, dit franchement, parce que ça contredit deux principes du
projet :

- **D1 — une source de vérité par fait.** Il y en a désormais deux pour « à quoi
  ressemble ce buddy » : le fichier et le calque. La règle de résolution est donc
  fixée une fois, en un seul endroit (`BuddyOverrides.apply(to:)`), et jamais
  dupliquée dans une vue.
- **« Le buddy est de la donnée, pas du code »** — une édition ne se partage
  plus : envoyer son fichier à un collègue n'envoie pas ses retouches. Le
  contre-poids est une **exportation** explicite (« Enregistrer sous… »), qui
  aplatit calque + fichier en un `.buddy` autonome. Sans elle, l'arbitrage
  fermerait le « buddy par entreprise » ; avec elle, il le rend simplement
  volontaire.

Ce que ça achète : aucune écriture destructrice dans un fichier que l'utilisateur
a écrit à la main (R1 est le même risque, un dossier plus loin), une
réinitialisation qui est une suppression de clé plutôt qu'une restauration de
sauvegarde, et un buddy **créé dans l'app** qui n'a besoin d'aucun fichier pour
exister.

| Module | Responsabilité |
|---|---|
| `BuddyOverrides` | Le calque : `[buddyID: [expression: Override]]` + manifestes créés dans l'app. Codable, une seule clé `UserDefaults`. |
| `BuddyOverrides.apply(to:)` | Fusion manifeste ↔ calque. **Le seul endroit** qui connaît la précédence. |
| `BuddyEditorView` | La section : liste des expressions à gauche, éditeur à droite. |
| `ExpressionEditor` | Une expression : images (ajout, suppression, réordonnancement), couleur, taille, vitesse, mouvement. |
| `BuddyExportWriter` | Aplatit calque + fichier en un `.buddy` (écriture atomique, jamais par-dessus la source sans confirmation). |

Ce qui est éditable, et pourquoi c'est exactement ça : le format porte déjà
`frames`, `colour`, `fontSize` et `framesPerSecond` par expression
(`BuddyManifest.swift:56-84`), et `MotionKind` est un **vocabulaire fermé** de six
cas (`MotionKind.swift:20-32`) — donc un menu, jamais une saisie. Aujourd'hui le
mouvement est déduit du nom de l'expression (`BuddyFile.swift`,
`MotionKind.default(for:)`) et ne peut pas être choisi ; l'éditeur le rend
explicite, et le format devra l'écrire à l'export.

**L'aperçu passe par `BuddyView`**, comme partout ailleurs depuis le 2026-08-20 :
un aperçu dessiné autrement montrerait quelque chose que l'app n'affiche jamais.
Dans l'éditeur, et seulement là, le budget d'animation monte à `lively` pour que
la vitesse s'y juge ; la fenêtre fermée, il retombe à `still`.

**Budget.** 0 % fenêtre fermée. Fenêtre ouverte : une seule section montée à la
fois, un `TimelineView` dans l'éditeur, écritures du calque coalescées comme
celles des préférences (T2). Le rechargement à chaud existant reste la voie pour
les fichiers ; le calque notifie directement.

## 4. Alternatives Considered

**Garder une classe unique de préférences.** Écarté : c'est la cause mécanique du
filtrage manuel de publishers et du drapeau `suppressPrefsReposition`. Le défaut
est structurel, pas cosmétique.

**Une RFC séparée pour notifications et voix.** Écarté : 175 lignes au total.
Du cérémonial.

**`@AppStorage` plutôt qu'un store maison.** Écarté : `@AppStorage` n'offre pas
de chemin de migration, et le patron `LegacyNotchPosition` de la référence montre
qu'on en aura besoin.

**Supprimer la voix.** Défendable — elle est off par défaut dans la référence
elle-même. Gardée parce qu'elle coûte 43 lignes une fois le reste en place.

**L'éditeur réécrit le `.buddy`.** Proposé, **écarté par arbitrage du
2026-08-20**. C'était la seule option qui gardait une source de vérité unique et
un buddy partageable par construction. Écartée parce qu'elle fait écrire l'app
dans un fichier que l'utilisateur édite à la main, avec tout ce que R1 décrit
(sauvegarde, atomicité, diff consenti) pour un gain que l'exportation explicite
rend disponible à la demande.

**Un onglet plutôt qu'une barre latérale.** Écarté : sept sections en onglets
tiennent mal, et les onglets n'ont pas de niveau de regroupement — la référence
visuelle qui a motivé cette demande sépare « Avancé » du reste, ce qu'une barre
d'onglets ne sait pas faire.

**Une deuxième RFC pour l'éditeur.** Écarté sur demande : l'éditeur est une
section de la fenêtre, et deux fiches qui se citent l'une l'autre pour une même
fenêtre coûtent plus de comptabilité qu'elles n'en clarifient.

## 5. Action plan

| # | Tâche | Statut | % |
|---|---|---|---|
| T1 | Les trois modèles `@Observable` + `PreferencesStore` | **done** | **100** |
| T2 | Écritures coalescées (60 changements → 1 écriture, sous test) | **done** | **100** |
| T3 | Cadre de migration généralisé | **done** | **100** |
| T4 | `applyStartAtLogin` + réconciliation au premier lancement | **partial** | **60** |
| T5 | `SettingsView` + sous-vues (< 200 l. chacune) | **done** | **100** |
| T9 | **Internationalisation** — hors périmètre initial, voir ci-dessous | **done** | **100** |
| T6 | Pop-out de fin de session + dédup — **livré par RFC-012** (`AlertPresenter`, `AlertPolicy`) | **done** | **100** |
| T7 | `VoiceAnnouncer` paresseux + debounce 4 s | **done** | **100** |
| T8 | Retour haptique | **done** | **100** |
| T10 | Coquille segmentée : barre latérale, sections, sélection persistante | **done** | **100** |
| T11 | Sept sections, chacune un fichier de moins de 200 lignes | **done** | **100** |
| T12 | `BuddyOverrides` + `apply(to:)` + une seule clé `UserDefaults` | **done** | **100** |
| T13 | `ExpressionEditor` : images, couleur, taille, vitesse, mouvement | **done** | **100** |
| T14 | Duplication et suppression d'un buddy | **done** | **100** |
| T15 | `BuddyExportWriter` : aplatir calque + fichier en `.buddy` autonome | **done** | **100** |
| T16 | Aperçu live via `BuddyView`, budget `lively` limité à l'éditeur | **done** | **100** |

### Ce qui a résisté, à l'implémentation du 2026-08-20

**`@Observable` change la sémantique de `didSet`.** Une propriété stockée devient
une propriété calculée autour du registrar, donc s'assigner à soi-même depuis son
propre `didSet` **ré-entre dans le setter** au lieu d'être ignoré comme sur une
propriété stockée ordinaire. Le premier `pixelSize` bornait sa valeur dans
`didSet` et récursait jusqu'à épuiser la pile : le test a tué le runner entier
avec un SIGSEGV, sans nom de test. Bornage en propriété calculée.

**Le login item demande un bundle.** `SMAppService.mainApp` échoue sur un binaire
nu, ce qu'est l'app tant que RFC-011 n'a pas empaqueté. Le réglage lit l'état
réel du système plutôt qu'un drapeau stocké — c'est la moitié de la leçon que la
référence documente elle-même (`BuddyPreferences.swift:453-456`) — et se désactive
en disant pourquoi. **T4 reste à 60 % : le code est là, il n'est pas vérifiable.**

**« Aucun réglage sans effet » a coûté du câblage, pas des cases.** Regrouper par
dossier passe par `SessionGroup.ungrouped` plutôt que par un second type de ligne
dans la vue ; le silence quand le terminal est au premier plan est poussé dans
`AlertTracker` au lieu d'y être lu ; la grosseur des pixels descend jusqu'à
`BuddyView` en paramètre. Trois câblages pour trois interrupteurs, et zéro
interrupteur décoratif.

**Critère de sortie.** Une session qui se termine déclenche **exactement une**
notification — pas deux, pas zéro — sur dix essais. Un drag complet de la
fenêtre ne produit **aucune** écriture `UserDefaults` avant le relâchement.
Changer la couleur du buddy ne provoque **aucun** recalcul de frame de fenêtre.

**Critère de sortie de l'éditeur.** Modifier une image de l'expression `working`
la voit changer dans la notch **sans relancer l'app**. Réinitialiser cette
expression restitue exactement ce que dit le fichier. Exporter puis charger le
`.buddy` obtenu redonne le buddy édité, à l'identique — vérifié en comparant les
manifestes, pas les fichiers.

**Où en est ce critère (2026-08-20).** Le troisième point est **tenu et sous
test** (`BuddyOverridesTests.exportRoundTrip`, plus le cas positionnel taille
avant vitesse). Les deux premiers sont écrits mais **vérifiés seulement par les
tests du calque** : ils demandent une session réelle et un clic, pas une
assertion.

### Décidé le 2026-08-19 : une fenêtre de préférences native

Les réglages vivent dans **une fenêtre macOS standard**, pas dans le panneau de
la notch.

La référence fait l'inverse : son sélecteur d'apparence occupe
`NotchContentView.swift:2778-3470`, soit ~700 lignes à l'intérieur de la vue du
panneau. Trois raisons de ne pas la suivre :

- **Le panneau se replie dès que le curseur s'en va.** Une surface de réglages
  qui disparaît quand on va chercher sa souris est hostile.
- **La notch est étroite et le panneau est éphémère.** Les réglages sont
  parcourus, comparés, revisités — ils veulent une fenêtre qu'on redimensionne et
  qu'on laisse ouverte.
- **C'est 700 lignes de moins dans la vue du panneau**, qui est précisément ce
  qui a fait de `NotchContentView` un fichier de 3 738 lignes.

Contrainte à traiter : l'app est en `.accessory`, sans menu ni Dock, donc **`⌘,`
n'est atteignable nulle part**. L'ouverture se fait depuis le panneau de la
notch — un bouton d'engrenage — et la fenêtre, elle, est une `NSWindow`
ordinaire : redimensionnable, déplaçable, listée dans le sélecteur de fenêtres,
et qui **peut** devenir clé (contrairement au panneau, cf. RFC-002), donc les
champs de saisie et les raccourcis y fonctionnent.

### Ajout hors périmètre : l'internationalisation

Demandée après la rédaction de la fiche. Français et anglais, réglable, détectée
au premier lancement.

**Le catalogue est une `struct` Swift, pas des fichiers `.strings`.** Une clé
manquante dans un `.strings` est un raté à l'exécution : l'app affiche la clé
brute ou retombe silencieusement sur une autre langue, et personne ne le voit
avant qu'un utilisateur le signale. Ici chaque langue est une instance de la même
structure, donc **ajouter une chaîne sans la traduire ne compile pas**.

Le prix est réel : ce n'est pas un format qu'un traducteur peut éditer. À deux
langues dans un outil personnel le compromis est dans le bon sens, et le jour où
une troisième arrive avec quelqu'un d'autre pour l'écrire, le catalogue peut
passer en `.strings` sans toucher aux sites d'appel.

Trois points de conception :

- **`.system` reste un cas distinct**, jamais résolu une fois pour toutes.
  Quelqu'un qui change la langue de macOS s'attend à ce que l'app suive ; stocker
  la valeur résolue la figerait.
- **Une langue absente retombe entièrement en anglais**, pas à moitié. Un
  utilisateur portugais obtient une langue qu'il lit, pas une interface à demi
  traduite.
- **La locale des dates suit l'interface**, sinon un panneau français affiche
  « August 23 » sous « semaine ».

Un test vérifie que les deux catalogues **diffèrent réellement**, pour attraper
un copier-coller non traduit.

### La fenêtre est native, et le panneau reste ouvert derrière

`⌘,` n'atteint rien — l'app est en `.accessory`, sans barre de menus. L'engrenage
du panneau est l'unique porte d'entrée.

**Défaut trouvé à l'usage :** cliquer l'engrenage repliait le panneau. Le suivi
de survol faisait son travail au pire moment — le curseur quitte la pastille pour
aller vers la fenêtre qui vient de s'ouvrir. Corrigé par un état d'épinglage qui
court-circuite les deux sources de survol tant que les réglages sont ouverts, et
qui **revérifie la réalité** au désépinglage plutôt que de la supposer.

La fenêtre est **un cran au-dessus de `.statusBar`**, pas à `.floating`
(`SettingsWindow.swift:78`). C'est une correction, pas un détail : `.floating`
vaut 3 et `.statusBar` vaut 25, donc une fenêtre « flottante » s'ouvrait
**sous** la pastille qui venait de l'ouvrir.

## 6. Open Questions

**Q1bis — La fenêtre de préférences doit-elle apparaître dans le Dock quand elle
est ouverte ?** Une app `.accessory` n'a pas d'icône ; certains utilitaires
basculent temporairement en `.regular` tant qu'une fenêtre est ouverte, pour
qu'elle soit atteignable au `⌘Tab`. Le prix est une icône qui apparaît et
disparaît.

**Q1 — Combien de préférences exposer ?**
La référence en a vingt, dont six styles × six couleurs. Chaque réglage est du
code, de l'UI et un cas de migration à vie.

**Q2 — La pop-out de fin de session interrompt-elle ?**
Elle sort la pastille de la notch pour former une pilule plus large. Sur un écran
partagé ou en présentation, c'est une apparition non sollicitée.

**Q3 — Le « peek » aléatoire survit-il ?**
`NotchContentView.swift:620` : toutes les 28-75 s, la pastille s'anime 1,6 s
même au repos. C'est un réveil périodique permanent pour un effet décoratif.
Recommandation : derrière une préférence, **off par défaut**.

```sh
# Coût du peek, mesuré des deux façons sur 10 minutes :
PEEK=1 ./scripts/perfcheck.sh A 600; PEEK=0 ./scripts/perfcheck.sh A 600
column -s, -t docs/perf/*-010-A.csv
```

## Notes d'implémentation

Pavés d'arbitrage déplacés depuis le code (2026-08-20), repris tels quels.

### `Sources/VibeBuddy/Settings/SettingsShell.swift` — `struct SettingsShell`

**Pourquoi segmenté plutôt qu'un seul formulaire.** Ce qui a été livré d'abord
était un unique `Form` à deux sections. Tout ce que les RFC ouvertes s'apprêtent
à ajouter — élément de démarrage, alertes par événement, voix, saut vers le
terminal, utilisation, diagnostics — atterrit dans ce même formulaire, et un
formulaire de vingt lignes hétérogènes est la version UI du monolithe que la
RFC-010 passe sa première page à critiquer dans le *modèle*.

**Une seule section montée à la fois.** `NavigationSplitView` ne construit que le
détail sélectionné : la timeline de l'éditeur de buddy n'existe pas pendant qu'on
lit la page À propos. C'est tout le budget d'animation de cette fenêtre : une
horloge, au seul endroit où le mouvement est le sujet.

**Dynamic Type ici, tailles fixes dans la pastille.** Chaque texte de cette
fenêtre utilise un style sémantique (`.body`, `.caption`, `.callout`, `.title2`),
donc quelqu'un qui a agrandi la taille de texte système est suivi. La pastille ne
peut pas en faire autant : la notch fait 38 pt de haut, une dimension matérielle
qu'aucune préférence ne déplace, donc les tailles du buddy viennent de son
manifeste et restent en points.

### `Sources/VibeBuddy/Settings/SettingsShell.swift` — `SettingsShell.Tab`

Les sections qui n'ont rien derrière elles ne sont pas listées du tout. Une
section qui promet un sujet et livre une page vide est pire qu'une section
absente — même règle que le panneau, qui n'affiche pas de heatmap parce que la
RFC-009 n'existe pas.

### `Sources/VibeBuddy/Settings/SettingsWindow.swift` — `final class SettingsWindow`

Une vraie fenêtre macOS, délibérément différente du panneau de la notch. La
RFC-010 a tranché : les préférences ne vivent **pas** dans la pastille. Le
panneau se replie dès que le curseur en sort, et une surface de préférences qui
disparaît pendant qu'on tend la main vers la souris est hostile. Les préférences
se parcourent, se comparent et se reprennent — elles veulent une fenêtre qu'on
peut redimensionner et laisser ouverte.

Elle **peut** aussi devenir key, contrairement à `NotchPanel`, donc les champs de
texte et la navigation clavier fonctionnent ici. C'est l'autre moitié de la
raison de les séparer.

L'app est un accessoire sans barre de menus, donc `⌘,` n'atteint rien. La seule
entrée est l'engrenage dans l'en-tête du panneau.

Fenêtre redimensionnable : une barre latérale plus un éditeur de buddy ne tient
pas dans un 520×360 fixe, et les sections diffèrent assez en hauteur pour qu'une
taille unique soit fausse pour la plupart d'entre elles.

### `Sources/VibeBuddy/Settings/Sections/BuddySection.swift` — `struct BuddySection`

**La couche, pas le fichier.** Les édits vont dans `BuddyOverrides` (préférences) ;
le fichier `.buddy` n'est jamais écrit. Arbitré le 2026-08-20 (RFC-010 §3), et
cela coûte quelque chose de réel — un édit ne voyage plus avec le fichier — ce
qui est la raison d'être de l'`Exporter` deux lignes plus bas.

**Vivant, sinon ce n'est pas un éditeur.** Chaque changement re-résout le
manifeste et le pousse vers la notch, donc le buddy à l'écran est le buddy en
cours d'édition. Un éditeur dont le résultat n'apparaît qu'après un relancement
est un champ de texte avec des étapes en plus.

### `Sources/VibeBuddy/Settings/BuddyEditor/BuddyActionsRow.swift` — `struct BuddyActionsRow`

La ligne décide seulement de ce qui est *offert* ; chaque action est une méthode
de la section qui possède le manifeste et le magasin d'overrides, passée en
closure. Garder le travail hors d'un corps de vue est ce qui permet à ces actions
de rester lisibles — et testables — à côté de l'état qu'elles modifient.

Les deux boutons destructifs sont conditionnels pour des raisons différentes :
réinitialiser n'a pas de sens quand il n'y a rien à réinitialiser, et supprimer
est refusé sur un buddy venu d'un fichier, puisque l'app n'écrit jamais dans les
fichiers `.buddy`.

### `Sources/VibeBuddy/Settings/BuddyEditor/BuddyPreviewStrip.swift` — `struct BuddyPreviewStrip`

Via `BuddyView`, comme partout ailleurs : un éditeur qui prévisualise son sujet
avec un autre moteur de rendu prévisualise quelque chose que l'app n'affiche
jamais. C'est le seul endroit où le budget d'animation tourne en `lively` — le
champ de vitesse ne se juge pas sur une image fixe.

### `Sources/VibeBuddy/Settings/BuddyEditor/ExpressionEditorView.swift` — `struct ExpressionEditorView`

**Chaque champ est à trois états.** Un champ est soit édité, soit hérité du
fichier. « Hérité » est affiché plutôt que silencieusement pré-rempli, pour que
réinitialiser soit un acte visible et non une conjecture sur la valeur qui était
là à l'origine.

**Un vocabulaire fermé, donc un menu** (champ *motion*). Le manifeste choisit un
mouvement, il n'en décrit jamais un — laisser une préférence porter un script
mettrait un évaluateur d'expressions dans la boucle de rendu.
