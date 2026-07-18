import Foundation
import CoreMotion
import CoreLocation
import Combine

#if canImport(WeatherKit)
import WeatherKit
#endif

#if canImport(HealthKit)
import HealthKit
#endif

// MARK: - EnvironmentState
// The full picture of what the app knows about the world right now.
// This maps 1:1 with what SceneController.update* methods tracked in the original.

public struct EnvironmentState: Equatable {
    // Motion
    public var acceleration: SIMD3<Float> = .zero      // x, y, z — raw CMAcceleration
    public var accelerationMagnitude: Float = 0         // |a| — the key driver of energy
    public var isShaking: Bool = false
    public var isQuiet: Bool = true                     // ambient mic quiet detection

    // Movement
    public var speed: Double = 0                        // m/s from GPS
    public var altitude: Double = 0                     // metres

    // Location context
    public var latitude: Double = 0
    public var longitude: Double = 0
    public var city: String = ""
    public var continent: Continent = .unknown
    public var isAtAirport: Bool = false
    public var airportName: String = ""

    // Time/environment
    public var isDaytime: Bool = true
    public var isFullMoon: Bool = false
    public var isSunny: Bool = false
    public var weatherCondition: WeatherCondition = .clear

    // Health (Apple Watch)
    public var heartRate: Double = 0                    // BPM
    public var hrv: Double = 0                          // SDNN ms — calm/stress signal
}

public enum Continent: String, CaseIterable {
    case northAmerica = "North America"
    case southAmerica = "South America"
    case europe = "Europe"
    case africa = "Africa"
    case asia = "Asia"
    case oceania = "Oceania"
    case antarctica = "Antarctica"
    case unknown = "Unknown"
}

public enum WeatherCondition {
    case clear, cloudy, rain, snow, storm, fog, unknown
}

#if canImport(WeatherKit)
extension WeatherCondition {
    /// Collapses WeatherKit's ~40 conditions onto the handful the mood model uses.
    static func from(_ condition: WeatherKit.WeatherCondition) -> WeatherCondition {
        switch condition {
        case .clear, .mostlyClear, .hot:
            return .clear
        case .cloudy, .mostlyCloudy, .partlyCloudy, .breezy, .windy:
            return .cloudy
        case .drizzle, .rain, .heavyRain, .sunShowers, .freezingDrizzle, .freezingRain,
             .hail, .sleet, .wintryMix:
            return .rain
        case .flurries, .snow, .heavySnow, .blizzard, .blowingSnow, .sunFlurries, .frigid:
            return .snow
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms,
             .strongStorms, .hurricane, .tropicalStorm:
            return .storm
        case .foggy, .haze, .smoky, .blowingDust:
            return .fog
        @unknown default:
            return .unknown
        }
    }
}
#endif

// MARK: - EnvironmentDetector

@MainActor
public class EnvironmentDetector: NSObject, ObservableObject {

    @Published public private(set) var state = EnvironmentState()

    // Derived mood — this is the key output, fed into AudioEngine
    @Published public private(set) var mood: MoodVector = .neutral

    // MARK: - Managers
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()
    private var geocoder = CLGeocoder()

    /// The audio engine owns the mic (one engine for input + output). We read the
    /// room level and quiet/loud state from it rather than opening a second engine.
    private let audioEngine: AudioEngine

    /// Room sound level, 0–1. Exposed so the UI can show a live input meter.
    public var inputLevel: Float { audioEngine.micLevel }

    #if canImport(HealthKit)
    private let healthStore = HKHealthStore()
    #endif

    #if canImport(WeatherKit)
    private let weatherService = WeatherService.shared
    #endif

    // MARK: - Internal state
    private var accelerationHistory: [Float] = []
    private let historyLength = 50          // ~1 second at 50Hz
    private var environmentRefreshTimer: Timer?
    private var audioCancellable: AnyCancellable?

    // Mood is recomputed from sensors arriving at up to 50Hz, but republishing at
    // that rate thrashes SwiftUI and the audio graph. Coalesce to ~10Hz.
    private var moodNeedsUpdate = false
    private var moodThrottleTimer: Timer?

    // Geocoding and weather are rate-limited by Apple — only refetch when the
    // user has actually moved meaningfully, or enough time has passed.
    private var lastGeocodedLocation: CLLocation?
    private var lastWeatherLocation: CLLocation?
    private var lastWeatherFetch: Date?
    private let geocodeMinDistance: CLLocationDistance = 500
    private let weatherMinDistance: CLLocationDistance = 5_000
    private let weatherMinInterval: TimeInterval = 15 * 60

