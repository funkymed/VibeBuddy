# VibeBuddy — Refonte UI premium SwiftUI

Tu travailles sur **VibeBuddy**, une application macOS native en **Swift / SwiftUI** qui vit dans le notch du MacBook et permet de suivre l'utilisation de claude-code dans le terminal.

Je veux refondre l'interface actuelle pour atteindre un niveau de finition **AAA / Apple-quality / top-tier**, sans changer la logique fonctionnelle existante.

## Direction artistique

La direction doit s'inspirer de la **première proposition de redesign validée** :

- interface macOS native premium
- dark UI profonde
- surfaces légèrement différenciées
- accent principal bleu électrique / cyan
- effets de glow et néon subtils mais bien présents
- bordures extrêmement subtiles
- hiérarchie typographique forte
- aspect technique mais élégant
- sensation de produit Apple / outil développeur haut de gamme
- pas d'esthétique gaming
- pas de cyberpunk excessif
- pas de gradients agressifs
- pas de gros éléments décoratifs

### IMPORTANT : VibeBuddy

Le petit Buddy en haut à gauche est un élément identitaire majeur.

**Conserver exactement le Buddy / sprite existant.**

Ne pas le remplacer par une grosse tête de robot, un avatar 3D, une illustration ou un nouveau personnage.

Le Buddy doit rester petit, pixel-art, inspiré d'EVE dans WALL-E, avec ses différentes expressions selon l'état de l'application.

Il doit être traité comme un élément d'interface vivant, pas comme un hero/header.

Le Buddy peut être la principale source de lumière visuelle de l'interface grâce à un **halo/glow très subtil** qui varie selon son état.

---

# 1. Créer un mini Design System SwiftUI

Avant de modifier les vues, créer une couche de tokens UI centralisée.

Par exemple :

```swift
enum VibeTheme {
    enum Colors { ... }
    enum Typography { ... }
    enum Spacing { ... }
    enum Radius { ... }
    enum Border { ... }
    enum Glow { ... }
    enum Shadow { ... }
}
```

Le nom exact peut être adapté à l'architecture existante.

L'objectif est de ne plus avoir de valeurs arbitraires dispersées dans les Views.

Le Design System doit centraliser les couleurs, espacements, rayons, typographies, bordures et effets lumineux.

---

# 2. Palette de couleurs

**IMPORTANT : ne pas produire une interface monochrome.**

Les couleurs font partie intégrante de l'identité de VibeBuddy.

### Base

```text
background       #050608
surface          #0A0C10
surfaceElevated  #10141A
interactive      #181D24
```

Les bordures doivent être réalisées avec des blancs très faibles, environ 8–12% d'opacité.

### Identité VibeBuddy

```text
accentBlue       #00A8FF
accentCyan       #38C7FF
accentBlueDeep   #0077FF
```

Le bleu/cyan est la couleur principale de VibeBuddy.

### États

```text
working          #55FF55
finished         #FF9D2E
failed           #FF3B45
highPriority     #C84CFF
awaiting         #00BBFF
sleeping         #00BBFF
```

Les couleurs d'état doivent être utilisées de manière cohérente dans :

- status dot
- badges
- progress rings
- accents
- Buddy glow
- boutons ou contrôles lorsque pertinent

Ne pas créer de nouvelles couleurs arbitraires dans chaque composant.

---

# 3. Système de glow / néon

Le glow est une partie réelle du Design System.

Il doit être **subtil, premium et maîtrisé**.

L'objectif est de donner l'impression que certains éléments émettent une lumière, et non de transformer l'application en interface cyberpunk.

Créer plusieurs niveaux :

### Glow faible

Pour les éléments actifs secondaires :

- environ 8–12% d'opacité
- rayon large
- très peu visible

### Glow moyen

Pour :

- bouton actif
- progress ring actif
- Buddy

Environ 15–25% d'opacité.

### Glow fort

Réservé aux moments importants :

- changement d'état du Buddy
- permission en attente
- action principale

Environ 20–30% maximum.

Éviter le glow permanent sur tous les composants.

### Exemple conceptuel

Un bouton actif bleu doit donner quelque chose proche de :

```text
border        #00A8FF
background    #00A8FF à 6–10%
inner glow    #00A8FF à ~15%
outer glow    #00A8FF à ~10%
```

Le glow doit être obtenu avec les APIs SwiftUI/Core Graphics adaptées (`shadow`, overlays, gradients très subtils si nécessaire), sans introduire une dépendance inutile.

