import SwiftUI
import MapKit
import CoreLocation

// MARK: - Enhanced Spotify Import View (NEW)

struct EnhancedSpotifyImportView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var spotifyManager: SpotifyManager
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var locationManager: LocationManager
    
    @State private var isLoading = false
    @State private var recentTracks: [SpotifyImportTrack] = []
    @State private var selectedTracks: Set<String> = []
    @State private var selectedLocation: String?
    @State private var assignmentType: LocationAssignmentType = .region
    @State private var errorMessage: String?
    @State private var showingLocationPicker = false
    @State private var importStep: ImportStep = .loading
    
    enum ImportStep {
        case loading
        case trackSelection
        case locationAssignment
        case confirmation
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                LociTheme.Colors.appBackground
                    .ignoresSafeArea()
                
                switch importStep {
                case .loading:
                    LoadingImportView()
                case .trackSelection:
                    TrackSelectionView()
                case .locationAssignment:
                    LocationAssignmentView()
                case .confirmation:
                    ImportConfirmationView()
                }
            }
            .navigationTitle("Import Recent Plays")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
                
                if importStep == .trackSelection {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Next") {
                            withAnimation { importStep = .locationAssignment }
                        }
                        .disabled(selectedTracks.isEmpty)
                        .foregroundColor(selectedTracks.isEmpty ? LociTheme.Colors.disabledState : LociTheme.Colors.secondaryHighlight)
                    }
                }
            }
        }
        .onAppear {
            loadRecentTracks()
        }
    }
    
    // MARK: - Loading View
    
    @ViewBuilder
    func LoadingImportView() -> some View {
        VStack(spacing: LociTheme.Spacing.large) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: LociTheme.Colors.secondaryHighlight))
                .scaleEffect(1.5)
            
            VStack(spacing: LociTheme.Spacing.small) {
                Text("Fetching Your Recent Plays")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("Getting your last 50 tracks from Spotify")
                    .font(LociTheme.Typography.body)
                    .foregroundColor(LociTheme.Colors.subheadText)
            }
        }
    }
    
    // MARK: - Track Selection View
    
    @ViewBuilder
    func TrackSelectionView() -> some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            // Header
            VStack(spacing: LociTheme.Spacing.small) {
                Text("Select Tracks to Share")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                HStack {
                    Button(selectedTracks.count == recentTracks.count ? "Deselect All" : "Select All") {
                        if selectedTracks.count == recentTracks.count {
                            selectedTracks.removeAll()
                        } else {
                            selectedTracks = Set(recentTracks.map { $0.id })
                        }
                    }
                    .font(.system(size: 14))
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
                    
                    Spacer()
                    
                    Text("\(selectedTracks.count) of \(recentTracks.count) selected")
                        .font(.system(size: 14))
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
            }
            .padding(.horizontal)
            
            // Track List
            List(recentTracks, id: \.id) { track in
                SelectableTrackRow(
                    track: track,
                    isSelected: selectedTracks.contains(track.id)
                ) {
                    if selectedTracks.contains(track.id) {
                        selectedTracks.remove(track.id)
                    } else {
                        selectedTracks.insert(track.id)
                    }
                }
                .listRowBackground(LociTheme.Colors.contentContainer)
            }
            .listStyle(PlainListStyle())
        }
    }
    
    // MARK: - Location Assignment View
    
    @ViewBuilder
    func LocationAssignmentView() -> some View {
        VStack(spacing: LociTheme.Spacing.large) {
            // Header
            VStack(spacing: LociTheme.Spacing.small) {
                Text("Where to Share?")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("Choose where to share your \(selectedTracks.count) tracks")
                    .font(LociTheme.Typography.body)
                    .foregroundColor(LociTheme.Colors.subheadText)
            }
            
            // Assignment Type Selector
            VStack(spacing: LociTheme.Spacing.medium) {
                LocationTypeSelector(selectedType: $assignmentType)
                
                // Current location display or picker
                if let location = selectedLocation {
                    SelectedLocationDisplay(
                        locationName: location,
                        type: assignmentType
                    ) {
                        selectedLocation = nil
                    }
                } else {
                    LocationPickerButtons(
                        assignmentType: assignmentType,
                        onCurrentLocation: getCurrentLocation,
                        onManualSelect: { showingLocationPicker = true }
                    )
                }
            }
            .padding(LociTheme.Spacing.medium)
            .lociCard()
            
            // Continue Button
            if selectedLocation != nil {
                Button("Continue") {
                    withAnimation { importStep = .confirmation }
                }
                .lociButton(.primary, isFullWidth: true)
            }
        }
        .sheet(isPresented: $showingLocationPicker) {
            // REUSE your existing LocationSelectionView from SpotifyImportView.swift
            LocationSelectionView(
                selectedLocation: $selectedLocation,
                selectedLocationInfo: .constant(nil)
            )
        }
    }
    
    // MARK: - Confirmation View
    
    @ViewBuilder
    func ImportConfirmationView() -> some View {
        VStack(spacing: LociTheme.Spacing.large) {
            // Success Header
            VStack(spacing: LociTheme.Spacing.medium) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
                
                Text("Ready to Share!")
                    .font(LociTheme.Typography.heading)
                    .foregroundColor(LociTheme.Colors.mainText)
            }
            
            // Summary
            VStack(spacing: LociTheme.Spacing.medium) {
                ImportSummaryCard(
                    trackCount: selectedTracks.count,
                    location: selectedLocation ?? "Unknown",
                    assignmentType: assignmentType
                )
                
                // Final confirmation
                Button("Share My Music") {
                    processImport()
                }
                .lociButton(.gradient, isFullWidth: true)
                
                Button("Back to Edit") {
                    withAnimation { importStep = .locationAssignment }
                }
                .lociButton(.secondary, isFullWidth: true)
            }
        }
    }
    
    private func loadRecentTracks() {
        isLoading = true
        
        Task {
            do {
                // Call your fixed Spotify import method here
                let tracks = try await spotifyManager.fetchRecentlyPlayedTracks(limit: 50)
                
                await MainActor.run {
                    self.recentTracks = tracks
                    self.selectedTracks = Set(tracks.map { $0.id }) // Select all by default
                    self.importStep = .trackSelection
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func getCurrentLocation() {
        // Use your existing LocationManager
        locationManager.requestOneTimeLocation { location in
            guard let location = location else { return }
            
            Task {
                // Use your existing ReverseGeocoding service
                let buildingInfo = await ReverseGeocoding.shared.reverseGeocodeAsync(location: location)
                
                DispatchQueue.main.async {
                    if self.assignmentType == .region {
                        // For region: use city/area from buildingInfo
                        self.selectedLocation = buildingInfo?.city ?? buildingInfo?.neighborhood ?? "Your Area"
                    } else {
                        // For building: use specific building name
                        self.selectedLocation = buildingInfo?.name ?? "Current Location"
                    }
                }
            }
        }
    }
    
    private func processImport() {
        guard let location = selectedLocation else { return }
        
        // Filter selected tracks
        let tracksToImport = recentTracks.filter { selectedTracks.contains($0.id) }
        
        // Create import batch
        let importBatch = ImportBatch(
            id: UUID(),
            tracks: tracksToImport,
            location: location,
            assignmentType: assignmentType,
            importedAt: Date()
        )
        
        // Save to data store (triggers leaderboard update)
        dataStore.saveImportBatch(importBatch)
        
        // Update SpotifyManager
        spotifyManager.hasRecentImports = true
        
        // Show success feedback
        NotificationManager.shared.showImportSuccessNotification(
            trackCount: tracksToImport.count,
            location: location
        )
        
        dismiss()
    }
}

// MARK: - Selectable Track Row

struct SelectableTrackRow: View {
    let track: SpotifyImportTrack
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: LociTheme.Spacing.medium) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? LociTheme.Colors.secondaryHighlight : LociTheme.Colors.disabledState)
                
                // Track info
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
                
                // Played time
                Text(track.playedAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12))
                    .foregroundColor(LociTheme.Colors.subheadText)
            }
            .padding(.vertical, LociTheme.Spacing.xSmall)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Original Spotify Import View

