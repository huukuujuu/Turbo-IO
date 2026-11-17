import Foundation

@main struct AnswerReadingTests {
    static func main() {
        func fixture(_ length: Int, completion: Double = 2) -> (StandbyVoiceSession, () -> [StandbyVoiceSession.Command]) {
            let session = StandbyVoiceSession()
            var sent: [StandbyVoiceSession.Command] = []
            session.send = { _, command in sent.append(command); return true }
            session.cloudEnabled = true; session.continuousASREnabled = true; session.vadEnabled = true
            session.enable(target: "synthetic", connected: true)
            session.receive(from: "synthetic", type: 1, audioBytes: 0, now: 0)
            let id = session.cloudRoundID!
            session.cloudEndpoint(id: id, now: 1)
            for offset in stride(from: 0, to: length, by: 20) {
                session.cloudText(String(repeating: "가", count: min(20, length-offset)), final: false, id: id, now: completion)
            }
            session.cloudComplete(id: id, now: completion)
            return (session, { sent })
        }
        func tick(_ session: StandbyVoiceSession, _ time: Double) {
            session.receive(from: "synthetic", type: 3, audioBytes: 100, now: time)
            session.tick(now: time)
        }
        for length in [40, 64, 100, 360, 370, 382, 800] {
            let (session, commands) = fixture(length)
            tick(session, 12)
            precondition(session.phase == .displaying)
            precondition(!commands().contains(.stopAudio) && !commands().contains(.exit))
            let stream = session.cloudSessionID!, next = UUID()
            session.cloudUtteranceBegan(id: next, session: stream, now: 13)
            precondition(session.phase == .recording && session.cloudRoundID == next)
            tick(session, 32); precondition(session.phase == .recording)
        }
        let (long, commands) = fixture(380)
        tick(long, 28)
        long.receive(from: "synthetic", type: 11, audioBytes: 0, now: 28)
        long.receive(from: "synthetic", type: 11, audioBytes: 0, now: 35)
        tick(long, 37); precondition(long.phase == .displaying)
        tick(long, 38)
        precondition(long.phase == .idle && commands().filter { $0 == .exit }.count == 1)
        let (fallback, _) = fixture(500)
        tick(fallback, 101); precondition(fallback.phase == .displaying)
        tick(fallback, 102); precondition(fallback.phase == .idle)
        let (lostAudio, _) = fixture(500)
        lostAudio.tick(now: 12); precondition(lostAudio.phase == .reading)
        lostAudio.receive(from: "synthetic", type: 11, audioBytes: 0, now: 13)
        precondition(lostAudio.phase == .recording && lostAudio.cloudSessionID != nil)
        let (dismissed, dismissedCommands) = fixture(500)
        tick(dismissed, 12)
        dismissed.receive(from: "synthetic", type: 8, audioBytes: 0, now: 13)
        precondition(dismissed.phase == .idle && !dismissedCommands().contains(.exit))
        let (capped, _) = fixture(1000, completion: 119)
        tick(capped, 120); precondition(capped.phase == .reading)
        capped.tick(now: 238); precondition(capped.phase == .reading)
        capped.tick(now: 239); precondition(capped.phase == .idle)
        print("Answer turn checks passed: 7 lengths, barge-in after 10s, next-turn timeout, duplicate event, fallback, capture recovery, manual exit, session cap.")
    }
}
