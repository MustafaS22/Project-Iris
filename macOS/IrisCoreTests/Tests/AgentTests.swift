import XCTest
@testable import IrisCore

final class AgentPolicyTests: XCTestCase {
    func testSimpleRequestsStayInChat() {
        for input in ["Hi", "What's 2+2?", "Explain how to create an agent", "Don't create an agent for this", "An example: `create an agent`", "What is an agent?", "Explain agents to me", "Write an email to Sam", "Open Safari", "Solve the question on my screen", "How would you build a complete app with tests, compare sources and prepare a report?", "Don't use an agent to create a complete, detailed report from these sources and compare all of the options with test cases."] {
            XCTAssertFalse(AgentPolicy.shouldDeploy(input), input)
        }
    }
    func testExplicitAndComplexTasksDelegateLocally() throws {
        XCTAssertTrue(AgentPolicy.shouldDeploy("Create an agent to compare my research notes"))
        XCTAssertTrue(AgentPolicy.shouldDeploy("Hi", explicit: true))
        XCTAssertTrue(AgentPolicy.shouldDeploy("Build a complete study planner website with a working weekly schedule, then test the interactions and prepare a detailed report of the project."))
        XCTAssertTrue(try ChatMentions.parse("@agent @website @drive build a study planner").agent)
        XCTAssertEqual(try ChatMentions.parse("@agent @website @drive build a study planner").creation, .website)
        XCTAssertFalse(try ChatMentions.parse("`@agent` this is code").agent)
        XCTAssertEqual(ChatMentions.highlightedRanges(in: "@agent task").count, 1)
    }
    func testSpecialtiesAndColors() {
        XCTAssertEqual(AgentPolicy.specialty(for: "Build a website"), .builder)
        XCTAssertEqual(AgentPolicy.specialty(for: "Research competitors"), .researcher)
        XCTAssertEqual(AgentPolicy.specialty(for: "Prepare a study guide"), .analyst)
        var hues: [Double] = []
        for _ in 0..<6 { hues.append(AgentPolicy.hue(existing: hues, theme: 0.15)) }
        XCTAssertEqual(Set(hues).count, 6)
        XCTAssertFalse(hues.contains { abs($0-0.15) < 0.04 })
    }
    func testRestartsNeverAutoResumeOrRestoreApproval() {
        var run = AgentRun(name: "Scout", specialty: .researcher, hue: 0.55, task: "Compare notes", context: "", preferences: Preferences())
        run.status = .running; run.approved = true
        let restored = AgentPolicy.restored(run)
        XCTAssertEqual(restored.status, .interrupted); XCTAssertFalse(restored.approved)
        XCTAssertFalse(AgentPolicy.supportedActions.contains("readFile"))
        XCTAssertFalse(AgentPolicy.supportedActions.contains("generateImage"))
        XCTAssertFalse(AgentPolicy.supportedActions.contains("drawOnScreen"))
    }
    func testShakeRequiresReversalsNearCorner() {
        var gesture = AgentCornerGesture()
        for i in 0..<8 { XCTAssertFalse(gesture.sample(x: Double(i)*20, time: Double(i)*0.05, inCorner: true)) }
        var triggered = false
        for i in 0..<6 { triggered = gesture.sample(x: i.isMultiple(of: 2) ? 0 : 60, time: 1+Double(i)*0.05, inCorner: true) || triggered }
        XCTAssertTrue(triggered)
        XCTAssertFalse(gesture.sample(x: 0, time: 2, inCorner: false))
    }
}