struct SpotifyImportView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var spotifyManager: SpotifyManager
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var reverseGeocoding: ReverseGeocoding
    
    @State private var selectedImportMode: SpotifyImportMode = .recentTracks
    @State private var selectedLocation: String?
    @State private var selectedLocationInfo: SelectedLocationInfo?
    @State private var showingLocationPicker = false
    @State private var isImporting = false
    @State private var importProgress: Double = 0.0
    @State private var importedTracks: [ImportedTrack] = []
    @State private var showingPreview = false
    @State private var selectedPlaylist: SpotifyPlaylist?
    @State private var showingPlaylistPicker = false
    @State private var importError: String?
    
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
                        
                        // Authentication Check
                        if !spotifyManager.isAuthenticated {
                            SpotifyAuthPrompt()
                        } else {
                            // Import Mode Selection
                            ImportModeSelectionCard(selectedMode: $selectedImportMode)
                            
                            // Location Assignment
                            LocationAssignmentCard(
                                selectedLocation: $selectedLocation,
                                showingLocationPicker: $showingLocationPicker
                            )
                            
                            // Mode-specific Configuration
                            Group {
                                switch selectedImportMode {
                                case .timeRange:
                                    TimeRangeSelectionCard(
                                        startDate: $selectedStartDate,
                                        endDate: $selectedEndDate
                                    )
                                case .playlist:
                                    PlaylistSelectionCard(
                                        selectedPlaylist: $selectedPlaylist,
                                        showingPlaylistPicker: $showingPlaylistPicker
                                    )
                                case .recentTracks:
                                    RecentTracksInfoCard()
                                }
                            }
                            
                            // Error Display
                            if let error = importError {
                                ImportErrorCard(error: error) {
                                    importError = nil
                                }
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
            LocationSelectionView(
                selectedLocation: $selectedLocation,
                selectedLocationInfo: $selectedLocationInfo
            )
        }
        .sheet(isPresented: $showingPlaylistPicker) {
            PlaylistPickerView(
                selectedPlaylist: $selectedPlaylist,
                playlists: spotifyManager.userPlaylists
            )
        }
        .onAppear {
            if spotifyManager.isAuthenticated && spotifyManager.userPlaylists.isEmpty {
                Task {
                    await spotifyManager.loadUserPlaylists()
                }
            }
        }
    }
    
    private var canStartImport: Bool {
        guard spotifyManager.isAuthenticated && selectedLocation != nil && !isImporting else {
            return false
        }
        
        switch selectedImportMode {
        case .recentTracks:
            return true
        case .timeRange:
            return selectedStartDate < selectedEndDate
        case .playlist:
            return selectedPlaylist != nil
        }
    }
    
    private func startImport() {
        guard canStartImport else { return }
        
        isImporting = true
        importProgress = 0.0
        importedTracks = []
        importError = nil
        
        Task {
            await performImport()
        }
    }
    
    private func performImport() async {
        do {
            await MainActor.run {
                importProgress = 0.1
            }
            
            let tracks: [ImportedTrack]
            
            switch selectedImportMode {
            case .recentTracks:
                tracks = try await importRecentTracks()
            case .timeRange:
                tracks = try await importTimeRange()
            case .playlist:
                tracks = try await importPlaylist()
            }
            
            await MainActor.run {
                self.importedTracks = tracks
                self.importProgress = 1.0
                self.isImporting = false
                
                if tracks.isEmpty {
                    self.importError = "No tracks found for the selected period. Try a different time range or check that you were listening to music during this time."
                }
            }
            
        } catch {
            await MainActor.run {
                self.isImporting = false
                self.importProgress = 0.0
                self.importError = "Import failed: \(error.localizedDescription)"
                print("❌ Import error: \(error)")
            }
        }
    }
    
    private func importRecentTracks() async throws -> [ImportedTrack] {
        // Import last 6 hours of tracks
        let endTime = Date()
        let startTime = Calendar.current.date(byAdding: .hour, value: -6, to: endTime) ?? endTime
        
        await MainActor.run {
            importProgress = 0.3
        }
        
        return try await spotifyManager.importFromTimeRange(start: startTime, end: endTime)
    }
    
    private func importTimeRange() async throws -> [ImportedTrack] {
        await MainActor.run {
            importProgress = 0.3
        }
        
        return try await spotifyManager.importFromTimeRange(start: selectedStartDate, end: selectedEndDate)
    }
    
    private func importPlaylist() async throws -> [ImportedTrack] {
        guard let playlist = selectedPlaylist else {
            throw ImportError.noPlaylistSelected
        }
        
        await MainActor.run {
            importProgress = 0.3
        }
        
        let trackData = try await spotifyManager.getPlaylistTracks(playlistId: playlist.id)
        
        await MainActor.run {
            importProgress = 0.8
        }
        
        return trackData.map { track in
            ImportedTrack(
                id: track.id,
                name: track.title,
                artist: track.artist,
                album: track.album,
                playedAt: track.playedAt,
                spotifyId: track.id
            )
        }
    }
    
    private func saveImportedTracks() {
        guard let location = selectedLocation else { return }
        
        let events = importedTracks.map { track in
            ListeningEvent(
                timestamp: track.playedAt,
                latitude: selectedLocationInfo?.coordinate.latitude ?? 0.0,
                longitude: selectedLocationInfo?.coordinate.longitude ?? 0.0,
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
            duration: .oneHour, // Approximate based on time span
            mode: .unknown, // Mark as imported
            events: events
        )
        
        dataStore.container.mainContext.insert(session)
        try? dataStore.container.mainContext.save()
        
        // Update session history
        dataStore.sessionHistory.insert(session, at: 0)
        
        // Show success notification
        NotificationManager.shared.notifyImportCompleted(trackCount: importedTracks.count)
        
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

// MARK: - Spotify Auth Prompt

struct SpotifyAuthPrompt: View {
    @EnvironmentObject var spotifyManager: SpotifyManager
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            Image(systemName: "music.note.tv")
                .font(.system(size: 32))
                .foregroundColor(LociTheme.Colors.primaryAction)
            
            VStack(spacing: LociTheme.Spacing.small) {
                Text("Connect Spotify")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("You need to connect your Spotify account to import your listening history")
                    .font(LociTheme.Typography.body)
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .multilineTextAlignment(.center)
            }
            
            Button("Connect Spotify") {
                spotifyManager.startAuthorization()
            }
            .lociButton(.primary, isFullWidth: true)
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard()
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
    @EnvironmentObject var reverseGeocoding: ReverseGeocoding
    
    @State private var isLoadingCurrentLocation = false
    @State private var locationError: String?
    
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
                VStack(spacing: LociTheme.Spacing.small) {
                    Button(action: getCurrentLocation) {
                        HStack {
                            if isLoadingCurrentLocation {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: LociTheme.Colors.mainText))
                                    .scaleEffect(0.8)
                                Text("Getting location...")
                            } else {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 18))
                                Text("Use Current Location")
                            }
                            
                            Spacer()
                            
                            if !isLoadingCurrentLocation {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                                    .foregroundColor(LociTheme.Colors.subheadText)
                            }
                        }
                        .foregroundColor(LociTheme.Colors.mainText)
                        .padding(LociTheme.Spacing.medium)
                        .background(LociTheme.Colors.disabledState.opacity(0.3))
                        .cornerRadius(LociTheme.CornerRadius.small)
                    }
                    .disabled(isLoadingCurrentLocation)
                    
                    Button(action: { showingLocationPicker = true }) {
                        HStack {
                            Image(systemName: "map")
                                .font(.system(size: 18))
                            Text("Select on Map")
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundColor(LociTheme.Colors.subheadText)
                        }
                        .foregroundColor(LociTheme.Colors.mainText)
                        .padding(LociTheme.Spacing.medium)
                        .background(LociTheme.Colors.disabledState.opacity(0.3))
                        .cornerRadius(LociTheme.CornerRadius.small)
                    }
                    
                    if let error = locationError {
                        HStack(spacing: LociTheme.Spacing.small) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 14))
                                .foregroundColor(LociTheme.Colors.primaryAction)
                            
                            Text(error)
                                .font(LociTheme.Typography.caption)
                                .foregroundColor(LociTheme.Colors.primaryAction)
                            
                            Spacer()
                        }
                    }
                }
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
    
    private func getCurrentLocation() {
        guard locationManager.authorizationStatus == .authorizedAlways ||
              locationManager.authorizationStatus == .authorizedWhenInUse else {
            locationError = "Location permission required"
            locationManager.requestPermissions()
            return
        }
        
        isLoadingCurrentLocation = true
        locationError = nil
        
        locationManager.requestOneTimeLocation { location in
            guard let location = location else {
                self.locationError = "Could not get current location"
                self.isLoadingCurrentLocation = false
                return
            }
            
            Task {
                let buildingInfo = await self.reverseGeocoding.reverseGeocodeAsync(location: location)
                
                DispatchQueue.main.async {
                    if let buildingInfo = buildingInfo {
                        self.selectedLocation = buildingInfo.name
                    } else {
                        // Fallback to coordinate-based location
                        let fallbackName = "Location \(String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude))"
                        self.selectedLocation = fallbackName
                    }
                    self.isLoadingCurrentLocation = false
                }
            }
        }
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
            
            // Info about Spotify limits
            HStack(spacing: LociTheme.Spacing.small) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundColor(LociTheme.Colors.subheadText)
                
                Text("Spotify provides recently played tracks from the last 50 plays. For older data, try playlist import.")
                    .font(.system(size: 11))
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .multilineTextAlignment(.leading)
                
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

// MARK: - Playlist Selection Card

struct PlaylistSelectionCard: View {
    @Binding var selectedPlaylist: SpotifyPlaylist?
    @Binding var showingPlaylistPicker: Bool
    @EnvironmentObject var spotifyManager: SpotifyManager
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            HStack {
                Image(systemName: "music.note.list")
                    .font(.system(size: 16))
                    .foregroundColor(LociTheme.Colors.notificationBadge)
                
                Text("Select Playlist")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Spacer()
            }
            
            if let playlist = selectedPlaylist {
                SelectedPlaylistDisplay(playlist: playlist) {
                    selectedPlaylist = nil
                }
            } else {
                Button("Choose Playlist") {
                    showingPlaylistPicker = true
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(LociTheme.Colors.disabledState.opacity(0.3))
                .cornerRadius(LociTheme.CornerRadius.small)
                
                if spotifyManager.userPlaylists.isEmpty {
                    Text("Loading playlists...")
                        .font(LociTheme.Typography.caption)
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
            }
            
            // Info
            HStack(spacing: LociTheme.Spacing.small) {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundColor(LociTheme.Colors.notificationBadge)
                
                Text("Import all tracks from a playlist. Tracks will be timestamped with when they were added to the playlist.")
                    .font(.system(size: 12))
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .multilineTextAlignment(.leading)
                
                Spacer()
            }
            .padding(LociTheme.Spacing.small)
            .background(LociTheme.Colors.notificationBadge.opacity(0.1))
            .cornerRadius(LociTheme.CornerRadius.small)
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer)
    }
}

// MARK: - Recent Tracks Info Card

struct RecentTracksInfoCard: View {
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 16))
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
                
                Text("Recent Tracks")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: LociTheme.Spacing.small) {
                Text("This will import your recently played tracks from the last 6 hours.")
                    .font(LociTheme.Typography.body)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("• Quick and easy import")
                    .font(LociTheme.Typography.caption)
                    .foregroundColor(LociTheme.Colors.subheadText)
                
                Text("• Perfect for capturing a recent listening session")
                    .font(LociTheme.Typography.caption)
                    .foregroundColor(LociTheme.Colors.subheadText)
                
                Text("• Uses Spotify's recently played data")
                    .font(LociTheme.Typography.caption)
                    .foregroundColor(LociTheme.Colors.subheadText)
            }
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer)
    }
}

