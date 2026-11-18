import XCTest
@testable import IrisCore

final class IrisCoreTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000_000)
    func testPauseResumeDoesNotCountInterruptedTime() {
        var session = StudySession.start(goal: "Understand recursion", minutes: 25, at: start)
        session.pause(at: start.addingTimeInterval(300))
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(3600)), 1200)
        session.resume(at: start.addingTimeInterval(3600))
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(3900)), 900)
        XCTAssertEqual(session.progress(at: start.addingTimeInterval(3900)), 0.4, accuracy: 0.001)
    }
    func testDeadlineCompletesAcrossSleepAndNeverGoesNegative() {
        let session = StudySession.start(goal: "Read", minutes: 1, at: start)
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(1000)), 0)
        XCTAssertEqual(session.progress(at: start.addingTimeInterval(1000)), 1)
    }
    func testSessionRoundTripAndRecoveryPause() throws {
        let original = StudySession.start(goal: "Read", minutes: 25, at: start)
        var restored = try JSONDecoder().decode(StudySession.self, from: JSONEncoder().encode(original))
        restored.pause(at: start.addingTimeInterval(100))
        XCTAssertFalse(restored.isRunning); XCTAssertEqual(restored.pausedRemaining, 1400)
    }
    func testActivityPriorityExpiryAndStableTies() {
        let items: [LiveActivity] = [
            .init(id: "media", kind: .media, title: "Music", symbol: "", expiresAt: nil),
            .init(id: "focus", kind: .focus, title: "Focus", symbol: "", expiresAt: nil),
            .init(id: "old", kind: .urgent, title: "Expired", symbol: "", expiresAt: start),
            .init(id: "urgent", kind: .urgent, title: "Safety", symbol: "", expiresAt: nil)]
        XCTAssertEqual(ActivityRouter.ranked(items, at: start).map(\.id), ["urgent", "focus", "media"])
    }
    func testQuietHoursAcrossMidnightAndNudgeCooldown() {
        var prefs = Preferences(); prefs.proactive = true
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let night = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 23))!
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 12))!
        XCTAssertTrue(ProactivePolicy.isQuiet(at: night, preferences: prefs, calendar: calendar))
        XCTAssertFalse(ProactivePolicy.isQuiet(at: day, preferences: prefs, calendar: calendar))
        prefs.quietEnabled = false
        XCTAssertFalse(ProactivePolicy.mayNudge(at: day, preferences: prefs, lastNudge: day.addingTimeInterval(-60), fullScreen: false))
        XCTAssertFalse(ProactivePolicy.mayNudge(at: day, preferences: prefs, lastNudge: nil, fullScreen: true))
        XCTAssertTrue(ProactivePolicy.mayNudge(at: day, preferences: prefs, lastNudge: day.addingTimeInterval(-1800), fullScreen: false))
    }
    func testSensitiveAppsCannotBeAllowlisted() {
        for id in ["com.apple.Safari", "com.google.Chrome", "com.1password.1password", "com.bank.app"] { XCTAssertFalse(ContextPolicy.permitsCapture(bundleID: id, allowlist: [id])) }
        XCTAssertFalse(ContextPolicy.permitsCapture(bundleID: "com.apple.Preview", allowlist: []))
        XCTAssertTrue(ContextPolicy.permitsCapture(bundleID: "com.apple.Preview", allowlist: ["com.apple.Preview"]))
        XCTAssertFalse(ContextPolicy.permitsCapture(bundleID: nil, allowlist: []))
    }
    func testProviderURLRejectsUnsafeDestinations() throws {
        XCTAssertNoThrow(try ProviderEndpoint.validate("http://127.0.0.1:1234/v1"))
        XCTAssertNoThrow(try ProviderEndpoint.validate("https://models.example.com/v1"))
        for input in ["http://models.example.com", "file:///etc/passwd", "https://user:pass@example.com", "https://example.com?token=x", "", "ftp://localhost"] { XCTAssertThrowsError(try ProviderEndpoint.validate(input), input) }
    }
    func testEveryCapabilityHasPolicyAndNoDestructiveCapabilityIsExposed() {
        for capability in IrisCapability.available { XCTAssertFalse(capability.offline.isEmpty); XCTAssertFalse(capability.failure.isEmpty); XCTAssertFalse(capability.audit.isEmpty); XCTAssertNotEqual(capability.risk, .destructive); if capability.risk == .externalWrite { XCTAssertTrue(capability.confirmation) } }
    }
}

extension IrisCoreTests {
    func testNotchFramesUseDisplayOriginAndStayAtTopCenter() {
        let screen = CGRect(x: -1920, y: 900, width: 1920, height: 1080)
        let frame = SurfaceGeometry.frame(in: screen, desired: CGSize(width: 472, height: 460))
        XCTAssertEqual(frame.midX, screen.midX); XCTAssertEqual(frame.maxY, screen.maxY)
        XCTAssertTrue(screen.contains(frame))
    }
    func testNotchPanelStaysFlushWithPhysicalScreenEdge() {
        let screen = CGRect(x: -1440, y: 360, width: 1440, height: 900)
        let desired = CGSize(width: 1000, height: 760)
        let visible = CGRect(x: -1440, y: 410, width: 1440, height: 814)
        XCTAssertEqual(SurfaceGeometry.notchFrame(in: screen, visible: visible, safeTop: 30, desired: desired).maxY, screen.maxY)
        let hiddenBar = SurfaceGeometry.notchFrame(in: screen, visible: screen, safeTop: 0, desired: desired)
        XCTAssertEqual(hiddenBar.maxY, screen.maxY)
        let cameraHousing = SurfaceGeometry.notchFrame(in: screen, visible: screen, safeTop: 38, desired: desired)
        XCTAssertEqual(cameraHousing.maxY, screen.maxY)
        XCTAssertEqual(cameraHousing.midX, screen.midX)
        XCTAssertTrue(screen.contains(cameraHousing))
    }
    func testOversizedSurfaceStaysInsideSmallDisplay() {
        let screen = CGRect(x: 500, y: -700, width: 800, height: 600)
        let frame = SurfaceGeometry.frame(in: screen, desired: CGSize(width: 1600, height: 1200))
        XCTAssertTrue(screen.contains(frame)); XCTAssertEqual(frame.maxY, screen.maxY)
    }
}

extension IrisCoreTests {
    func testFreshAndUpgradedUsersSeeOnboardingBeforePresence() {
        XCTAssertTrue(LaunchPolicy.needsOnboarding(completed: false, revision: 2))
        XCTAssertTrue(LaunchPolicy.needsOnboarding(completed: true, revision: 1))
        XCTAssertFalse(LaunchPolicy.needsOnboarding(completed: true, revision: 2))
    }
}
