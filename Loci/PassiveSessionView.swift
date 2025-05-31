import SwiftUI
import MapKit
import CoreLocation

// MARK: - Passive Session View

struct PassiveSessionView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var analyticsEngine: AnalyticsEngine
    
    @State private var selectedLocation: SelectedLocation?
    @State private var showingLocationPicker = false
    @State private var showingManualEntry = false
    @State private var isLoadingLocation = false
    @State private var locationError: String?
    
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
                    PassiveSessionHeader()
                    
                    // Location Selection
                    LocationSelectionCard(
                        selectedLocation: $selectedLocation,
                        isLoading: $isLoadingLocation,
                        error: $locationError,
                        onCurrentLocation: getCurrentLocation,
                        onManualSelect: { showingLocationPicker = true }
                    )
                    
                    // Session Info
                    SessionInfoCard(location: selectedLocation)
                    
                    // Start Button
                    StartPassiveSessionButton(
                        canStart: selectedLocation != nil,
                        location: selectedLocation,
                        onStart: startSession
                    )
                    
                    // Privacy Note
                    PrivacyNoteCard()
                }
                .padding(.horizontal, LociTheme.Spacing.medium)
                .padding(.vertical, LociTheme.Spacing.large)
            }
        }
        .sheet(isPresented: $showingLocationPicker) {
            LocationPickerView(
                selectedLocation: $selectedLocation,
                mapRegion: $mapRegion
            )
        }
        .sheet(isPresented: $showingManualEntry) {
            ManualLocationEntryView(selectedLocation: $selectedLocation)
        }
        .onAppear {
            setupInitialLocation()
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
        
        // Get one-time location fix
        if let currentLocation = locationManager.currentLocation {
            // Reverse geocode
            Task {
                let building = await ReverseGeocoding.shared.reverseGeocodeAsync(location: currentLocation)
                
                await MainActor.run {
                    if let building = building {
                        self.selectedLocation = SelectedLocation(
                            coordinate: currentLocation.coordinate,
                            buildingInfo: building,
                            source: .current
                        )
                        self.mapRegion.center = currentLocation.coordinate
                    } else {
                        self.locationError = "Could not determine building name"
                    }
                    self.isLoadingLocation = false
                }
            }
        } else {
            locationError = "Could not get current location"
            isLoadingLocation = false
        }
    }
    
    private func startSession() {
        guard let location = selectedLocation else { return }
        
        // Start passive session using the new SessionManager method
        sessionManager.startSession(mode: .passive, manualRegion: location.buildingInfo.name)
    }
}

// MARK: - Passive Session Header

struct PassiveSessionHeader: View {
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            Image(systemName: "location.square.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
                .glow(color: LociTheme.Colors.secondaryHighlight, radius: 12)
            
            Text("Stay-in-Place Session")
                .font(LociTheme.Typography.heading)
                .foregroundColor(LociTheme.Colors.mainText)
            
            Text("Perfect for coffee shops, libraries, or any fixed location. We'll track your music without continuous location updates.")
                .font(LociTheme.Typography.body)
                .foregroundColor(LociTheme.Colors.mainText.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, LociTheme.Spacing.medium)
    }
}

// MARK: - Location Selection Card

struct LocationSelectionCard: View {
    @Binding var selectedLocation: SelectedLocation?
    @Binding var isLoading: Bool
    @Binding var error: String?
    let onCurrentLocation: () -> Void
    let onManualSelect: () -> Void
    
    var body: some View {
        VStack(spacing: LociTheme.Spacing.medium) {
            HStack {
                Label("Location", systemImage: "location")
                    .font(LociTheme.Typography.subheading)
                    .foregroundColor(LociTheme.Colors.subheadText)
                
                Spacer()
            }
            
            if isLoading {
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: LociTheme.Colors.secondaryHighlight))
                    
                    Text("Finding your location...")
                        .font(LociTheme.Typography.body)
                        .foregroundColor(LociTheme.Colors.mainText.opacity(0.7))
                    
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
                Text(error)
                    .font(LociTheme.Typography.caption)
                    .foregroundColor(LociTheme.Colors.primaryAction)
            }
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer)
    }
}