---

# 4. Buddy et lumière ambiante

Le Buddy original doit rester exactement le sprite actuel.

Ajouter éventuellement un halo très discret autour de lui :

```text
idle       → orange
working    → vert
awaiting   → cyan
finished   → cyan
failed     → rouge
sleeping   → bleu
```

Le halo doit être suffisamment discret pour ne jamais masquer le pixel-art.

L'idée est que le Buddy semble **vivant et lumineux**, comme une petite créature technologique.

Le reste de l'interface peut reprendre légèrement cette couleur d'état lorsqu'elle est pertinente.

---

# 5. Spacing

Créer une échelle cohérente :

```text
4
6
8
12
16
20
24
32
```

Éviter les valeurs arbitraires comme 13, 17, 23 sauf nécessité visuelle.

---

# 6. Radius

Utiliser quelques rayons cohérents :

```text
small   6
medium  10
large   14
pill    999
```

---

# 7. Typography

Créer une hiérarchie claire :

- section title
- screen title
- card title
- body
- secondary
- caption
- badge

Utiliser les polices système macOS / SF Pro lorsque possible.

Pour les informations techniques comme :

- chemin de projet
- durée
- version
- nom de session
- informations claude-code

une typographie monospaced peut être utilisée ponctuellement.

Ne pas transformer toute l'interface en terminal.

---

# 8. Structure générale

Repenser l'écran comme une hiérarchie visuelle claire :

```text
┌──────────────────────────────────────────────┐
│ Buddy                 0 / 2       settings ⏻ │
│                                              │
│ VibeBuddy  v0.1.0                            │
│                                              │
│ ──────────────────────────────────────────── │
│                                              │
│ AUTORISATION                                 │
│ AskUserQuestion   notch                      │
│                                              │
│ question                                     │
│                                              │
│ ┌──────────────────────────────────────────┐ │
│ │ Garder la mesure                      →  │ │
│ └──────────────────────────────────────────┘ │
│                                              │
│ ┌──────────────────────────────────────────┐ │
│ │ Mesurer d'abord son coût               › │ │
│ └──────────────────────────────────────────┘ │
│                                              │
│ ┌──────────────────────────────────────────┐ │
│ │ Calculer à la main...                  › │ │
│ └──────────────────────────────────────────┘ │
│                                              │
│ Votre choix est renvoyé à Claude...          │
│                                              │
│ Refuser                 Répondre terminal    │
│                                              │
│ SESSIONS  2                                  │
│                                              │
│ ┌──────────────────────────────────────────┐ │
│ │ ● notch   high   terminé       73%      │ │
│ │   opus 5   depuis 6h46                  │ │
│ │   ~/Sites/notch                         │ │
│ └──────────────────────────────────────────┘ │
│                                              │
│ CONSOMMATION                                 │
│ session  ●●○○○○○○○○  18%                   │
│ semaine  ●●○○○○○○○○  20%                   │
└──────────────────────────────────────────────┘
```

Cette structure est indicative.

Conserver les données et comportements actuels.

---

# 9. Header

Le header doit être premium et discret.

À gauche :

**Buddy original**

À droite :

- compteur de permissions / questions
- bouton settings
- bouton power

Les éléments doivent être visuellement secondaires.

Utiliser des SF Symbols lorsque pertinent :

- `slider.horizontal.3`
- `power`
- éventuellement `gearshape`

Les icônes doivent être fines, discrètes et parfaitement alignées.

Le compteur `0 / 2` doit ressembler à un petit status pill.

---

# 10. Header VibeBuddy

Le bloc :

`VibeBuddy v0.1.0`

doit devenir une vraie identité de produit.

Créer une surface légèrement différente du background :

- background légèrement plus clair
- radius 12 environ
- border très subtile
- padding généreux
- VibeBuddy en blanc
- version en bleu/cyan

Une très légère coloration bleue peut apparaître dans la surface ou la bordure.

Pas de gros gradient.

---

# 11. Section Autorisation

La section d'autorisation est l'élément le plus important lorsque claude-code attend une réponse.

Créer une hiérarchie claire.

### Section

`AUTORISATION`

Petit label uppercase, tracking légèrement augmenté, couleur accent lorsque la permission est active.

### Question

Afficher :

`AskUserQuestion`

avec `notch` comme information secondaire.

### Description

Améliorer :

