# RFC-017 — Installer le hook depuis les réglages

| | |
|---|---|
| **Status** | **in-progress (90 %)** — validée et codée le 2026-09-26, épreuve réelle passée ; reste la mesure (T8) |
| **Author** | Cyril Pereira |
| **Created** | 2026-09-26 |
| **Updated** | 2026-09-26 |
| **Phase** | 5 — Confort |
| **Depends on** | RFC-006 (`HookInstaller`, `ClaudeSettingsWriter`), RFC-007 (interception), RFC-010 (réglages) |
| **Related** | D6 (un seul écrivain de `settings.json`), R1, R7 |
| **Blocks** | — |

## 1. Context & Problem

L'interception des permissions — les six cas prouvés en réel le 2026-08-25 — ne
marche que si `vibe-hook` est déclaré dans `~/.claude/settings.json`. **Aujourd'hui,
rien dans l'app ne le fait ni ne le dit.**

Constaté le 2026-09-26 : une demande de permission sur podcaster n'apparaissait
pas dans la notch. L'app tournait, le socket existait
(`~/.vibebuddy/buddy.sock`), et `settings.json` ne déclarait qu'un hook,
`PreToolUse: rtk hook claude`. La sauvegarde du 2026-09-22 n'en contenait pas
davantage. Le développeur du produit lui-même n'avait pas le hook.

Ce qui existe :

| Élément | Où | Ce qu'il fait |
|---|---|---|
| `HookInstaller` | `Sources/VibeBuddyKit/Hook/HookInstaller.swift` | `install()`, `uninstall()`, `preview(_:)`, idempotent, nettoie les entrées obsolètes |
| `ClaudeSettingsWriter` | Kit | relecture avant mutation, sauvegarde horodatée, `replaceItemAt`, ordre préservé (D6) |
| `TextDiff.unified` | Kit | le diff que la CLI affiche |
| `--install-hook` | `Sources/VibeBuddy/main.swift:10`, `HookInstallCommand.swift` | seul chemin d'installation, **en terminal** |
| README l. 89-91 | | ne cite que `make install-hook` — une commande de développeur |

Donc :

1. **Un utilisateur installé par `brew install --cask` n'a aucun chemin documenté.**
   La commande qui marche pour lui —
   `/Applications/VibeBuddy.app/Contents/MacOS/VibeBuddy --install-hook` — n'est
   écrite nulle part.
2. **L'échec est silencieux.** Sans hook, l'app a l'air de fonctionner : alertes,
   usage et sessions passent par les transcripts. Seuls les panneaux de permission
   ne viennent jamais. Personne ne relie l'absence d'un panneau à une ligne
   manquante dans un fichier de configuration.
3. **La désinstallation laisse un hook orphelin.** `brew uninstall` retire l'app ;
   le `zap` du cask (`scripts/make-cask.sh:56`) ne touche pas `settings.json`. Claude
   Code continue d'appeler un `vibe-hook` qui n'existe plus, à chaque appel d'outil.
   L'effet exact côté Claude Code n'est pas mesuré (Q3).

## 2. Goals / Non-goals

### Goals

- **G1 — Voir l'état.** Les réglages disent si le hook est installé, absent, ou
  installé vers un chemin qui n'est pas celui de l'app qui tourne (app déplacée,
  build de dev).
- **G2 — Installer en un geste, avec consentement.** Un bouton montre le diff exact
  de `settings.json` et n'écrit qu'après confirmation. Toute écriture passe par
  `ClaudeSettingsWriter` (D6).
- **G3 — Désinstaller pareil.** Même diff, même confirmation, même écrivain.
- **G4 — Réparer.** Un hook qui pointe ailleurs se corrige par le même bouton :
  `HookInstaller.installing` remplace déjà l'entrée en place.
- **G5 — Signaler, une fois.** Quand une session vivante existe et que le hook est
  absent, l'app le dit une fois, sans bloquer.

### Non-goals

- **Installer sans demander.** Jamais : c'est la décision de RFC-006 et la parade R1.
  Écrire dans la configuration de l'outil de l'utilisateur sans son accord est ce
  que ce projet refuse depuis le premier jour.
