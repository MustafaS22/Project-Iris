import Foundation
import CoreGraphics

/// Bounded, declarative annotations. Coordinates are normalized from the display's top-left.
struct ScreenDrawing: Codable, Equatable, Hashable {
    struct Mark: Codable, Equatable, Hashable {
        var kind: String
        var x: Double
        var y: Double
        var width: Double?
        var height: Double?
        var text: String?
        var targetID: String? = nil
        var speech: String? = nil
        var object: String? = nil
        var color: String? = nil
        var points: [DrawingPoint]? = nil
        var closed: Bool? = nil
        var step: Int? = nil
    }
    var marks: [Mark]
    var narrate: Bool? = nil
    var mode: String? = nil
    var title: String? = nil
    var preset: String? = nil
    var figure: String? = nil
    var question: SolutionRegion? = nil
    static func decode(_ content: String) throws -> Self {
        guard content.utf8.count <= 16000 else { throw Failure.invalid }
        var raw=content.trimmingCharacters(in:.whitespacesAndNewlines)
        if raw.hasPrefix("```"),let first=raw.firstIndex(of:"\n"),raw.hasSuffix("```"){raw=String(raw[raw.index(after:first)..<raw.index(raw.endIndex,offsetBy:-3)]).trimmingCharacters(in:.whitespacesAndNewlines)}
        var parsed:Any
        do {
            parsed=try JSONSerialization.jsonObject(with:Data(raw.utf8),options:[.fragmentsAllowed])
            if let nested=parsed as? String,nested.utf8.count<=16000 {parsed=try JSONSerialization.jsonObject(with:Data(nested.utf8))}
        } catch {throw Failure.invalid}
        guard let object=parsed as? [String:Any] else{throw Failure.invalid}
        let data=try JSONSerialization.data(withJSONObject:object)
        let drawing: Self
        if object["solution"] != nil {
            drawing=try ScreenSolution.decode(data)
        } else if object["steps"] != nil || object["mode"] as? String == "solution" {
            drawing=try ScreenSolution.decode(data)
        } else if let id = object["preset"] as? String {
            guard let entry = DiagramLibrary.entry(id) else { throw Failure.invalid }
            var presetDrawing = entry.drawing
            if let narrate = object["narrate"] as? Bool { presetDrawing.narrate = narrate }
            drawing = presetDrawing
        } else {
            do {drawing=object["nodes"] != nil ? try JSONDecoder().decode(ConceptDiagram.self,from:data).drawing() : try JSONDecoder().decode(Self.self,from:data)}
            catch {throw Failure.invalid}
        }
        guard drawing.mode == nil || drawing.mode == "conceptual" || drawing.mode == "solution", (drawing.title?.count ?? 0) <= 100, (drawing.mode != "solution" || drawing.question?.valid == true), drawing.marks.count <= (drawing.preset == nil ? 24 : 64), (drawing.figure == nil || DiagramReference.validID(drawing.figure!)), drawing.marks.allSatisfy({ mark in
            ["arrow", "rectangle", "circle", "label", "callout", "node", "object", "path", "caption", "focus", "solution"].contains(mark.kind) &&
            mark.x.isFinite && mark.y.isFinite && (0...1).contains(mark.x) && (0...1).contains(mark.y) &&
            [mark.width, mark.height].compactMap { $0 }.allSatisfy { $0.isFinite && (-1...1).contains($0) } &&
            (mark.step == nil || (0...7).contains(mark.step!)) &&
            (mark.color == nil || DiagramObject.colors.contains(mark.color!)) &&
            (mark.kind != "object" || (DiagramObject.names.contains(mark.object ?? "") && (mark.width ?? 0) > 0 && (mark.height ?? 0) > 0 && mark.x + (mark.width ?? 0) <= 1 && mark.y + (mark.height ?? 0) <= 1)) &&
            (mark.kind != "focus" || ((mark.width ?? -1) >= 0 && (mark.height ?? -1) >= 0 && mark.x + (mark.width ?? 0) <= 1 && mark.y + (mark.height ?? 0) <= 1)) &&
            (mark.kind != "path" || ((2...64).contains(mark.points?.count ?? 0) && mark.points!.allSatisfy(\.valid) && (mark.width ?? 0) > 0 && (mark.height ?? 0) > 0 && mark.x + (mark.width ?? 0) <= 1 && mark.y + (mark.height ?? 0) <= 1)) &&
            (mark.text?.count ?? 0) <= (mark.kind == "solution" ? 1500 : 160) && (mark.targetID?.count ?? 0) <= 120 && (mark.targetID == nil || ["callout", "circle", "rectangle"].contains(mark.kind)) && (mark.speech?.count ?? 0) <= 400 &&
            (mark.kind != "node" || (!(mark.text ?? "").isEmpty && mark.width != nil && mark.height != nil && (mark.width ?? 0) > 0 && (mark.height ?? 0) > 0)) &&
            (["label", "callout", "caption"].contains(mark.kind) ? !(mark.text ?? "").isEmpty : mark.targetID != nil || (mark.width != nil && mark.height != nil))
        }) else { throw Failure.invalid }
        return drawing
    }
    /// Consecutive marks can form a single narrated scene-building step.
    var presentationSteps: [Range<Int>] {
        var result: [Range<Int>] = []
        for index in marks.indices {
            if index > 0, let step = marks[index].step, step == marks[index-1].step, let last = result.last {
                result[result.count-1] = last.lowerBound..<(index+1)
            } else { result.append(index..<(index+1)) }
        }
        return result
    }
    enum Failure: LocalizedError {
        case invalid
        var errorDescription: String? { "Iris couldn't read that visual explanation. Please try again with the question or diagram clearly visible." }
    }
}

