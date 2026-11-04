import AgentEventModule
import AppKit
import Combine
import CoreLocation
import Foundation
import MediaModule
import StockModule
import WeatherModule

/// 启动时统一设置面板的数据协调器。
///
/// 面板做功能开关，并在开启「灵动音乐 / 实时天气」时直接触发对应的系统授权校验，
/// 避免用户之后还要去设置中心手动授权。授权未就绪时会给出引导提示。
@MainActor
final class PermissionCoordinator: NSObject, ObservableObject {
    struct Feature: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let isOn: Bool
    }

    @Published private(set) var features: [Feature] = []
    @Published private(set) var locationAuthorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var authorizedMusicApps: Set<String> = []
    /// 授权引导文案，由音乐 / 天气授权校验填充。
    @Published var guidance: String?
    @Published var isAgentSelectionPresented = false

    var detectedAgentStatuses: [AgentHookStatus] {
        agentController.agentStatuses.filter(\.isDetected)
    }

    var isInstallingAgentPlugin: Bool {
        agentController.isBusy
    }

    private let mediaSettings: MediaMonitoringSettings
    private let weatherSettings: WeatherMonitoringSettings
    private let stockSettings: StockSettings
    private let agentController: AgentActivityController
    private let locationManager = CLLocationManager()
    private var cancellables: Set<AnyCancellable> = []

    init(
        mediaSettings: MediaMonitoringSettings,
        weatherSettings: WeatherMonitoringSettings,
        stockSettings: StockSettings,
        agentController: AgentActivityController,
        resetsAgentHooks: Bool = false
    ) {
        self.mediaSettings = mediaSettings
        self.weatherSettings = weatherSettings
        self.stockSettings = stockSettings
        self.agentController = agentController
        super.init()
        locationManager.delegate = self
        observeChanges()
        if resetsAgentHooks {
            agentController.resetInstalledHooksForFirstLaunch()
        }
        refresh()
    }

    func setEnabled(_ id: String, _ isOn: Bool) {
        switch id {
        case FeatureID.music:
            mediaSettings.isRealtimeMusicMonitoringEnabled = isOn
            mediaSettings.isSystemAudioCaptureEnabled = isOn
            if isOn {
                Task { await authorizeMusicIfNeeded() }
            }
        case FeatureID.weather:
            weatherSettings.isWeatherMonitoringEnabled = isOn
            if isOn {
                requestLocationAuthorization()
            }
        case FeatureID.stock:
            stockSettings.isPersistent = isOn

        default:
            break
        }
        refresh()
    }

    // MARK: - 授权校验

    /// 音乐 / Spotify 控制授权。仅对正在运行的音乐 App 发起系统「允许控制」提示。
    ///
    /// 灵动音乐本身基于系统媒体会话（MediaRemote）感知任意媒体的播放，不依赖特定 App；
    /// Apple Events 授权只用于灵动岛上的播放控制按钮，属于可选的附加能力。因此即便当前
    /// 没有音乐 App 在运行，灵动音乐也已正常开启，这里只尽力补做控制授权，不阻断开启。
    func authorizeMusicIfNeeded() async {
        guard !MusicControlAuthorization.authorizedTargets(for: mediaSettings)
            .contains(where: isRunningMediaApp) else {
            guidance = nil
            refresh()
            return
        }
        // 没有正在运行的音乐 App 时不打断首次设置流程；播放控制可稍后授权。
        guard MusicControlAuthorization.isAnyMusicAppRunning() else {
            guidance = nil
            refresh()
            return
        }

        let newlyAuthorized = await MusicControlAuthorization.requestAuthorization(
            for: mediaSettings
        )
        if newlyAuthorized.isEmpty, !deniedMusicApps.isEmpty {
            guidance = "媒体控制权限已被拒绝，可前往系统设置的“自动化”中重新开启。"
        } else {
            guidance = nil
        }
        refresh()
    }

    /// 定位授权：用于实时天气。首次开启时向系统请求「使用期间允许」，否则引导前往系统设置。
    func requestLocationAuthorization() {
        guard CLLocationManager.locationServicesEnabled() else {
            guidance = "系统定位服务当前已关闭，请先在系统设置中开启。"
            return
        }
        switch locationAuthorization {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied:
            guidance = "定位权限已被拒绝，可在系统设置中重新开启以获取天气。"
        case .restricted:
            guidance = "定位权限受系统限制，无法使用实时天气。"
        default:
            guidance = nil
        }
        refresh()
    }

    private func isRunningMediaApp(_ appName: String) -> Bool {
        let running = NSWorkspace.shared.runningApplications.map(\.bundleIdentifier)
        switch appName {
        case MusicControlAuthorization.musicAppName:
            return running.contains("com.apple.Music")
        case MusicControlAuthorization.spotifyAppName:
            return running.contains("com.spotify.client")
        default:
            return false
        }
    }

    private var deniedMusicApps: Set<String> {
        Set(mediaSettings.musicControlDeniedApps)
    }

    func setAgentEnabled(_ enabled: Bool, for agent: AgentHookAgent) {
        agentController.setAgentEnabled(enabled, for: agent)
    }

    // MARK: - 状态同步

    private enum FeatureID {
        static let music = "music"
        static let weather = "weather"
        static let stock = "stock"
        static let agent = "agent"
    }

    private func observeChanges() {
        mediaSettings.$isRealtimeMusicMonitoringEnabled
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        weatherSettings.$isWeatherMonitoringEnabled
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        stockSettings.$isPersistent
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        agentController.settings.$isEnabled
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        agentController.$agentStatuses
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        agentController.$isBusy
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    private func refresh() {
        locationAuthorization = locationManager.authorizationStatus
        authorizedMusicApps = MusicControlAuthorization.authorizedTargets(for: mediaSettings)
        features = [
            Feature(
                id: FeatureID.music,
                title: "灵动音乐",
                subtitle: "展示正在播放的音乐、封面与频谱动效",
                symbol: "music.note",
                isOn: mediaSettings.isRealtimeMusicMonitoringEnabled
            ),
            Feature(
                id: FeatureID.weather,
                title: "实时天气",
                subtitle: "显示天气状况",
                symbol: "cloud.sun",
                isOn: weatherSettings.isWeatherMonitoringEnabled
            ),


        ]
    }
}

extension PermissionCoordinator: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refresh()
        if weatherSettings.isWeatherMonitoringEnabled {
            if case .denied = locationAuthorization {
                guidance = "定位权限已被拒绝，可在系统设置中重新开启以获取天气。"
            } else {
                guidance = nil
            }
        }
    }
}
