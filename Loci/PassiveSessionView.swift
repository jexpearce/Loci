import SwiftUI
import MapKit
import CoreLocation

// MARK: - One-Place Session View

struct OnePlaceSessionView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var reverseGeocoding: ReverseGeocoding
    
    @State private var selectedLocation: SelectedLocation?
    @State private var showingLocationPicker = false
    @State private var isLoadingLocation = false
    @State private var locationError: String?
    @State private var showingLocationChangeAlert = false
    @State private var detectedLocationChange: String?
    
    // Map region
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    
    var body: some View {
        ZStack {
            LociTheme.Colors.appBackground
                .ignoresSafeArea()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: LociTheme.Spacing.large) {
                    // Header
                    OnePlaceSessionHeader()
                    
                    // Current Status Card (if session is active)
                    if sessionManager.isSessionActive && sessionManager.sessionMode == .onePlace {
                        OnePlaceActiveStatusCard()
                    } else {
                        // Location Selection
                        LocationSelectionCard(
                            selectedLocation: $selectedLocation,
                            isLoading: $isLoadingLocation,
                            error: $locationError,
                            onCurrentLocation: getCurrentLocation,
                            onManualSelect: { showingLocationPicker = true }
                        )
                        
                        // Features Info
                        OnePlaceFeaturesCard()
                        
                        // Start Button
                        StartOnePlaceSessionButton(
                            canStart: selectedLocation != nil,
                            location: selectedLocation,
                            onStart: startSession
                        )
                    }
                    
                    // Privacy & Battery Info
                    OnePlaceInfoCards()
                }
                .padding(.horizontal, LociTheme.Spacing.medium)
                .padding(.vertical, LociTheme.Spacing.large)
            }
        }
        .sheet(isPresented: $showingLocationPicker) {
            OnePlaceLocationPickerView(
                selectedLocation: $selectedLocation,
                mapRegion: $mapRegion
            )
        }
        .alert("Location Changed", isPresented: $showingLocationChangeAlert) {
            Button("Got it") {
                showingLocationChangeAlert = false
            }
        } message: {
            if let newLocation = detectedLocationChange {
                Text("We've detected you're now at \(newLocation). Your music tracking has automatically switched to this location.")
            }
        }
        .onAppear {
            setupInitialLocation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .buildingChangeDetected)) { notification in
            if let change = notification.object as? BuildingChange {
                detectedLocationChange = change.toBuildingName
                showingLocationChangeAlert = true
            }
        }
    }
    
    // MARK: - Actions
    
    private func setupInitialLocation() {
        if let location = locationManager.currentLocation {
            mapRegion.center = location.coordinate
        }
    }
    
    private func getCurrentLocation() {
        isLoadingLocation = true
        locationError = nil
        
        guard locationManager.authorizationStatus == .authorizedAlways ||
              locationManager.authorizationStatus == .authorizedWhenInUse else {
            locationError = "Location permission required"
            isLoadingLocation = false
            locationManager.requestPermissions()
            return
        }
        
        locationManager.requestOneTimeLocation { location in
            guard let location = location else {
                self.locationError = "Could not get current location"
                self.isLoadingLocation = false
                return
            }
            
            self.reverseGeocoding.reverseGeocode(location: location) { building in
                DispatchQueue.main.async {
                    if let building = building {
                        self.selectedLocation = SelectedLocation(
                            coordinate: location.coordinate,
                            buildingInfo: building,
                            source: .current
                        )
                        self.mapRegion.center = location.coordinate
                    } else {
                        self.locationError = "Could not determine building name"
                    }
                    self.isLoadingLocation = false
                }
            }
        }
    }
    
    private func startSession() {
        guard let location = selectedLocation else { return }
        
        sessionManager.startSession(
            mode: .onePlace,
            duration: nil, // One-place sessions don't have duration
            initialBuilding: location.buildingInfo.name
        )
    }
}

// MARK: - One-Place Session Header

