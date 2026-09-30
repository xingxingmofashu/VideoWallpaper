import Foundation

final class SignalHandler {
    private var sources: [DispatchSourceSignal] = []

    init(signals: [Int32], onSignal: @escaping () -> Void) {
        for sig in signals {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                onSignal()
            }
            source.resume()
            sources.append(source)
        }
    }
}