    // MARK: - Init

    public init(audioEngine: AudioEngine) {
        self.audioEngine = audioEngine
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 100 // only update every 100m
    }

    // MARK: - Start / Stop

    public func startDetection() {
        startDeviceMotion()
        startLocation()
        startAudioInput()
        startEnvironmentRefresh()
        startMoodThrottle()
        updateTimeOfDay()
        updateMoonPhase()
    }

    public func stopDetection() {
        motionManager.stopDeviceMotionUpdates()
        locationManager.stopUpdatingLocation()
        audioCancellable = nil
        environmentRefreshTimer?.invalidate()
        moodThrottleTimer?.invalidate()
    }

    // MARK: - Device Motion

    private func startDeviceMotion() {
        // deviceMotion, not raw accelerometer: Core Motion runs a sensor-fusion
        // pass that separates gravity from user acceleration properly. Subtracting
        // 1.0 from the raw magnitude conflates tilting the device with moving it.
        guard motionManager.isDeviceMotionAvailable else {
            print("❌ Device motion not available")
            return
        }
        print("✅ Starting device motion at 50Hz")
        motionManager.deviceMotionUpdateInterval = 1.0 / 50.0

        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: .main
        ) { [weak self] motion, error in
            guard let self, let motion else {
                if let error { print("❌ Motion error: \(error)") }
                return
            }
            Task { @MainActor in self.processMotion(motion) }
        }
    }

    private func processMotion(_ motion: CMDeviceMotion) {
        let ua = motion.userAcceleration          // gravity already removed
        let x = Float(ua.x), y = Float(ua.y), z = Float(ua.z)
        let movementMag = sqrt(x*x + y*y + z*z)

        state.acceleration = SIMD3(x, y, z)

        // Rotation contributes to perceived motion — waving the phone around
        // registers even when linear acceleration stays low.
        let rr = motion.rotationRate
        let rotationMag = Float(sqrt(rr.x*rr.x + rr.y*rr.y + rr.z*rr.z))

        let combined = movementMag + rotationMag * 0.15

        accelerationHistory.append(combined)
        if accelerationHistory.count > historyLength {
            accelerationHistory.removeFirst()
        }

        let avg = accelerationHistory.reduce(0, +) / Float(accelerationHistory.count)
        state.accelerationMagnitude = avg
        state.isShaking = avg > 0.4

        setMoodNeedsUpdate()
    }

    // MARK: - Audio Input

    private func startAudioInput() {
        // The mic is owned by the audio engine now; just observe its quiet/loud
        // state (hysteresis already applied there) and mirror it into the mood.
        audioCancellable = audioEngine.$isQuiet
            .removeDuplicates()
            .sink { [weak self] quiet in
                Task { @MainActor [weak self] in
                    self?.state.isQuiet = quiet
                    self?.setMoodNeedsUpdate()
                }
            }
    }

    // MARK: - Mood throttle

    private func setMoodNeedsUpdate() {
        moodNeedsUpdate = true
    }

    private func startMoodThrottle() {
        moodThrottleTimer?.invalidate()
        moodThrottleTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.moodNeedsUpdate else { return }
                self.moodNeedsUpdate = false
                self.updateMood()
            }
        }
    }

    // MARK: - Location

    private func startLocation() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    private func updateCity(from location: CLLocation) {
        // Actually debounce, by distance. CLGeocoder is hard rate-limited by Apple
        // and starts failing silently if you call it on every location update.
        if let last = lastGeocodedLocation,
           location.distance(from: last) < geocodeMinDistance {
            return
        }
        guard !geocoder.isGeocoding else { return }
        lastGeocodedLocation = location

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self else { return }
            if let error {
                // Clear the marker so the next update retries rather than
                // pinning us to a location we never resolved.
                Task { @MainActor in self.lastGeocodedLocation = nil }
                print("⚠️ Geocode failed: \(error.localizedDescription)")
                return
            }
            guard let placemark = placemarks?.first else { return }
            Task { @MainActor in
                self.state.city = placemark.locality ?? ""
                self.state.continent = Continent.from(placemark: placemark)
                self.state.isAtAirport = self.detectAirport(from: placemark)
                self.state.airportName = placemark.name ?? ""
                self.setMoodNeedsUpdate()
            }
        }
    }

    // MARK: - Weather

    private func updateWeather(for location: CLLocation) {
        #if canImport(WeatherKit)
        // Rate-limit: WeatherKit calls are metered against your account quota.
        if let last = lastWeatherLocation,
           let fetched = lastWeatherFetch,
           location.distance(from: last) < weatherMinDistance,
           Date().timeIntervalSince(fetched) < weatherMinInterval {
            return
        }
        lastWeatherLocation = location
        lastWeatherFetch = Date()

        Task { [weak self] in
            guard let self else { return }
            do {
                let weather = try await weatherService.weather(for: location)
                let current = weather.currentWeather
                await MainActor.run {
                    self.state.weatherCondition = WeatherCondition.from(current.condition)
                    // "Sunny" means clear *and* daylight — a clear midnight is not sunny.
                    self.state.isSunny = current.isDaylight
                        && (current.condition == .clear || current.condition == .mostlyClear)
                    self.setMoodNeedsUpdate()
                }
            } catch {
                // Most common cause: missing the WeatherKit capability on the App ID.
                print("⚠️ WeatherKit failed: \(error.localizedDescription)")
                await MainActor.run { self.lastWeatherFetch = nil }
            }
        }
        #endif
    }

    // MARK: - Time / Astronomy

    private func updateTimeOfDay() {
        let hour = Calendar.current.component(.hour, from: Date())
        state.isDaytime = hour >= 6 && hour < 20
    }

    /// Fraction through the lunar cycle: 0 = new moon, 0.5 = full moon.
    public var moonPhase: Double {
        // Reference new moon: 2000-01-06 18:14 UTC. The previous epoch here was
        // Jan 1 2024, which was not a new moon (the nearest was Jan 11) — that put
        // the phase ~10 days out, so isFullMoon never fired on an actual full moon.
        let referenceNewMoon = Date(timeIntervalSince1970: 947_182_440)
        let synodicMonth = 29.530588853
        let days = Date().timeIntervalSince(referenceNewMoon) / 86400
        let phase = (days.truncatingRemainder(dividingBy: synodicMonth) / synodicMonth)
        return phase < 0 ? phase + 1 : phase
    }

    private func updateMoonPhase() {
        // ±0.07 ≈ ±2 days, which absorbs the drift of this linear model against
        // the real cycle (the moon's orbit is eccentric, so it runs up to ~0.5 day
        // early or late). Verified against known full moons: lands at 0.45–0.48.
        state.isFullMoon = abs(moonPhase - 0.5) < 0.07
    }

    // MARK: - Environment Refresh

    private func startEnvironmentRefresh() {
        // Refresh time/moon/weather periodically — not every frame
        environmentRefreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateTimeOfDay()
                self?.updateMoonPhase()
                self?.setMoodNeedsUpdate()
            }
        }
    }

    // MARK: - Airport Detection

    private func detectAirport(from placemark: CLPlacemark) -> Bool {
        let name = (placemark.name ?? "").lowercased()
        let areasOfInterest = placemark.areasOfInterest ?? []
        return name.contains("airport") || name.contains("terminal") ||
               areasOfInterest.contains { $0.lowercased().contains("airport") }
    }

    // MARK: - HealthKit (Apple Watch)

    public func requestHealthAccess() async {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let types: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        ]

        do {
            try await healthStore.requestAuthorization(toShare: [], read: types)
        } catch {
            print("⚠️ HealthKit authorization failed: \(error.localizedDescription)")
            return
        }

        startHeartRateQuery()
        startHRVQuery()   // was authorized above but never queried — state.hrv sat at 0
        #endif
    }

    #if canImport(HealthKit)
    /// Streams the newest sample of `identifier`, converted to `unit`, into `apply`.
    private func streamSamples(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        apply: @escaping @MainActor (Double) -> Void
    ) {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return }

        let handler: (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = {
            [weak self] _, samples, _, _, error in
            guard self != nil else { return }
            if let error {
                print("⚠️ Health query \(identifier.rawValue) failed: \(error.localizedDescription)")
                return
            }
            guard let sample = samples?.last as? HKQuantitySample else { return }
            let value = sample.quantity.doubleValue(for: unit)
            Task { @MainActor in apply(value) }
        }

        let query = HKAnchoredObjectQuery(
            type: type,
            predicate: HKQuery.predicateForSamples(withStart: Date(), end: nil),
            anchor: nil,
            limit: HKObjectQueryNoLimit,
            resultsHandler: handler
        )
        query.updateHandler = handler
        healthStore.execute(query)
    }
    #endif

    private func startHeartRateQuery() {
        #if canImport(HealthKit)
        streamSamples(.heartRate, unit: HKUnit(from: "count/min")) { [weak self] bpm in
            self?.state.heartRate = bpm
            self?.setMoodNeedsUpdate()
        }
        #endif
    }

    private func startHRVQuery() {
        #if canImport(HealthKit)
        streamSamples(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli)) { [weak self] sdnn in
            self?.state.hrv = sdnn
            self?.setMoodNeedsUpdate()
        }
        #endif
    }

    // MARK: - Mood Derivation

    private func updateMood() {
        var energy: Float = 0
        var valence: Float = 0.5

        // --- Energy axis ---

        // Accelerometer: subtract gravity, amplify — shake/walk should hit 0.5+ easily
        let accelEnergy = min(1.0, state.accelerationMagnitude * 6.0)
        energy += accelEnergy * 0.6

        // Speed: walking=1.4m/s scores ~0.05, vehicle=30m/s scores 0.2
        let speedEnergy = Float(min(1.0, state.speed / 30.0))
        energy += speedEnergy * 0.2

        // Heart rate: resting=60, active=150+
        if state.heartRate > 0 {
            let hrNorm = Float((state.heartRate - 60) / 90)
            energy += max(0, hrNorm) * 0.2
        }

        // Room sound — the signal RjDj was built on. A loud room lifts energy;
        // a silent one pulls it down, so scenes settle when you do.
        let roomLevel = audioEngine.micLevel
        energy += roomLevel * 0.35
        if state.isQuiet { energy -= 0.1 }

        // Clamp energy
        energy = max(0, min(1, energy))

        // --- Valence axis ---

        valence += state.isDaytime ? 0.15 : -0.15
        valence += state.isSunny   ? 0.10 : 0
        valence += state.isFullMoon ? -0.10 : 0
        valence += state.isAtAirport ? -0.05 : 0

        switch state.continent {
        case .antarctica: valence -= 0.2
        default: break
        }

        if state.hrv > 0 {
            let hrvCalm = Float(min(1.0, state.hrv / 60.0))
            valence += (hrvCalm - 0.5) * 0.2
        }

        switch state.weatherCondition {
        case .clear:  valence += 0.1
        case .rain:   valence -= 0.1
        case .storm:  valence -= 0.2; energy = min(1, energy + 0.1)
        case .fog:    valence -= 0.05
        default: break
        }

        valence = max(0, min(1, valence))

        mood = MoodVector(energy: energy, valence: valence)
    }
}

