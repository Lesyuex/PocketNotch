import Combine
@preconcurrency import CoreLocation
import Foundation

@MainActor
public final class WeatherViewModel: NSObject, ObservableObject {
    @Published public private(set) var snapshot: WeatherSnapshot?
    @Published public private(set) var isMonitoringEnabled: Bool
    @Published public private(set) var statusText = "天气监控未开启"
    @Published public private(set) var locationName: String?
    @Published public private(set) var currentCompactMetric: WeatherCompactMetric

    private let settings: WeatherMonitoringSettings
    private let service: any WeatherProviding
    private let locationManager: CLLocationManager
    private let geocoder = CLGeocoder()
    private let snapshotCache: WeatherSnapshotCache
    private var settingsCancellables = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?
    private var locationRefreshTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var locationRetryTask: Task<Void, Never>?
    private var geocodeTask: Task<Void, Never>?
    private var compactRotationTask: Task<Void, Never>?
    private var compactPresentationCount = 0
    private var isRequestingLocation = false
    private var consecutiveRefreshFailures = 0
    private var lastCoordinate: CLLocationCoordinate2D?
    private var isActive = false
    /// 定位授权改为「岛上首次真正打开天气内容时才申请」，每个 App 会话至多一次。
    private var didRequestLocationThisSession = false

    private static let retryDelays: [Duration] = [
        .seconds(15),
        .seconds(30),
        .seconds(60),
        .seconds(120),
        .seconds(300),
    ]
    private static let refreshInterval: Duration = .seconds(60)

    public convenience init(settings: WeatherMonitoringSettings) {
        self.init(
            settings: settings,
            service: OpenMeteoWeatherService(),
            locationManager: CLLocationManager()
        )
    }

    init(
        settings: WeatherMonitoringSettings,
        service: any WeatherProviding,
        locationManager: CLLocationManager,
        snapshotCache: WeatherSnapshotCache = WeatherSnapshotCache()
    ) {
        self.settings = settings
        self.service = service
        self.locationManager = locationManager
        self.snapshotCache = snapshotCache
        self.isMonitoringEnabled = settings.isWeatherMonitoringEnabled
        self.currentCompactMetric = settings.compactMetrics[0]
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if let savedCoordinate = settings.savedCoordinate {
            lastCoordinate = CLLocationCoordinate2D(
                latitude: savedCoordinate.latitude,
                longitude: savedCoordinate.longitude
            )
        }
        snapshot = snapshotCache.load()
        observeSettings()
    }

    public func activate() {
        guard !isActive else { return }
        isActive = true
        updateCompactMetricRotation()
        // 天气授权前不启动定位与数据获取，避免启动时直接弹出系统定位授权窗口；
        // 用户在授权窗口开启天气后，由 observeSettings 触发 startMonitoring。
        guard settings.isWeatherMonitoringEnabled else { return }
        startMonitoring()
    }

    public func deactivate() {
        isActive = false
        cancelRefreshTasks()
        compactRotationTask?.cancel()
        compactRotationTask = nil
        locationManager.stopUpdatingLocation()
    }

    /// 唤起天气数据：仅在天气已授权时加载，避免未授权时展开页面触发系统定位弹窗。
    public func ensureActiveContent() {
        guard isActive, settings.isWeatherMonitoringEnabled else { return }
        requestLocationAuthorizationIfNeeded()
        if snapshot == nil {
            startMonitoring()
        }
    }

    /// 岛上首次真正打开天气内容、且系统尚未决定定位授权时，发起一次定位授权请求；
    /// 每个 App 会话至多一次。已授权/已拒绝或未开启自动定位时静默跳过。
    private func requestLocationAuthorizationIfNeeded() {
        guard !didRequestLocationThisSession else { return }
        guard settings.isAutomaticLocationEnabled else { return }
        guard CLLocationManager.locationServicesEnabled() else { return }
        guard locationManager.authorizationStatus == .notDetermined else { return }
        didRequestLocationThisSession = true
        locationManager.requestWhenInUseAuthorization()
    }