struct OnePlaceSessionHeader: View {
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            Image(systemName: "location.square.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
                .glow(color: LociTheme.Colors.secondaryHighlight, radius: 12)
            
            VStack(spacing: LociTheme.Spacing.small) {
                Text("One-Place Session")
                    .font(LociTheme.Typography.heading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("Perfect for staying in one location. We'll automatically detect when you move to a new building.")
                    .font(LociTheme.Typography.body)
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
    }
}

// MARK: - One-Place Active Status Card

struct OnePlaceActiveStatusCard: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var dataStore: DataStore
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            // Status Header
            HStack {
                HStack(spacing: LociTheme.Spacing.small) {
                    Circle()
                        .fill(LociTheme.Colors.secondaryHighlight)
                        .frame(width: 12, height: 12)
                        .glow(color: LociTheme.Colors.secondaryHighlight, radius: 4)
                    
                    Text("ACTIVE SESSION")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(LociTheme.Colors.secondaryHighlight)
                }
                
                Spacer()
                
                Text("One-Place")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(LociTheme.Colors.subheadText)
                    .padding(.horizontal, LociTheme.Spacing.small)
                    .padding(.vertical, LociTheme.Spacing.xxSmall)
                    .background(LociTheme.Colors.disabledState.opacity(0.5))
                    .cornerRadius(LociTheme.CornerRadius.small)
            }
            
            // Current Building
            VStack(spacing: LociTheme.Spacing.small) {
                if let building = sessionManager.currentBuilding {
                    Text("Currently at")
                        .font(LociTheme.Typography.caption)
                        .foregroundColor(LociTheme.Colors.subheadText)
                    
                    Text(building)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(LociTheme.Colors.mainText)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                } else {
                    Text("Getting your location...")
                        .font(LociTheme.Typography.body)
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
                
                if sessionManager.hasDetectedLocationChange {
                    HStack(spacing: LociTheme.Spacing.xSmall) {
                        Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(LociTheme.Colors.primaryAction)
                        
                        Text("Location updated automatically")
                            .font(.system(size: 12))
                            .foregroundColor(LociTheme.Colors.primaryAction)
                    }
                    .padding(.horizontal, LociTheme.Spacing.small)
                    .padding(.vertical, LociTheme.Spacing.xSmall)
                    .background(LociTheme.Colors.primaryAction.opacity(0.1))
                    .cornerRadius(LociTheme.CornerRadius.small)
                }
            }
            
            // Session Stats
            HStack(spacing: LociTheme.Spacing.medium) {
                OnePlaceStatItem(
                    icon: "music.note",
                    value: "\(dataStore.currentSessionEvents.count)",
                    label: "Tracks"
                )
                
                OnePlaceStatItem(
                    icon: "clock.arrow.circlepath",
                    value: sessionDuration,
                    label: "Active"
                )
                
                OnePlaceStatItem(
                    icon: "location.magnifyingglass",
                    value: "Auto",
                    label: "Detection"
                )
            }
            
            // Quick Actions
            HStack(spacing: LociTheme.Spacing.small) {
                Button("View Details") {
                    // Show session details
                }
                .lociButton(.secondary)
                
                Button("End Session") {
                    sessionManager.stopSession()
                }
                .lociButton(.primary)
            }
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard()
    }
    
    private var sessionDuration: String {
        guard let elapsed = sessionManager.getSessionElapsed() else { return "0m" }
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - One-Place Stat Item

struct OnePlaceStatItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.xSmall) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
            
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(LociTheme.Colors.mainText)
            
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(LociTheme.Colors.subheadText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LociTheme.Spacing.small)
        .background(LociTheme.Colors.appBackground.opacity(0.5))
        .cornerRadius(LociTheme.CornerRadius.small)
    }
}

// MARK: - Location Selection Card (Reused from previous implementation)

struct LocationSelectionCard: View {
    @Binding var selectedLocation: SelectedLocation?
    @Binding var isLoading: Bool
    @Binding var error: String?
    let onCurrentLocation: () -> Void
    let onManualSelect: () -> Void
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            HStack {
                Label("Select Your Location", systemImage: "location.square")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Spacer()
            }
            