// MARK: - Import Error Card

struct ImportErrorCard: View {
    let error: String
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.small) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(LociTheme.Colors.primaryAction)
                
                Text("Import Error")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 16))
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
            }
            
            Text(error)
                .font(LociTheme.Typography.body)
                .foregroundColor(LociTheme.Colors.subheadText)
                .multilineTextAlignment(.leading)
        }
        .padding(LociTheme.Spacing.medium)
        .background(LociTheme.Colors.primaryAction.opacity(0.1))
        .cornerRadius(LociTheme.CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: LociTheme.CornerRadius.medium)
                .stroke(LociTheme.Colors.primaryAction.opacity(0.3), lineWidth: 1)
        )
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
            
            if tracks.isEmpty {
                VStack(spacing: LociTheme.Spacing.small) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 24))
                        .foregroundColor(LociTheme.Colors.subheadText.opacity(0.5))
                    
                    Text("No tracks found")
                        .font(LociTheme.Typography.body)
                        .foregroundColor(LociTheme.Colors.subheadText)
                    
                    Text("Try a different time range or check that you were listening to music during this period")
                        .font(LociTheme.Typography.caption)
                        .foregroundColor(LociTheme.Colors.subheadText.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, LociTheme.Spacing.large)
            } else {
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

// MARK: - Location Selection View (Enhanced)

struct LocationSelectionView: View {
    @Binding var selectedLocation: String?
    @Binding var selectedLocationInfo: SelectedLocationInfo?
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var reverseGeocoding: ReverseGeocoding
    @EnvironmentObject var locationManager: LocationManager
    
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @State private var isReverseGeocoding = false
    @State private var searchText = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                // Map
                Map(coordinateRegion: $mapRegion)
                    .ignoresSafeArea(edges: .bottom)
                
                // Center crosshair
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
                
                // Selection UI
                VStack {
                    Spacer()
                    
                    VStack(spacing: LociTheme.Spacing.medium) {
                        if isReverseGeocoding {
                            HStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Finding building...")
                                    .font(LociTheme.Typography.body)
                                    .foregroundColor(.white)
                            }
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(LociTheme.CornerRadius.medium)
                        }
                        
                        HStack(spacing: LociTheme.Spacing.small) {
                            Button("Cancel") {
                                dismiss()
                            }
                            .lociButton(.secondary)
                            
                            Button("Select This Location") {
                                selectCurrentLocation()
                            }
                            .lociButton(.primary)
                            .disabled(isReverseGeocoding)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Select Location")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Center on user's current location if available
                if let currentLocation = locationManager.currentLocation {
                    mapRegion.center = currentLocation.coordinate
                }
            }
        }
    }
    
    private func selectCurrentLocation() {
        isReverseGeocoding = true
        let coordinate = mapRegion.center
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        Task {
            let buildingInfo = await reverseGeocoding.reverseGeocodeAsync(location: location)
            
            DispatchQueue.main.async {
                if let buildingInfo = buildingInfo {
                    self.selectedLocation = buildingInfo.name
                    self.selectedLocationInfo = SelectedLocationInfo(
                        coordinate: coordinate,
                        buildingName: buildingInfo.name
                    )
                } else {
                    // Fallback to coordinate-based location
                    let fallbackName = "Location \(String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude))"
                    self.selectedLocation = fallbackName
                    self.selectedLocationInfo = SelectedLocationInfo(
                        coordinate: coordinate,
                        buildingName: fallbackName
                    )
                }
                
                self.isReverseGeocoding = false
                dismiss()
            }
        }
    }
}

