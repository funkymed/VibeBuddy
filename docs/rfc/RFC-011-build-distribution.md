# RFC-011 — Build, empaquetage, signature et distribution

| | |
|---|---|
| **Status** | todo (0 %) |
| **Author** | Cyril Pereira |
| **Created** | 2026-08-19 |
| **Updated** | 2026-08-19 |
| **Phase** | 6 — Livraison |
| **Depends on** | RFC-006 (nom de la seconde cible) |
| **Related** | R7 · décision « auto-signé, zéro API Accessibilité » |
| **Blocks** | — |

## 1. Context & Problem

Tant que le projet se lance par `swift run`, il n'existe pas vraiment. Il faut un
`.app` qu'on installe une fois et qu'on oublie.

Le problème est la signature. Apple exige une identité stable pour deux raisons
distinctes : Gatekeeper (l'utilisateur peut-il ouvrir l'app ?) et la persistance
des autorisations (l'app garde-t-elle ses permissions d'une version à l'autre ?).
La référence documente le second point sans détour en `GlobalHotkeys.swift:35-37` :
**la signature ad-hoc change l'identité à chaque build, donc l'autorisation
Accessibilité est révoquée à chaque mise à jour**.

État de la référence : `scripts/build.sh:108-137` fabrique un certificat
auto-signé à CN stable via `openssl`, **avec un repli en signature ad-hoc
ligne 135**. Aucune notarisation (vérifié : `notary` absent de `build.sh` et de
`make-dmg.sh`). Et le cask contourne le problème en désactivant la protection de
l'OS à la place de l'utilisateur : `xattr -dr com.apple.quarantine` en postflight
(`release.yml:124-126`).

**Décision prise pour ce projet : auto-signé à CN stable, sans compte Apple.** La
contrepartie est assumée — friction Gatekeeper au premier lancement — et la
conséquence la plus douloureuse est neutralisée en amont : **notch-buddy
n'utilise aucune API exigeant l'Accessibilité en v1** (ni raccourcis globaux, ni
détection plein-écran par AX, cf. RFC-002). Sans permission à révoquer, la
faiblesse de l'auto-signature ne coûte plus rien à l'usage.

## 2. Goals / Non-goals

**Goals.** `build.sh` (universel avec repli mono-arch), génération d'icône,
`Info.plist`, signature à identité stable, DMG, workflow de release, cask Homebrew.

**Non-goals.**
- **La notarisation.** Rouvrable le jour où un compte Apple est pris (Q3).
- **L'auto-update in-app.** `UpdateChecker.swift` (372 l.) télécharge, monte,
  recopie dans `/Applications`, **se re-signe** (`:255-272`) et se relance via un
  script shell (`:278-305`). Une app qui se réécrit et se re-signe elle-même est
  un vecteur d'auto-compromission disproportionné pour un utilitaire de notch.
  Homebrew fait ce travail mieux. On garde au plus un contrôle de version passif
  avec un lien.

## 3. Proposed Solution

| Livrable | Base |
|---|---|
| `scripts/build.sh` | `Notch-Pilot/scripts/build.sh` |
| `scripts/make-dmg.sh` | `Notch-Pilot/scripts/make-dmg.sh` (`hdiutil` seul) |
| `scripts/generate-icon.swift` | `Notch-Pilot/scripts/generate-icon.swift` |
| `.github/workflows/release.yml` | `Notch-Pilot/.github/workflows/release.yml` |

**Repris tel quel :**

| Brique | `fichier:ligne` | Pourquoi |
|---|---|---|
| Build universel + repli mono-arch | `build.sh:31-44` | `--arch arm64 --arch x86_64` exige Xcode complet ; les Command Line Tools seuls échouent. |
| Icône décrite en Swift → `iconutil` | `build.sh:58-67` | Aucun binaire d'asset en dépôt. |
| `Info.plist` : `LSUIElement`, `LSMinimumSystemVersion 14.0` | `build.sh:69-106` | |
| `NSSupportsAutomaticGraphicsSwitching` | `build.sh:102` | Compte directement dans le budget énergie. |
| Certificat auto-signé à CN stable | `build.sh:108-137` | Cf. le commentaire `:108-111`. |
| `security set-key-partition-list` | `build.sh:128`, `release.yml:52-53` | Permet de signer sans invite en CI. |
| DMG via `hdiutil` seul | `make-dmg.sh:38-45` | |
| `git add` avant `git diff --cached` dans le bump du cask | `release.yml:140-147` | Sans lui, le tout premier cask est invisible pour `git diff`. |

**Modifié :**
- **Suppression du repli ad-hoc** (`build.sh:135`). Le repli *est* le bug : il
  transforme un échec de signature en build silencieusement dégradé. Le
  certificat à CN stable est stocké hors dépôt et réutilisé ; si la signature
  échoue, le build échoue.
- `build.sh:36` masque stderr du build universel (`2>/dev/null`), donc **une vraie
  erreur de compilation se déguise en repli mono-arch**. Corrigé : distinguer
  « Xcode absent » d'« échec de compilation ».
- Deux cibles à empaqueter : `notch-buddy` et `notch-hook` (RFC-006), toutes deux
  dans `Contents/MacOS/`, toutes deux signées.
- Postflight `xattr -dr com.apple.quarantine` (`release.yml:119-129`) : conservé
  tant qu'on n'est pas notarisé, mais **documenté explicitement dans le README**.
  Retirer silencieusement la quarantaine à la place de l'utilisateur sans le lui
  dire n'est pas acceptable.

## 4. Alternatives Considered

**Notariser (compte Apple, 99 $/an).** Techniquement la bonne réponse : supprime
R7 en entier — pas de friction Gatekeeper, pas de `xattr` à retirer, permissions
stables entre versions. Écartée sur contrainte de coût. Le renoncement aux API
Accessibilité est ce qui rend l'alternative gratuite acceptable.

**Ad-hoc pur, sans certificat.** Écarté : identité différente à chaque build.

**Distribuer un zip plutôt qu'un DMG.** Marginalement plus simple, mais le cask
Homebrew et le glisser-déposer vers `/Applications` sont mieux servis par un DMG.

**Garder l'auto-update.** Écarté, cf. Non-goals.

## 5. Action plan

| # | Tâche | Statut | % |
|---|---|---|---|
| T1 | `Package.swift` deux cibles + `build.sh` universel avec vrai diagnostic d'échec | todo | 0 |
| T2 | `generate-icon.swift` + `iconutil` | todo | 0 |
| T3 | `Info.plist` (`LSUIElement`, `NSSupportsAutomaticGraphicsSwitching`) | todo | 0 |
| T4 | Certificat auto-signé à CN stable, hors dépôt, **sans repli ad-hoc** | todo | 0 |
| T5 | Signature des deux exécutables + `codesign --verify --strict --deep` | todo | 0 |
| T6 | `make-dmg.sh` | todo | 0 |
| T7 | Workflow GitHub Actions + bump du cask | todo | 0 |
| T8 | README : documenter la friction Gatekeeper et le retrait de quarantaine | todo | 0 |
| T9 | Perfcheck de release : les 3 scénarios sur machine propre, collés dans la note de version | todo | 0 |

**Critère de sortie.** `./scripts/build.sh && ./scripts/make-dmg.sh` produit un
DMG sur une machine propre. Le DMG installé sur un **second compte utilisateur
macOS** se lance (le clic droit → Ouvrir est acceptable et documenté).
`codesign --verify --strict --deep` passe. Le verdict de `spctl -a -t exec -vv`
est consigné dans cette RFC, quel qu'il soit. Bundle < 5 Mo.

## 6. Open Questions

**Q1 — L'identité de signature doit-elle être partagée entre machines ?**
Si le build tourne à la fois en local et en CI avec deux certificats différents,
les permissions sautent quand même. Une seule identité, exportée et chiffrée dans
les secrets GitHub.

```sh
# État actuel du trousseau et vérification d'un bundle signé :
security find-identity -v -p codesigning
codesign -dv --verbose=4 dist/*.app 2>&1 | grep -E 'Authority|TeamIdentifier|flags'
spctl -a -t exec -vv dist/*.app 2>&1
```

**Q2 — Publie-t-on un tap Homebrew, ou un simple DMG en release GitHub ?**
Le tap est ~2 j de travail et suppose des utilisateurs. Le DMG seul suffit tant
que l'app est personnelle.

**Q3 — À quel moment rouvrir la notarisation ?**
Deux déclencheurs objectifs : le jour où quelqu'un d'autre installe l'app, ou le
jour où une fonction exige l'Accessibilité (raccourcis globaux). Tant que ni l'un
ni l'autre, l'auto-signature tient.

**Q4 — Que fait `--bench` en release ?**
RFC-001 prévoit une commande de mesure. Doit-elle rester dans le binaire
distribué ? Utile pour diagnostiquer un rapport de lenteur, mais c'est une
surface de plus.
