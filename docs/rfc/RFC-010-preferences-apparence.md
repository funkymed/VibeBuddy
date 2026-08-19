# RFC-010 — Préférences, apparence et surfaces expressives

| | |
|---|---|
| **Status** | todo (0 %) |
| **Author** | Cyril Pereira |
| **Created** | 2026-08-19 |
| **Updated** | 2026-08-19 |
| **Phase** | 5 — Confort |
| **Depends on** | RFC-001 |
| **Related** | D2 · consommée par RFC-002, RFC-005 et RFC-012 |
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

## 2. Goals / Non-goals

**Goals.** Un modèle de préférences typé, **scindé en trois surfaces
d'invalidation distinctes**, avec migrations. L'UI de réglages. Les annonces
vocales et le retour haptique, comme *rendus* d'alerte.

**Déplacé en RFC-012.** La détection d'état et la politique d'alerte — quand
alerter, sur quel événement, avec quelle déduplication — ne sont plus ici. C'est
l'objectif n°1 du produit, pas un réglage à côté du choix de la couleur du buddy.
Cette RFC ne garde que les *préférences* d'alerte (activer/désactiver par
événement) et les surfaces de rendu qu'elle pilote.

**Non-goals.** La géométrie de fenêtre (RFC-002 consomme `LayoutPrefs`). Le rendu
du buddy (RFC-005 consomme `AppearancePrefs`).

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

## 5. Action plan

| # | Tâche | Statut | % |
|---|---|---|---|
| T1 | Les trois modèles `@Observable` + `PreferencesStore` | todo | 0 |
| T2 | Écritures coalescées (vérifier : aucune écriture par frame de drag) | todo | 0 |
| T3 | Cadre de migration généralisé | todo | 0 |
| T4 | `applyStartAtLogin` + réconciliation au premier lancement | todo | 0 |
| T5 | `SettingsView` + sous-vues (< 200 l. chacune) | todo | 0 |
| T6 | `SpeechPresenter` + pop-out de fin de session + dédup à la minute | todo | 0 |
| T7 | `VoiceAnnouncer` paresseux + debounce | todo | 0 |
| T8 | Retour haptique | todo | 0 |

**Critère de sortie.** Une session qui se termine déclenche **exactement une**
notification — pas deux, pas zéro — sur dix essais. Un drag complet de la
fenêtre ne produit **aucune** écriture `UserDefaults` avant le relâchement.
Changer la couleur du buddy ne provoque **aucun** recalcul de frame de fenêtre.

## 6. Open Questions

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