/// Screen-space constraints shared by dragging recovery, resizing and roaming.
enum FloatingGeometry {
    static func clamped(_ origin: CGPoint, size: CGSize, bounds: CGRect) -> CGPoint {
        CGPoint(x: min(max(bounds.minX, origin.x), max(bounds.minX, bounds.maxX - size.width)),
                y: min(max(bounds.minY, origin.y), max(bounds.minY, bounds.maxY - size.height)))
    }
}


/// The model supplies anchors; Iris owns typography, spacing and leader geometry.
enum AnnotationLayout {
    struct Callout {
        let id: Int
        let text: String
        let target: CGPoint?
        let rect: CGRect
        let leader: [CGPoint]
    }
    struct Result {
        let callouts: [Callout]
        let shapes: [(index: Int, mark: ScreenDrawing.Mark)]
    }
    private struct Item {
        let id: Int
        let text: String
        let target: CGPoint?
        let proposed: CGPoint
        let size: CGSize
        let preferredLeft: Bool?
    }
    static func make(_ drawing: ScreenDrawing, size: CGSize, measure: (String) -> CGSize) -> Result {
        guard size.width > 0, size.height > 0 else { return .init(callouts: [], shapes: []) }
        let safe = CGRect(origin: .zero, size: size).insetBy(dx: min(24, size.width * 0.04), dy: min(32, size.height * 0.06))
        func point(_ mark: ScreenDrawing.Mark) -> CGPoint { .init(x: mark.x * size.width, y: mark.y * size.height) }
        func endpoint(_ mark: ScreenDrawing.Mark) -> CGPoint { .init(x: (mark.x + (mark.width ?? 0)) * size.width, y: (mark.y + (mark.height ?? 0)) * size.height) }
        func clipped(_ p: CGPoint) -> CGPoint { .init(x: min(size.width, max(0, p.x)), y: min(size.height, max(0, p.y))) }
        var items: [Item] = [], consumed = Set<Int>()
        for (index, mark) in drawing.marks.enumerated() where ["label", "callout"].contains(mark.kind) {
            let text = String((mark.text ?? "").prefix(96))
            let measured = measure(text)
            let labelSize = CGSize(width: min(safe.width, max(112, min(244, measured.width + 52))), height: min(60, max(40, measured.height + 20)))
            let proposed = point(mark)
            var target: CGPoint? = mark.kind == "callout" ? clipped(proposed) : nil
            var preferredLeft: Bool?
            if mark.kind == "label" {
                // Compatibility: older replies use separate label/arrow pairs. Match their tails,
                // replace them with a leader attached to the label edge, and draw text last.
                let label = CGRect(origin: proposed, size: labelSize).insetBy(dx: -36, dy: -24)
                let match = drawing.marks.enumerated().filter { $0.element.kind == "arrow" && !consumed.contains($0.offset) && label.contains(point($0.element)) }.min {
                    let a = point($0.element), b = point($1.element)
                    return hypot(a.x - proposed.x, a.y - proposed.y) < hypot(b.x - proposed.x, b.y - proposed.y)
                }
                if let match {
                    consumed.insert(match.offset); target = clipped(endpoint(match.element))
                    preferredLeft = proposed.x + labelSize.width / 2 < target!.x
                }
            }
            items.append(.init(id: index, text: text, target: target, proposed: proposed, size: labelSize, preferredLeft: preferredLeft))
        }
        let anchored = items.filter { $0.target != nil }
        let targets = anchored.compactMap(\.target)
        let centerX = targets.isEmpty ? safe.midX : (targets.map(\.x).min()! + targets.map(\.x).max()!) / 2
        let minX = targets.map(\.x).min() ?? safe.midX, maxX = targets.map(\.x).max() ?? safe.midX
        var left: [Item] = [], right: [Item] = []
        for item in anchored.sorted(by: { $0.target!.x < $1.target!.x }) {
            if item.preferredLeft ?? (item.target!.x <= centerX) { left.append(item) } else { right.append(item) }
        }
        // Keep a dense reply from overflowing one column when all anchors are on the same side.
        let capacity = max(1, Int((safe.height + 8) / 68))
        while left.count > capacity, right.count < capacity { right.insert(left.removeLast(), at: 0) }
        while right.count > capacity, left.count < capacity { left.append(right.removeFirst()) }
        var result: [Callout] = []
        func column(_ values: [Item], onLeft: Bool) {
            let ordered = values.sorted { $0.target!.y == $1.target!.y ? $0.id < $1.id : $0.target!.y < $1.target!.y }
            guard !ordered.isEmpty else { return }
            let maximumHeight = max(28, (safe.height - CGFloat(max(0, ordered.count - 1)) * 4) / CGFloat(ordered.count))
            let heights = ordered.map { min($0.size.height, maximumHeight) }
            let total = heights.reduce(0, +)
            let gap = ordered.count > 1 ? min(12, max(4, (safe.height - total) / CGFloat(ordered.count - 1))) : 12
            var origins: [CGFloat] = []
            for item in ordered {
                let desired = item.target!.y - heights[origins.count] / 2
                let previous = origins.last.map { $0 + heights[origins.count - 1] + gap } ?? safe.minY
                origins.append(max(safe.minY, max(desired, previous)))
            }
            // Backward pass shifts the column into the viewport without disturbing target order.
            for i in ordered.indices.reversed() {
                let limit = i == ordered.count - 1 ? safe.maxY - heights[i] : origins[i + 1] - gap - heights[i]
                origins[i] = min(origins[i], limit)
            }
            for (i, item) in ordered.enumerated() {
                let width = min(item.size.width, max(100, safe.width * 0.32))
                let suggestedX = onLeft ? minX - 72 - width : maxX + 72
                let x = min(safe.maxX - width, max(safe.minX, suggestedX))
                let rect = CGRect(x: x, y: max(safe.minY, origins[i]), width: width, height: heights[i])
                let target = item.target!
                let start = CGPoint(x: onLeft ? rect.maxX + 7 : rect.minX - 7, y: rect.midY)
                let elbow = CGPoint(x: onLeft ? min(start.x + 22, target.x - 12) : max(start.x - 22, target.x + 12), y: rect.midY)
                result.append(.init(id: item.id, text: item.text, target: target, rect: rect, leader: [start, elbow, target]))
            }
        }
        column(left, onLeft: true); column(right, onLeft: false)
        for item in items where item.target == nil {
            var rect = CGRect(origin: FloatingGeometry.clamped(item.proposed, size: item.size, bounds: safe), size: item.size)
            for _ in 0..<items.count where result.contains(where: { $0.rect.insetBy(dx: -6, dy: -6).intersects(rect) }) {
                let next = rect.offsetBy(dx: 0, dy: rect.height + 10)
                rect.origin = FloatingGeometry.clamped(next.origin, size: rect.size, bounds: safe)
                if result.contains(where: { $0.rect.intersects(rect) }) { rect.origin.x = max(safe.minX, rect.minX - rect.width - 16) }
            }
            result.append(.init(id: item.id, text: item.text, target: nil, rect: rect, leader: []))
        }
        return .init(callouts: result.sorted { $0.id < $1.id }, shapes: drawing.marks.enumerated().filter { !["label", "callout"].contains($0.element.kind) && !consumed.contains($0.offset) }.map { ($0.offset, $0.element) })
    }
}

