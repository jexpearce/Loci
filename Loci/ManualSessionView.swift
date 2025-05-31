import SwiftUI
import MapKit
import CoreLocation

// MARK: - Manual Session View

struct ManualSessionView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var dataStore: DataStore
    
    @State private var selectedRegion: String?
    @State private var showingRegionPicker = false
    @State private var showingManualEntry = false
    
    var body: some View {
        ZStack {
            LociTheme.Colors.appBackground
                .ignoresSafeArea()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: LociTheme.Spacing.large) {
                    // Header
                    ManualSessionHeader()
                    
                    // Region Selection
                    RegionSelectionCard(
                        selectedRegion: $selectedRegion,
                        onMapSelect: { showingRegionPicker = true },
                        onManualEntry: { showingManualEntry = true }
                    )
                    
                    // Session Info
                    ManualSessionInfoCard(region: selectedRegion)
                    
                    // Start Button
                    StartManualSessionButton(
                        canStart: selectedRegion != nil,
                        region: selectedRegion,
                        onStart: startSession
                    )
                    
                    // Privacy Note
                    ManualPrivacyNoteCard()
                }
                .padding(.horizontal, LociTheme.Spacing.medium)
                .padding(.vertical, LociTheme.Spacing.large)
            }
        }
        .sheet(isPresented: $showingRegionPicker) {
            RegionPickerView(selectedRegion: $selectedRegion)
        }
        .sheet(isPresented: $showingManualEntry) {
            ManualRegionEntryView(selectedRegion: $selectedRegion)
        }
    }
    
    // MARK: - Actions
    
    private func startSession() {
        guard let region = selectedRegion else { return }
        sessionManager.startSession(mode: .manual, manualRegion: region)
    }
}

// MARK: - Manual Session Header

struct ManualSessionHeader: View {
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            Image(systemName: "map.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(LociTheme.Colors.primaryAction)
                .glow(color: LociTheme.Colors.primaryAction, radius: 12)
            
            Text("Manual Region Session")
                .font(LociTheme.Typography.heading)
                .foregroundColor(LociTheme.Colors.mainText)
            
            Text("Perfect for privacy-conscious users. Pick any region or building manually - no GPS required. We'll track your music and associate it with your chosen location.")
                .font(LociTheme.Typography.body)
                .foregroundColor(LociTheme.Colors.mainText.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, LociTheme.Spacing.medium)
    }
}

// MARK: - Region Selection Card

struct RegionSelectionCard: View {
    @Binding var selectedRegion: String?
    let onMapSelect: () -> Void
    let onManualEntry: () -> Void
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            HStack {
                Label("Region", systemImage: "building.2")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.subheadText)
                
                Spacer()
            }
            
            if let region = selectedRegion {
                SelectedRegionView(region: region) {
                    selectedRegion = nil
                }
            } else {
                RegionSelectionOptions(
                    onMapSelect: onMapSelect,
                    onManualEntry: onManualEntry
                )
            }
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer)
    }
}

// MARK: - Selected Region View

struct SelectedRegionView: View {
    let region: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xSmall) {
                HStack(spacing: LociTheme.Spacing.xSmall) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(LociTheme.Colors.primaryAction)
                    
                    Text(region)
                        .font(LociTheme.Typography.body)
                        .foregroundColor(LociTheme.Colors.mainText)
                }
                
                Text("Manual selection")
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
        .background(LociTheme.Colors.cardBackground.opacity(0.5))
        .cornerRadius(LociTheme.CornerRadius.small)
    }
}

// MARK: - Region Selection Options

struct RegionSelectionOptions: View {
    let onMapSelect: () -> Void
    let onManualEntry: () -> Void
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.small) {
            Button(action: onMapSelect) {
                HStack {
                    Image(systemName: "map")
                        .font(.system(size: 18))
                    
                    Text("Select on Map")
                        .font(LociTheme.Typography.body)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
                .foregroundColor(LociTheme.Colors.mainText)
                .padding(LociTheme.Spacing.medium)
                .background(LociTheme.Colors.cardBackground.opacity(0.5))
                .cornerRadius(LociTheme.CornerRadius.small)
            }
            
            Button(action: onManualEntry) {
                HStack {
                    Image(systemName: "keyboard")
                        .font(.system(size: 18))
                    
                    Text("Type Region Name")
                        .font(LociTheme.Typography.body)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
                .foregroundColor(LociTheme.Colors.mainText)
                .padding(LociTheme.Spacing.medium)
                .background(LociTheme.Colors.cardBackground.opacity(0.5))
                .cornerRadius(LociTheme.CornerRadius.small)
            }
        }
    }
}

