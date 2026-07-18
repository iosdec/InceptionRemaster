import MapKit
import SwiftUI
import Combine

// MARK: - MapSnapshotProvider
// Renders a satellite view of the user's actual location — the "map thing" the
// original showed behind the maze. Uses MapKit's snapshotter (Apple Maps imagery,
// licensed for in-app use) rather than a baked-in tile, so it follows you and
// carries no third-party imagery.

@MainActor
public final class MapSnapshotProvider: ObservableObject {

    @Published public private(set) var image: UIImage?

    /// How far across the snapshot spans, in metres. Roughly a neighbourhood.
    private let spanMetres: CLLocationDistance = 2_500

    private var lastCoordinate: CLLocationCoordinate2D?
    private var isRendering = false

    public init() {}

    /// Regenerate only when the user has moved enough to matter — snapshotting is
    /// expensive and the imagery barely changes within a couple hundred metres.
    public func update(latitude: Double, longitude: Double, size: CGSize) {
        guard latitude != 0 || longitude != 0, size.width > 0 else { return }
        let coord = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)

        if let last = lastCoordinate {
            let moved = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            if moved < 250, image != nil { return }
        }
        guard !isRendering else { return }

        isRendering = true
        lastCoordinate = coord
        render(coordinate: coord, size: size)
    }

    private func render(coordinate: CLLocationCoordinate2D, size: CGSize) {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: spanMetres,
            longitudinalMeters: spanMetres
        )
        options.size = size
        options.mapType = .satellite
        options.showsBuildings = true

        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start(with: .global()) { [weak self] snapshot, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isRendering = false
                if let snapshot {
                    self.image = snapshot.image
                } else if let error {
                    print("⚠️ Map snapshot failed: \(error.localizedDescription)")
                    self.lastCoordinate = nil   // retry on the next update
                }
            }
        }
    }
}