// MARK: - Playlist Picker View

struct PlaylistPickerView: View {
    @Binding var selectedPlaylist: SpotifyPlaylist?
    let playlists: [SpotifyPlaylist]
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                LociTheme.Colors.appBackground
                    .ignoresSafeArea()
                
                if playlists.isEmpty {
                    VStack(spacing: LociTheme.Spacing.medium) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 48))
                            .foregroundColor(LociTheme.Colors.subheadText)
                        
                        Text("No playlists found")
                            .font(LociTheme.Typography.subheading)
                            .foregroundColor(LociTheme.Colors.mainText)
                        
                        Text("Create some playlists in Spotify to import them here")
                            .font(LociTheme.Typography.body)
                            .foregroundColor(LociTheme.Colors.subheadText)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    List(playlists) { playlist in
                        PlaylistRow(playlist: playlist, isSelected: selectedPlaylist?.id == playlist.id) {
                            selectedPlaylist = playlist
                            dismiss()
                        }
                        .listRowBackground(LociTheme.Colors.contentContainer)
                    }
                    .listStyle(PlainListStyle())
                    .background(LociTheme.Colors.appBackground)
                }
            }
            .navigationTitle("Select Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
                }
            }
        }
    }
}

struct PlaylistRow: View {
    let playlist: SpotifyPlaylist
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                    Text(playlist.name)
                        .font(LociTheme.Typography.body)
                        .foregroundColor(LociTheme.Colors.mainText)
                        .lineLimit(1)
                    
