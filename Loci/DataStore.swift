import Foundation
import SwiftData
import Combine
import CloudKit

@MainActor
class DataStore: ObservableObject {
    static let shared = DataStore()

    private let container: ModelContainer

    @Published var currentSessionEvents: [ListeningEvent] = []
    @Published var sessionHistory: [Session] = []

    private init() {
        self.container = try! ModelContainer(
            for: Session.self, ListeningEvent.self
        )
        
        fetchSessionHistory()
    }

    // MARK: - Current Session Management

    func addEvent(_ event: ListeningEvent) {
        Task { @MainActor in
            container.mainContext.insert(event)
            try? container.mainContext.save()    // ① persist immediately
            currentSessionEvents.append(event)
            CloudSyncManager.shared.enqueueEvent(event)  // ② queue it for CloudKit sync
        }
    }

    func clearCurrentSession() {
        Task { @MainActor in
            currentSessionEvents.removeAll()
        }
    }

    // MARK: - Session History Management

    func saveSession(startTime: Date, endTime: Date, duration: SessionDuration) {
        Task { @MainActor in
            let session = Session(startTime: startTime, endTime: endTime, duration: duration, events: currentSessionEvents)
            container.mainContext.insert(session)
            try? container.mainContext.save()

            sessionHistory.insert(session, at: 0)
            clearCurrentSession()
        }
    }
    
    /// Save a SessionData to persistent storage by converting it to a Session model
    func saveSession(_ sessionData: SessionData) {
        Task { @MainActor in
            let session = Session(
                startTime: sessionData.startTime,
                endTime: sessionData.endTime,
                duration: sessionData.duration,
                events: sessionData.events
            )
            session.id = sessionData.id
            container.mainContext.insert(session)
            try? container.mainContext.save()
            sessionHistory.insert(session, at: 0)
            clearCurrentSession()
        }
    }

    private func fetchSessionHistory() {
        Task { @MainActor in
            let descriptor = FetchDescriptor<Session>(
                sortBy: [SortDescriptor(\Session.startTime, order: .reverse)]
            )
            sessionHistory = (try? container.mainContext.fetch(descriptor)) ?? []
        }
    }

    // MARK: - Export Utilities

    func exportSessionAsJSON(_ session: Session) -> Data? {
        let sessionData = SessionData(
            id: session.id,
            startTime: session.startTime,
            endTime: session.endTime,
            duration: session.duration,
            events: session.events
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(sessionData)
    }

    func exportSessionAsCSV(_ session: Session) -> String {
        var csv = "Timestamp,Latitude,Longitude,Building,Track,Artist,Album,Genre\n"
        for event in session.events {
            let row = [
                ISO8601DateFormatter().string(from: event.timestamp),
                String(event.latitude),
                String(event.longitude),
                event.buildingName ?? "",
                event.trackName,
                event.artistName,
                event.albumName ?? "",
                event.genre ?? ""
            ]
            csv += row.map { field in
                let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
                return field.contains(",") ? "\"\(escaped)\"" : escaped
            }.joined(separator: ",") + "\n"
        }
        return csv
    }
}

