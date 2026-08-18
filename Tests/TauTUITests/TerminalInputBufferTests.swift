import Dispatch
import Testing
@testable import TauTUI

private final class ManualEscapeFlushScheduler {
    private struct ScheduledWork {
        let deadline: Int
        let workItem: DispatchWorkItem
    }

    private var now = 0
    private var scheduled: [ScheduledWork] = []

    var delays: [Int] = []

    func schedule(milliseconds: Int, workItem: DispatchWorkItem) {
        self.delays.append(milliseconds)
        self.scheduled.append(ScheduledWork(deadline: self.now + milliseconds, workItem: workItem))
    }

    func advance(milliseconds: Int) {
        self.now += milliseconds
        let due = self.scheduled.filter { $0.deadline <= self.now }
        self.scheduled.removeAll { $0.deadline <= self.now }
        due.forEach { $0.workItem.perform() }
    }
}

@Suite("Terminal input buffering")
struct TerminalInputBufferTests {
    @Test
    func `escape ambiguity timeout preserves local and SSH compatibility`() {
        #expect(ProcessTerminal.resolveEscapeAmbiguityTimeoutMilliseconds(environment: [:]) == 30)
        #expect(ProcessTerminal
            .resolveEscapeAmbiguityTimeoutMilliseconds(environment: ["SSH_TTY": "/dev/pts/1"]) == 100)
        #expect(ProcessTerminal
            .resolveEscapeAmbiguityTimeoutMilliseconds(environment: ["SSH_CONNECTION": "host"]) == 100)
        #expect(ProcessTerminal.resolveEscapeAmbiguityTimeoutMilliseconds(environment: ["SSH_TTY": ""]) == 30)
    }

    @Test
    func `local split option enter remains one modified key through prior ambiguity window`() {
        let scheduler = ManualEscapeFlushScheduler()
        let parser = self.makeParser(environment: [:], scheduler: scheduler)

        #expect(parser.parseForTests("\u{001B}").isEmpty)
        #expect(scheduler.delays == [30])
        scheduler.advance(milliseconds: 20)

        let events = parser.parseForTests("\r")
        #expect(events.count == 1)
        guard events.count == 1, case let .key(.enter, modifiers) = events[0] else {
            Issue.record("expected one local Option-Enter event")
            return
        }
        #expect(modifiers == [.option])
    }

    @Test
    func `SSH split option enter remains one modified key`() {
        let scheduler = ManualEscapeFlushScheduler()
        let parser = self.makeParser(environment: ["SSH_TTY": "/dev/pts/1"], scheduler: scheduler)

        #expect(parser.parseForTests("\u{001B}").isEmpty)
        #expect(scheduler.delays == [100])
        scheduler.advance(milliseconds: 50)

        let events = parser.parseForTests("\r")
        #expect(events.count == 1)
        guard events.count == 1, case let .key(.enter, modifiers) = events[0] else {
            Issue.record("expected one Option-Enter event")
            return
        }
        #expect(modifiers == [.option])
    }

    @Test
    func `incomplete CSI uses its own sequence timeout over SSH`() {
        let scheduler = ManualEscapeFlushScheduler()
        let parser = self.makeParser(environment: ["SSH_TTY": "/dev/pts/1"], scheduler: scheduler)

        #expect(parser.parseForTests("\u{001B}[1;").isEmpty)
        #expect(scheduler.delays == [50])
        scheduler.advance(milliseconds: 49)

        let events = parser.parseForTests("3D")
        #expect(events.count == 1)
        guard events.count == 1, case let .key(.arrowLeft, modifiers) = events[0] else {
            Issue.record("expected one Option-Left event")
            return
        }
        #expect(modifiers == [.option])
    }

    @Test
    func `cancelled lone escape timer cannot flush a newer sequence`() {
        let scheduler = ManualEscapeFlushScheduler()
        let parser = self.makeParser(environment: [:], scheduler: scheduler)

        #expect(parser.parseForTests("\u{001B}").isEmpty)
        scheduler.advance(milliseconds: 5)
        #expect(parser.parseForTests("[").isEmpty)

        // Dispatch cancellation does not guarantee that an already-enqueued work item
        // cannot begin. Exercise the stale item explicitly before the CSI completes.
        scheduler.advance(milliseconds: 5)
        let events = parser.parseForTests("1;3D")

        #expect(events.count == 1)
        guard events.count == 1, case let .key(.arrowLeft, modifiers) = events[0] else {
            Issue.record("expected the newer CSI sequence to remain intact")
            return
        }
        #expect(modifiers == [.option])
    }

    private func makeParser(
        environment: [String: String],
        scheduler: ManualEscapeFlushScheduler) -> ProcessTerminal
    {
        ProcessTerminal(
            inputFileDescriptor: 0,
            outputFileDescriptor: 1,
            environment: environment,
            escapeFlushScheduler: scheduler.schedule)
    }
}
