import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
  guard condition() else {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
  }
}

private final class FakeScheduler: CameraTimeoutScheduler {
  final class Token: CameraTimerToken {
    let callback: () -> Void
    var cancelled = false
    init(_ callback: @escaping () -> Void) { self.callback = callback }
    func cancel() { cancelled = true }
    func fire() { if !cancelled { callback() } }
  }
  var tokens: [Token] = []
  func schedule(after seconds: TimeInterval, _ callback: @escaping () -> Void) -> CameraTimerToken {
    let token = Token(callback)
    tokens.append(token)
    return token
  }
}

private final class Rig {
  let scheduler = FakeScheduler()
  lazy var coordinator = CameraCoordinator(scheduler: scheduler, timeout: 1)
  var stops: [(CameraOwner, (Bool) -> Void)] = []
  var outcomes: [String: [CameraRequestOutcome]] = [:]
  var requests: [String: CameraRequestID] = [:]

  @discardableResult
  func request(_ name: String, _ owner: CameraOwner,
               then: ((CameraRequestOutcome) -> Void)? = nil) -> CameraRequestID {
    let id = coordinator.request(owner: owner, stop: { [unowned self] ack in
      self.stops.append((owner, ack))
    }, completion: { [unowned self] result in
      self.outcomes[name, default: []].append(result)
      then?(result)
    })
    requests[name] = id
    return id
  }

  func lease(_ name: String) -> CameraLeaseID {
    guard case .granted(let lease)? = outcomes[name]?.first else {
      expect(false, "\(name) has no lease"); fatalError("unreachable")
    }
    return lease
  }

  func failed(_ name: String, _ reason: CameraFailure) {
    expect(outcomes[name] == [.failed(reason)], "\(name) should fail exactly once: \(reason)")
  }
}

