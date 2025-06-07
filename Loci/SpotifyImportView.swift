import SwiftUI
import CoreLocation

struct SpotifyImportView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var spotifyManager: SpotifyManager
    @EnvironmentObject var dataStore: DataStore
    
    @State private var selectedImportMode: SpotifyImportMode = .recentTracks
    @State private var selectedLocation: String?
    @State private var showingLocationPicker = false
    @State private var isImporting = false
    @State private var importProgress: Double = 0.0
    @State private var importedTracks: [ImportedTrack] = []
    @State private var showingPreview = false
    
    // Time Range Selection
    @State private var selectedStartDate = Calendar.current.date(byAdding: .hour, value: -6, to: Date()) ?? Date()
    @State private var selectedEndDate = Date()
    
    var body: some View {
        NavigationView {
            ZStack {
                LociTheme.Colors.appBackground
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: LociTheme.Spacing.large) {
                        // Header
                        ImportHeaderView()
                        
                        // Import Mode Selection
                        ImportModeSelectionCard(selectedMode: $selectedImportMode)
                        
                        // Location Assignment
                        LocationAssignmentCard(
                            selectedLocation: $selectedLocation,
                            showingLocationPicker: $showingLocationPicker
                        )
                        
                        // Mode-specific Configuration
                        if selectedImportMode == .timeRange {
                            TimeRangeSelectionCard(
                                startDate: $selectedStartDate,
                                endDate: $selectedEndDate
                            )
                        }
                        
                        // Import Button
                        ImportButton(
                            canImport: canStartImport,
                            isImporting: isImporting,
                            progress: importProgress
                        ) {
                            startImport()
                        }
                        
                        // Preview Section
                        if !importedTracks.isEmpty {
                            ImportPreviewSection(tracks: importedTracks) {
                                saveImportedTracks()
                            }
                        }
                    }
                    .padding(.horizontal, LociTheme.Spacing.medium)
                    .padding(.top, LociTheme.Spacing.medium)
                }
            }
            .navigationTitle("Import from Spotify")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(LociTheme.Colors.subheadText)
                }
            }
        }
        .sheet(isPresented: $showingLocationPicker) {
            LocationSelectionView(selectedLocation: $selectedLocation)
        }
    }
    
    private var canStartImport: Bool {
        spotifyManager.isAuthenticated &&
        selectedLocation != nil &&
        !isImporting
    }
    
    private func startImport() {
        guard canStartImport else { return }
        
        isImporting = true
        importProgress = 0.0
        importedTracks = []
        
        Task {
            await performImport()
        }
    }
    
    private func performImport() async {
        switch selectedImportMode {
        case .recentTracks:
            await importRecentTracks()
        case .timeRange:
            await importTimeRange()
        case .playlist:
            await importPlaylist()
        }
        
        await MainActor.run {
            isImporting = false
            importProgress = 1.0
        }
    }
    
    private func importRecentTracks() async {
        // Import last 50 tracks from Spotify
        let endTime = Date()
        let startTime = Calendar.current.date(byAdding: .hour, value: -6, to: endTime) ?? endTime
        
        await importTracksForTimeRange(start: startTime, end: endTime)
    }
    
    private func importTimeRange() async {
        await importTracksForTimeRange(start: selectedStartDate, end: selectedEndDate)
    }
    
    private func importPlaylist() async {
        // TODO: Implement playlist import
        print("Playlist import not yet implemented")
    }
    
    private func importTracksForTimeRange(start: Date, end: Date) async {
        await withCheckedContinuation { continuation in
            spotifyManager.fetchRecentlyPlayed(after: start, before: end) { tracks in
                let imported = tracks.map { track in
                    ImportedTrack(
                        id: track.id,
                        name: track.title,
                        artist: track.artist,
                        album: track.album,
                        playedAt: track.playedAt,
                        spotifyId: track.id
                    )
                }
                
                DispatchQueue.main.async {
                    self.importedTracks = imported
                    self.importProgress = 1.0
                }
                
                continuation.resume()
            }
        }
    }
    
    private func saveImportedTracks() {
        guard let location = selectedLocation else { return }
        
        let events = importedTracks.map { track in
            ListeningEvent(
                timestamp: track.playedAt,
                latitude: 0.0, // No specific coordinates for imports
                longitude: 0.0,
                buildingName: location,
                trackName: track.name,
                artistName: track.artist,
                albumName: track.album,
                genre: nil,
                spotifyTrackId: track.spotifyId,
                sessionMode: .unknown // Mark as imported
            )
        }
        
        // Create a synthetic session for the import
        let session = Session(
            startTime: importedTracks.first?.playedAt ?? Date(),
            endTime: importedTracks.last?.playedAt ?? Date(),
            duration: .oneHour, // Approximate
            mode: .unknown, // Mark as imported
            events: events
        )
        
        dataStore.container.mainContext.insert(session)
        try? dataStore.container.mainContext.save()
        
        // Update session history
        dataStore.sessionHistory.insert(session, at: 0)
        
        dismiss()
    }
}

