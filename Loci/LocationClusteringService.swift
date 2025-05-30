import Foundation
import CoreLocation

class LocationClusteringService {
    // Clustering parameters
    private let clusterRadiusMeters: CLLocationDistance = 100 // Buildings within 100m are same cluster
    private let minPointsForCluster = 3
    private let maxClusters = 10000 // Prevent memory issues
    
    private var clusters: [LocationCluster] = []
    private var clusterIndex: [String: LocationCluster] = [:] // Building name -> Cluster
    
    // MARK: - Cluster Management
    
    func findOrCreateCluster(for location: CLLocation, buildingName: String? = nil) -> LocationCluster {
        // First check if we have a cluster for this building name
        if let building = buildingName, let existingCluster = clusterIndex[building] {
            // Update cluster center if needed
            updateClusterCenter(existingCluster, with: location)
            return existingCluster
        }
        
        // Find nearby cluster
        if let nearbyCluster = findNearbyCluster(for: location) {
            // Add building to index if provided
            if let building = buildingName {
                clusterIndex[building] = nearbyCluster
            }
            updateClusterCenter(nearbyCluster, with: location)
            return nearbyCluster
        }
        
        // Create new cluster
        let newCluster = createCluster(at: location, buildingName: buildingName)
        return newCluster
    }
    
    private func findNearbyCluster(for location: CLLocation) -> LocationCluster? {
        let nearestCluster = clusters
            .map { cluster in
                (cluster: cluster, distance: location.distance(from: cluster.centerLocation))
            }
            .filter { $0.distance <= clusterRadiusMeters }
            .min { $0.distance < $1.distance }
        
        return nearestCluster?.cluster
    }
    
    private func createCluster(at location: CLLocation, buildingName: String?) -> LocationCluster {
        let cluster = LocationCluster(
            id: UUID(),
            centerLatitude: location.coordinate.latitude,
            centerLongitude: location.coordinate.longitude,
            radius: clusterRadiusMeters,
            primaryBuilding: buildingName,
            pointCount: 1,
            lastUpdated: Date()
        )
        
        clusters.append(cluster)
        
        // Add to index
        if let building = buildingName {
            clusterIndex[building] = cluster
        }
        
        // Manage cluster count
        if clusters.count > maxClusters {
            mergeSparseCluster()
        }
        
        return cluster
    }
    
    private func updateClusterCenter(_ cluster: LocationCluster, with newLocation: CLLocation) {
        // Update cluster center using weighted average
        let currentCenter = cluster.centerLocation
        let newLat = (currentCenter.coordinate.latitude * Double(cluster.pointCount) + newLocation.coordinate.latitude) / Double(cluster.pointCount + 1)
        let newLon = (currentCenter.coordinate.longitude * Double(cluster.pointCount) + newLocation.coordinate.longitude) / Double(cluster.pointCount + 1)
        
        // Find and update the cluster
        if let index = clusters.firstIndex(where: { $0.id == cluster.id }) {
            clusters[index].centerLatitude = newLat
            clusters[index].centerLongitude = newLon
            clusters[index].pointCount += 1
            clusters[index].lastUpdated = Date()
        }
    }
    
    // MARK: - Cluster Analysis
    
    func getClustersInRegion(center: CLLocation, radius: CLLocationDistance) -> [LocationCluster] {
        return clusters.filter { cluster in
            center.distance(from: cluster.centerLocation) <= radius
        }
    }
    
    func getHotspots(minimumActivity: Int = 10) -> [LocationCluster] {
        return clusters
            .filter { $0.pointCount >= minimumActivity }
            .sorted { $0.pointCount > $1.pointCount }
    }
    
    func mergeNearbyClusters(threshold: CLLocationDistance = 50) {
        var mergedClusters: [LocationCluster] = []
        var processedIds = Set<UUID>()
        
        for cluster in clusters {
            guard !processedIds.contains(cluster.id) else { continue }
            
            // Find all clusters within threshold
            let nearby = clusters.filter { other in
                other.id != cluster.id &&
                !processedIds.contains(other.id) &&
                cluster.centerLocation.distance(from: other.centerLocation) <= threshold
            }
            
            if nearby.isEmpty {
                mergedClusters.append(cluster)
                processedIds.insert(cluster.id)
            } else {
                // Merge clusters
                let allClusters = [cluster] + nearby
                let merged = mergeClusters(allClusters)
                mergedClusters.append(merged)
                
                // Mark all as processed
                allClusters.forEach { processedIds.insert($0.id) }
                
                // Update index
                allClusters.forEach { oldCluster in
                    if let building = oldCluster.primaryBuilding {
                        clusterIndex[building] = merged
                    }
                }
            }
        }
        
        clusters = mergedClusters
    }
    
