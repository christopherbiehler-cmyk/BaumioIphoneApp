import MetricKit
import OSLog

/// Empfängt MetricKit-Diagnosen (Abstürze, Hänger, Performance) von iOS.
/// Daten erscheinen im Xcode Organizer → Crashes & Energy, nachdem Nutzer sie via
/// TestFlight oder den App Store übermitteln.
final class BaumioMetricSubscriber: NSObject, MXMetricManagerSubscriber {
    static let shared = BaumioMetricSubscriber()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "de.baumio", category: "MetricKit")

    private override init() { super.init() }

    func register() {
        MXMetricManager.shared.add(self)
    }

    // Allgemeine Performance-Metriken (Startzeit, Energie, Netzwerk, …)
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            logger.info("📊 MetricKit Metriken empfangen (Zeitraum: \(payload.timeStampBegin, privacy: .public) – \(payload.timeStampEnd, privacy: .public))")
        }
    }

    // Crash- und Hang-Diagnosen (ab iOS 14)
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            if let crashes = payload.crashDiagnostics, !crashes.isEmpty {
                for crash in crashes {
                    logger.error("💥 Crash: \(crash.callStackTree.jsonRepresentation(), privacy: .public)")
                    let stack = String(decoding: crash.callStackTree.jsonRepresentation(), as: UTF8.self)
                    ErrorLogger.report(
                        .error,
                        context: "metrickit.crash",
                        message: "Absturz: Exception \(crash.exceptionType?.intValue ?? -1), Signal \(crash.signal?.intValue ?? -1), App \(crash.applicationVersion)",
                        details: "Beendigungsgrund: \(crash.terminationReason ?? "-")\n\(String(stack.prefix(8000)))"
                    )
                }
            }
            if let hangs = payload.hangDiagnostics, !hangs.isEmpty {
                logger.warning("⏳ \(hangs.count, privacy: .public) Hang(s) gemeldet")
                for hang in hangs {
                    let seconds = hang.hangDuration.converted(to: .seconds).value
                    let stack = String(decoding: hang.callStackTree.jsonRepresentation(), as: UTF8.self)
                    ErrorLogger.report(
                        .error,
                        context: "metrickit.hang",
                        message: "Hang von \(Int(seconds)) s, App \(hang.applicationVersion)",
                        details: String(stack.prefix(8000))
                    )
                }
            }
            if let diskWrites = payload.diskWriteExceptionDiagnostics, !diskWrites.isEmpty {
                logger.warning("💾 Übermäßige Disk-Schreibvorgänge: \(diskWrites.count, privacy: .public)")
            }
        }
    }
}
