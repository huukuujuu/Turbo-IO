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
            for _ in 0..<length / 20 {
                session.cloudText(String(repeating: "가", count: 20), final: false, id: id, now: completion)
            }
            session.cloudComplete(id: id, now: completion)
            return (session, { sent })
        }
        let (long, commands) = fixture(500)
        long.receive(from: "synthetic", type: 3, audioBytes: 100, now: 11)
        long.tick(now: 12)
        precondition(long.phase == .reading)
        precondition(commands().filter { $0 == .stopAudio }.count == 1)
        precondition(!commands().contains(.exit) && !commands().contains(.vadTimeout))
        long.audioFailed()
        precondition(long.phase == .reading)
        long.tick(now: 101)
        precondition(long.phase == .reading)
        long.tick(now: 102)
        precondition(long.phase == .idle && commands().filter { $0 == .exit }.count == 1)

        let (short, _) = fixture(20)
        short.tick(now: 12); short.tick(now: 31)
        precondition(short.phase == .reading)
        short.tick(now: 32); precondition(short.phase == .idle)

        let (interrupted, _) = fixture(500)
        interrupted.tick(now: 12)
        interrupted.receive(from: "synthetic", type: 1, audioBytes: 0, now: 13)
        precondition(interrupted.phase == .recording)

        let (dismissed, dismissedCommands) = fixture(500)
        dismissed.tick(now: 12)
        dismissed.receive(from: "synthetic", type: 8, audioBytes: 0, now: 13)
        precondition(dismissed.phase == .idle && !dismissedCommands().contains(.exit))

        let (capped, _) = fixture(1000, completion: 119)
        capped.tick(now: 120)
        precondition(capped.phase == .reading)
        capped.tick(now: 298); precondition(capped.phase == .reading)
        capped.tick(now: 299); precondition(capped.phase == .idle)
        print("Answer reading checks passed: long/short retention, microphone stop, new wake, manual exit, session cap.")
    }
}
