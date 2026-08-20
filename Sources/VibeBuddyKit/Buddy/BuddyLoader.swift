import Foundation

/// Finds and validates buddies, and never returns nothing: every failure mode
/// resolves to the built-in buddy rather than to no face at all.
public struct BuddyLoader: Sendable {

    /// Why a manifest could not be used. A value, never a trap.
    public enum LoadError: Error, CustomStringConvertible, Equatable {
        case notFound
        case unreadable(String)
        case invalid(BuddyManifest.ValidationError)

        public var description: String {
            switch self {
            case .notFound: return "introuvable"
            case let .unreadable(detail): return "illisible : \(detail)"
            case let .invalid(error): return error.description
            }
        }
    }


    public static var searchPath: String {
        (SupportDirectory.path as NSString).appendingPathComponent("buddies")
    }

    public struct Loaded: Sendable, Equatable {
        public let manifest: BuddyManifest
        /// Nil for the built-in buddy.
        public let path: String?
        public let isFallback: Bool
    }

    public private(set) var problems: [String] = []

    public init() {}

    /// Load `id`, or the built-in buddy if it cannot be loaded.
    public mutating func load(id: String?) -> Loaded {
        guard let id, id != BuiltInBuddy.id else {
            return Loaded(manifest: BuiltInBuddy.manifest, path: nil, isFallback: false)
        }
        let path = "\(Self.searchPath)/\(id).buddy"
        switch Self.read(path: path) {
        case let .success(manifest):
            return Loaded(manifest: manifest, path: path, isFallback: false)
        case let .failure(error):
            problems.append("« \(id) » : \(error)")
            return Loaded(manifest: BuiltInBuddy.manifest, path: nil, isFallback: true)
        }
    }

    /// Every buddy that parses, for a picker.
    public static func available() -> [BuddyManifest] {
        var found = [BuiltInBuddy.manifest]
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: searchPath)
        else { return found }
        for entry in entries.sorted() {
            guard entry.hasSuffix(".buddy") else { continue }
            if case let .success(manifest) = read(path: "\(searchPath)/\(entry)") {
                found.append(manifest)
            }
        }
        return found
    }

    public static func read(path: String) -> Result<BuddyManifest, LoadError> {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8)
        else { return .failure(.notFound) }

        let id = (path as NSString).lastPathComponent
            .replacingOccurrences(of: ".buddy", with: "")
        let result = BuddyFile.parse(text, id: id, name: id.capitalized)
        guard let manifest = result.manifest else {
            return .failure(.unreadable(result.problems.joined(separator: " · ")))
        }
        do {
            try manifest.validate()
            return .success(manifest)
        } catch let error as BuddyManifest.ValidationError {
            return .failure(.invalid(error))
        } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
    }
}

/// The buddy that ships in the binary, written in the same `.buddy` text format
/// as any other so the format is exercised on every launch.
///
/// Kept byte-for-byte in step with `assets/buddies/eve.buddy`, which is the
/// copy a person edits; a test compares the two.
public enum BuiltInBuddy {
    public static let id = "eve"