enum AnnotationPlayback {
    static func progress(elapsed: Double, index: Int, duration: Double = 0.52) -> Double {
        let t = min(1, max(0, (elapsed - Double(index) * 0.095) / max(0.01, duration)))
        return t * t * (3 - 2 * t)
    }
    static func duration(count: Int) -> Double { Double(max(0, count - 1)) * 0.095 + 0.82 }
}


/// One explicit affine transform: normalized captured-window pixels → normalized display points.
/// Retina scale cancels in normalized coordinates; negative desktop origins remain meaningful.
struct ScreenProjection {
    let imageFrame: CGRect // Quartz global points, top-left origin.
    let displayFrame: CGRect
    func displayPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (imageFrame.minX + point.x * imageFrame.width - displayFrame.minX) / displayFrame.width,
                y: (imageFrame.minY + point.y * imageFrame.height - displayFrame.minY) / displayFrame.height)
    }
    func displayRect(_ rect: CGRect) -> CGRect {
        CGRect(origin: displayPoint(rect.origin), size: CGSize(width: rect.width * imageFrame.width / displayFrame.width, height: rect.height * imageFrame.height / displayFrame.height))
    }
    func imageRect(_ rect: CGRect) -> CGRect {
        CGRect(x: (displayFrame.minX + rect.minX * displayFrame.width - imageFrame.minX) / imageFrame.width,
               y: (displayFrame.minY + rect.minY * displayFrame.height - imageFrame.minY) / imageFrame.height,
               width: rect.width * displayFrame.width / imageFrame.width, height: rect.height * displayFrame.height / imageFrame.height)
    }
    func resolve(_ drawing: ScreenDrawing, targets: [GuidanceTarget]) throws -> ScreenDrawing {
        guard imageFrame.width > 0, imageFrame.height > 0, displayFrame.width > 0, displayFrame.height > 0 else { throw ScreenDrawing.Failure.invalid }
        var output = drawing
        if let question=drawing.question {output.question=SolutionRegion(displayRect(question.rect))}
        output.marks = try drawing.marks.map { original in
            var mark = original
            if let id = mark.targetID {
                guard let target = targets.first(where: { $0.id == id }) else { throw ScreenDrawing.Failure.invalid }
                if ["circle", "rectangle"].contains(mark.kind) {
                    mark.x = target.rect.minX; mark.y = target.rect.minY; mark.width = target.rect.width; mark.height = target.rect.height
                } else {
                    mark.x = target.rect.midX; mark.y = target.rect.midY
                }
            } else {
                let p = displayPoint(CGPoint(x: mark.x, y: mark.y))
                mark.x = p.x; mark.y = p.y
                mark.width = mark.width.map { $0 * imageFrame.width / displayFrame.width }
                mark.height = mark.height.map { $0 * imageFrame.height / displayFrame.height }
            }
            guard (0...1).contains(mark.x), (0...1).contains(mark.y) else { throw ScreenDrawing.Failure.invalid }
            return mark
        }
        return output
    }
}


