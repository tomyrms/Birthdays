import SwiftUI
import WidgetKit

@main
struct BirthdaysApp: App {
    @StateObject private var store = BirthdayStore()
    @StateObject private var notificationRouter = NotificationRouter.shared
    @AppStorage(BirthdayAccent.storageKey) private var accentHex = BirthdayAccent.defaultHex

    var body: some Scene {
        WindowGroup {
            BirthdayHomeView()
                .environmentObject(store)
                .environmentObject(notificationRouter)
                .tint(BirthdayAccent.color(for: accentHex))
                .task {
                    // Une seule explosion par lancement de process, ici et pas
                    // dans une vue interne : changer de teinte ou revenir d'un
                    // sheet ne doit pas la redéclencher. Et uniquement s'il y a
                    // effectivement un anniversaire à fêter aujourd'hui.
                    LaunchCelebration.shared.fireOnce(hasBirthdayToday: store.hasBirthdayToday)
                    BirthdayAccent.publishToSharedStorage(accentHex)
                    // La timeline reste valide jusqu'à minuit : sans ce
                    // rechargement, un widget mis à jour continue d'afficher le
                    // rendu produit par la version précédente de l'app.
                    WidgetCenter.shared.reloadAllTimelines()
                    notificationRouter.start()
                    // L'autorisation doit être demandée au lancement : sans elle,
                    // la planification est ignorée en silence et aucun rappel
                    // n'arrive tant que l'écran Rappels n'a pas été ouvert.
                    _ = await NotificationScheduler.shared.requestAuthorizationIfNeeded()
                    await store.rescheduleNotifications()
                }
        }
    }
}