    private func observeSettings() {
        settings.$isWeatherMonitoringEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                if self.isMonitoringEnabled != enabled {
                    self.isMonitoringEnabled = enabled
                }
                self.updateCompactMetricRotation()
                // 灵动开关只控制灵动显示，不停止天气获取。
                guard self.isActive, enabled else { return }
                self.startMonitoring()
            }
            .store(in: &settingsCancellables)

        settings.$compactMetrics
            .removeDuplicates()
            .sink { [weak self] metrics in
                guard let self, let firstMetric = metrics.first else { return }
                self.currentCompactMetric = firstMetric
                self.updateCompactMetricRotation()
            }
            .store(in: &settingsCancellables)

        settings.$isAutomaticLocationEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                guard let self, self.isActive, self.isMonitoringEnabled else { return }
                if isEnabled {
                    self.updateStatus("正在获取位置")
                    self.requestLocationIfAuthorized()
                } else {
                    self.cancelLocationRetry()
                    self.refreshUsingSavedCoordinate()
                }
            }
            .store(in: &settingsCancellables)
    }

    func beginCompactPresentation() {
        compactPresentationCount += 1
        updateCompactMetricRotation()
    }

    func endCompactPresentation() {
        compactPresentationCount = max(compactPresentationCount - 1, 0)
        updateCompactMetricRotation()
    }

    private func updateCompactMetricRotation() {
        compactRotationTask?.cancel()
        compactRotationTask = nil

        let metrics = settings.compactMetrics
        guard let firstMetric = metrics.first else { return }
        if !metrics.contains(currentCompactMetric) {
            currentCompactMetric = firstMetric
        }
        guard compactPresentationCount > 0,
              isMonitoringEnabled,
              metrics.count > 1 else {
            return
        }

        compactRotationTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(10))
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                self.advanceCompactMetric()
            }
        }
    }

    private func advanceCompactMetric() {
        let metrics = settings.compactMetrics
        guard metrics.count > 1 else { return }
        guard let index = metrics.firstIndex(of: currentCompactMetric) else {
            currentCompactMetric = metrics[0]
            return
        }
        currentCompactMetric = metrics[(index + 1) % metrics.count]
    }

    private func startMonitoring() {
        cancelRetry()
        cancelLocationRetry()
        if snapshot == nil {
            snapshot = snapshotCache.load()
        }
        if settings.isAutomaticLocationEnabled {
            updateStatus("正在获取位置")
            requestLocationIfAuthorized()
        } else {
            refreshUsingSavedCoordinate()
        }
        startRefreshLoop()
    }

    private func stopMonitoring() {
        cancelRefreshTasks()
        locationManager.stopUpdatingLocation()
    }

    private func requestLocationIfAuthorized() {
        guard !isRequestingLocation else { return }
        guard CLLocationManager.locationServicesEnabled() else {
            updateStatus("定位服务不可用")
            return
        }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            // 启动/监听阶段绝不自动请求定位（会弹系统窗）；由 PocketNotch 授权窗口的「定位」项点击触发。
            updateStatus("尚未授权定位，可在 PocketNotch 授权窗口开启")
        case .authorizedAlways, .authorizedWhenInUse:
            isRequestingLocation = true
            locationManager.requestLocation()
        case .denied, .restricted:
            updateStatus("请允许 PocketNotch 使用位置")
        @unknown default:
            updateStatus("无法获取位置")
        }
    }

    private func scheduleLocationRetry() {
        locationRetryTask?.cancel()
        locationRetryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            guard let self, !Task.isCancelled, self.isActive else { return }
            self.locationRetryTask = nil
            self.requestLocationIfAuthorized()
        }
    }

    private func cancelLocationRetry() {
        locationRetryTask?.cancel()
        locationRetryTask = nil
    }

    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Self.refreshInterval)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                if self.settings.isAutomaticLocationEnabled {
                    self.requestLocationIfAuthorized()
                } else if let coordinate = self.lastCoordinate {
                    await self.refreshWeather(at: coordinate)
                }
            }
        }
    }

    private func refreshUsingSavedCoordinate() {
        guard let coordinate = lastCoordinate else {
            updateStatus("请先开启自动定位获取位置")
            return
        }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        updateLocationName(for: location)
        updateStatus("正在更新天气")
        locationRefreshTask?.cancel()
        locationRefreshTask = Task { [weak self] in
            await self?.refreshWeather(at: coordinate)
        }
    }

    private func refreshWeather(at coordinate: CLLocationCoordinate2D) async {
        guard isActive, !Task.isCancelled else { return }
        do {
            let refreshedSnapshot = try await service.currentWeather(at: coordinate)
            guard !Task.isCancelled, isActive else { return }

            cancelRetry()
            snapshotCache.save(refreshedSnapshot)
            if hasVisibleChanges(comparedWith: refreshedSnapshot) {
                snapshot = refreshedSnapshot
            }
            updateStatus(refreshedSnapshot.conditionText)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, isActive else { return }
            if snapshot == nil {
                consecutiveRefreshFailures += 1
                updateStatus("正在重新获取天气")
                scheduleRetry(at: coordinate)
            } else {
                updateStatus("天气更新失败")
            }
        }
    }

    private func scheduleRetry(at coordinate: CLLocationCoordinate2D) {
        guard isActive, snapshot == nil else { return }
        retryTask?.cancel()

        let delayIndex = min(
            max(consecutiveRefreshFailures - 1, 0),
            Self.retryDelays.count - 1
        )
        let delay = Self.retryDelays[delayIndex]
        retryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.retryTask = nil
            await self.refreshWeather(at: coordinate)
        }
    }

    private func cancelRetry() {
        retryTask?.cancel()
        retryTask = nil
        consecutiveRefreshFailures = 0
    }

    private func hasVisibleChanges(comparedWith newSnapshot: WeatherSnapshot) -> Bool {
        guard let snapshot else { return true }
        return snapshot.temperature != newSnapshot.temperature
            || snapshot.apparentTemperature != newSnapshot.apparentTemperature
            || snapshot.humidity != newSnapshot.humidity
            || snapshot.weatherCode != newSnapshot.weatherCode
            || snapshot.isDay != newSnapshot.isDay
            || snapshot.windSpeed != newSnapshot.windSpeed
            || snapshot.windGust != newSnapshot.windGust
            || snapshot.forecast != newSnapshot.forecast
    }

    private func updateStatus(_ newStatus: String) {
        guard statusText != newStatus else { return }
        statusText = newStatus
    }

    private func cancelRefreshTasks() {
        refreshTask?.cancel()
        refreshTask = nil
        locationRefreshTask?.cancel()
        locationRefreshTask = nil
        geocodeTask?.cancel()
        geocodeTask = nil
        geocoder.cancelGeocode()
        cancelRetry()
        cancelLocationRetry()
        isRequestingLocation = false
    }
}