            if isLoading {
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: LociTheme.Colors.secondaryHighlight))
                    
                    Text("Finding your location...")
                        .font(LociTheme.Typography.body)
                        .foregroundColor(LociTheme.Colors.subheadText)
                    
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(LociTheme.Colors.contentContainer)
                .cornerRadius(LociTheme.CornerRadius.medium)
            } else if let location = selectedLocation {
                SelectedLocationView(location: location) {
                    selectedLocation = nil
                }
            } else {
                LocationSelectionOptions(
                    onCurrentLocation: onCurrentLocation,
                    onManualSelect: onManualSelect
                )
            }
            
            if let error = error {
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
        .padding(LociTheme.Spacing.medium)
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer)
    }
}

// MARK: - One-Place Features Card

struct OnePlaceFeaturesCard: View {
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            HStack {
                Text("How It Works")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Spacer()
            }
            
            VStack(spacing: LociTheme.Spacing.small) {
                OnePlaceFeatureRow(
                    icon: "location.fill",
                    title: "Set Once",
                    description: "Choose your location and we'll remember it"
                )
                
                OnePlaceFeatureRow(
                    icon: "arrow.triangle.turn.up.right.circle",
                    title: "Auto-Detect",
                    description: "Automatically switches when you move buildings"
                )
                
                OnePlaceFeatureRow(
                    icon: "battery.100",
                    title: "Battery Efficient",
                    description: "Uses minimal power with smart location monitoring"
                )
                
                OnePlaceFeatureRow(
                    icon: "infinity",
                    title: "No Time Limit",
                    description: "Session continues until you manually stop it"
                )
            }
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer)
    }
}

// MARK: - One-Place Feature Row

struct OnePlaceFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: LociTheme.Spacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(LociTheme.Colors.subheadText)
            }
            
            Spacer()
        }
    }
}

// MARK: - One-Place Info Cards

struct OnePlaceInfoCards: View {
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            // Battery Info
            HStack(spacing: LociTheme.Spacing.small) {
                Image(systemName: "battery.100")
                    .font(.system(size: 16))
                    .foregroundColor(LociTheme.Colors.secondaryHighlight)
                
                VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                    Text("Minimal Battery Impact")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(LociTheme.Colors.mainText)
                    
                    Text("Uses iOS significant location changes instead of continuous GPS")
                        .font(.system(size: 12))
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
                
                Spacer()
            }
            .padding(LociTheme.Spacing.small)
            .background(LociTheme.Colors.secondaryHighlight.opacity(0.1))
            .cornerRadius(LociTheme.CornerRadius.small)
            
            // Privacy Info
            HStack(spacing: LociTheme.Spacing.small) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 16))
                    .foregroundColor(LociTheme.Colors.primaryAction)
                
                VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                    Text("Privacy First")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(LociTheme.Colors.mainText)
                    
                    Text("Location data stays on your device unless you choose to share")
                        .font(.system(size: 12))
                        .foregroundColor(LociTheme.Colors.subheadText)
                }
                
                Spacer()
            }
            .padding(LociTheme.Spacing.small)
            .background(LociTheme.Colors.primaryAction.opacity(0.1))
            .cornerRadius(LociTheme.CornerRadius.small)
        }
    }
}

// MARK: - Start One-Place Session Button

struct StartOnePlaceSessionButton: View {
    let canStart: Bool
    let location: SelectedLocation?
    let onStart: () -> Void
    
    var body: some View {
        Button(action: onStart) {
            HStack(spacing: LociTheme.Spacing.small) {
                Image(systemName: "play.fill")
                Text("Start One-Place Session")
            }
        }
        .lociButton(.gradient, isFullWidth: true)
        .disabled(!canStart)
        .opacity(canStart ? 1.0 : 0.6)
    }
}

// MARK: - One-Place Location Picker View

