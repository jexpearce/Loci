//
//  NotificationManager.swift
//  Loci
//
//  Created by Jex Pearce on 30/05/2025.
//
import Foundation
import UserNotifications
import CoreLocation

class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published var isNotificationEnabled = false
    @Published var scheduledReminders: [SessionReminder] = []
    
    let notificationCenter = UNUserNotificationCenter.current()
    private let userDefaults = UserDefaults.standard
    
    // Notification identifiers
    private let sessionReminderPrefix = "com.loci.sessionReminder"
    private let sessionEndPrefix = "com.loci.sessionEnd"
    private let matchAlertPrefix = "com.loci.matchAlert"
    private let achievementPrefix = "com.loci.achievement"
    
    private override init() {
        super.init()
        notificationCenter.delegate = self
        checkNotificationStatus()
        loadScheduledReminders()
    }
    
    // MARK: - Permission Management
    
    func requestNotificationPermission() {
        notificationCenter.requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.isNotificationEnabled = granted
                if granted {
                    self?.setupNotificationCategories()
                }
            }
            
            if let error = error {
                print("❌ Notification permission error: \(error)")
            }
        }
    }
    
    private func checkNotificationStatus() {
        notificationCenter.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.isNotificationEnabled = settings.authorizationStatus == .authorized
            }
        }
    }
    
    // MARK: - Notification Categories
    
    private func setupNotificationCategories() {
        // Session reminder actions
        let startSessionAction = UNNotificationAction(
            identifier: "START_SESSION",
            title: "Start Session",
            options: [.foreground]
        )
        
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_REMINDER",
            title: "Remind in 1 hour",
            options: []
        )
        
        let sessionReminderCategory = UNNotificationCategory(
            identifier: "SESSION_REMINDER",
            actions: [startSessionAction, snoozeAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        // Match alert actions
        let viewMatchAction = UNNotificationAction(
            identifier: "VIEW_MATCH",
            title: "View Match",
            options: [.foreground]
        )
        
        let matchAlertCategory = UNNotificationCategory(
            identifier: "MATCH_ALERT",
            actions: [viewMatchAction],
            intentIdentifiers: [],
            options: []
        )
        
        notificationCenter.setNotificationCategories([sessionReminderCategory, matchAlertCategory])
    }
    
    // MARK: - Session Notifications
    
    func scheduleSessionReminder(at date: Date, title: String? = nil) {
        let reminder = SessionReminder(
            id: UUID(),
            scheduledTime: date,
            title: title ?? "Time to start a Loci session!",
            isRecurring: false
        )
        
        scheduleNotification(for: reminder)
        
        // Save to scheduled reminders
        scheduledReminders.append(reminder)
        saveScheduledReminders()
    }
    
    func scheduleRecurringReminder(timeOfDay: DateComponents, days: Set<Int>, title: String? = nil) {
        // days: 1 = Sunday, 7 = Saturday
        for day in days {
            var components = timeOfDay
            components.weekday = day
            
            let reminder = SessionReminder(
                id: UUID(),
                scheduledTime: nextDate(matching: components) ?? Date(),
                title: title ?? "Start your daily Loci session 🎵",
                isRecurring: true,
                recurrenceRule: RecurrenceRule(timeComponents: timeOfDay, weekdays: days)
            )
            
            scheduleNotification(for: reminder)
            scheduledReminders.append(reminder)
        }
        
        saveScheduledReminders()
    }
    
    private func scheduleNotification(for reminder: SessionReminder) {
        let content = UNMutableNotificationContent()
        content.title = "Loci"
        content.body = reminder.title
        content.categoryIdentifier = "SESSION_REMINDER"
        content.sound = .default
        content.badge = 1
        
        // Add custom data
        content.userInfo = [
            "reminderId": reminder.id.uuidString,
            "type": "sessionReminder"
        ]
        
        let trigger: UNNotificationTrigger
        
        if reminder.isRecurring, let rule = reminder.recurrenceRule {
            // Create recurring trigger
            trigger = UNCalendarNotificationTrigger(dateMatching: rule.timeComponents, repeats: true)
        } else {
            // One-time trigger
            trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: reminder.scheduledTime.timeIntervalSinceNow,
                repeats: false
            )
        }
        
        let request = UNNotificationRequest(
            identifier: "\(sessionReminderPrefix).\(reminder.id.uuidString)",
            content: content,
            trigger: trigger
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("❌ Failed to schedule notification: \(error)")
            } else {
                print("✅ Scheduled reminder for \(reminder.scheduledTime)")
            }
        }
    }
    
    // MARK: - Session End Notifications
    
    func notifySessionEnded(_ session: SessionData, analytics: SessionAnalytics) {
        let content = UNMutableNotificationContent()
        content.title = "Session Complete! 🎉"
        content.body = "You listened to \(analytics.totalTracks) tracks across \(analytics.uniqueLocations) locations"
        content.sound = .default
        
        // Add detailed summary
        if let topArtist = analytics.topArtist {
            content.subtitle = "Top artist: \(topArtist)"
        }
        
        content.userInfo = [
            "sessionId": session.id.uuidString,
            "type": "sessionEnd"
        ]
        
        let request = UNNotificationRequest(
            identifier: "\(sessionEndPrefix).\(session.id.uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        
        notificationCenter.add(request)
    }
    // MARK: - Match Notifications
    
    func notifyNewMatch(_ match: Match, userName: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = "New Match! \(match.matchType.emoji)"
        
        switch match.matchType {
        case .strong:
            content.body = "You have a strong music connection with someone!"
        case .musicTwin:
            content.body = "Found your music twin! 🎵"
        case .neighbor:
            content.body = "Someone near you shares your music taste!"
        case .scheduleMatch:
            content.body = "Found someone who listens at the same times as you!"
        case .casual:
            content.body = "New music connection discovered!"
        }
        
        content.categoryIdentifier = "MATCH_ALERT"
        content.sound = UNNotificationSound(named: UNNotificationSoundName("match_sound.wav"))
        
        content.userInfo = [
            "matchId": match.userId.uuidString,
            "type": "match",
            "matchType": String(describing: match.matchType)
        ]
        
        let request = UNNotificationRequest(
            identifier: "\(matchAlertPrefix).\(match.userId.uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        
        notificationCenter.add(request)
    }
    
    // MARK: - Achievement Notifications
    
    func notifyAchievement(_ achievement: Achievement) {
        let content = UNMutableNotificationContent()
        content.title = "Achievement Unlocked! \(achievement.badge)"
        content.body = achievement.description
        content.sound = UNNotificationSound(named: UNNotificationSoundName("achievement_sound.wav"))
        
        content.userInfo = [
            "achievementId": achievement.id,
            "type": "achievement"
        ]
        
        let request = UNNotificationRequest(
            identifier: "\(achievementPrefix).\(achievement.id)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        
        notificationCenter.add(request)
    }
    
    // MARK: - Leaderboard Notifications
    
    func showLeaderboardSyncNotification(privacyLevel: LeaderboardPrivacyLevel, scopes: [LocationScope]) {
        guard isNotificationEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Leaderboards Updated! 🏆"
        
        let scopeText = scopes.map { $0.displayName.lowercased() }.joined(separator: " & ")
        let privacyText = privacyLevel.showsRealName ? "with your name" : "anonymously"
        
        content.body = "Your music data is now shared \(privacyText) on \(scopeText) leaderboards"
        content.sound = .default
        
        content.userInfo = [
            "type": "leaderboardSync",
            "privacyLevel": privacyLevel.rawValue
        ]
        
        let request = UNNotificationRequest(
            identifier: "leaderboard.sync.\(Date().timeIntervalSince1970)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        )
        
        notificationCenter.add(request)
    }
    
    func showImportSuccessNotification(trackCount: Int, location: String) {
        guard isNotificationEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Import Complete! 📱"
        content.body = "Added \(trackCount) tracks to \(location)"
        content.sound = .default
        
        content.userInfo = [
            "type": "importSuccess",
            "trackCount": trackCount
        ]
        
        let request = UNNotificationRequest(
            identifier: "import.success.\(Date().timeIntervalSince1970)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        
        notificationCenter.add(request)
    }
    
    // MARK: - Location-Based Notifications
    
    func scheduleLocationReminder(for location: CLLocation, radius: CLLocationDistance, message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Loci Location Alert"
        content.body = message
        content.sound = .default
        content.categoryIdentifier = "SESSION_REMINDER"
        
        let region = CLCircularRegion(
            center: location.coordinate,
            radius: radius,
            identifier: UUID().uuidString
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false
        
        let trigger = UNLocationNotificationTrigger(region: region, repeats: true)
        
        let request = UNNotificationRequest(
            identifier: "location.\(region.identifier)",
            content: content,
            trigger: trigger
        )
        
        notificationCenter.add(request)
    }
    
    // MARK: - Reminder Management
    
    func cancelReminder(_ reminder: SessionReminder) {
        let identifier = "\(sessionReminderPrefix).\(reminder.id.uuidString)"
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        
        scheduledReminders.removeAll { $0.id == reminder.id }
        saveScheduledReminders()
    }
    
    func cancelAllReminders() {
        notificationCenter.getPendingNotificationRequests { requests in
            let reminderIds = requests
                .filter { $0.identifier.hasPrefix(self.sessionReminderPrefix) }
                .map { $0.identifier }
            
            self.notificationCenter.removePendingNotificationRequests(withIdentifiers: reminderIds)
        }
        
        scheduledReminders.removeAll()
        saveScheduledReminders()
    }
    
    // MARK: - Persistence
    
    private func saveScheduledReminders() {
        if let encoded = try? JSONEncoder().encode(scheduledReminders) {
            userDefaults.set(encoded, forKey: "com.loci.scheduledReminders")
        }
    }
    
    private func loadScheduledReminders() {
        guard let data = userDefaults.data(forKey: "com.loci.scheduledReminders"),
              let decoded = try? JSONDecoder().decode([SessionReminder].self, from: data) else {
            return
        }
        
        scheduledReminders = decoded
    }
    
    // MARK: - Helper Methods
    
    private func nextDate(matching components: DateComponents) -> Date? {
        return Calendar.current.nextDate(
            after: Date(),
            matching: components,
            matchingPolicy: .nextTime
        )
    }
    
    func updateBadgeCount(_ count: Int) {
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().setBadgeCount(count)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notifications even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        
        let userInfo = response.notification.request.content.userInfo
        
        switch response.actionIdentifier {
        case "START_SESSION":
            // Post notification to start session
            NotificationCenter.default.post(name: .startSessionFromNotification, object: nil)
            
        case "SNOOZE_REMINDER":
            // Reschedule for 1 hour later
            if let reminderId = userInfo["reminderId"] as? String,
               let reminder = scheduledReminders.first(where: { $0.id.uuidString == reminderId }) {
                let newDate = Date().addingTimeInterval(3600)
                scheduleSessionReminder(at: newDate, title: reminder.title)
            }
            
        case "VIEW_MATCH":
            // Post notification to view match
            if let matchId = userInfo["matchId"] as? String {
                NotificationCenter.default.post(
                    name: .viewMatchFromNotification,
                    object: nil,
                    userInfo: ["matchId": matchId]
                )
            }
            
        default:
            break
        }
        
        completionHandler()
    }
}

// MARK: - Supporting Types

struct SessionReminder: Identifiable, Codable {
    let id: UUID
    let scheduledTime: Date
    let title: String
    let isRecurring: Bool
    var recurrenceRule: RecurrenceRule?
}

struct RecurrenceRule: Codable {
    let timeComponents: DateComponents
    let weekdays: Set<Int>
}

struct Achievement {
    let id: String
    let title: String
    let description: String
    let badge: String
    let unlockedAt: Date
}

// MARK: - Notification Names

extension Notification.Name {
    static let startSessionFromNotification = Notification.Name("com.loci.startSessionFromNotification")
    static let viewMatchFromNotification = Notification.Name("com.loci.viewMatchFromNotification")
}