                    if let description = playlist.description, !description.isEmpty {
                        Text(description)
                            .font(LociTheme.Typography.caption)
                            .foregroundColor(LociTheme.Colors.subheadText)
                            .lineLimit(2)
                    }
                    
                    Text("\(playlist.trackCount) tracks")
                        .font(LociTheme.Typography.caption)
                        .foregroundColor(LociTheme.Colors.primaryAction)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(LociTheme.Colors.secondaryHighlight)
                }
            }
            .padding(.vertical, LociTheme.Spacing.small)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Supporting Components

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

struct SelectedPlaylistDisplay: View {
    let playlist: SpotifyPlaylist
    let onRemove: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xSmall) {
                Text(playlist.name)
                    .font(LociTheme.Typography.body)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("\(playlist.trackCount) tracks")
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
        .background(LociTheme.Colors.notificationBadge.opacity(0.1))
        .cornerRadius(LociTheme.CornerRadius.small)
    }
}

// MARK: - Supporting Types

enum ImportError: Error, LocalizedError {
    case noPlaylistSelected
    case spotifyNotConnected
    case noLocationSelected
    
    var errorDescription: String? {
        switch self {
        case .noPlaylistSelected:
            return "No playlist selected"
        case .spotifyNotConnected:
            return "Spotify not connected"
        case .noLocationSelected:
            return "No location selected"
        }
    }
}