- **Surveiller `settings.json` en continu.** Pas de veilleur FSEvents de plus : l'état
  se relit à l'ouverture de la section et au retour au premier plan, comme
  `PermissionsSection` le fait déjà pour TCC. Coût au repos : zéro.
- **Toucher aux réglages de projet** (`.claude/settings.json`, `settings.local.json`).
  Seul le fichier utilisateur est concerné.
- **Changer `permissions.defaultMode`.** Le mode `auto` fait taire toute demande
  (`docs/hook.md`, épreuve du 2026-08-21) ; on peut le **signaler** (Q4), jamais le
  modifier.

## 3. Proposed Solution

### 3.1 L'état, calculé dans le Kit

```swift
public enum HookInstallState: Equatable, Sendable {
    case installed                 // toutes les entrées, vers notre chemin
    case missing                   // aucune entrée à nous
    case stale(path: String)       // entrées à nous, vers un autre chemin
    case partial                   // certains événements seulement
    case unreadable(String)        // fichier illisible : on n'écrit rien
}
```

`HookInstaller.state(of: OrderedJSON) -> HookInstallState` : une fonction pure,
testable sans disque, qui compare le fichier à `installing(_:hookPath:)`. Si
`preview(before) == before`, c'est `installed` — la même définition que la CLI
(« Déjà installé, rien à écrire »).

### 3.2 La section des réglages

Dans **Permissions** (`Sources/VibeBuddy/Settings/Sections/PermissionsSection.swift`),
un second groupe « Claude Code », sous les permissions macOS : c'est le même genre
de question — « qu'est-ce qui doit être autorisé pour que l'app marche ? » — et la
même mécanique de relecture au retour au premier plan.

| État | Badge | Bouton |
|---|---|---|
| `installed` | vert « Installé » | « Retirer… » |
| `missing` | orange « Absent » | « Installer… » |
| `stale` | orange « À réparer » + le chemin | « Réparer… » |
| `partial` | orange « Incomplet » | « Réparer… » |
| `unreadable` | rouge « Illisible » + la raison | aucun |

La lecture se fait **hors du fil principal** (`Task.detached`), comme
`PermissionsSection.reload` : la leçon du gel en release (`docs/hook.md`, « Un gel
qui n'arrive qu'en release ») vaut pour toute E/S dans une vue de réglages.

### 3.3 Le consentement

Le bouton ouvre une feuille :

- le chemin du fichier ;
- le diff unifié (`TextDiff.unified`), en monospace, scrollable ;
- le dossier où la sauvegarde sera prise ;
- « Annuler » par défaut, « Écrire » en action.

À la confirmation : `install()` ou `uninstall()`, puis relecture de l'état. En cas
d'échec, le message d'erreur s'affiche dans la feuille et rien n'est écrit — le
comportement de `ClaudeSettingsWriter` sur un fichier illisible.

**Le diff est recalculé au moment d'écrire, pas réutilisé.** Si le fichier a changé
entre l'ouverture de la feuille et le clic, on n'écrit pas ce que l'utilisateur n'a
pas vu : on réaffiche le nouveau diff.

### 3.4 L'avis unique (G5)

Quand une première session devient vivante et que l'état demande un clic
(`missing`, `stale` ou `partial`), une puce « Permissions non reliées » s'affiche sur
la ligne d'identité du panneau, à côté de celle de mise à jour. Un clic ouvre
Réglages › Autorisations. Elle disparaît pour de bon dès que l'utilisateur l'a
cliquée **ou** qu'il a installé ou retiré le hook depuis les réglages : dans les deux
cas, il sait (`HookNotice.seenKey`, remis à zéro par « Réinitialiser tous les
réglages »). Aucune horloge nouvelle : l'état se relit au lancement, au passage de
zéro à une session vivante, et après une écriture des réglages (D3).

*Écart avec la première version de la fiche* : elle remettait l'avis à zéro quand
l'utilisateur retirait lui-même le hook. C'était le contraire du but — qui retire
le hook sait qu'il le retire.

### 3.5 Documentation

- README : remplacer `make install-hook` par « Réglages › Permissions » pour
  l'utilisateur, et garder la commande pour le développeur.
- Cask : un `caveats` qui rappelle de retirer le hook depuis les réglages avant
  `brew uninstall` (Q3).