- line height
- largeur de ligne
- contraste
- spacing

Éviter que le texte paraisse comprimé.

---

# 12. Actions d'autorisation

Les trois réponses doivent être de vrais composants réutilisables.

Créer par exemple :

```swift
VibeActionButton(...)
```

États :

- normal
- hover
- pressed
- focused
- disabled

La première action sélectionnée / principale doit être visuellement dominante.

Utiliser :

- border accent
- background accent à faible opacité
- très léger inner glow
- très léger outer glow
- chevron à droite

Les deux autres restent plus neutres.

Le bouton doit être sobre mais clairement interactif.

---

# 13. Boutons du bas

`Refuser`

doit rester clairement rouge mais élégant.

`Répondre dans le terminal`

doit être l'action principale secondaire, avec l'accent bleu VibeBuddy.

Les deux boutons doivent avoir exactement la même hauteur et un alignement parfait.

Créer un composant commun plutôt que deux implémentations différentes.

---

# 14. Mode normal

Lorsque aucune question n'est active, l'écran doit naturellement réorganiser son espace.

La section :

`SESSIONS`

devient le contenu principal.

Il ne doit pas rester un énorme espace vide correspondant à l'autorisation.

Le layout doit être adaptatif.

Le même Design System doit être utilisé dans les deux modes :

1. mode normal
2. mode autorisation

---

# 15. Session Card

Transformer chaque session en composant réutilisable :

```swift
VibeSessionCard(...)
```

Structure :

### Ligne principale

```text
●  notch     high     terminé              73%
```

Le status doit être immédiatement identifiable.

### Informations secondaires

```text
opus 5    depuis 6h46
```

### Projet

```text
/Users/.../Sites/notch
```

Le chemin doit être plus discret et éventuellement utiliser une police monospaced.

### Progression

Le pourcentage doit être accompagné d'un anneau de progression discret.

L'anneau doit utiliser la couleur de l'état lorsque pertinent et rester fin.

---

# 16. Status system

Les états doivent avoir une sémantique cohérente :

### Running

Accent bleu / cyan.

### Completed

Orange.

### Error

Rouge.

### Waiting / Permission

Bleu ou cyan.

### Idle

Gris neutre.

Le status dot, badge, progress indicator et Buddy glow doivent utiliser la même sémantique.

---

# 17. Badges

Créer un composant :

```swift
VibeBadge(...)
```

pour :

- `high`
- `terminé`
- `erreur`
- `auto`
- `default`

Les badges doivent être petits :

- faible opacité de background
- texte coloré
- radius pill
- padding horizontal faible

Ils ne doivent jamais attirer plus l'attention que le nom de la session.

---

# 18. Consommation

Créer :

```swift
VibeUsageMeter(...)
```

Pour :

```text
session
semaine
```

Conserver les petits cercles de consommation car ils donnent une identité visuelle intéressante.

Mais :

- alignement parfait
- spacing régulier
- taille légèrement réduite
- progression très lisible
- pourcentage aligné
- timestamp secondaire

Exemple :

```text
session    ● ● ○ ○ ○ ○ ○ ○ ○ ○    18%   ↻ 20:49
semaine    ● ● ○ ○ ○ ○ ○ ○ ○ ○    20%   ↻ 23 août, 21:59
```

La partie active peut utiliser la couleur d'accent ou d'état.

---

# 19. Background et profondeur

Le background doit être presque noir mais ne pas être `Color.black` partout.

Utiliser plusieurs niveaux :

```text
Background
   ↓
Surface
   ↓
Surface Elevated
   ↓
Interactive
```

Chaque niveau doit avoir une différence extrêmement subtile.

Le but est d'obtenir de la profondeur sans une succession artificielle de rectangles.

Les borders doivent être très discrètes.

---

# 20. Règle visuelle importante

L'interface doit respecter cette hiérarchie :

```text
Buddy / état
     ↓
information principale
     ↓
action
     ↓
information secondaire
```

Les couleurs et le glow doivent guider l'œil, pas décorer.

Utiliser le bleu VibeBuddy pour les éléments actifs.

Utiliser les couleurs d'état uniquement lorsqu'elles transmettent une information.

Ne jamais appliquer simultanément plusieurs gros glows de couleurs différentes.

---

# 21. Animations

Ajouter de petites animations SwiftUI lorsque cela apporte quelque chose :

- changement d'état du Buddy
- apparition d'une session
- changement de progression
- activation d'une permission
- hover des boutons
- changement de status

