import Foundation

struct AvatarPose: Equatable {
    var gazeX = 0.0
    var gazeY = 0.0
    var floatX = 0.0
    var floatY = 0.0
    var roll = 0.0
    var leftOpen = 1.0
    var rightOpen = 1.0
    var anger = 0.0
    var happiness = 0.0

    func blended(to other: AvatarPose, amount: Double) -> AvatarPose {
        let t = min(1, max(0, amount))
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        return .init(gazeX: mix(gazeX, other.gazeX), gazeY: mix(gazeY, other.gazeY), floatX: mix(floatX, other.floatX), floatY: mix(floatY, other.floatY), roll: mix(roll, other.roll), leftOpen: mix(leftOpen, other.leftOpen), rightOpen: mix(rightOpen, other.rightOpen), anger: mix(anger, other.anger), happiness: mix(happiness, other.happiness))
    }
}

/// Monotonic, frame-sampled motion. No repeating animation transactions or accumulated timers.
struct AvatarMotion {
    private(set) var state: IrisState
    let started: TimeInterval
    private var transitionStarted: TimeInterval
    private var from: AvatarPose
    private let expressionSeed: UInt64
    static let transitionDuration = 0.58
    static let blinkInterval = 5.0
    static let glanceDuration = 2.2

    init(state: IrisState, at time: TimeInterval, expressionSeed: UInt64 = .random(in: .min ... .max)) {
        self.state = state; started = time
        self.expressionSeed = expressionSeed
        transitionStarted = time - Self.transitionDuration
        from = Self.expression(state)
    }
    mutating func transition(to newState: IrisState, at time: TimeInterval, glanceStarted: TimeInterval? = nil) {
        guard newState != state else { return }
        from = pose(at: time, glanceStarted: glanceStarted)
        state = newState; transitionStarted = time
    }
    static func ease(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * t * (t * (t * 6 - 15) + 10)
    }
    static func blink(at elapsed: Double) -> Double {
        guard elapsed >= blinkInterval else { return 0 }
        let phase = (elapsed - blinkInterval).truncatingRemainder(dividingBy: blinkInterval)
        if phase < 0.075 { return ease(phase / 0.075) }
        if phase < 0.105 { return 1 }
        if phase < 0.27 { return 1 - ease((phase - 0.105) / 0.165) }
        return 0
    }
    static func glanceInterval(unitRandom: Double, first: Bool = false) -> Double {
        let value = min(1, max(0, unitRandom))
        return first ? 1.5 + value : 4 + value * 4
    }
    static func glance(at elapsed: Double) -> Double {
        guard elapsed >= 0, elapsed < glanceDuration else { return 0 }
        if elapsed < 0.4 { return ease(elapsed / 0.4) }
        if elapsed < 1.35 { return 1 }
        return 1 - ease((elapsed - 1.35) / (glanceDuration - 1.35))
    }
    func pose(at time: TimeInterval, glanceStarted: TimeInterval? = nil, reducedMotion: Bool = false) -> AvatarPose {
        var target = Self.expression(state)
        guard !reducedMotion else { return target }
        let t = max(0, time - started)
        let asleep = state == .sleeping || state == .dormant
        if !asleep {
            target.floatX = 0.021 * sin(t * 2 * .pi / 7.4) + 0.006 * sin(t * 2 * .pi / 11.3)
            target.floatY = 0.032 * sin(t * 2 * .pi / 5.8) + 0.006 * sin(t * 2 * .pi / 9.7)
            target.roll += 0.9 * sin(t * 2 * .pi / 8.2)
            target.gazeX = 0.012 * sin(t * 0.38)
            target.gazeY = 0.008 * sin(t * 0.29)
            if state == .thinking || state == .vision {
                let points: [(Double, Double)] = [(-0.065, -0.035), (0.060, -0.045), (0.045, 0.018), (-0.045, 0.012)]
                let phase = t / 4.4
                let index = Int(phase.truncatingRemainder(dividingBy: Double(points.count)))
                let next = (index + 1) % points.count
                // Hold the gaze, then make one soft eye movement; both eyes stay coherent.
                let blend = Self.ease((phase - floor(phase) - 0.68) / 0.32)
                target.gazeX = points[index].0 + (points[next].0 - points[index].0) * blend
                target.gazeY = points[index].1 + (points[next].1 - points[index].1) * blend
            }
            let stateAge = max(0, time - transitionStarted)
            if state == .permission {
                // A lifted gaze settles into small, connected glances with long holds.
                let settle = Self.ease((stateAge - 1.15) / 1.15)
                let variation = Self.unit(expressionSeed)
                let step = stateAge / (5.5 + variation * 2.6)
                let leg = Int(step) % 4
                let glances = [0.0, 0.05, -0.028, 0.012]
                let lateral = Self.ease((step - floor(step) - 0.83) / 0.17)
                target.gazeX = glances[leg] + (glances[(leg + 1) % glances.count] - glances[leg]) * lateral
                target.gazeY = -0.056 + 0.031 * settle
                target.floatX *= 0.3
                target.floatY *= 0.42
            }
            applyExpression(to: &target, elapsed: stateAge)
            if state == .answering {
                let breath = 0.025 * sin(t * 2 * .pi / 2.6)
                target.leftOpen += breath; target.rightOpen += breath
            }
            if let glanceStarted {
                let glance = Self.glance(at: time - glanceStarted)
                target.gazeX *= 1 - glance
                target.gazeY = target.gazeY * (1 - glance) + 0.105 * glance
                target.leftOpen *= 1 - 0.1 * glance; target.rightOpen *= 1 - 0.1 * glance
            }
            let blink = Self.blink(at: t)
            target.leftOpen = target.leftOpen * (1 - blink) + 0.05 * blink
            target.rightOpen = target.rightOpen * (1 - blink) + 0.05 * blink
        }
        return from.blended(to: target, amount: Self.ease((time - transitionStarted) / Self.transitionDuration))
    }
    /// A bounded expression beat, sampled from the clock so skipped frames never
    /// restart it. Cursor guidance, work glances and the five-second blink still win.
    private func applyExpression(to pose: inout AvatarPose, elapsed: Double) {
        let thinking = state == .thinking
        guard thinking || state == .idle || state == .attention else { return }

        let seed = expressionSeed ^ (thinking ? 0x6472616674696e67 : 0x69646c655f697269)
        let spacing = thinking ? 10.5 + Self.unit(seed) * 4 : 15 + Self.unit(seed) * 5
        let cycle = UInt64(elapsed / spacing)
        let roll = Self.mix(seed &+ cycle)
        let start = (thinking ? 3.0 : 5.8) + Self.unit(roll) * 2
        let attack = 0.78, release = 0.94
        let hold = 0.72 + Self.unit(roll >> 11) * 0.52
        let duration = attack + hold + release
        let age = elapsed - Double(cycle) * spacing - start
        guard age >= 0, age < duration else { return }

        let strength = Self.ease(age / attack) * Self.ease((duration - age) / release)
        let direction = (roll & 4) == 0 ? -1.0 : 1.0
        // Alternate two pairs, then choose a member randomly, so adjacent beats differ.
        let choice = Int((cycle & 1) * 2 + (roll & 1))
        var expression = pose
        switch (thinking, choice) {
        case (false, 0): // warm eye smile
            expression.happiness = 1
            expression.leftOpen = 0.75; expression.rightOpen = 0.75
        case (false, 1): // quick wink
            if direction < 0 { expression.leftOpen = 0.34 } else { expression.rightOpen = 0.34 }
            expression.roll += direction * 1.15
        case (false, 2): // curious peek
            expression.gazeX = direction * 0.065; expression.gazeY = -0.022
            expression.leftOpen = direction < 0 ? 1.10 : 0.90
            expression.rightOpen = direction < 0 ? 0.90 : 1.10
            expression.roll += direction * 1.5
        case (false, _): // brightens up briefly
            expression.leftOpen = 1.19; expression.rightOpen = 1.19
            expression.gazeY = -0.024
        case (true, 0): // looks up as if considering an idea
            expression.gazeX = direction * 0.065; expression.gazeY = -0.077
            expression.leftOpen = direction < 0 ? 0.68 : 1.0
            expression.rightOpen = direction < 0 ? 1.0 : 0.68
        case (true, 1): // settles into concentration
            expression.leftOpen = 0.61; expression.rightOpen = 0.65
            expression.gazeY = 0.04
        case (true, 2): // a little aha moment
            expression.leftOpen = 1.22; expression.rightOpen = 1.22
            expression.gazeY = -0.055
        case (true, _): // pauses to look sideways
            expression.gazeX = direction * 0.082
            expression.roll += direction * 1.4
        }
        pose = pose.blended(to: expression, amount: strength)
    }

