import Foundation

enum ScalePreset: String, CaseIterable {
    case full        = "1x"
    case half        = "1/2x"
    case twoHalf     = "1/2.5x"
    case third       = "1/3x"
    case thirdHalf   = "1/3.5x"
    case quarter     = "1/4x"

    var factor: Double {
        switch self {
        case .full:      return 1.0
        case .half:      return 0.5
        case .twoHalf:   return 1.0 / 2.5
        case .third:     return 1.0 / 3.0
        case .thirdHalf: return 1.0 / 3.5
        case .quarter:   return 0.25
        }
    }

    var displayName: String { rawValue }

    static var `default`: ScalePreset { .half }

    static func load() -> ScalePreset {
        let raw = UserDefaults.standard.string(forKey: "captureScale") ?? ""
        return ScalePreset(rawValue: raw) ?? .default
    }

    func save() {
        UserDefaults.standard.set(self.rawValue, forKey: "captureScale")
    }
}