    private func mergeClusters(_ clustersToMerge: [LocationCluster]) -> LocationCluster {
        let totalPoints = clustersToMerge.reduce(0) { $0 + $1.pointCount }
        
        // Weighted average for center
        let weightedLat = clustersToMerge.reduce(0.0) { sum, cluster in
            sum + (cluster.centerLatitude * Double(cluster.pointCount))
        } / Double(totalPoints)
        
        let weightedLon = clustersToMerge.reduce(0.0) { sum, cluster in
            sum + (cluster.centerLongitude * Double(cluster.pointCount))
        } / Double(totalPoints)
        
        // Choose primary building from largest cluster
        let primaryBuilding = clustersToMerge
            .max { $0.pointCount < $1.pointCount }?
            .primaryBuilding
        
        return LocationCluster(
            id: UUID(),
            centerLatitude: weightedLat,
            centerLongitude: weightedLon,
            radius: clusterRadiusMeters,
            primaryBuilding: primaryBuilding,
            pointCount: totalPoints,
            lastUpdated: Date()
        )
    }
    
    private func mergeSparseCluster() {
        // Remove clusters with least activity
        clusters.sort { $0.pointCount > $1.pointCount }
        let keepCount = Int(Double(maxClusters) * 0.9)
        
        // Remove sparse clusters from index
        let removedClusters = Array(clusters.suffix(from: keepCount))
        removedClusters.forEach { cluster in
            if let building = cluster.primaryBuilding {
                clusterIndex.removeValue(forKey: building)
            }
        }
        
        clusters = Array(clusters.prefix(keepCount))
    }
    
    // MARK: - Persistence
    
    func saveClusters() {
        // Save to UserDefaults or file system
        if let encoded = try? JSONEncoder().encode(clusters) {
            UserDefaults.standard.set(encoded, forKey: "com.loci.locationClusters")
        }
    }
    
    func loadClusters() {
        guard let data = UserDefaults.standard.data(forKey: "com.loci.locationClusters"),
              let decoded = try? JSONDecoder().decode([LocationCluster].self, from: data) else {
            return
        }
        
        clusters = decoded
        
        // Rebuild index
        clusterIndex.removeAll()
        clusters.forEach { cluster in
            if let building = cluster.primaryBuilding {
                clusterIndex[building] = cluster
            }
        }
    }
    
    // MARK: - Statistics
    
    func getClusteringStats() -> ClusteringStatistics {
        let totalClusters = clusters.count
        let totalPoints = clusters.reduce(0) { $0 + $1.pointCount }
        let averageClusterSize = totalClusters > 0 ? Double(totalPoints) / Double(totalClusters) : 0
        
        let largestCluster = clusters.max { $0.pointCount < $1.pointCount }
        let densestArea = findDensestArea()
        
        return ClusteringStatistics(
            totalClusters: totalClusters,
            totalDataPoints: totalPoints,
            averageClusterSize: averageClusterSize,
            largestCluster: largestCluster,
            densestArea: densestArea,
            coverageAreaKm2: calculateCoverageArea()
        )
    }
    
    private func findDensestArea() -> (center: CLLocation, clusterCount: Int)? {
        guard !clusters.isEmpty else { return nil }
        
        // Grid-based density calculation
        let gridSize: CLLocationDistance = 1000 // 1km grid
        var densityGrid: [GridCell: Int] = [:]
        
        for cluster in clusters {
            let gridCell = GridCell(
                latIndex: Int(cluster.centerLatitude * 100), // ~1km precision
                lonIndex: Int(cluster.centerLongitude * 100)
            )
            densityGrid[gridCell, default: 0] += 1
        }
        
        guard let densest = densityGrid.max(by: { $0.value < $1.value }) else { return nil }
        
        let centerLat = Double(densest.key.latIndex) / 100
        let centerLon = Double(densest.key.lonIndex) / 100
        
        return (CLLocation(latitude: centerLat, longitude: centerLon), densest.value)
    }
    
    private func calculateCoverageArea() -> Double {
        guard !clusters.isEmpty else { return 0 }
        
        // Simplified convex hull area calculation
        let lats = clusters.map { $0.centerLatitude }
        let lons = clusters.map { $0.centerLongitude }
        
        let latRange = (lats.max() ?? 0) - (lats.min() ?? 0)
        let lonRange = (lons.max() ?? 0) - (lons.min() ?? 0)
        
        // Approximate km² (very rough for small areas)
        let latKm = latRange * 111.0
        let lonKm = lonRange * 111.0 * cos((lats.max() ?? 0) * .pi / 180)
        
        return latKm * lonKm
    }
}

// MARK: - Supporting Types

struct LocationCluster: Identifiable, Codable, Hashable {
    let id: UUID
    var centerLatitude: Double
    var centerLongitude: Double
    let radius: CLLocationDistance
    var primaryBuilding: String?
    var pointCount: Int
    var lastUpdated: Date
    
    var centerLocation: CLLocation {
        CLLocation(latitude: centerLatitude, longitude: centerLongitude)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: LocationCluster, rhs: LocationCluster) -> Bool {
        lhs.id == rhs.id
    }
}

struct ClusteringStatistics {
    let totalClusters: Int
    let totalDataPoints: Int
    let averageClusterSize: Double
    let largestCluster: LocationCluster?
    let densestArea: (center: CLLocation, clusterCount: Int)?
    let coverageAreaKm2: Double
}

private struct GridCell: Hashable {
    let latIndex: Int
    let lonIndex: Int
}