extension ScreenDrawing.Mark {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind)
        targetID = try c.decodeIfPresent(String.self, forKey: .targetID)
        x = targetID == nil ? try c.decode(Double.self, forKey: .x) : (try c.decodeIfPresent(Double.self, forKey: .x) ?? 0)
        y = targetID == nil ? try c.decode(Double.self, forKey: .y) : (try c.decodeIfPresent(Double.self, forKey: .y) ?? 0)
        width = try c.decodeIfPresent(Double.self, forKey: .width)
        height = try c.decodeIfPresent(Double.self, forKey: .height)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        speech = try c.decodeIfPresent(String.self, forKey: .speech)
        object = try c.decodeIfPresent(String.self, forKey: .object)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        points = try c.decodeIfPresent([DrawingPoint].self, forKey: .points)
        closed = try c.decodeIfPresent(Bool.self, forKey: .closed)
        step = try c.decodeIfPresent(Int.self, forKey: .step)
    }
}


/// A small semantic diagram: Iris owns spacing and connector endpoints, not the model.
struct ConceptDiagram: Decodable {
    struct Node: Decodable { let id: String; let text: String; var speech: String?; var object: String?; var color: String? }
    struct Edge: Decodable { let from: String; let to: String }
    var title: String?
    let nodes: [Node]
    var edges: [Edge]?
    var narrate: Bool?
    func drawing() throws -> ScreenDrawing {
        let links = edges ?? []
        let ids = nodes.map(\.id)
        guard (1...8).contains(nodes.count), Set(ids).count == ids.count,
              nodes.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 80 && !$0.text.isEmpty && $0.text.count <= 80 && ($0.speech?.count ?? 0) <= 400 && ($0.object == nil || DiagramObject.names.contains($0.object!)) && ($0.color == nil || DiagramObject.colors.contains($0.color!)) }),
              links.count <= 12, links.allSatisfy({ ids.contains($0.from) && ids.contains($0.to) && $0.from != $0.to }) else { throw ScreenDrawing.Failure.invalid }
        // Rank a DAG so branches are evenly distributed; cycles use a readable grid.
        var ranks = Dictionary(uniqueKeysWithValues: ids.map { ($0, 0) })
        var remaining = Set(ids)
        while !remaining.isEmpty {
            guard let id = ids.first(where: { candidate in remaining.contains(candidate) && !links.contains(where: { $0.to == candidate && remaining.contains($0.from) }) }) else { break }
            remaining.remove(id)
            for edge in links where edge.from == id { ranks[edge.to] = max(ranks[edge.to] ?? 0, (ranks[id] ?? 0) + 1) }
        }
        let ranked = remaining.isEmpty && (ranks.values.max() ?? 0) < 4
        let columns = ranked ? (ranks.values.max() ?? 0) + 1 : min(3, nodes.count)
        var rects: [String: CGRect] = [:]
        for (index, node) in nodes.enumerated() {
            let col = ranked ? ranks[node.id]! : index % columns
            let peers = ranked ? nodes.filter { ranks[$0.id] == col }.map(\.id) : nodes.enumerated().filter { $0.offset % columns == col }.map { $0.element.id }
            let row = peers.firstIndex(of: node.id)!
            let w = min(0.23, 0.76 / Double(columns)), h = min(0.24, 0.48 / Double(peers.count))
            let center = CGPoint(x: 0.5 + (Double(col) - Double(columns - 1) / 2) * (0.80 / Double(columns)), y: 0.54 + (Double(row) - Double(peers.count - 1) / 2) * (0.60 / Double(peers.count)))
            rects[node.id] = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
        }
        var marks: [ScreenDrawing.Mark] = []
        var appeared = Set<String>(), pending = links
        func connector(_ edge: Edge) -> ScreenDrawing.Mark {
            let a = rects[edge.from]!, b = rects[edge.to]!
            let dx = b.midX - a.midX, dy = b.midY - a.midY
            func boundary(_ rect: CGRect, towardX x: CGFloat, towardY y: CGFloat) -> CGPoint {
                let scale = 1 / max(abs(x) / (rect.width / 2), abs(y) / (rect.height / 2))
                return CGPoint(x: rect.midX + x * scale, y: rect.midY + y * scale)
            }
            let start = boundary(a, towardX: dx, towardY: dy), end = boundary(b, towardX: -dx, towardY: -dy)
            return .init(kind: "arrow", x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y)
        }
        for node in nodes {
            appeared.insert(node.id)
            for edge in pending where appeared.contains(edge.from) && appeared.contains(edge.to) { marks.append(connector(edge)) }
            pending.removeAll { appeared.contains($0.from) && appeared.contains($0.to) }
            let rect = rects[node.id]!
            let object = node.object ?? DiagramObject.infer(node.text)
            marks.append(.init(kind: object == nil ? "node" : "object", x: rect.minX, y: rect.minY, width: rect.width, height: rect.height, text: node.text, speech: node.speech ?? node.text, object: object, color: node.color))
        }
        return .init(marks: marks, narrate: narrate ?? true, mode: "conceptual", title: title)
    }
}


