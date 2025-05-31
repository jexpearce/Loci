import UIKit
import BackgroundTasks

       // <- keep @main ONLY if you remove @main from LociApp
class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {

        // Register early, exactly once
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.loci.sessionUpdate",
            using: nil
        ) { task in
            // Forward the work to SessionManager
            SessionManager.shared.handleBackgroundTask(task: task)
        }

        return true
    }
}