// MARK: - Selected Location View

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
                        .foregroundColor(LociTheme.Colors.mainText.opacity(0.7))
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
        .background(LociTheme.Colors.cardBackground.opacity(0.5))
        .cornerRadius(LociTheme.CornerRadius.small)
    }
}

// MARK: - Location Selection Options

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
                .background(LociTheme.Colors.cardBackground.opacity(0.5))
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
                .background(LociTheme.Colors.cardBackground.opacity(0.5))
                .cornerRadius(LociTheme.CornerRadius.small)
            }
        }
    }
}

// MARK: - Session Info Card

struct SessionInfoCard: View {
    let location: SelectedLocation?
    
    var body: some View {
        VStack(alignment: .leading, spacing: LociTheme.Spacing.small) {
            Text("Session Details")
                .font(LociTheme.Typography.caption)
                .foregroundColor(LociTheme.Colors.subheadText)
            
            HStack(spacing: LociTheme.Spacing.medium) {
                InfoItem(
                    icon: "music.note",
                    label: "Track Interval",
                    value: "Every 90 seconds"
                )
                
                Spacer()
                
                InfoItem(
                    icon: "battery.100",
                    label: "Battery Impact",
                    value: "Minimal"
                )
            }
            
            Text("Loci will check your Spotify every 90 seconds and associate all tracks with \(location?.buildingInfo.name ?? "your selected location").")
                .font(LociTheme.Typography.caption)
                .foregroundColor(LociTheme.Colors.mainText.opacity(0.7))
                .padding(.top, LociTheme.Spacing.xSmall)
        }
        .padding(LociTheme.Spacing.medium)
        .lociCard(backgroundColor: LociTheme.Colors.contentContainer.opacity(0.5))
    }
}

struct InfoItem: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
            
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(LociTheme.Colors.subheadText)
            
            Text(value)
                .font(LociTheme.Typography.caption)
                .foregroundColor(LociTheme.Colors.mainText)
        }
    }
}

// MARK: - Start Session Button

struct StartPassiveSessionButton: View {
    let canStart: Bool
    let location: SelectedLocation?
    let onStart: () -> Void
    
    var body: some View {
        Button(action: onStart) {
            HStack(spacing: LociTheme.Spacing.small) {
                Image(systemName: "play.fill")
                Text("Start Session")
            }
        }
        .lociButton(.gradient, isFullWidth: true)
        .disabled(!canStart)
        .opacity(canStart ? 1.0 : 0.6)
    }
}

// MARK: - Privacy Note Card

struct PrivacyNoteCard: View {
    var body: some View {
        HStack(spacing: LociTheme.Spacing.small) {
            Image(systemName: "lock.shield")
                .font(.system(size: 16))
                .foregroundColor(LociTheme.Colors.secondaryHighlight)
            
            VStack(alignment: .leading, spacing: LociTheme.Spacing.xxSmall) {
                Text("Privacy First")
                    .font(LociTheme.Typography.caption)
                    .foregroundColor(LociTheme.Colors.mainText)
                
                Text("Location is only captured once at session start. No continuous tracking.")
                    .font(.system(size: 11))
                    .foregroundColor(LociTheme.Colors.mainText.opacity(0.7))
            }
            
            Spacer()
        }
        .padding(LociTheme.Spacing.small)
        .background(LociTheme.Colors.secondaryHighlight.opacity(0.1))
        .cornerRadius(LociTheme.CornerRadius.small)
    }
}

// MARK: - Location Picker View

struct LocationPickerView: View {
    @Binding var selectedLocation: SelectedLocation?
    @Binding var mapRegion: MKCoordinateRegion
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var isReverseGeocoding = false
    @State private var showingSearchBar = false
    @State private var searchText = ""
    
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
                
                // Selection info
                VStack {
                    Spacer()
                    
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
                    
                    HStack {
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
            .navigationTitle("Select Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSearchBar.toggle() }) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(LociTheme.Colors.secondaryHighlight)
                    }
                }
            }
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
        
        Task {
            let building = await ReverseGeocoding.shared.reverseGeocodeAsync(location: location)
            
            await MainActor.run {
                if let building = building {
                    self.selectedLocation = SelectedLocation(
                        coordinate: coordinate,
                        buildingInfo: building,
                        source: .manual
                    )
                    dismiss()
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
                    dismiss()
                }
                isReverseGeocoding = false
            }
        }
    }
}