    private static func mix(_ input: UInt64) -> UInt64 {
        var n = input &+ 0x9e3779b97f4a7c15
        n = (n ^ (n >> 30)) &* 0xbf58476d1ce4e5b9
        n = (n ^ (n >> 27)) &* 0x94d049bb133111eb
        return n ^ (n >> 31)
    }

    private static func unit(_ input: UInt64) -> Double {
        Double(mix(input) & 0xffff) / 65_535
    }

    private static func expression(_ state: IrisState) -> AvatarPose {
        var pose = AvatarPose()
        switch state {
        case .dormant: pose.leftOpen = 0.12; pose.rightOpen = 0.12
        case .sleeping: pose.leftOpen = 0.78; pose.rightOpen = 0.78
        case .thinking, .studying: pose.leftOpen = 0.9; pose.rightOpen = 0.9
        case .listening: pose.leftOpen = 1.16; pose.rightOpen = 1.16
        case .error: pose.anger = 1; pose.leftOpen = 0.94; pose.rightOpen = 0.94
        case .warning, .disconnected: pose.leftOpen = 0.83; pose.rightOpen = 0.91
        case .attention: pose.leftOpen = 1.05; pose.rightOpen = 1.05
        case .celebration: pose.happiness = 1; pose.leftOpen = 0.7; pose.rightOpen = 0.7
        case .vision: pose.leftOpen = 1.06; pose.rightOpen = 1.06
        case .permission:
            pose.leftOpen = 1.19
            pose.rightOpen = 1.11
            pose.gazeY = -0.035
            pose.roll = -1.6
        default: break
        }
        return pose
    }
}