struct DrawingPoint: Codable, Equatable, Hashable {
    var x: Double
    var y: Double
    var cx: Double? = nil
    var cy: Double? = nil
    var c2x: Double? = nil
    var c2y: Double? = nil
    var valid: Bool {
        [x,y,cx,cy,c2x,c2y].compactMap { $0 }.allSatisfy { $0.isFinite && (0...1).contains($0) } &&
        ((cx == nil && cy == nil && c2x == nil && c2y == nil) || (cx != nil && cy != nil && c2x != nil && c2y != nil))
    }
}

enum DiagramObject {
    static let names: Set<String> = ["sun", "plant", "leaf", "chloroplast", "cell", "atom", "molecule", "cloud", "droplet", "earth", "flame", "thermometer", "beaker", "battery", "resistor", "magnet", "heart", "lungs"]
    static let colors: Set<String> = ["accent", "white", "yellow", "orange", "red", "green", "cyan", "blue", "purple"]
    static func infer(_ text: String) -> String? {
        let text = text.lowercased()
        let matches: [(String,[String])] = [
            ("chloroplast",["chloroplast", "chlorophyll"]), ("sun",["sunlight", "sun", "solar"]),
            ("plant",["plant", "photosynthesis"]), ("leaf",["leaf", "leaves"]), ("cell",["cell", "nucleus"]),
            ("atom",["atom", "electron"]), ("molecule",["molecule"]),
            ("cloud",["cloud", "condensation"]), ("droplet",["water", "rain", "precipitation"]),
            ("earth",["earth", "planet"]), ("flame",["heat", "fire", "flame"]),
            ("thermometer",["temperature", "thermometer"]), ("beaker",["beaker", "chemical", "solution"]),
            ("battery",["battery", "power source"]), ("resistor",["resistor", "resistance"]),
            ("magnet",["magnet"]), ("heart",["heart"]), ("lungs",["lung", "breathing"])]
        return matches.first(where: { pair in pair.1.contains(where: { term in
            let words = text.split { !$0.isLetter }.map(String.init)
            return term.contains(" ") ? text.contains(term) : words.contains(term) || words.contains(term + "s")
        }) })?.0
    }
}
