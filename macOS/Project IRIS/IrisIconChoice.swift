import Foundation

enum IrisIconChoice: String, CaseIterable, Identifiable {
    case mochi, pixel, orbit, sticker, bloom, blueprint, goldenHour, chrome, midnight
    var id: String { rawValue }
    var asset: String { "AlternateIcon-" + rawValue }
    var title: String {
        switch self { case .mochi: "Mochi"; case .pixel: "Pixel"; case .orbit: "Orbit"; case .sticker: "Sticker"; case .bloom: "Bloom"; case .blueprint: "Blueprint"; case .goldenHour: "Golden Hour"; case .chrome: "Chrome"; case .midnight: "Midnight" }
    }
    var detail: String {
        switch self { case .mochi: "Soft & squishy"; case .pixel: "Pocket arcade"; case .orbit: "Little space explorer"; case .sticker: "A bright little misfit"; case .bloom: "Flower power"; case .blueprint: "Made of ideas"; case .goldenHour: "Always a warm welcome"; case .chrome: "A polished companion"; case .midnight: "For the night owls" }
    }
}