// MARK: - Manual Location Entry View

struct ManualLocationEntryView: View {
    @Binding var selectedLocation: SelectedLocation?
    @Environment(\.dismiss) var dismiss
    
    @State private var buildingName = ""
    @State private var address = ""
    @State private var selectedCategory: BuildingCategory = .other
    
    var body: some View {
        NavigationView {
            ZStack {
                LociTheme.Colors.appBackground
                    .ignoresSafeArea()
                
                VStack(spacing: LociTheme.Spacing.large) {
                    // Building Name
                    VStack(alignment: .leading, spacing: LociTheme.Spacing.xSmall) {
                        Text("Building Name")
                            .font(LociTheme.Typography.caption)
                            .foregroundColor(LociTheme.Colors.subheadText)
                        
                        TextField("e.g. Blue Bottle Coffee", text: $buildingName)
                            .textFieldStyle(LociTextFieldStyle())
                    }
                    
                    // Address (optional)
                    VStack(alignment: .leading, spacing: LociTheme.Spacing.xSmall) {
                        Text("Address (Optional)")
                            .font(LociTheme.Typography.caption)
                            .foregroundColor(LociTheme.Colors.subheadText)
                        
                        TextField("e.g. 123 Main St", text: $address)
                            .textFieldStyle(LociTextFieldStyle())
                    }
                    
                    // Category
                    VStack(alignment: .leading, spacing: LociTheme.Spacing.xSmall) {
                        Text("Category")
                            .font(LociTheme.Typography.caption)
                            .foregroundColor(LociTheme.Colors.subheadText)
                        
                        CategoryPicker(selectedCategory: $selectedCategory)
                    }
                    
                    Spacer()
                    
                    // Action Buttons
                    HStack {
                        Button("Cancel") {
                            dismiss()
                        }
                        .lociButton(.secondary)
                        
                        Button("Save") {
                            saveManualLocation()
                        }
                        .lociButton(.primary)
                        .disabled(buildingName.isEmpty)
                    }
                }
                .padding()
            }
            .navigationTitle("Enter Location")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func saveManualLocation() {
        // Create manual location with default coordinates
        let building = BuildingInfo(
            name: buildingName,
            address: address.isEmpty ? nil : address,
            category: selectedCategory,
            coordinates: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            confidence: 1.0,
            neighborhood: nil,
            city: nil,
            postalCode: nil,
            country: nil
        )
        
        selectedLocation = SelectedLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            buildingInfo: building,
            source: .typed
        )
        
        dismiss()
    }
}

// MARK: - Category Picker

struct CategoryPicker: View {
    @Binding var selectedCategory: BuildingCategory
    
    let categories = BuildingCategory.allCases.filter { $0 != .unknown }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LociTheme.Spacing.small) {
                ForEach(categories, id: \.self) { category in
                    CategoryChip(
                        category: category,
                        isSelected: selectedCategory == category
                    ) {
                        withAnimation(LociTheme.Animation.smoothEaseInOut) {
                            selectedCategory = category
                        }
                    }
                }
            }
        }
    }
}

struct CategoryChip: View {
    let category: BuildingCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: LociTheme.Spacing.xxSmall) {
                Text(category.emoji)
                Text(category.rawValue)
                    .font(LociTheme.Typography.caption)
            }
            .foregroundColor(isSelected ? LociTheme.Colors.appBackground : LociTheme.Colors.mainText)
            .padding(.horizontal, LociTheme.Spacing.small)
            .padding(.vertical, LociTheme.Spacing.xSmall)
            .background(
                RoundedRectangle(cornerRadius: LociTheme.CornerRadius.small)
                    .fill(isSelected ? LociTheme.Colors.secondaryHighlight : LociTheme.Colors.disabledState)
            )
        }
    }
}

// MARK: - Supporting Types

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

// MARK: - Text Field Style

struct LociTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(LociTheme.Spacing.small)
            .background(LociTheme.Colors.contentContainer)
            .cornerRadius(LociTheme.CornerRadius.small)
            .foregroundColor(LociTheme.Colors.mainText)
    }
}
