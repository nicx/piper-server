import Foundation
import UserNotifications

/// Debounced desktop notifications: one "abgestürzt" per down-episode and one
/// "wieder aktiv" when it recovers, instead of one per auto-restart attempt.
@MainActor
final class Notifier {
    private var serverDown = false

    func report(serverHealthy healthy: Bool, detail: String = "") {
        if healthy {
            guard serverDown else { return }
            serverDown = false
            post(title: "Piper wieder aktiv", body: "Der Sprachdienst läuft wieder.")
        } else {
            guard !serverDown else { return }
            serverDown = true
            post(title: "Piper abgestürzt", body: detail.isEmpty ? "Der Sprachdienst wurde beendet." : detail)
        }
    }

    /// Reset without notifying — used for a deliberate stop.
    func clear() {
        serverDown = false
    }

    func oneShot(title: String, body: String) {
        post(title: title, body: body)
    }

    private func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