@MainActor final class AgentRuntimeTests: XCTestCase {
    private func store() -> IrisAgentStore { IrisAgentStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("agents.json")) }
    private func job(_ task: String = "Write a brief") -> AgentRun { .init(name: "Quill", specialty: .writer, hue: 0.55, task: task, context: "Selected reference only", preferences: Preferences()) }
    private func until(_ condition: () -> Bool) async {
        for _ in 0..<200 { if condition() { return }; try? await Task.sleep(for: .milliseconds(5)) }
        XCTFail("Timed out waiting for local fixture")
    }
    func testIndependentConcurrentJobsAndQueue() async throws {
        let s = store(); var running = 0, peak = 0
        s.answer = { run, partial in
            running += 1; peak = max(peak, running)
            partial("Draft for " + run.task)
            try await Task.sleep(for: .milliseconds(30))
            running -= 1
            return "Finished " + run.task
        }
        let ids = try (0..<4).map { try s.deploy(job("task \($0)")) }
        await until { s.runs.filter { $0.status == .completed }.count == 4 }
        XCTAssertEqual(peak, 2)
        XCTAssertEqual(Set(ids.compactMap { s.run($0)?.result }).count, 4)
        XCTAssertTrue(s.runs.allSatisfy { $0.modelTurns == 1 })
        s.shutdown()
    }
    func testReviewAndRealToolReceiptsBeforeCompletion() async throws {
        let s = store(); var calls = 0, executed = 0
        s.answer = { run, _ in
            calls += 1
            if calls == 1 { return "Saving the draft.\n```iris-actions\n{\"actions\":[{\"type\":\"writeFile\",\"folder\":\"folder\",\"path\":\"draft.txt\",\"content\":\"Hello\"}]}\n```" }
            XCTAssertTrue(run.transcript.contains { $0.text.contains("Saved draft.txt") })
            return "Saved the draft."
        }
        s.execute = { _ in executed += 1; return .init(text: "Saved draft.txt") }
        let id = try s.deploy(job())
        await until { s.run(id)?.status == .waiting }
        XCTAssertEqual(executed, 0); XCTAssertEqual(calls, 1)
        s.approve(id)
        await until { s.run(id)?.status == .completed }
        XCTAssertEqual(executed, 1); XCTAssertEqual(calls, 2)
        s.shutdown()
    }
    func testStopRejectsLatePartialAndLateCompletion() async throws {
        let s = store()
        s.answer = { _, partial in
            try? await Task.sleep(for: .milliseconds(50))
            partial("late update")
            return "late result"
        }
        let id = try s.deploy(job())
        await until { s.run(id)?.status == .running }
        s.stop(id)
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(s.run(id)?.status, .stopped)
        XCTAssertEqual(s.run(id)?.partial, ""); XCTAssertEqual(s.run(id)?.result, "")
        s.shutdown()
    }
    func testUnsupportedActionsNeverExecute() async throws {
        let s = store(); var calls = 0
        s.answer = { _, _ in "```iris-actions\n{\"actions\":[{\"type\":\"readFile\",\"folder\":\"x\",\"path\":\"secret.txt\"}]}\n```" }
        s.mayExecute = { _ in true }; s.execute = { _ in calls += 1; return .init(text: "not allowed") }
        let id = try s.deploy(job())
        await until { s.run(id)?.status == .failed }
        XCTAssertEqual(calls, 0)
        s.shutdown()
    }
    func testActionBudgetStopsRunawayLoop() async throws {
        let s = store(); var actions = 0
        s.answer = { _, _ in "```iris-actions\n{\"actions\":[{\"type\":\"createFolder\",\"folder\":\"x\",\"path\":\"test\"}]}\n```" }
        s.mayExecute = { _ in true }; s.execute = { _ in actions += 1; return .init(text: "Created folder") }
        let id = try s.deploy(job())
        await until { s.run(id)?.status == .failed }
        XCTAssertEqual(s.run(id)?.modelTurns, 4); XCTAssertEqual(actions, 4)
        s.shutdown()
    }
    func testComputerActionsAreSerialized() async throws {
        let s = store(); var active = 0, peak = 0
        s.answer = { run, _ in run.modelTurns == 1 ? "```iris-actions\n{\"actions\":[{\"type\":\"createFolder\",\"folder\":\"x\",\"path\":\"test\"}]}\n```" : "Done" }
        s.mayExecute = { _ in true }
        s.execute = { _ in active += 1; peak = max(peak, active); try await Task.sleep(for: .milliseconds(20)); active -= 1; return .init(text: "Created folder") }
        _ = try s.deploy(job("First")); _ = try s.deploy(job("Second"))
        await until { s.runs.filter { $0.status == .completed }.count == 2 }
        XCTAssertEqual(peak, 1); XCTAssertFalse(s.computerBusy)
        s.shutdown()
    }
}

final class AgentPeekInteractionTests: XCTestCase {
    func testPassingOverAnAvatarDoesNotExpand() {
        let id = UUID(); var state = AgentPeekState()
        state.hover(id, inside: true, at: 10); state.advance(at: 10.5)
        XCTAssertNil(state.selectedID)
        state.hover(id, inside: false, at: 10.5); state.advance(at: 11)
        XCTAssertNil(state.selectedID)
    }
    func testProlongedHoverSelectsOnlyThatAgent() {
        let first = UUID(), second = UUID(); var state = AgentPeekState()
        state.hover(first, inside: true, at: 0); state.advance(at: 0.8)
        XCTAssertEqual(state.selectedID, first)
        state.hover(second, inside: true, at: 1); state.advance(at: 1.4)
        XCTAssertEqual(state.selectedID, first)
        state.advance(at: 1.8); XCTAssertEqual(state.selectedID, second)
    }
    func testClickExpandsAndClickToCloseStaysClosed() {
        let id = UUID(); var state = AgentPeekState()
        state.hover(id, inside: true, at: 0); state.click(id)
        XCTAssertEqual(state.selectedID, id)
        state.click(id); state.advance(at: 2)
        XCTAssertNil(state.selectedID)
        state.hover(id, inside: false, at: 3); state.hover(id, inside: true, at: 4); state.advance(at: 5)
        XCTAssertEqual(state.selectedID, id)
    }
    func testFinishedAgentCannotLeaveStalePeekOpen() {
        let id = UUID(); var state = AgentPeekState(selectedID: id)
        state.hover(id, inside: true, at: 0); state.retain([])
        state.advance(at: 1)
        XCTAssertNil(state.selectedID); XCTAssertNil(state.hoveredID)
    }
}