// MARK: - NotificationManager Extension

extension NotificationManager {
    func notifyImportCompleted(trackCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Import Complete! 🎵"
        content.body = "Successfully imported \(trackCount) tracks from Spotify"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "import.completed.\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        
        notificationCenter.add(request)
    }
}

// MARK: - Supporting Views for Location Assignment

struct LocationTypeSelector: View {
    @Binding var selectedType: LocationAssignmentType
    
    var body: some View {
        HStack(spacing: 0) {
            LocationTypeButton(
                title: "Region",
                subtitle: "Share with your area",
                icon: "map.fill",
                isSelected: selectedType == .region
            ) {
                selectedType = .region
            }
            
            LocationTypeButton(
                title: "Building",
                subtitle: "Share with specific place",
                icon: "building.2.fill",
                isSelected: selectedType == .building
            ) {
                selectedType = .building
            }
        }
        .background(LociTheme.Colors.disabledState)
        .cornerRadius(LociTheme.CornerRadius.medium)
    }
}

struct LocationTypeButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: LociTheme.Spacing.xSmall) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .white : LociTheme.Colors.subheadText)
                
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSelected ? .white : LociTheme.Colors.mainText)
                
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : LociTheme.Colors.subheadText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LociTheme.Spacing.medium)
            .background(isSelected ? LociTheme.Colors.primaryAction : Color.clear)
            .cornerRadius(LociTheme.CornerRadius.small)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SelectedLocationDisplay: View {
    let locationName: String
    let type: LocationAssignmentType
    let onRemove: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: type == .region ? "map.fill" : "building.2.fill")
                .font(.system(size: 18))
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Selected \(type == .region ? "Region" : "Building")")
                    .font(.system(size: 12))
                    .foregroundColor(LociTheme.Colors.subheadText)
                
                Text(locationName)
                    .font(LociTheme.Typography.body)
                    .foregroundColor(LociTheme.Colors.mainText)
                    .fontWeight(.medium)
            }
            
            Spacer()
            
            Button("Change") {
                onRemove()
            }
            .font(.system(size: 14))
            .foregroundColor(LociTheme.Colors.primaryAction)
        }
        .padding(LociTheme.Spacing.medium)
        .background(LociTheme.Colors.secondaryHighlight.opacity(0.1))
        .cornerRadius(LociTheme.CornerRadius.small)
    }
}

