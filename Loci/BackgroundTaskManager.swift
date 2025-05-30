import UIKit

final class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()
    private init() {}

    private var tasks: [UIBackgroundTaskIdentifier] = []

    /// Begins a new background task and returns its identifier.
    func beginTask(_ name: String = "LociTracking") -> UIBackgroundTaskIdentifier {
        let id = UIApplication.shared.beginBackgroundTask(withName: name) {
            // expiration handler: end the task if time expires
            self.endTask(id)
        }
        tasks.append(id)
        return id
    }

    /// Ends the given background task.
    func endTask(_ id: UIBackgroundTaskIdentifier) {
        UIApplication.shared.endBackgroundTask(id)
        tasks.removeAll { $0 == id }
    }

    /// Ends all outstanding tasks (safe to call on teardown).
    func endAllTasks() {
        tasks.forEach { UIApplication.shared.endBackgroundTask($0) }
        tasks.removeAll()
    }
}

