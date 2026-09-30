import Foundation

final class SignalHandler {
    private var sources: [DispatchSourceSignal] = []

    init(signals: [Int32], onSignal: @escaping (Int32) -> Void) {
        for sig in signals {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                onSignal(sig)
            }
            source.resume()
            sources.append(source)
        }
    }
}