struct LocationPickerButtons: View {
    let assignmentType: LocationAssignmentType
    let onCurrentLocation: () -> Void
    let onManualSelect: () -> Void
    @EnvironmentObject var locationManager: LocationManager
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.small) {
            Button(action: onCurrentLocation) {
                HStack {
                    Image(systemName: "location.fill")
                        .font(.system(size: 18))
                        .foregroundColor(LociTheme.Colors.secondaryHighlight)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use Current Location")
                            .font(LociTheme.Typography.body)
                            .foregroundColor(LociTheme.Colors.mainText)
                        
                        Text(assignmentType == .region ? "Auto-detect your region" : "Find nearest building")
                            .font(.system(size: 12))
                            .foregroundColor(LociTheme.Colors.subheadText)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
                .padding(LociTheme.Spacing.medium)
                .background(LociTheme.Colors.secondaryHighlight.opacity(0.1))
                .cornerRadius(LociTheme.CornerRadius.small)
            }
            .disabled(locationManager.authorizationStatus != .authorizedAlways && 
                     locationManager.authorizationStatus != .authorizedWhenInUse)
            
            Button(action: onManualSelect) {
                HStack {
                    Image(systemName: "map")
                        .font(.system(size: 18))
                        .foregroundColor(LociTheme.Colors.mainText)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Select on Map")
                            .font(LociTheme.Typography.body)
                            .foregroundColor(LociTheme.Colors.mainText)
                        
                        Text("Choose manually like Hinge")
                            .font(.system(size: 12))
                            .foregroundColor(LociTheme.Colors.subheadText)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
                .padding(LociTheme.Spacing.medium)
                .background(LociTheme.Colors.disabledState.opacity(0.3))
                .cornerRadius(LociTheme.CornerRadius.small)
            }
        }
    }
}

struct ImportSummaryCard: View {
    let trackCount: Int
    let location: String
    let assignmentType: LocationAssignmentType
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            HStack {
                Text("Import Summary")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                Spacer()
            }
            
            VStack(spacing: LociTheme.Spacing.small) {
                SummaryRow(icon: "music.note", label: "Tracks", value: "\(trackCount)")
                SummaryRow(icon: assignmentType == .region ? "map.fill" : "building.2.fill", 
                          label: assignmentType == .region ? "Region" : "Building", 
                          value: location)
                SummaryRow(icon: "clock", label: "Time", value: "Now")
            }
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard()
    }
}

struct SummaryRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(LociTheme.Colors.primaryAction)
                .frame(width: 24)
            
            Text(label)
                .font(LociTheme.Typography.body)
                .foregroundColor(LociTheme.Colors.subheadText)
            
            Spacer()
            
            Text(value)
                .font(LociTheme.Typography.body)
                .foregroundColor(LociTheme.Colors.mainText)
                .fontWeight(.medium)
        }
    }
}
