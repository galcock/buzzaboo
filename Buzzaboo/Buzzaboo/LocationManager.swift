import CoreLocation
import CloudKit

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var location: CLLocation?
    var userIdentifier: String
    private var lastUpdateTime: Date = Date.distantPast
    private let updateInterval: TimeInterval = 300 // 5 minutes (300 seconds)

    init(userIdentifier: String) {
        self.userIdentifier = userIdentifier
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 50 // Only update if moved more than 50 meters
        print("LocationManager initialized for user: \(userIdentifier)")
        checkLocationAuthorization()
    }

    func checkLocationAuthorization() {
        print("Checking location authorization status")
        switch manager.authorizationStatus {
        case .notDetermined:
            print("Location authorization not determined, requesting permission")
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            print("Location services are restricted or denied. Please enable in Settings.")
        case .authorizedWhenInUse, .authorizedAlways:
            print("Location authorized, starting updates")
            manager.startUpdatingLocation()
        @unknown default:
            print("Unknown authorization status.")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            self.location = location
            
            // Check if we should update CloudKit based on time interval
            let now = Date()
            if now.timeIntervalSince(lastUpdateTime) >= updateInterval {
                lastUpdateTime = now
                print("Location updated after 5 minute interval: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                updateUserLocationInCloudKit(location: location)
            } else {
                // Still track location locally but don't update CloudKit
                print("Location changed but not updating CloudKit yet")
            }
        } else {
            print("No valid location received")
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("Location authorization changed to: \(status.rawValue)")
        checkLocationAuthorization()
    }

    func updateUserLocationInCloudKit(location: CLLocation) {
        print("Attempting to update location in CloudKit for user: \(userIdentifier)")
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "identifier == %@", userIdentifier)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)

        let operation = CKQueryOperation(query: query)
        operation.recordMatchedBlock = { (recordID, result) in
            switch result {
            case .success(let record):
                print("Found record to update location: \(record["firstName"] ?? "Unknown")")
                record["location"] = CLLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                database.save(record) { savedRecord, error in
                    if let error = error {
                        print("Update location save error: \(error.localizedDescription)")
                    } else {
                        print("Location updated in CloudKit for user: \(self.userIdentifier) at \(location.coordinate.latitude), \(location.coordinate.longitude)")
                    }
                }
            case .failure(let error):
                print("Record fetch error for location update: \(error.localizedDescription)")
            }
        }

        operation.queryResultBlock = { result in
            switch result {
            case .success:
                print("Query completed successfully for location update")
            case .failure(let error):
                print("Query operation error for location update: \(error.localizedDescription)")
            }
        }

        database.add(operation)
    }
}