Utiliser des animations courtes et naturelles.

Pas d'animations permanentes ou distrayantes.

Le Buddy peut avoir les animations les plus expressives.

Le glow peut légèrement respirer lors d'un état actif, mais de manière extrêmement subtile.

---

# 22. Contraintes spécifiques au notch

C'est une application qui vit dans le notch du MacBook.

Le design doit donc être pensé pour un espace extrêmement compact.

Ne jamais considérer l'écran comme une fenêtre desktop classique.

Priorités :

1. information importante immédiatement visible
2. densité maîtrisée
3. excellente lisibilité
4. interactions accessibles
5. pas de décoration inutile

Les composants doivent supporter différentes hauteurs de fenêtre.

Éviter les tailles fixes qui cassent lorsque le contenu varie.

Utiliser autant que possible :

- `LayoutPriority`
- `ScrollView`
- `ViewThatFits`
- contraintes adaptatives

Éviter les coordonnées hardcodées.

---

# 23. Architecture SwiftUI

Ne pas mélanger :

- données
- logique métier
- design
- composants UI

Créer une séparation claire.

Par exemple :

```text
VibeBuddy
├── DesignSystem
│   ├── VibeTheme
│   ├── VibeColors
│   ├── VibeTypography
│   ├── VibeSpacing
│   ├── VibeGlow
│   ├── VibeButton
│   ├── VibeBadge
│   ├── VibeCard
│   ├── VibeProgressRing
│   └── VibeUsageMeter
│
├── Components
│   ├── BuddyView
│   ├── HeaderView
│   ├── AuthorizationView
│   ├── SessionCard
│   └── ConsumptionView
│
└── Screens
    └── DashboardView
```

Adapter cette structure à l'architecture existante plutôt que de déplacer inutilement tout le projet.

---

# 24. Ne pas casser le fonctionnel

Avant toute modification :

- comprendre l'architecture actuelle
- identifier les Views existantes
- identifier les models
- identifier les ViewModels
- identifier les actions existantes
- identifier les états du Buddy
- identifier les interactions avec claude-code / terminal

**Ne pas modifier la logique métier.**

**Ne pas modifier les APIs.**

**Ne pas modifier les modèles de données sauf nécessité absolue.**

**Ne pas réécrire le fonctionnement du Buddy.**

Le travail demandé est avant tout une refonte UI/UX et une structuration du Design System.

Si une modification fonctionnelle semble nécessaire, la signaler avant de la faire.

---

# 25. Niveau de finition attendu

Je veux un résultat comparable à une application macOS moderne extrêmement soignée.

Chaque détail compte :

- alignements
- baseline typography
- padding
- contrastes
- proportions
- radius
- transitions
- hover
- états actifs
- densité
- hiérarchie
- couleurs
- lumière
- glow

Ne pas simplement "mettre des couleurs et des borders".

Le résultat doit donner l'impression que **le design a été pensé comme un système complet**.

L'interface doit être :

**minimaliste + technique + chaleureuse + lumineuse + premium.**

VibeBuddy doit donner l'impression d'être un petit compagnon vivant qui observe claude-code travailler en arrière-plan.

Le Buddy apporte la personnalité.

La couleur et le glow apportent la vie.

L'interface apporte la précision.

---

# 26. Méthode de travail

Avant de modifier massivement le code :

1. analyser le code existant
2. identifier les composants actuels
3. proposer le mapping entre composants existants et nouveaux composants
4. mettre en place les tokens du Design System
5. implémenter la palette de couleurs
6. implémenter le système de glow
7. refactorer progressivement les composants UI
8. vérifier le mode normal
9. vérifier le mode autorisation
10. vérifier les différents états du Buddy
11. vérifier les tailles de fenêtre du notch
12. supprimer les valeurs UI hardcodées devenues inutiles

Ne pas faire une réécriture complète si le code existant peut être amélioré progressivement.

Le résultat final doit rester maintenable.

## Critère final

Quand je regarde VibeBuddy, je dois avoir immédiatement la sensation :

> "C'est un petit produit Apple premium pour développeurs."

et non :

> "C'est un dashboard web mis dans une fenêtre macOS."

Le Buddy original reste la mascotte et le point de personnalité principal.

**Important : les couleurs, les états lumineux et le glow font partie du produit. Ne pas les supprimer ou les réduire à quelques textes colorés.**
