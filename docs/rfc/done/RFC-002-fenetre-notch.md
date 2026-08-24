# RFC-002 — Fenêtre notch : NSPanel, click-through, ancrage multi-écran

| | |
|---|---|
| **Status** | **done (100 %)** — clôturée le 2026-08-23. Le test sur écran externe est **reporté, pas oublié** : il demande un moniteur branché et ne bloque plus rien. |
| **Author** | Cyril Pereira |
| **Created** | 2026-08-19 |
| **Updated** | 2026-08-19 |
| **Phase** | 1 — Fondations |
| **Depends on** | RFC-001 |
| **Related** | RFC-010 (LayoutPrefs) |
| **Blocks** | RFC-005, RFC-007, RFC-008 |

## 1. Context & Problem

La surface entière de l'app est une fenêtre collée à la notch, qui doit :
se replier en pastille et se déployer en panneau ; laisser passer les clics dans
ses zones transparentes vers la barre de menus en dessous ; survivre au
branchement d'un écran externe et au verrouillage de session.

Aucun de ces trois points n'est trivial, et la référence y consacre 825 lignes
(`NotchWindow.swift`) dont la moitié corrige des cas particuliers réels. Les
reproduire par déduction coûterait plusieurs jours ; ils sont documentés dans le
code et directement réutilisables.

Deux dettes à ne pas reprendre :
- `updateCollapsed` est **no-op quand `isExpanded`** (`NotchWindow.swift:626-641`) :
  rustine contre une course entre deux `onChange` qui se déclenchent au même
  re-rendu SwiftUI.
- `suppressPrefsReposition` (`NotchWindow.swift:494-509`) : drapeau qui neutralise
  les observateurs Combine pendant un drag, symptôme de « les préférences servent
  de bus d'événements ».

## 2. Goals / Non-goals

**Goals.** Un `NSPanel` `.nonactivatingPanel` `.statusBar` ; morphing
pastille ↔ panneau piloté par une machine à états explicite ; hit-test sélectif ;
résolution d'écran stable ; réaction à `didChangeScreenParameters` ; détection de
survol cadencée par le `WakeCoordinator` et **coupée quand la pastille est masquée**.

**Non-goals.** Le contenu SwiftUI (RFC-005, 007, 008). Les préférences elles-mêmes
(RFC-010). **Toute API exigeant l'Accessibilité** : ni raccourcis globaux, ni
détection plein-écran par AX — décision prise avec RFC-011 (signature auto-signée).

## 3. Proposed Solution

| Module | Responsabilité |
|---|---|
| `NotchPanel` | La `NSPanel`. Ne contient **aucun** calcul de frame. |
| `NotchFrameSolver` | **Pur et testable** : (fraction, écran, taille souhaitée) → `NSRect`. Contient les aimants. |
| `PillLayout` | **Pur.** Les trois slots — oreille, encoche, oreille — avec leurs largeurs **mesurées** et le décalage d'alignement. |
| `ClickThroughHostView` | Hit-test sélectif au-dessus de l'hôte SwiftUI. |
| `SnapPreviewPanel` | Aperçu translucide de la zone d'accroche pendant un drag. |
| `HoverProbe` | Remplace `MouseMonitor`. Cadencé par `WakeCoordinator`, **arrêté quand invisible**. |
| `PanelState` | Machine à états explicite : `.hidden / .pill / .speech / .panel`. |

**Repris tel quel** — les briques dont la raison d'être est documentée :

