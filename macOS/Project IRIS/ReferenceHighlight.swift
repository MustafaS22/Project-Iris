import Foundation
import CoreGraphics

/// Reference regions use the original image's top-left coordinates, independent of
/// screen size, letterboxing and Retina scale. The same transform drives ink and gaze.
enum ReferenceHighlight {
    static func fitted(image: CGSize, canvas: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0 else { return .zero }
        let box = CGRect(x: canvas.width * 0.14, y: canvas.height * 0.265, width: canvas.width * 0.72, height: canvas.height * 0.50)
        let scale = min(box.width / image.width, box.height / image.height)
        return CGRect(x: box.midX - image.width * scale / 2, y: box.midY - image.height * scale / 2, width: image.width * scale, height: image.height * scale)
    }
    static func rect(_ mark: ScreenDrawing.Mark, image: CGSize, canvas: CGSize) -> CGRect {
        let frame = fitted(image: image, canvas: canvas)
        return CGRect(x: frame.minX + mark.x * frame.width, y: frame.minY + mark.y * frame.height, width: (mark.width ?? 0) * frame.width, height: (mark.height ?? 0) * frame.height)
    }
    static func opacity(index: Int, drawing: ScreenDrawing, visible: Int, revealFrom: Int, elapsed: Double) -> Double {
        guard visible > 0, index < visible else { return 0 }
        let active=drawing.presentationSteps.first { $0.contains(min(visible,drawing.marks.count)-1) }
        if active?.contains(index) == true { return min(1,max(0,elapsed/0.28)) }
        let previous=drawing.presentationSteps.last { $0.upperBound <= revealFrom }
        return previous?.contains(index) == true ? max(0,1-elapsed/0.22) : 0
    }
    struct Region { let name: String; let x, y, w, h: Double }
    private static func r(_ name: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Region { .init(name: name, x: x, y: y, w: w, h: h) }
    // Authored against each bundled source image, not the former generated artwork.
    static let regions: [String: [[Region]]] = [
        "neuron": [[r("Dendrites",0.03,0.075,0.28,0.20)], [r("Cell body",0.13,0.38,0.25,0.32)], [r("Axon",0.43,0.425,0.38,0.085)], [r("Myelin",0.59,0.425,0.12,0.08)], [r("Synapse · enlarged",0.49,0.055,0.18,0.24)]],
        "digestive-system": [[r("Mouth",0.43,0.08,0.14,0.07)], [r("Oesophagus",0.48,0.19,0.10,0.31)], [r("Stomach",0.54,0.52,0.19,0.12)], [r("Small intestine",0.39,0.71,0.25,0.14)], [r("Liver",0.31,0.51,0.24,0.10)], [r("Large intestine",0.30,0.65,0.42,0.26)]],
        "atomic-orbitals": [[r("s orbital",0.39,0.38,0.18,0.23)], [r("p orbitals & axes",0.18,0.06,0.75,0.84)]],
        "hybridisation": [[r("s and p orbitals",0.02,0.04,0.29,0.90)], [r("Four sp³ hybrids",0.50,0.29,0.49,0.55)]],
        "hybridisation-sp2": [[r("Three hybrid directions",0.17,0.20,0.66,0.76)], [r("120° planar geometry",0.58,0.18,0.40,0.58)]],
        "water-molecule": [[r("Oxygen and hydrogen",0.18,0.10,0.66,0.84)], [r("Bent molecular geometry",0.27,0.29,0.59,0.60)]],
        "atom": [[r("Electron probability cloud",0.08,0.17,0.68,0.69)], [r("Enlarged nucleus",0.68,0.005,0.31,0.34)]],
        "animal-cell": [[r("Cell membrane & cytoplasm",0.02,0.25,0.96,0.65)], [r("Nucleus",0.63,0.02,0.23,0.33)], [r("Mitochondrion",0.11,0.12,0.24,0.18)], [r("Endoplasmic reticulum",0.43,0.13,0.48,0.43)]],
        "photosynthesis": [[r("Light reactions",0.34,0.01,0.49,0.44)], [r("Water",0.15,0.11,0.20,0.22),r("Carbon dioxide",0.13,0.46,0.23,0.21)], [r("Calvin cycle & sugars",0.33,0.55,0.57,0.43)]],
        "circulation": [[r("Heart",0.48,0.24,0.17,0.13)], [r("Pulmonary circulation",0.35,0.19,0.43,0.20)], [r("Systemic circulation",0.24,0.37,0.57,0.57)]],
        "dna": [[r("DNA double helix",0.08,0.01,0.51,0.98)], [r("Complementary bases",0.60,0.44,0.39,0.44)]],
        "client-server": [[r("Client & request",0.00,0.11,0.68,0.68)], [r("Server",0.69,0.20,0.30,0.63)], [r("Response",0.31,0.48,0.39,0.25)]],
        "binary-tree": [[r("Root and branches",0.15,0.00,0.69,0.45)], [r("Search paths",0.14,0.31,0.72,0.68)]],
        "neural-network": [[r("Input layer",0.04,0.10,0.21,0.82)], [r("Hidden layer",0.43,0.02,0.22,0.96),r("Output layer",0.84,0.31,0.16,0.40)]],
        "heat-transfer": [[r("Conduction through the handle",0.52,0.36,0.39,0.19)], [r("Convection in the water",0.20,0.42,0.44,0.31)], [r("Radiation from the hob",0.04,0.70,0.69,0.27)]],
        "wave": [[r("Wavelength & period",0.03,0.01,0.60,0.48)], [r("Frequency and wave speed",0.10,0.43,0.88,0.55)]]
    ]
    static func marks(id: String, speeches: [String]) -> [ScreenDrawing.Mark] {
        guard let stages = regions[id], stages.count == speeches.count else { return [] }
        return stages.enumerated().flatMap { step, regions in
            regions.enumerated().map { index, r in
                ScreenDrawing.Mark(kind: "focus", x: r.x, y: r.y, width: r.w, height: r.h, text: r.name, speech: index == 0 ? speeches[step] : nil, step: step)
            }
        }
    }
}
