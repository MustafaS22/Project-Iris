import Foundation

struct AvatarCursorGaze: Equatable {
    var x = 0.0
    var y = 0.0
    var weight = 0.0
}

/// Local proximity response, independent of frame rate. Coordinates use positive-down view space.
struct AvatarCursorMotion {
    private(set) var gaze = AvatarCursorGaze()
    private var lastTime: Double?
    /// Persistent attention for onboarding targets or unrestricted cursor following.
    static func directed(dx: Double, dy: Double, size: Double) -> AvatarCursorGaze {
        guard dx.isFinite, dy.isFinite, size.isFinite, size > 0 else { return .init() }
        let reach = max(60, size * 1.2)
        let length = max(reach, hypot(dx, dy))
        return .init(x: dx / length * 0.105, y: dy / length * 0.085, weight: 1)
    }
    static func target(dx: Double, dy: Double, size: Double) -> AvatarCursorGaze {
        guard dx.isFinite, dy.isFinite, size.isFinite, size > 0 else { return .init() }
        let radius = max(120, size * 3)
        let distance = hypot(dx, dy)
        guard distance < radius else { return .init() }
        let fade = AvatarMotion.ease((distance - radius * 0.55) / (radius * 0.45))
        let reach = max(60, size * 1.2)
        return .init(x: min(1, max(-1, dx / reach)) * 0.105, y: min(1, max(-1, dy / reach)) * 0.085, weight: 1 - fade)
    }
    mutating func update(target: AvatarCursorGaze, at time: Double) -> AvatarCursorGaze {
        let dt = min(0.1, max(0, time - (lastTime ?? (time - 1.0 / 60))))
        lastTime = time
        let blend = 1 - exp(-dt / 0.12)
        gaze.x += (target.x - gaze.x) * blend
        gaze.y += (target.y - gaze.y) * blend
        gaze.weight += (target.weight - gaze.weight) * blend
        return gaze
    }
    static func apply(_ gaze: AvatarCursorGaze, to pose: AvatarPose) -> AvatarPose {
        var result = pose
        let weight = min(1, max(0, gaze.weight))
        result.gazeX += (gaze.x - result.gazeX) * weight
        result.gazeY += (gaze.y - result.gazeY) * weight
        return result
    }
}