| Brique | `fichier:ligne` | Pourquoi |
|---|---|---|
| `canBecomeKey = false` | `NotchWindow.swift:206-215` | Contrainte structurante : interdit `keyboardShortcut`, donc impose des hotkeys globaux (donc l'Accessibilité) — raison de plus de renoncer aux raccourcis en v1. |
| `ClickThroughHostingView` / `hitTest` | `NotchWindow.swift:671-727` | En mode silhouette la fenêtre reste large de 560 pt alors que la pastille est étroite : sans hit-test sélectif, elle avale les clics de la barre de menus. |
| `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]` | `NotchWindow.swift:133` | |
| `resolveScreen(savedID:)` | `NotchWindow.swift:231-240` | `NSScreen.main` suit le **focus clavier** : l'utiliser fait sauter la fenêtre d'écran quand on tape ailleurs. |
| Géométrie depuis l'écran encoché | `NotchWindow.swift:79-102` | Prendre `NSScreen.main` rend la silhouette trop étroite au retour d'un écran externe. |
| Hystérésis enter/exit du survol | `MouseMonitor.swift:52-57`, `:119-120` | Sans elle, le jitter au pixel près fait clignoter le panneau à chaque poll. |

**Repris avec modification :**
- Aimants et `snapToReleaseLocation` (`NotchWindow.swift:455-510`) : logique
  correcte mais mêlée à la fenêtre → extraite dans `NotchFrameSolver`, testable
  sans écran.
- `suppressPrefsReposition` et le no-op de `updateCollapsed` **disparaissent** :
  avec un solver pur et une seule application de frame par transition d'état, il
  n'y a plus de course à neutraliser.
- Poll souris (`MouseMonitor.swift:40`) : conservé à 10 Hz — `NSEvent.mouseLocation`
  ne fait pas d'IPC — mais cadencé par le `WakeCoordinator` et **coupé quand la
  pastille est masquée**. Un `NSTrackingArea` serait event-driven mais ne couvre
  pas une fenêtre à hit-test sélectif ; à réévaluer (Q2).
- Requête AX plein-écran (`MouseMonitor.swift:66-72`, `:81-117`) : **supprimée**
  en v1 (pas d'Accessibilité). Si le besoin revient, remplacer le poll par
  `NSWorkspace.didActivateApplicationNotification` + une requête unique.

## 4. Alternatives Considered

**Une `NSWindow` ordinaire plutôt qu'une `NSPanel`.** Écartée : `.nonactivatingPanel`
est ce qui permet d'interagir sans voler le focus au terminal — l'app n'a ni
dock, ni barre de menus, elle ne doit jamais devenir active.

**`NSTrackingArea` au lieu du poll souris.** Séduisant (0 réveil), mais le
commentaire `MouseMonitor.swift:9-14` explique pourquoi la référence poll : la
fenêtre est plus large que sa zone visible et le tracking suivrait la fenêtre,
pas la pastille. À trancher en Q2 avec une mesure.

**Garder la géométrie dans la `NSPanel`.** Écartée : elle devient intestable, ce
qui est précisément ce qui a produit les deux rustines citées.

## 5. Action plan

| # | Tâche | Statut | % |
|---|---|---|---|
| T1 | `NotchFrameSolver` pur + tests (mono-écran, écran externe, fraction hors bornes) | **done** | **100** |
| T9 | `PillLayout` : trois slots, largeurs mesurées, décalage d'alignement | **done** | **100** |
| T2 | `NotchPanel` + `collectionBehavior` + `canBecomeKey = false` | **done** | **100** |
| T3 | `ClickThroughHostView` + test manuel « cliquer à travers les marges » | **done** | **100** — vérifié à la main, un défaut de drag trouvé et corrigé |
| T4 | `PanelState` + transitions pastille ↔ panneau | **done** | **100** |
| T5 | `HoverProbe` cadencé, coupé quand invisible | **done** | **100** |
| T6 | Réaction à `didChangeScreenParameters` + `resolveScreen` | **done** | **100** — code livré et exercé sur l'écran interne. La manche sur écran externe reste à jouer quand un moniteur est là : sans encoche, `notchWidth` retombe à 24 et la disposition change. Arbitrage du 2026-08-23 : ne bloque pas la clôture. |
| T7 | Drag + aimants + `SnapPreviewPanel` | **done** | **100** |
| T8 | `perfcheck.sh` scénarios A et C, comparés au plancher de RFC-001 | **done** | **100** |
| T10 | **Trois défauts de survol corrigés** (course d'animation, zone périmée, curseur) | **done** | **100** |

### T10 — le survol, trois fois de suite

**La course d'animation.** `applyState` sautait le changement de cadre quand
`frame.size == carrier`. En pleine animation la fenêtre passe par toutes les
tailles intermédiaires, dont celle vers laquelle on revient : un repli demandé
pendant l'ouverture prenait le raccourci, l'animation d'ouverture continuait par
dessous, et la fenêtre finissait à 460 pt alors que l'état disait pastille. La
bande de survol faisait donc 460 pt de haut, et le panneau s'ouvrait bien avant
que le pointeur atteigne le noir. Une animation de durée nulle supplante
désormais celle en vol, et chaque changement d'état porte une génération.

**La zone périmée.** Le rect d'une `NSTrackingArea` ne suit pas un
redimensionnement, et `layout()` n'est pas appelé pour un simple changement de
cadre. La zone est reconstruite sur `setFrameSize` et réaffirmée une fois le
cadre stabilisé.

**Le pointeur déjà à l'intérieur.** Une zone de suivi n'envoie aucun événement
d'entrée pour un pointeur déjà présent quand elle est créée. Au lancement, ou
après chaque repli, le panneau attendait le filet à 5 s. La zone signale
elle-même un pointeur déjà dedans.

**Le curseur, enfin.** `canBecomeKey` vaut `false` : AppKit ne consulte les
cursor rects que pour la fenêtre key, et une zone `.cursorUpdate` n'a jamais été
livrée (zéro appel en trace live). SwiftUI déclare ses zones dans `CursorZones`,
et `ClickThroughHostView` pose la main depuis `mouseMoved` — après la
réinitialisation d'AppKit pour le même événement, donc sans se battre.

**Critère de sortie — partiellement atteint le 2026-08-19.**

| Point | État |
|---|---|
| `perfcheck A` sous +10 % du plancher RFC-001 | **PASS** — `phys_footprint` 10,5 Mo contre 10,0 Mo de plancher, soit +5 % |
| **0 réveil quand la pastille est masquée** | **PASS** — 0,000 réveil inactif/s, 9,8 Mo, mode `--bench hidden` |
| Pastille affichée, sonde de survol active | **PASS** — 0,055 réveil/s brut, **0,000 net** après retrait de la sonde de mesure |
| Géométrie calculée sur la machine réelle | **PASS** — pastille centrée à ras de l'encoche (1137+32 = 1169), 2 pt de garde hors centre, aimants captant 0,02 / 0,48 / 0,97 et laissant 0,28 libre |
| Panneau se déploie au survol et se replie | **PASS** — vérifié à la main le 2026-08-19 |
| Clic dans la zone transparente atteint la barre de menus | **PASS** — vérifié à la main |
| Glissement et aimants | **PASS** — vérifié à la main |
| Scénario C — pastille affichée, survol actif | **PASS** — 10,7 Mo, 0,000 % CPU, **0,000 réveil inactif/s**, latence nulle |
| Écran externe branché puis débranché | **non vérifié** — demande du matériel |

**Défaut trouvé par le test manuel, corrigé.** Le clic traversait bien, **mais
déplaçait aussi la pastille**. Quand `ClickThroughHostView.hitTest` rend `nil`,
aucune *vue* ne prend l'événement — AppKit le remonte alors à la *fenêtre*,
c'est-à-dire au gestionnaire de glissement. Un clic dans une marge transparente
ouvrait donc le menu **et** armait un drag.

Correctif : `mouseDown` n'arme le glissement que si le point tombe dans
`host.absorbingRect`. La référence porte le même défaut — elle intercepte dans
`sendEvent(_:)` sur `.leftMouseDown` (`NotchWindow.swift:414-420`) sans jamais
tester la région de hit-test.

Le point restant n'est pas automatisable ici : `screencapture` exige
l'autorisation d'enregistrement d'écran, absente du terminal, et
`CGWarpMouseCursorPosition` déplace le curseur **sans émettre d'événement**, donc
ne simule pas un survol.

Le sondage à 1 Hz ne produit aucun réveil *inactif* : la marge de 25 % passée au
noyau le fait coalescer avec les timers déjà programmés par le système. C'était
l'hypothèse de conception du `WakeCoordinator`, elle est vérifiée — et elle tient
même à l'étage `.responsive`, qui ne coûte que 0,036 réveil inactif/s à 10 Hz.

**Ajout hors périmètre initial : animation d'ouverture.** La transition
pastille ↔ panneau était instantanée (`animate: false`). Elle est désormais en
`easeOut`, **0,26 s à l'ouverture contre 0,18 s à la fermeture**, les deux axes
ensemble : ouvrir est une demande de voir, qui mérite de se dérouler ; fermer est
un congé, qu'il ne faut pas faire traîner par-dessus la barre de menus.

Une version séquentielle — élargir puis descendre — a été essayée et abandonnée :
elle se lisait bien mais coûtait 0,34 s contre 0,26 s, et le panneau s'ouvre à
chaque survol.

**Un fondu parasite, trouvé à l'œil.** La croissance paraissait translucide. Deux
causes : le `body` basculait entre une vue `pill` et une vue `panel`, ce qui
change l'*identité* de la vue — SwiftUI en insérait une et en retirait une, avec
sa transition par défaut, un fondu ; et le panneau était rempli en
`.black.opacity(0.92)` là où la pastille est opaque. Corrigé par **une forme
unique**, toujours la même identité, dont seules les dimensions changent. Rien ne
s'estompe parce que rien n'est jamais inséré ni retiré.

**Le contenu suit le cadre, il ne le précède pas.** Les vues du panneau
apparaissent à **62 % de la croissance** (0,16 s sur 0,26), avec un fondu
explicite de 0,12 s ; au repli elles sont retirées **avant** que le cadre ne se
referme.

Les insérer au début était doublement faux. La forme fait encore 38 pt de haut,
donc une mise en page grandeur nature apparaissait dans une pastille et le cadre
la rattrapait ensuite. Et le fondu observé n'était pas voulu : c'était la
**transition d'insertion par défaut de SwiftUI**, dont je ne contrôlais ni le
moment ni la durée puisque je ne l'avais pas demandée.

L'asymétrie au repli est délibérée : laisser une mise en page déjà calculée se
faire écraser dans une pastille se lit comme un effondrement, pas comme une
fermeture.

Trois points de conception :

- **`easeOut`, pas `easeInOut`** — un départ en *ease-in* se lit comme de la
  latence, puisque le geste qui déclenche est déjà passé.
- **La région de hit-test saute immédiatement à sa valeur cible.** L'interpoler
  ferait sortir le pointeur du panneau en cours d'agrandissement, ce qui
  déclencherait un repli aussitôt : le panneau clignoterait au lieu de s'ouvrir.
- **`accessibilityDisplayShouldReduceMotion` est respecté.** Qui a demandé moins
  d'animation ne l'a pas demandé seulement dans les autres applications.

## 6. Open Questions

**Q1 — La pastille reste-t-elle visible sans session Claude ?**
La référence a `alwaysVisible = true` par défaut (`BuddyPreferences.swift:399`),
ce qui maintient un rendu permanent plus une boucle de « peek » toutes les 28-75 s
(`NotchContentView.swift:620`) qui rallume tout. Recommandation : défaut à
`false`, et en mode épinglé un rendu statique à 0 Hz.

**~~Q2 — `NSTrackingArea` peut-il remplacer le poll 10 Hz ?~~ TRANCHÉE (2026-08-19)**

**Oui. Et ma première réponse — « non, on sonde en deux étages » — était fausse,
démentie par l'usage puis par la mesure.**

Trois options ont été examinées :

- **`NSTrackingArea`** — suit la *fenêtre*, or celle-ci est bien plus large que la
  pastille qu'elle dessine. Il se déclencherait sur toutes les marges
  transparentes. C'est déjà la raison que documente `MouseMonitor.swift:9-14`.
- **`NSEvent.addGlobalMonitorForEvents(.mouseMoved)`** — événementiel, coût nul
  souris immobile. Mais il dépend d'une autorisation *Input Monitoring*, et
  RFC-011 a écarté toute API à autorisation pour le v1 : accepter une signature
  auto-signée n'a d'intérêt que s'il n'y a rien à révoquer. Vérifié au banc, les
  permissions apparaissent accordées **uniquement parce que le terminal les
  possède** et que le binaire de test en hérite ; une `.app` distribuée ne les
  aurait pas.
### Le système de slots, et le décalage qu'on oublie

La pastille est un `HStack` de trois slots : une oreille, le trou matériel, une
oreille. Le slot central est laissé **vide** — c'est un trou, tout ce qu'on y
dessine est invisible par construction.

**La pastille et l'encoche sont toutes deux centrées.** Le slot central ne
retombe donc sur le trou que si les deux oreilles ont exactement la même
largeur ; sinon il dérive de la moitié de l'écart. La correction est un décalage
de `(droite − gauche) / 2`, et elle est facile à oublier parce qu'elle est
**invisible dans le cas symétrique**.

Mesuré sur cette machine, le décalage n'est jamais nul :

| Cas | Gauche | Encoche | Droite | Total | Décalage |
|---|---|---|---|---|---|
| repos | 53 | 220 | 18 | 291 | **−17,5** |
| 2 sessions | 53 | 220 | 34 | 307 | **−9,5** |
| 10 sessions | 53 | 220 | 41 | 314 | **−6,0** |
| alerte | 53 | 220 | 109 | 382 | **+28,0** |

La première version posait chaque élément en `overlay` avec un décalage constant
depuis le centre de l'encoche. C'était faux dans les quatre cas, et chaque
overlay devait connaître la demi-largeur du trou et sa propre marge — deux
constantes qui n'avaient aucune raison de se connaître.

**Divergence assumée avec la référence : les largeurs sont mesurées, pas
déclarées.** Notch-Pilot code 56 pt pour son buddy et 84 pour sa consommation
(`NotchContentView.swift:292-293`). Ça tient jusqu'à ce qu'un buddy ait un visage
plus long ou qu'un manifeste change son corps de police, et le contenu déborde
alors d'un slot dimensionné pour autre chose. Ici chaque slot est mesuré via
`NSAttributedString`, donc un compteur qui passe de `×9` à `×10` gagne ses 7 pt
tout seul.

Le cadre de la fenêtre et le contenu tirent du **même** `PillLayout` : les
dimensionner séparément est exactement comme un slot finit rogné par une
pastille mesurée pour autre chose.

### Ce que j'avais mal jugé

J'ai écarté `NSTrackingArea` en affirmant qu'il suit la *fenêtre*, bien plus large
que la pastille, et se déclencherait donc sur les marges transparentes. **C'est
vrai de la seule variante qui suit `bounds`.** `NSTrackingArea(rect:)` prend un
rectangle explicite, et `absorbingRect` — déjà calculé pour le hit-test — est
exactement la région qui dessine. Le bon rectangle était là depuis le début.

Point non évident à conserver : **`.activeAlways` est indispensable**. L'app est
en `.accessory` et ne devient jamais active ; tout ce qui dépend de l'état actif
ne se déclencherait jamais.

### Le trajet des trois versions

| Version | Latence | Réveils inactifs/s | Verdict |
|---|---|---|---|
| Deux étages, 1 Hz → 10 Hz | jusqu'à **1 s** | 0,000 | rejetée à l'usage — le délai est la première chose qu'on remarque |
| 10 Hz constant | ~50 ms | **6,326** | rejetée à la mesure — 3× le budget |
| **`NSTrackingArea`, événementiel** | **0** | **0,000** | retenue |

### La mesure qui ne valait rien

Le scénario C initial donnait 0,036 réveil/s pour `.responsive`. Chiffre **faux** :
le banc enregistrait un client de cadence avec une closure **vide**. Il
chronométrait le timer, pas le travail. Le vrai coût n'est pas la fréquence,
c'est `NSEvent.mouseLocation` — que mon propre commentaire décrivait comme « une
lecture locale bon marché » alors que c'est un aller-retour au serveur de
fenêtres.

Leçon retenue dans le protocole de mesure : **un banc dont la closure ne fait rien
ne mesure rien.**

### Conséquence sur RFC-001

`Cadence.responsive` (0,1 s) a été **supprimée** : plus aucun consommateur, et
elle n'existait que pour être exclue du budget au repos. Toutes les cadences
sont de nouveau des cadences de repos, la plus fine est 1 Hz, et l'invariant
« < 2 réveils/s au repos » tient par construction, sans exception à documenter.

Le sondage subsiste derrière le suivi événementiel, à **5 s**, comme filet : un
curseur téléporté par un raccourci ou par `CGWarpMouseCursorPosition` n'émet
aucun événement d'entrée.

**Q3 — Que fait la fenêtre quand aucun écran n'a de notch ?**
Le README de la référence dit « fonctionne aussi sur les écrans non encochés ».
Position et hauteur de repli à définir.

## Notes d'implémentation

Pavés d'arbitrage déplacés depuis le code lors de la coupe des commentaires
(2026-08-20). Le code garde à leur place une ligne de renvoi vers cette section.

### `NotchPanel.suppressesHover` — une seule surface à la fois

La première version maintenait le panneau **ouvert** pendant que la fenêtre de
réglages était affichée, pour ne pas faire perdre le contexte à l'utilisateur.
C'était faux deux fois : le panneau est au niveau `.statusBar` (25) et une
fenêtre flottante à `.floating` (3), donc le panneau épinglé recouvrait
simplement les réglages qu'il venait d'ouvrir — et deux surfaces qui se disputent
le même écran valent moins qu'une seule.

Il se replie désormais. Une surface à la fois, et le survol reste inerte pour que
la pastille ne se redéploie pas sous la fenêtre de réglages.

### `NotchPanel.applyState` — la garde de mi-animation

`frame.size == carrier` n'est **pas** une raison de sauter le changement de
cadre. En cours d'animation la fenêtre passe momentanément par toutes les tailles
intermédiaires, dont celle vers laquelle on repart. Traiter ce cas comme « on y
est déjà » était le bug : un repli demandé pendant que l'ouverture grandissait
encore prenait le raccourci, l'ouverture continuait dessous, et la fenêtre
finissait à la taille panneau alors que l'état disait pastille. Les zones de
survol sont lues sur la fenêtre : une bande de 38 pt devenait une colonne de
460 pt, ce qui arme le panneau bien avant que le pointeur n'atteigne le noir — et
seulement après une première ouverture.

### `NotchPanel.canBecomeKey` — jamais key, jamais main

`.nonactivatingPanel` seul empêche l'app de s'activer au clic, mais le panneau
volerait quand même le statut *key* à l'éditeur ou au terminal en dessous — c'est
précisément ce que l'utilisateur est en train de regarder. Le prix : aucun
raccourci clavier ne peut fonctionner dans le panneau ; les boutons, si, puisque
les événements souris ne dépendent pas du statut key.

### `ClickThroughHostView.setFrameSize` — la séquence du rectangle périmé

Correctif de « le panneau s'ouvre avant que le pointeur ne l'atteigne, mais
seulement après l'avoir ouvert une fois ». Le rectangle confié à `NSTrackingArea`
est en coordonnées de vue et ne suit pas un redimensionnement ; `layout()` n'est
pas appelé pour un simple changement de cadre sur une vue qui ne pilote aucun
Auto Layout. La séquence était :

1. le panneau s'ouvre — région `.full`, suivi 560×460 ;
2. il se replie — `hitRegion` devient `.strip` **alors que la fenêtre fait encore
   460 de haut**, donc la bande est construite à 460 ;
3. la fenêtre rétrécit à 38, et rien ne reconstruit le rectangle.

Dès lors une colonne douze fois plus haute que la pastille armait le survol.
C'est le redimensionnement qui compte ici, donc c'est lui qui reconstruit.

### `HoverProbe` — pourquoi ce sondage existe encore

L'arbitrage complet (moniteur global vs `NSTrackingArea` vs sondage, les trois
versions et leurs mesures) est en §6, Q2. Résumé : le suivi événementiel de
`ClickThroughHostView` est le mécanisme ; ce sondage n'est plus qu'un filet, à
cadence `.idle`, pour les cas qu'une tracking area rate vraiment — un curseur
téléporté par un raccourci ou par `CGWarpMouseCursorPosition` n'émet aucun
événement d'entrée.

### `NotchShellView.pillContent` — trois slots, aucun décalage propre

Le détail chiffré est en §6, « Le système de slots, et le décalage qu'on oublie ».
Les slots sont posés en un seul `HStack` plutôt qu'en deux overlays décalés
indépendamment ; ils ne portent aucun décalage propre, c'est `body` qui positionne
la pastille entière, de sorte que la forme et son contenu bougent ensemble.

### `AppCoordinator` — le coordinateur tient le graphe, et sait s'arrêter

L'implémentation de référence injecte neuf objets directement dans une unique vue
SwiftUI (`AppDelegate.swift:5-15`), ce qui est la cause première de son fichier de
vue de 3 738 lignes. Ici le coordinateur tient le graphe et ne distribue à chaque
couche que ce dont elle a besoin.

Sa seconde fonction est celle que la référence n'assure jamais : **arrêter**.
Rien n'y appelle `stop()`, donc ses timers continuent de battre capot fermé. La
veille et le verrouillage de l'écran suspendent ici le `WakeCoordinator`, ce qui
démonte le timer partagé jusqu'à zéro.
