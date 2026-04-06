import Foundation

enum ScalePreset: String, CaseIterable {
    case full    = "1x"
    case half    = "1/2x"
    case quarter = "1/4x"
    case eighth  = "1/8x"

    var factor: Double {
        switch self {
        case .full:    return 1.0
        case .half:    return 0.5
        case .quarter: return 0.25
        case .eighth:  return 0.125
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
