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
        let schema = ModelSchema([Session.self, ListeningEvent.self])
        self.container = ModelContainer(schema: schema)
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

    private func fetchSessionHistory() {
        Task { @MainActor in
            let query = Query<Session>().sorted(by: \Session.startTime, order: .descending)
            sessionHistory = (try? container.mainContext.fetch(query)) ?? []
        }
    }

    // MARK: - Export Utilities

    func exportSessionAsJSON(_ session: Session) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(session)
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