extension WeatherViewModel: @preconcurrency CLLocationManagerDelegate {
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isActive else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            requestLocationIfAuthorized()
        case .denied, .restricted:
            isRequestingLocation = false
            cancelLocationRetry()
            updateStatus("请允许 PocketNotch 使用位置")
        case .notDetermined:
            break
        @unknown default:
            isRequestingLocation = false
            updateStatus("无法获取位置")
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        isRequestingLocation = false
        guard settings.isAutomaticLocationEnabled else { return }
        guard let location = locations.last else { return }
        cancelLocationRetry()
        lastCoordinate = location.coordinate
        settings.saveCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        updateLocationName(for: location)
        cancelRetry()
        locationRefreshTask?.cancel()
        locationRefreshTask = Task { [weak self] in
            await self?.refreshWeather(at: location.coordinate)
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isRequestingLocation = false
        guard isActive else { return }
        guard snapshot == nil else {
            updateStatus("位置更新失败")
            return
        }
        updateStatus("正在重新获取位置")
        scheduleLocationRetry()
    }

    private func updateLocationName(for location: CLLocation) {
        geocodeTask?.cancel()
        geocoder.cancelGeocode()
        geocodeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let placemark = try await geocoder.reverseGeocodeLocation(location).first
                guard !Task.isCancelled, let placemark else { return }
                locationName = Self.displayName(for: placemark)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                locationName = nil
            }
        }
    }

    private static func displayName(for placemark: CLPlacemark) -> String? {
        [placemark.subLocality, placemark.locality, placemark.administrativeArea]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}