@main
private struct VerifyCameraCoordinator {
  static func main() {
    let checks: [(String, () -> Void)] = [
      ("initial acquisition and exact currentness", {
        let r = Rig(); r.request("A", .vision)
        expect(r.coordinator.isCurrent(r.lease("A")), "initial lease")
        expect(r.outcomes["A"]?.count == 1 && r.stops.isEmpty, "one initial completion, no stop")
      }),
      ("handoff waits for exact physical stop", {
        let r = Rig(); r.request("A", .vision); let a = r.lease("A"); r.request("B", .depth)
        expect(!r.coordinator.isCurrent(a) && r.outcomes["B"] == nil, "old invalid, B waits")
        expect(r.stops.count == 1 && r.stops[0].0 == .vision, "stop exact owner")
        r.stops[0].1(true)
        expect(r.coordinator.isCurrent(r.lease("B")), "B granted after acknowledgment")
      }),
      ("supersession preserves one physical stop", {
        let r = Rig(); r.request("A", .vision); r.request("B", .depth); r.request("C", .menu)
        r.failed("B", .superseded); expect(r.stops.count == 1, "one stop for A")
        r.stops[0].1(true); expect(r.coordinator.isCurrent(r.lease("C")), "C current")
      }),
      ("stale request and lease cannot affect new owner", {
        let r = Rig(); let id = r.request("A", .vision); let a = r.lease("A")
        r.request("B", .route); r.stops[0].1(true)
        r.coordinator.release(a); r.coordinator.cancel(id)
        expect(r.coordinator.isCurrent(r.lease("B")) && r.stops.count == 1, "stale controls ignored")
      }),
      ("foreign coordinator identities remain distinct", {
        let a = Rig(); let b = Rig(); let request = a.request("A", .vision); b.request("B", .vision)
        expect(a.lease("A") != b.lease("B"), "foreign leases differ")
        b.coordinator.release(a.lease("A")); b.coordinator.cancel(request)
        expect(b.coordinator.isCurrent(b.lease("B")) && b.stops.isEmpty, "foreign controls ignored")
      }),
      ("timeout retains gate and late ack does not resume", {
        let r = Rig(); r.request("A", .vision); r.request("B", .depth)
        r.scheduler.tokens.last!.fire(); r.failed("B", .timedOut)
        r.request("C", .menu); r.failed("C", .physicalStopFailed)
        r.stops[0].1(true); expect(r.coordinator.currentStatus == .idle, "late ack frees gate")
        r.request("D", .route); expect(r.coordinator.isCurrent(r.lease("D")), "explicit fresh start")
        expect(r.outcomes["B"]?.count == 1, "B never resumed")
      }),
      ("failed stop can later be positively acknowledged", {
        let r = Rig(); r.request("A", .vision); r.request("B", .depth)
        r.stops[0].1(false); r.failed("B", .physicalStopFailed)
        r.stops[0].1(false); r.stops[0].1(true)
        expect(r.coordinator.currentStatus == .idle && r.outcomes["B"]?.count == 1, "late ack after fail")
      }),
      ("release closes gate until acknowledgment", {
        let r = Rig(); r.request("A", .vision); r.coordinator.release(r.lease("A")); r.request("B", .menu)
        expect(r.stops.count == 1 && r.outcomes["B"] == nil, "release not physical ack")
        r.stops[0].1(true); expect(r.coordinator.isCurrent(r.lease("B")), "B after release ack")
      }),
      ("cancel granted request invalidates its exact lease", {
        let r = Rig(); let id = r.request("A", .vision); let a = r.lease("A")
        r.coordinator.cancel(id); expect(!r.coordinator.isCurrent(a) && r.stops.count == 1, "granted cancel stops")
        r.stops[0].1(true); expect(r.outcomes["A"]?.count == 1, "grant completed only once")
      }),
      ("cancel pending request retains gate", {
        let r = Rig(); r.request("A", .vision); let b = r.request("B", .depth)
        r.coordinator.cancel(b); r.coordinator.cancel(b); r.failed("B", .cancelled)
        r.request("C", .menu); expect(r.stops.count == 1, "cancel preserves A stop")
        r.stops[0].1(true); expect(r.coordinator.isCurrent(r.lease("C")), "C after ack")
      }),
      ("background stops active owner without auto-resume", {
        let r = Rig(); r.request("A", .vision); r.coordinator.enterBackground(); r.coordinator.enterBackground()
        expect(r.stops.count == 1 && !r.coordinator.isCurrent(r.lease("A")), "background stop once")
        r.request("B", .depth); r.failed("B", .backgrounded)
        r.coordinator.enterForeground(); expect(r.coordinator.currentStatus != .idle, "foreground keeps gate")
        r.stops[0].1(true); expect(r.coordinator.currentStatus == .idle, "no automatic start")
        r.request("C", .route); expect(r.coordinator.isCurrent(r.lease("C")), "manual restart")
      }),
      ("background cancels waiting request", {
        let r = Rig(); r.request("A", .vision); r.request("B", .depth); r.coordinator.enterBackground()
        r.failed("B", .backgrounded); r.stops[0].1(true); r.coordinator.enterForeground()
        expect(r.coordinator.currentStatus == .idle, "background wait not revived")
      }),
      ("duplicate old acknowledgments preserve newer lease", {
        let r = Rig(); r.request("A", .vision); r.request("B", .depth); r.stops[0].1(true)
        r.request("C", .route); r.stops[0].1(true); expect(r.outcomes["C"] == nil, "old ack cannot grant C")
        r.stops[1].1(true); r.stops[0].1(true); r.stops[1].1(false)
        expect(r.coordinator.isCurrent(r.lease("C")), "new owner remains current")
      }),
      ("cancelled timer cannot affect later stop", {
        let r = Rig(); r.request("A", .vision); r.request("B", .depth); let old = r.scheduler.tokens[0]
        r.stops[0].1(true); expect(old.cancelled, "timer cancelled on ack")
        r.request("C", .menu); old.callback()
        expect(r.outcomes["C"] == nil, "stale timeout cannot fail current waiter")
        r.stops[1].1(true); expect(r.coordinator.isCurrent(r.lease("C")), "C granted normally")
      }),
      ("supersession completion reentry preserves newest request", {
        let r = Rig(); r.request("A", .vision)
        r.request("B", .depth) { outcome in
          if outcome == .failed(.superseded) { r.request("D", .route) }
        }
        r.request("C", .menu); r.failed("B", .superseded); r.failed("C", .superseded)
        r.stops[0].1(true); expect(r.coordinator.isCurrent(r.lease("D")), "reentrant D must win")
      }),
      ("cancel completion reentry preserves new waiter", {
        let r = Rig(); r.request("A", .vision)
        let id = r.request("B", .depth) { outcome in
          if outcome == .failed(.cancelled) { r.request("C", .route) }
        }
        r.coordinator.cancel(id); r.stops[0].1(true)
        expect(r.coordinator.isCurrent(r.lease("C")), "cancel callback's C not erased")
      }),
      ("timeout completion can acknowledge then request", {
        let r = Rig(); r.request("A", .vision)
        r.request("B", .depth) { outcome in
          if outcome == .failed(.timedOut) { r.stops[0].1(true); r.request("C", .route) }
        }
        r.scheduler.tokens[0].fire()
        expect(r.coordinator.isCurrent(r.lease("C")), "timeout callback new lease retained")
      }),
      ("synchronous adapter ack and request reentry", {
        let scheduler = FakeScheduler(); let c = CameraCoordinator(scheduler: scheduler)
        var outcomes: [CameraLeaseID] = []
        c.request(owner: .vision, stop: { ack in
          ack(true)
          c.request(owner: .route, stop: { $0(true) }) { if case .granted(let l) = $0 { outcomes.append(l) } }
        }) { if case .granted(let l) = $0 { outcomes.append(l) } }
        c.request(owner: .depth, stop: { $0(true) }) { if case .granted(let l) = $0 { outcomes.append(l) } }
        expect(outcomes.count == 3 && c.isCurrent(outcomes.last!), "sync stop reentry latest owner")
      }),
      ("grant callback can release synchronously", {
        let r = Rig(); r.request("A", .vision) { if case .granted(let l) = $0 { r.coordinator.release(l) } }
        expect(r.stops.count == 1 && !r.coordinator.isCurrent(r.lease("A")), "grant callback release retained")
        r.stops[0].1(true); expect(r.coordinator.currentStatus == .idle, "sync release completed")
      }),
      ("all owners use their own granted stop adapter", {
        let r = Rig()
        for (index, owner) in CameraOwner.allCases.enumerated() {
          r.request("owner\(index)", owner)
          if index > 0 { r.stops[index - 1].1(true) }
          expect(r.coordinator.isCurrent(r.lease("owner\(index)")), "owner current")
        }
        expect(r.stops.map { $0.0 } == [.vision, .depth, .menu], "exact old adapters")
      }),
      ("lease client cancellation waits for hardware and replies once", {
        let scheduler = FakeScheduler(); let c = CameraCoordinator(scheduler: scheduler)
        var ack: ((Bool) -> Void)?; var invalidated = 0; var ready: [Bool] = []; var stopped: [Bool] = []
        let client = CameraLeaseClient(owner: .vision, coordinator: c) { invalidated += 1 }
        client.acquire(stop: { ack = $0 }) { ready.append($0) }
        expect(client.isCurrent && ready == [true], "client acquired")
        client.cancel { stopped.append($0) }; client.cancel { stopped.append($0) }
        expect(!client.isCurrent && stopped.isEmpty && invalidated == 1, "stop outstanding")
        ack?(true); ack?(true)
        expect(stopped == [true, true] && c.currentStatus == .idle, "one reply for each stop observer")
      }),
      ("released client retains stop reply until physical acknowledgment", {
        let c = CameraCoordinator(scheduler: FakeScheduler())
        var ack: ((Bool) -> Void)?; var stopped: [Bool] = []
        var client: CameraLeaseClient? = CameraLeaseClient(owner: .vision, coordinator: c)
        client?.acquire(stop: { ack = $0 }) { _ in }
        weak var retained = client
        client?.cancel { stopped.append($0) }
        client = nil
        expect(retained != nil && stopped.isEmpty, "pending stop retains client")
        ack?(true)
        expect(stopped == [true] && c.currentStatus == .idle, "released client still replies")
        ack = nil
        expect(retained == nil, "client released after hardware callback")
        retained = nil
      }),
      ("dropped hardware callback still delivers timeout after client release", {
        let scheduler = FakeScheduler(); let c = CameraCoordinator(scheduler: scheduler)
        var stopped: [Bool] = []
        var client: CameraLeaseClient? = CameraLeaseClient(owner: .vision, coordinator: c)
        client?.acquire(stop: { _ in }) { _ in }
        weak var retained = client
        client?.cancel { stopped.append($0) }
        client = nil
        expect(retained != nil && stopped.isEmpty, "client retained until timeout")
        scheduler.tokens[0].fire()
        expect(stopped == [false] && retained == nil, "timeout replies and releases client")
        retained = nil
        if case .blockedUnconfirmed = c.currentStatus {} else { expect(false, "gate stays blocked") }
      }),
      ("late permission cannot start a cancelled client", {
        let c = CameraCoordinator(scheduler: FakeScheduler()); var ack: ((Bool) -> Void)?; var starts = 0
        let client = CameraLeaseClient(owner: .vision, coordinator: c)
        client.acquire(stop: { ack = $0 }) { _ in }
        let permissionReply = { if client.isCurrent { starts += 1 } }
        client.cancel(); ack?(true); permissionReply()
        expect(starts == 0, "late permission rejected")
      }),
      ("cancel queued client without inventing hardware stop", {
        let r = Rig(); r.request("A", .vision)
        var ready: [Bool] = []; var stopCalls = 0; var cancelled: [Bool] = []
        let client = CameraLeaseClient(owner: .menu, coordinator: r.coordinator)
        client.acquire(stop: { _ in stopCalls += 1 }) { ready.append($0) }
        client.cancel { cancelled.append($0) }; r.stops[0].1(true)
        expect(ready == [false] && cancelled == [true] && stopCalls == 0, "queued cancellation")
        expect(r.coordinator.currentStatus == .idle, "cancelled client never granted")
      }),
      ("client revoked by another owner awaits the same stop", {
        let c = CameraCoordinator(scheduler: FakeScheduler()); var ack: ((Bool) -> Void)?
        var invalidated = 0; var stopped: [Bool] = []; var next: CameraLeaseID?
        let client = CameraLeaseClient(owner: .vision, coordinator: c) { invalidated += 1 }
        client.acquire(stop: { ack = $0 }) { _ in }
        c.request(owner: .depth, stop: { $0(true) }) { if case .granted(let l) = $0 { next = l } }
        client.cancel { stopped.append($0) }
        expect(next == nil && stopped.isEmpty && invalidated == 1, "revoked client awaiting stop")
        ack?(true)
        expect(next.map(c.isCurrent) == true && stopped == [true], "next granted after same ack")
      }),
      ("client stop timeout reports unconfirmed without freeing gate", {
        let scheduler = FakeScheduler(); let c = CameraCoordinator(scheduler: scheduler)
        var ack: ((Bool) -> Void)?; var stopped: [Bool] = []
        let client = CameraLeaseClient(owner: .route, coordinator: c)
        client.acquire(stop: { ack = $0 }) { _ in }
        client.cancel { stopped.append($0) }; scheduler.tokens[0].fire()
        expect(stopped == [false], "bounded stop failure reply")
        var next: CameraRequestOutcome?
        c.request(owner: .menu, stop: { $0(true) }) { next = $0 }
        expect(next == .failed(.physicalStopFailed), "gate remains closed")
        ack?(true)
        expect(stopped == [false] && c.currentStatus == .idle, "late ack not a second reply")
      }),
      ("client physical failure and late positive ack", {
        let c = CameraCoordinator(scheduler: FakeScheduler()); var ack: ((Bool) -> Void)?; var stopped: [Bool] = []
        let client = CameraLeaseClient(owner: .route, coordinator: c)
        client.acquire(stop: { ack = $0 }) { _ in }
        client.cancel { stopped.append($0) }; ack?(false); ack?(true)
        expect(stopped == [false] && c.currentStatus == .idle, "failed stop later acknowledged")
      }),
      ("one-shot native reply is safe under reentry", {
        var results: [Int] = []; var reply: CameraOnceReply<Int>!
        reply = CameraOnceReply { value in results.append(value); reply.finish(2) }
        reply.finish(1); reply.finish(3)
        expect(results == [1], "native reply consumed before callback")
      }),
      ("ready callback can immediately cancel its acquisition", {
        let c = CameraCoordinator(scheduler: FakeScheduler()); var ack: ((Bool) -> Void)?; var ready: [Bool] = []
        let client = CameraLeaseClient(owner: .vision, coordinator: c)
        client.acquire(stop: { ack = $0 }) { granted in ready.append(granted); client.cancel() }
        expect(ready == [true] && !client.isCurrent && ack != nil, "inline ready cancellation")
        ack?(true); expect(c.currentStatus == .idle, "no orphan acquisition after inline cancel")
      }),
    ]
    for (name, check) in checks { check(); print("PASS: \(name)") }
    print("PASS \(checks.count) camera ownership scenarios")
  }
}