// MARK: - Import Header

struct ImportHeaderView: View {
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
                .glow(color: LociTheme.Colors.secondaryHighlight, radius: 12)
            
            VStack(spacing: LociTheme.Spacing.small) {
                Text("Import from Spotify")
                    .font(LociTheme.Typography.heading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("Bring your listening history into Loci and associate it with a location")
                    .font(LociTheme.Typography.body)
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Import Mode Selection Card

struct ImportModeSelectionCard: View {
    @Binding var selectedMode: SpotifyImportMode
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            HStack {
                Text("Import Type")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Spacer()
            }
            
            VStack(spacing: LociTheme.Spacing.small) {
                ForEach(SpotifyImportMode.allCases, id: \.self) { mode in
                    ImportModeRow(
                        mode: mode,
                        isSelected: selectedMode == mode
                    ) {
                        withAnimation(LociTheme.Animation.smoothEaseInOut) {
                            selectedMode = mode
                        }
                    }
                }
            }
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard()
    }
}

// MARK: - Import Mode Row

struct ImportModeRow: View {
    let mode: SpotifyImportMode
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: LociTheme.Spacing.medium) {
                // Icon
                Image(systemName: mode.icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? LociTheme.Colors.secondaryHighlight : LociTheme.Colors.subheadText)
                    .frame(width: 24)
                
                // Content
                VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                    Text(mode.displayName)
                        .font(LociTheme.Typography.body)
                        .foregroundColor(LociTheme.Colors.mainText)
                        .fontWeight(.medium)
                    
                    Text(mode.description)
                        .font(LociTheme.Typography.caption)
                        .foregroundColor(LociTheme.Colors.subheadText)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? LociTheme.Colors.secondaryHighlight : LociTheme.Colors.disabledState)
            }
            .padding(LociTheme.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: LociTheme.CornerRadius.small)
                    .fill(isSelected ? LociTheme.Colors.secondaryHighlight.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: LociTheme.CornerRadius.small)
                            .stroke(
                                isSelected ? LociTheme.Colors.secondaryHighlight : LociTheme.Colors.disabledState,
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Location Assignment Card

struct LocationAssignmentCard: View {
    @Binding var selectedLocation: String?
    @Binding var showingLocationPicker: Bool
    @EnvironmentObject var locationManager: LocationManager
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            HStack {
                Image(systemName: "location.square")
                    .font(.system(size: 16))
                    .foregroundColor(LociTheme.Colors.primaryAction)
                
                Text("Assign to Location")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Spacer()
            }
            
            if let locationName = selectedLocation {
                SimpleSelectedLocationDisplay(locationName: locationName) {
                    selectedLocation = nil
                }
            } else {
                LocationSelectionButtons(showingLocationPicker: $showingLocationPicker)
            }
            
            // Info
            HStack(spacing: LociTheme.Spacing.small) {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundColor(LociTheme.Colors.primaryAction)
                
                Text("All imported tracks will be associated with this location")
                    .font(.system(size: 12))
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .multilineTextAlignment(.leading)
                
                Spacer()
            }
            .padding(LociTheme.Spacing.small)
            .background(LociTheme.Colors.primaryAction.opacity(0.1))
            .cornerRadius(LociTheme.CornerRadius.small)
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer)
    }
}

// MARK: - Time Range Selection Card

struct TimeRangeSelectionCard: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 16))
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
                
                Text("Time Range")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Spacer()
            }
            
            VStack(spacing: LociTheme.Spacing.small) {
                // Start Date
                DateTimePicker(
                    title: "Start",
                    date: $startDate,
                    icon: "calendar.badge.plus"
                )
                
                // End Date
                DateTimePicker(
                    title: "End",
                    date: $endDate,
                    icon: "calendar.badge.minus"
                )
            }
            
            // Duration Display
            HStack {
                Text("Duration:")
                    .font(LociTheme.Typography.caption)
                    .foregroundColor(LociTheme.Colors.subheadText)
                
                Text(durationText)
                    .font(LociTheme.Typography.caption)
                    .foregroundColor(LociTheme.Colors.mainText)
                    .fontWeight(.medium)
                
                Spacer()
            }
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer)
    }
    
    private var durationText: String {
        let duration = endDate.timeIntervalSince(startDate)
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Date Time Picker

struct DateTimePicker: View {
    let title: String
    @Binding var date: Date
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(LociTheme.Colors.subheadText)
                .frame(width: 20)
            
            Text(title)
                .font(LociTheme.Typography.body)
                .foregroundColor(LociTheme.Colors.mainText)
            
            Spacer()
            
            DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .colorScheme(.dark)
        }
        .padding(LociTheme.Spacing.small)
        .background(LociTheme.Colors.disabledState.opacity(0.3))
        .cornerRadius(LociTheme.CornerRadius.small)
    }
}

