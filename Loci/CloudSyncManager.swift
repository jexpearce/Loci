import Foundation
import CloudKit

/// Syncs ListeningEvent records to CloudKit, with offline caching
final class CloudSyncManager {
    static let shared = CloudSyncManager()
    private let database: CKDatabase
    private var pendingEvents: [UUID: ListeningEvent] = [:]
    private let queue = DispatchQueue(label: "com.loci.cloudsync")

    private init(container: CKContainer = .default()) {
        self.database = container.publicCloudDatabase
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAccountChange),
            name: .CKAccountChanged,
            object: nil
        )
        syncPendingEvents()
    }

    /// Enqueue an event for sync; will retry until successful
    func enqueueEvent(_ event: ListeningEvent) {
        queue.async {
            self.pendingEvents[event.id] = event
            self.syncPendingEvents()
        }
    }

    /// Attempts to send all pending events to CloudKit
    private func syncPendingEvents() {
        for (id, event) in pendingEvents {
            let recordID = CKRecord.ID(recordName: id.uuidString)
            let record = CKRecord(recordType: "ListeningEvent", recordID: recordID)
            record["timestamp"] = event.timestamp as CKRecordValue
            record["latitude"] = event.latitude as CKRecordValue
            record["longitude"] = event.longitude as CKRecordValue
            record["buildingName"] = event.buildingName as CKRecordValue?
            record["trackName"] = event.trackName as CKRecordValue
            record["artistName"] = event.artistName as CKRecordValue
            record["albumName"] = event.albumName as CKRecordValue?
            record["genre"] = event.genre as CKRecordValue?
            record["spotifyTrackId"] = event.spotifyTrackId as CKRecordValue

            database.save(record) { [weak self] _, error in
                guard let self = self else { return }
                if let error = error {
                    print("[CloudSyncManager] error saving event \(id): \(error)")
                } else {
                    // Remove on success
                    self.queue.async {
                        self.pendingEvents.removeValue(forKey: id)
                    }
                }
            }
        }
    }

    @objc private func handleAccountChange() {
        syncPendingEvents()
    }
}
