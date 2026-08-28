import Foundation
import UIKit
import UserNotifications

/// Reçoit les notifications pendant que l'app est au premier plan et route les
/// appuis vers la fiche concernée. Sans ce délégué, iOS masque les alertes
/// quand l'app est ouverte et un appui sur la notification ne fait rien.
@MainActor
final class NotificationRouter: NSObject, ObservableObject {
    static let shared = NotificationRouter()

    @Published var pendingBirthdayID: UUID?
    @Published var pendingAddRequest = false

    func start() {
        UNUserNotificationCenter.current().delegate = self
    }
}

extension NotificationRouter: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let raw = userInfo["birthdayID"] as? String,
              let id = UUID(uuidString: raw) else { return }
        await MainActor.run {
            NotificationRouter.shared.pendingBirthdayID = id
        }
    }
}