// MARK: - Import Button

struct ImportButton: View {
    let canImport: Bool
    let isImporting: Bool
    let progress: Double
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: LociTheme.Spacing.small) {
                if isImporting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                    
                    Text("Importing...")
                } else {
                    Image(systemName: "square.and.arrow.down")
                    Text("Import Tracks")
                }
            }
        }
        .lociButton(.gradient, isFullWidth: true)
        .disabled(!canImport)
        .opacity(canImport ? 1.0 : 0.6)
    }
}

// MARK: - Import Preview Section

struct ImportPreviewSection: View {
    let tracks: [ImportedTrack]
    let onSave: () -> Void
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            HStack {
                Text("Import Preview")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Spacer()
                
                Text("\(tracks.count) tracks")
                    .font(LociTheme.Typography.caption)
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
            }
            
            LazyVStack(spacing: LociTheme.Spacing.small) {
                ForEach(tracks.prefix(10)) { track in
                    ImportedTrackRow(track: track)
                }
                
                if tracks.count > 10 {
                    Text("+ \(tracks.count - 10) more tracks")
                        .font(LociTheme.Typography.caption)
                        .foregroundColor(LociTheme.Colors.subheadText)
                        .padding()
                }
            }
            
            Button(action: onSave) {
                HStack {
                    Image(systemName: "checkmark.circle")
                    Text("Save \(tracks.count) Tracks")
                }
            }
            .lociButton(.primary, isFullWidth: true)
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard()
    }
}

// MARK: - Imported Track Row

struct ImportedTrackRow: View {
    let track: ImportedTrack
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                Text(track.name)
                    .font(LociTheme.Typography.body)
                    .foregroundColor(LociTheme.Colors.mainText)
                    .lineLimit(1)
                
                Text(track.artist)
                    .font(LociTheme.Typography.caption)
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text(track.playedAt.formatted(date: .omitted, time: .shortened))
                .font(LociTheme.Typography.caption)
                .foregroundColor(LociTheme.Colors.subheadText)
        }
        .padding(.vertical, LociTheme.Spacing.xxSmall)
    }
}

// MARK: - Supporting Types

struct ImportedTrack: Identifiable {
    let id: String
    let name: String
    let artist: String
    let album: String
    let playedAt: Date
    let spotifyId: String
}

// MARK: - Location Selection View (Placeholder)

struct LocationSelectionView: View {
    @Binding var selectedLocation: String?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Location Selection")
                    .font(LociTheme.Typography.heading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("This would be a location picker interface")
                    .font(LociTheme.Typography.body)
                    .foregroundColor(LociTheme.Colors.subheadText)
                
                Button("Select Test Location") {
                    selectedLocation = "Test Coffee Shop"
                    dismiss()
                }
                .lociButton(.primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LociTheme.Colors.appBackground)
            .navigationTitle("Select Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
// MARK: - Reused Components (from OnePlaceSessionView)

struct SelectedLocationDisplay: View {
    let location: SelectedLocation
    let onRemove: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xSmall) {
                Text(location.buildingInfo.name)
                    .font(LociTheme.Typography.body)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                if let address = location.buildingInfo.address {
                    Text(address)
                        .font(LociTheme.Typography.caption)
                        .foregroundColor(LociTheme.Colors.subheadText)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(LociTheme.Colors.disabledState)
            }
        }
        .padding(LociTheme.Spacing.medium)
        .background(LociTheme.Colors.secondaryHighlight.opacity(0.1))
        .cornerRadius(LociTheme.CornerRadius.small)
    }
}

struct LocationSelectionButtons: View {
    @Binding var showingLocationPicker: Bool
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.small) {
            Button("Use Current Location") {
                // This would be handled by parent view
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(LociTheme.Colors.disabledState.opacity(0.3))
            .cornerRadius(LociTheme.CornerRadius.small)
            
            Button(action: { showingLocationPicker = true }) {
                Text("Select on Map")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(LociTheme.Colors.disabledState.opacity(0.3))
            .cornerRadius(LociTheme.CornerRadius.small)
        }
    }
}

struct SimpleSelectedLocationDisplay: View {
    let locationName: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xSmall) {
                Text(locationName)
                    .font(LociTheme.Typography.body)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("Selected location")
                    .font(LociTheme.Typography.caption)
                    .foregroundColor(LociTheme.Colors.subheadText)
            }
            
            Spacer()
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(LociTheme.Colors.disabledState)
            }
        }
        .padding(LociTheme.Spacing.medium)
        .background(LociTheme.Colors.secondaryHighlight.opacity(0.1))
        .cornerRadius(LociTheme.CornerRadius.small)
    }
}