    public static let text = """
    # eve — un visage de robot sur un écran ovale à balayage
    #
    # « kind: eyes » change la grammaire des sections. Chaque expression décrit
    # jusqu'à trois lignes ; le premier mot dit de quoi on parle.
    #
    #   eye    l'œil — dessiné DEUX fois, en miroir, de part et d'autre de l'écran
    #   mouth  la bouche — une seule, centrée. Absente = pas de bouche.
    #          Les lignes « mouth » sont commentées : EVE n'a pas de bouche, et
    #          avec, le visage penche vers l'inquiétant. Décommenter les rétablit.
    #   time   la séquence et l'état de l'écran
    #
    # Clés d'un trait :
    #   shape  oval · iris · arc · ring · wing · line · dots · caret · x
    #   w h    largeur et hauteur, en points
    #   r      rayon des coins, pour « oval » seulement (r = h/2 donne un rond)
    #   t      épaisseur du trait, pour les autres formes (fraction, 0…1)
    #   bend   sens d'un « arc » : +1 sourit, −1 boude. Incline aussi « wing ».
    #   tilt   degrés, en miroir entre les deux yeux
    #   y      décalage vertical depuis le milieu de l'écran (négatif = vers le
    #          haut). À zéro partout ici : sans bouche, rien ne justifie de
    #          remonter les yeux.
    #   gap    écart entre les deux yeux (ligne « eye » seulement)
    #
    # Clés du temps :
    #   beat   secondes d'un TEMPS : les yeux tiennent une position pendant tout le
    #          temps, puis sont ailleurs au suivant. Il n'y a pas de trajet entre
    #          les deux — c'est ce qui rend le mouvement sec. La durée du
    #          clignement, elle, est fixe.
    #   blink  part des temps qui sont un clignement plutôt qu'un regard, 0…1.
    #   grain  part des cellules éteintes que le grain numérique allume faiblement.
    #   glitch arrachement de l'image, 0…1. 0 = un écran qui fonctionne.
    #   depth  amplitude des avancées et reculs : 0 immobile, 1 la valeur par
    #          défaut, au-dessus exagère
    #   gaze   none (droit devant, immobile) · calm (droit devant, mais avance et
    #          recule) · scan (gauche/droite, plus quelques haut/bas) · wander (les
    #          quatre directions) · dart (wander, deux fois plus vite)
    #
    # Le regard n'est pas un glissement : l'œil du côté vers lequel la tête tourne
    # fuit derrière la courbe et se rétrécit, l'autre se rapproche et s'élargit,
    # et l'écart entre les deux se resserre. C'est de la perspective calculée dans
    # la rastérisation, pas un rotation3DEffect — celui-ci ré-échantillonne, et une
    # grille de pixels ré-échantillonnée est une grille de pixels floue.
    #
    # L'écran est un rectangle arrondi, pas un ovale, et il n'a pas de contour :
    # ce sont les scanlines allumées qui dessinent sa surface. Il fait 80×30, soit
    # 40×15 cellules à 2 pt par pixel. C'est le maximum :
    # l'oreille de la pastille plafonne à 96 pt (PillLayout.maxSlotWidth) et la
    # hauteur est celle de l'encoche moins la marge.

    kind: eyes
    face: 80x30 r8

    # Endormi : les paupières fermées, deux croissants, et une bouche minuscule.
    sleeping (blue #5AA8DC)
    eye   shape:arc w:22 h:10 t:0.34 bend:1 gap:6 y:0
    # mouth shape:oval w:12 h:4 r:2 y:8
    time  beat:6 blink:0 grain:0.015 glitch:0 gaze:none

    # Au repos : deux ovales debout et un sourire plein.
    idle (amber #FFBB00)
    eye   shape:oval w:13 h:15 r:7 gap:16 y:0
    # mouth shape:arc w:24 h:9 t:0.6 bend:1 y:8
    time  beat:1.6 blink:0.3 grain:0.015 glitch:0 gaze:wander

    # Au travail : les mêmes yeux pleins qu'au repos, mais plissés — la
    # concentration se dit par la hauteur et une légère inclinaison, pas par une
    # forme à part. Deux essais
    # écartés avant celui-ci : l'anneau creux (« ring ») se lisait comme un trou,
    # l'œil à iris comme un œil de trop près. Regard qui ne
    # fait que gauche-droite, comme quelqu'un qui lit.
    working (green #70D46B)
    eye   shape:oval w:13 h:9 r:4.5 tilt:12 gap:16 y:0
    # mouth shape:oval w:14 h:5 r:2.5 y:8
    time  beat:1.2 blink:0.2 grain:0.012 glitch:0 gaze:scan

    # En attente : écarquillés, bouche ronde, et deux fois plus nerveux.
    awaiting (blue #5AB8FF)
    eye   shape:oval w:13 h:17 r:6.5 gap:16 y:0
    # mouth shape:oval w:10 h:10 r:5 y:8
    time  beat:1.4 blink:0.34 grain:0.015 glitch:0 gaze:dart

    # Terminé : deux arches épaisses. Il ne cherche plus rien du regard — il
    # avance et recule sur place, un peu fier de lui.
    finished (blue #5AB8FF)
    eye   shape:arc w:19 h:11 t:0.52 bend:-1 gap:10 y:0
    # mouth shape:arc w:20 h:9 t:0.4 bend:1 y:8
    time  beat:1.6 blink:0.15 depth:1.9 grain:0.012 glitch:0 gaze:calm

    # Échec : deux croix, et l'image qui décroche.
    failed (red #FF5555)
    eye   shape:x w:14 h:14 t:0.30 gap:14 y:0
    # mouth shape:arc w:20 h:8 t:0.38 bend:-1 y:8
    time  beat:0.5 blink:0.26 grain:0.07 glitch:0.85 gaze:scan
    """

    public static let manifest: BuddyManifest = {
        // Cannot fail: the text is a literal here and covered by a test.
        BuddyFile.parse(text, id: id, name: "Eve").manifest ?? BuddyManifest.empty
    }()
}

extension BuddyManifest {
    /// Last resort: renders a blank screen, crashes nowhere.
    static let empty = BuddyManifest(
        schema: supportedSchema, id: "empty", name: "—", colour: "#FFFFFF",
        face: FacePlate(),
        expressions: ["idle": Expression(
            eye: EyeSpec(pose: EyePose()), motion: .none, colour: nil)]
    )
}