## 4. Alternatives Considered

| Alternative | Pourquoi non |
|---|---|
| **Installer automatiquement au premier lancement** | Écrit dans la config d'un autre outil sans consentement. Contraire à R1 et à RFC-006. |
| **Documenter la commande seulement** | Ne résout pas l'échec silencieux (point 2) : personne ne va chercher une doc pour une fonction dont il ignore qu'elle manque. |
| **Case à cocher sans diff** | Moins de friction, mais l'utilisateur ne voit pas ce qu'on écrit dans un fichier de 25 clés écrit à la main. Le diff existe déjà ; le montrer ne coûte rien. |
| **Veilleur FSEvents sur `settings.json`** | Un réveil de plus pour un état qui change quelques fois dans la vie de l'app. La relecture à l'ouverture suffit. |
| **Désinstaller le hook depuis le cask (`uninstall script:`)** | Le cask lancerait le binaire de l'app qu'il est en train de retirer, sans confirmation possible. À réévaluer après mesure de Q3. |

## 5. Action plan

| # | Tâche | Statut | % |
|---|---|---|---|
| T1 | `HookInstallState` + `HookInstaller.state(of:)`, `inspect()`, `pendingDiff(removing:)`, `HookNotice` — `Sources/VibeBuddyKit/Hook/HookInstallState.swift`, 9 tests dans `HookInstallStateTests` | done | 100 |
| T2 | Groupe « Claude Code » dans `PermissionsSection` : badge, bouton, lecture hors du fil principal — `Settings/Sections/HookSettingsGroup.swift` | done | 100 |
| T3 | Feuille de consentement : diff, sauvegarde, écriture, erreur, diff recalculé avant d'écrire — `Settings/Sections/HookConsentSheet.swift` | done | 100 |
| T4 | Chaînes FR/EN dans `SettingsStrings` et `Strings` | done | 100 |
| T5 | Puce unique à la première session vivante sans hook (G5) — `PanelNotices`, `PanelNoticeChip` dans `DeployedPanel.swift`, câblage dans `AppCoordinator` | done | 100 |
| T6 | README + `caveats` du cask (`scripts/make-cask.sh`) | done | 100 |
| T7 | Épreuve réelle : installer, faire demander un `Bash` à un vrai Claude Code, décider depuis la notch ; retirer, vérifier que Claude Code demande de nouveau dans le terminal | done — installation et décision depuis la notch confirmées par l'utilisateur le 2026-09-26 ; le retrait n'a pas été rapporté | 100 |
| T8 | `make perf` scénario A : la section ne doit rien coûter au repos | todo | 0 |

**Charge estimée : 1-1,5 j.** Le Kit porte déjà l'essentiel ; le travail est dans
la vue et la feuille.

**Critère de sortie :** depuis une installation brew fraîche, sans terminal, un
utilisateur installe le hook, voit une demande de permission dans la notch, puis le
retire, et `settings.json` redevient identique octet pour octet à l'original.

## 6. Open Questions

| # | Question | Proposition |
|---|---|---|
| Q1 | Section **Permissions** ou section **Général** ? | **Tranchée : Permissions.** |
| Q2 | L'avis unique (G5) : dans le panneau, ou une notification système ? | **Tranchée : dans le panneau**, en puce sur la ligne d'identité. |
| Q3 | Que fait Claude Code quand `vibe-hook` n'existe plus ? Message d'erreur à chaque outil, ou silence ? | **Ouverte.** En attendant la mesure : `caveats` dans le cask, pas de `uninstall script:`. |
| Q4 | Signaler `defaultMode: "auto"`, qui rend le hook inutile ? | **Tranchée : oui**, en texte orange sous le badge quand le hook est installé, sans bouton. |
| Q5 | Garder `--install-hook` en CLI ? | **Tranchée : oui.** |

Mesurer Q3 :

```sh
# Pointer le hook vers un chemin absent, sur un fichier de réglages jetable
./.build/release/VibeBuddy --install-hook --settings /tmp/rfc017-settings.json --yes
# puis éditer le chemin vers /nonexistent/vibe-hook et lancer
claude --settings /tmp/rfc017-settings.json --include-hook-events
```