// MARK: - CLLocationManagerDelegate

extension EnvironmentDetector: CLLocationManagerDelegate {
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        state.speed     = max(0, location.speed)
        state.altitude  = location.altitude
        state.latitude  = location.coordinate.latitude
        state.longitude = location.coordinate.longitude
        updateCity(from: location)
        updateWeather(for: location)
        setMoodNeedsUpdate()
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}

// MARK: - Continent Helper

extension Continent {
    static func from(placemark: CLPlacemark) -> Continent {
        // iOS doesn't give continent directly — infer from country code
        guard let code = placemark.isoCountryCode else { return .unknown }
        switch code {
        case "US", "CA", "MX", "GT", "BZ", "HN", "SV", "NI", "CR", "PA":
            return .northAmerica
        case "BR", "AR", "CL", "CO", "PE", "VE", "EC", "BO", "PY", "UY", "GY", "SR", "GF":
            return .southAmerica
        case "GB", "FR", "DE", "IT", "ES", "PT", "NL", "BE", "CH", "AT", "SE", "NO", "DK",
             "FI", "PL", "CZ", "SK", "HU", "RO", "BG", "GR", "IE", "HR", "RS", "UA", "RU":
            return .europe
        case "NG", "ZA", "EG", "KE", "ET", "GH", "TZ", "MA", "DZ", "TN", "CI", "CM", "AO",
             "MZ", "MG", "SN", "ZM", "ZW", "RW", "SD":
            return .africa
        case "CN", "JP", "IN", "KR", "ID", "TH", "VN", "MY", "PH", "SG", "HK", "TW",
             "PK", "BD", "NP", "LK", "MM", "KH", "LA", "MN", "KZ", "UZ", "TR", "SA",
             "AE", "IL", "JO", "LB", "QA", "KW", "BH", "OM":
            return .asia
        case "AU", "NZ", "PG", "FJ", "SB", "VU", "WS", "TO", "PW", "FM", "MH", "KI", "NR", "TV":
            return .oceania
        case "AQ":
            return .antarctica
        default:
            return .unknown
        }
    }
}