struct OnePlaceLocationPickerView: View {
    @Binding var selectedLocation: SelectedLocation?
    @Binding var mapRegion: MKCoordinateRegion
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var reverseGeocoding: ReverseGeocoding
    
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var isReverseGeocoding = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Map
                Map(coordinateRegion: $mapRegion, annotationItems: annotations) { item in
                    MapAnnotation(coordinate: item.coordinate) {
                        LocationPin(isSelected: true)
                    }
                }
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
        }
    }
    
    private var annotations: [LocationAnnotation] {
        if let coordinate = selectedCoordinate {
            return [LocationAnnotation(coordinate: coordinate)]
        }
        return []
    }
    
    private func selectCurrentLocation() {
        isReverseGeocoding = true
        let coordinate = mapRegion.center
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        reverseGeocoding.reverseGeocode(location: location) { building in
            DispatchQueue.main.async {
                if let building = building {
                    self.selectedLocation = SelectedLocation(
                        coordinate: coordinate,
                        buildingInfo: building,
                        source: .manual
                    )
                } else {
                    // Fallback to coordinate-based location
                    let fallbackBuilding = BuildingInfo(
                        name: "Custom Location",
                        address: String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude),
                        category: .unknown,
                        coordinates: coordinate,
                        confidence: 0.5,
                        neighborhood: nil,
                        city: nil,
                        postalCode: nil,
                        country: nil
                    )
                    
                    self.selectedLocation = SelectedLocation(
                        coordinate: coordinate,
                        buildingInfo: fallbackBuilding,
                        source: .manual
                    )
                }
                
                self.isReverseGeocoding = false
                dismiss()
            }
        }
    }
}

// MARK: - Supporting Types (Reused)

struct SelectedLocation {
    let coordinate: CLLocationCoordinate2D
    let buildingInfo: BuildingInfo
    let source: LocationSource
    
    enum LocationSource {
        case current
        case manual
        case typed
        
        var icon: String {
            switch self {
            case .current: return "location.fill"
            case .manual: return "map.fill"
            case .typed: return "keyboard"
            }
        }
    }
}

struct LocationAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

struct LocationPin: View {
    let isSelected: Bool
    
    var body: some View {
        Image(systemName: "mappin.circle.fill")
            .font(.system(size: 30))
            .foregroundColor(isSelected ? LociTheme.Colors.primaryAction : LociTheme.Colors.secondaryHighlight)
            .background(
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
            )
    }
}

// MARK: - Reused Components

struct SelectedLocationView: View {
    let location: SelectedLocation
    let onRemove: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xSmall) {
                HStack(spacing: LociTheme.Spacing.xSmall) {
                    Image(systemName: location.source.icon)
                        .font(.system(size: 14))
                        .foregroundColor(LociTheme.Colors.secondaryHighlight)
                    
                    Text(location.buildingInfo.name)
                        .font(LociTheme.Typography.body)
                        .foregroundColor(LociTheme.Colors.mainText)
                }
                
                if let address = location.buildingInfo.address {
                    Text(address)
                        .font(LociTheme.Typography.caption)
                        .foregroundColor(LociTheme.Colors.subheadText)
                        .lineLimit(1)
                }
                
                HStack(spacing: LociTheme.Spacing.xxSmall) {
                    Text(location.buildingInfo.category.emoji)
                        .font(.system(size: 12))
                    
                    Text(location.buildingInfo.category.rawValue)
                        .font(LociTheme.Typography.caption)
                        .foregroundColor(LociTheme.Colors.subheadText)
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

struct LocationSelectionOptions: View {
    let onCurrentLocation: () -> Void
    let onManualSelect: () -> Void
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.small) {
            Button(action: onCurrentLocation) {
                HStack {
                    Image(systemName: "location.fill")
                        .font(.system(size: 18))
                    
                    Text("Use Current Location")
                        .font(LociTheme.Typography.body)
                    
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
            
            Button(action: onManualSelect) {
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
                .background(LociTheme.Colors.disabledState.opacity(0.3))
                .cornerRadius(LociTheme.CornerRadius.small)
            }
        }
    }
}