// MARK: - Manual Session Info Card

struct ManualSessionInfoCard: View {
    let region: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: LociTheme.Spacing.small) {
            Text("Session Details")
                .font(LociTheme.Typography.caption)
                .foregroundColor(LociTheme.Colors.subheadText)
            
            HStack(spacing: LociTheme.Spacing.medium) {
                InfoItem(
                    icon: "music.note",
                    label: "Track Collection",
                    value: "At session end"
                )
                
                Spacer()
                
                InfoItem(
                    icon: "location.slash",
                    label: "GPS Usage",
                    value: "None"
                )
            }
            
            Text("Loci will collect your recently played Spotify tracks when you end the session and associate them all with \(region ?? "your selected region").")
                .font(LociTheme.Typography.caption)
                .foregroundColor(LociTheme.Colors.mainText.opacity(0.7))
                .padding(.top, LociTheme.Spacing.xSmall)
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer.opacity(0.5))
    }
}

// MARK: - Start Manual Session Button

struct StartManualSessionButton: View {
    let canStart: Bool
    let region: String?
    let onStart: () -> Void
    
    var body: some View {
        Button(action: onStart) {
            HStack(spacing: LociTheme.Spacing.small) {
                Image(systemName: "play.fill")
                Text("Start Manual Session")
            }
        }
        .lociButton(.gradient, isFullWidth: true)
        .disabled(!canStart)
        .opacity(canStart ? 1.0 : 0.6)
    }
}

// MARK: - Manual Privacy Note Card

struct ManualPrivacyNoteCard: View {
    var body: some View {
        HStack(spacing: LociTheme.Spacing.small) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 16))
                .foregroundColor(LociTheme.Colors.primaryAction)
            
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                Text("Maximum Privacy")
                    .font(LociTheme.Typography.caption)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("No location permissions required. You control exactly what region is recorded.")
                    .font(.system(size: 11))
                    .foregroundColor(LociTheme.Colors.mainText.opacity(0.7))
            }
            
            Spacer()
        }
        .padding(LociTheme.Spacing.small)
        .background(LociTheme.Colors.primaryAction.opacity(0.1))
        .cornerRadius(LociTheme.CornerRadius.small)
    }
}

// MARK: - Region Picker View

struct RegionPickerView: View {
    @Binding var selectedRegion: String?
    @Environment(\.dismiss) var dismiss
    
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
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
                    .foregroundColor(LociTheme.Colors.primaryAction)
                
                // Selection info
                VStack {
                    Spacer()
                    
                    HStack {
                        Button("Cancel") {
                            dismiss()
                        }
                        .lociButton(.secondary)
                        
                        Button("Select This Area") {
                            selectedRegion = "Custom Region"
                            dismiss()
                        }
                        .lociButton(.primary)
                    }
                    .padding()
                }
            }
            .navigationTitle("Select Region")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Manual Region Entry View

struct ManualRegionEntryView: View {
    @Binding var selectedRegion: String?
    @Environment(\.dismiss) var dismiss
    
    @State private var regionName = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                LociTheme.Colors.appBackground
                    .ignoresSafeArea()
                
                VStack(spacing: LociTheme.Spacing.large) {
                    // Region Name
                    VStack(alignment: .leading, spacing: LociTheme.Spacing.xSmall) {
                        Text("Region Name")
                            .font(LociTheme.Typography.caption)
                            .foregroundColor(LociTheme.Colors.subheadText)
                        
                        TextField("e.g. Downtown District, Coffee Shop Area", text: $regionName)
                            .textFieldStyle(LociTextFieldStyle())
                    }
                    
                    Text("Enter any region, neighborhood, or area name. This will be associated with all tracks from your session.")
                        .font(LociTheme.Typography.caption)
                        .foregroundColor(LociTheme.Colors.mainText.opacity(0.7))
                        .multilineTextAlignment(.center)
                    
                    Spacer()
                    
                    // Action Buttons
                    HStack {
                        Button("Cancel") {
                            dismiss()
                        }
                        .lociButton(.secondary)
                        
                        Button("Save") {
                            selectedRegion = regionName
                            dismiss()
                        }
                        .lociButton(.primary)
                        .disabled(regionName.isEmpty)
                    }
                }
                .padding()
            }
            .navigationTitle("Enter Region")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
} 