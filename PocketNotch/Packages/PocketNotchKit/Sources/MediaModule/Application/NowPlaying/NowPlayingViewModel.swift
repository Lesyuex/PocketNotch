import AppKit
import Combine
import PocketNotchCore
import PocketNotchShared
import SwiftUI

enum CompactMediaPresentationIdentity: Equatable {
    case none
    case media
    case volume
    case headphones

    var preferredIslandWidth: CGFloat? {
        switch self {
        case .volume:
            CompactIslandTier.secondTierMinimumWidth
        case .none, .media, .headphones:
            nil
        }
    }
}

private enum DevicePresentationSource {
    case bluetoothConnection
    case audioOutputSwitch
    case playbackResumed
}

private enum DevicePresentationTiming {
    static let playbackResumePresentationDelay: TimeInterval = 10
    static let playbackResumedDisplayDurationMilliseconds = 2_400
    static let airPodsDisplayDurationMilliseconds = Int(
        AudioOutputDeviceSnapshot.airPodsHalfRotationDuration * 1_000
    )
    static let defaultDisplayDurationMilliseconds = 4_000
}

private struct MediaControlIdentity: Equatable {
    let title: String
    let artist: String
    let album: String?
    let sourceBundleIdentifier: String?
}

@MainActor
@Observable
public final class NowPlayingViewModel {
    public private(set) var info: NowPlayingInfo? {
        didSet { infoSubject.send(info) }
    }
    public private(set) var isShuffleEnabled = false
    public private(set) var isCurrentTrackFavorited = false
    /// 只控制媒体是否上岛（compact 常驻显示）；监听、频谱与展开态/锁屏显示不受开关控制。
    public private(set) var isRealtimeMusicMonitoringEnabled: Bool
    private(set) var musicSpectrumConfiguration: MusicSpectrumConfiguration
    /// 只要存在媒体会话就占用常驻位；暂停状态同样持续显示音乐。
    public private(set) var isCompactMediaDisplayActive = false {
        didSet { compactMediaDisplayActiveSubject.send(isCompactMediaDisplayActive) }
    }
    public private(set) var isInitialMediaStateResolved = false {
        didSet { initialStateResolvedSubject.send(isInitialMediaStateResolved) }
    }
    /// info 非空即代表存在媒体会话；暂停时 isPlaying=false，但仍属于有媒体。
    public var hasMedia: Bool { info != nil }
    /// 只有媒体自身封面到达才视为就绪；App 图标只作为前导区域的视觉兜底，不会解锁切歌通知。
    public var isMediaArtworkReady: Bool { info?.artworkData != nil }
    public var playbackCapabilities: MediaPlaybackCapabilities {
        MediaPlaybackCapabilities.resolve(
            sourceBundleIdentifier: info?.sourceBundleIdentifier
        )
    }
    public private(set) var statusText = "读取系统媒体信息中"
    /// 切歌弹窗载荷：识别到新歌曲后立即置值，轮播完由视图调 dismissSongNotification 清空。
    public private(set) var songNotification: SongNotification?
    /// 尾随区域旋律条的频段幅值（[0,1]）。暂停时停止采样并保留最后一帧，视图收拢为稳定暂停形态；仅面板关闭时清空。
    /// 当前频谱快照。高频更新走 `spectrumSubject`，不触发 `objectWillChange`，
    /// 避免展开态下视觉已隐藏的 compact 视图（Hidden Leading/Trailing）被逐帧连带重建。
    private let spectrumSubject = CurrentValueSubject<[Float], Never>([])
    public private(set) var spectrum: [Float] {
        get { spectrumSubject.value }
        set { spectrumSubject.send(newValue) }
    }
    /// 频谱高频通道：只被真正消费 `spectrum` 的视图（展开页 MelodyBars）订阅。
    public var spectrumPublisher: AnyPublisher<[Float], Never> {
        spectrumSubject.eraseToAnyPublisher()
    }
    /// Combine 桥接：`@Observable` 不再提供 `$` 投影，供非 SwiftUI 订阅者（MediaModule、锁屏控制器）观察低频状态。
    @ObservationIgnored private let infoSubject = CurrentValueSubject<NowPlayingInfo?, Never>(nil)
    /// 上一轮已授权的媒体 App 集合，用于在首次获得 Apple Events 授权后立即刷新一次。
    @ObservationIgnored private var previousAuthorizedTargets: Set<String> = []
    @ObservationIgnored private let compactMediaDisplayActiveSubject = CurrentValueSubject<Bool, Never>(false)
    @ObservationIgnored private let initialStateResolvedSubject = CurrentValueSubject<Bool, Never>(false)
    public var infoPublisher: AnyPublisher<NowPlayingInfo?, Never> { infoSubject.eraseToAnyPublisher() }
    public var compactMediaDisplayActivePublisher: AnyPublisher<Bool, Never> {
        compactMediaDisplayActiveSubject.eraseToAnyPublisher()
    }
    public var initialStateResolvedPublisher: AnyPublisher<Bool, Never> {
        initialStateResolvedSubject.eraseToAnyPublisher()
    }
    /// 旋律条渐变用的封面主色（最多 3 个）。仅封面变化时更新，停播不清（避免切歌闪白）。
    public private(set) var spectrumColors: [Color] = []
    /// 按频柱数量保存的逐列渐变：封面横向等分为 4/5/6 列，每根柱取同列的顶部→底部颜色。
    private(set) var spectrumBarGradientsByBarCount: [Int: [SpectrumBarGradient]] = [:]
    /// 封面最右缘颜色（2 个，含稍暗变体）。供展开态封面卡右侧色场衔接用；
    /// 只取边缘色，封面中央主色多扎眼都与其无关。
    public private(set) var edgeColors: [Color] = []
    /// 封面右缘「纵向色带」图：逐行平均色构成的无缝扩展层，
    /// 供展开态封面卡在封面与色场之间做环境色过渡；无内容、无拼接。
    public private(set) var edgeProfile: NSImage?
    /// 前导区域展示图：优先使用媒体封面；切歌后短窗口内等真封面（保留上一张），
    /// 等不到才换成播放 App 图标 —— 图标是「这首歌没有封面」的答案，不是占位。
    /// 统一使用归一化后的压缩封面，不再保留未压缩原图。
    public private(set) var displayArtwork: Data?
    /// 当前播放来源的系统应用图标；独立于封面回退，供展开态封面角标展示。
    public private(set) var sourceApplicationIcon: Data?
    /// 前导区域当前是否展示系统原始 App 图标兜底；用于关闭圆形裁剪和旋转。
    public private(set) var isUsingAppIconFallback = false
    /// 切歌后仍在等真封面。横幅等这个状态解除再弹：封面到了按封面弹，
    /// 等不到就按图标弹。
    public private(set) var isSongArtworkPending = false
    /// 音量键触发的 compact 临时展示；停止调节一段时间后自动清空，恢复当前常驻内容。
    private(set) var volumePresentation: AudioOutputVolumeSnapshot?

    private(set) var volumeIconStyle: VolumeIconStyle = .system

    /// 音量调节提醒的左耳图标：默认用系统音量符号；设为设备图标时，仅有外接输出设备才展示其外形图标，
    /// 本机（内置扬声器）仍保持系统默认的音量符号。
    var volumeIconSymbolName: String? {
        guard let volume = volumePresentation else { return nil }
        if volumeIconStyle == .system || volume.isBuiltIn {
            return volume.volumeSymbolName
        }
        return volume.deviceSymbolName
    }
    /// 蓝牙连接或暂停后恢复播放时的 compact 设备提示；短暂展示后自动恢复原有内容。
    private(set) var headphoneConnectionPresentation: ConnectedHeadphonesSnapshot?
    /// 提示即将退出：先让 compact 两侧内容完成归位与淡出，再真正清空展示数据。
    private(set) var isHeadphoneConnectionDismissing = false
    /// 默认音频输出设备切换时展示的岛下状态通知；生命周期独立于蓝牙连接的 compact 动画。
    private(set) var audioOutputNotification: AudioOutputDeviceSnapshot?
    /// 当前系统默认音频输出，供展开播放器持续展示，不跟随临时通知自动消失。
    private(set) var currentAudioOutput: AudioOutputDeviceSnapshot?
    /// 当前可用的系统音频输出，供展开播放器的设备菜单展示与切换。
    private(set) var availableAudioOutputs: [AudioOutputDevice] = []
    /// 当前默认输出的系统音量；不支持软件音量的设备为 nil。
    private(set) var currentAudioOutputVolume: Double?
    private(set) var isCurrentAudioOutputMuted = false
    /// 音频输出通知即将退出；不影响只属于蓝牙连接事件的 compact 动画。
    private(set) var isAudioOutputNotificationDismissing = false

    var compactPresentationIdentity: CompactMediaPresentationIdentity {
        if volumePresentation != nil { return .volume }
        if headphoneConnectionPresentation != nil { return .headphones }
        if isCompactMediaDisplayActive { return .media }
        return .none
    }

    /// 只有实际渲染在 compact 左右耳的反馈才参与临时内容仲裁。
    /// 岛下方的音频输出通知拥有独立生命周期，不应抢占 compact 层。
    var hasCompactTransientPresentation: Bool {
        volumePresentation != nil || headphoneConnectionPresentation != nil
    }

    /// 上次提取过调色板的封面数据，用于判重、避免重复取色。
    private var lastPaletteArtwork: Data?
    private var songChangeDetector = SongChangeDetector()
    /// App 图标来源：可替换以便在测试里覆盖「没有封面时用图标」的路径。
    var applicationIconProvider = ApplicationIconProvider()
        /// 切歌后「真等封面」的窗口：期间保留上一张封面，到点仍未到达才翻到 App 图标。
    /// 只为「封面晚一个快照到达」的常见情况留短窗口 —— 多数播放器的封面就在
    /// 同一批或下一批快照里，等到了就只翻一次面。取 0.08s：低于「感觉被等了
    /// 一下」的感知阈值（~0.1s），再长就会让静止的旧封面配新标题。
    var songArtworkWaitInterval: TimeInterval = 0.08
    private var pendingSongArtworkTask: Task<Void, Never>?
    /// 当前展示图所属的歌曲：切到新歌而封面未到时据此判定「不能继续用上一首的封面」。
    private var displayedArtworkSongKey: String?
    /// 正在等封面的歌曲：等待窗口期间不因重复快照重起窗口。
    private var pendingArtworkSongKey: String?
    /// 切歌那批快照带来的封面与切歌前显示的字节完全相同 —— 极可能是「先推歌名、
    /// 封面滞后一批」。这类封面先不下定论，等下一批快照确认；窗口与普通情况
    /// 同一把尺子（songArtworkWaitInterval），画面本来就没变化，不额外拖延。
    private var suspectedStaleArtwork: Data?
    /// 同一首歌的横幅幂等窗口：窗口内只更正封面、不再新建第二条。8s 覆盖
    /// 「图标兜底那条 + 真封面那条」「A→B→A 回切」这些几秒内的重复。
    var songBannerIdempotencyWindow: TimeInterval = 8
    /// 横幅落定缓冲：nil 时与等真封面窗口同值（songArtworkWaitInterval），横幅和
    /// 封面用同一把尺子——封面等多久，横幅就等多久，不会一个快一个慢。
    /// 置 0 为同步发布（测试用）。
    var songBannerSettleDelay: TimeInterval?
    private struct PendingSongBanner {
        let key: String
        let info: NowPlayingInfo
        let artwork: Data
    }
    private var pendingSongBanner: PendingSongBanner?
    private var pendingSongBannerTask: Task<Void, Never>?

    private let service: MediaRemoteProviding
    private let notificationSettings: IslandNotificationSettings
    private let notchViewModel: NotchViewModel?
    private var spectrumProvider: AudioSpectrumProviding
    /// compact 渲染端共享的频谱缓冲：FFT 发射线程写入，CVDisplayLink 渲染端每帧读取（不订阅 @Published）。
    let spectrumBuffer = SpectrumBuffer()
    private let spectrumDeliveryGate = SpectrumDeliveryGate()
    private let volumeService: AudioOutputVolumeProviding
    private let bluetoothConnectionService: BluetoothDeviceConnectionProviding
    private let volumeKeyInterceptor: SystemVolumeKeyInterceptorService
    private let shuffleStateRefreshInterval: TimeInterval
    /// MediaRemote 通知不是可靠的传输层；周期性对账用于修复丢失/合并的暂停和切源事件。
    /// 设为 0 可在测试或特殊集成中关闭周期校准，但生产环境保持低频轮询。
    private let mediaStateReconciliationInterval: TimeInterval
    private let playbackResumePresentationDelay: TimeInterval
    private let now: () -> Date
    private var isObserving = false
    private var mediaStateReconciliationTask: Task<Void, Never>?
    private var isSpectrumRunning = false
    /// 锁屏音乐小组件是否在显示（其 MelodyBars 直接读取 `spectrum`）。
    /// 锁屏不可见、岛也未展开时，SwiftUI 端没有 `spectrum` 消费者，不发布 @Published 以消除逐帧视图失效。
    private var isLockScreenSpectrumConsumerActive = false
    private var volumePresentationDismissTask: Task<Void, Never>?
    private var headphonePresentationDismissTask: Task<Void, Never>?
    private var playbackDeviceBatteryTask: Task<Void, Never>?
    private var devicePresentationSource: DevicePresentationSource?
    private var playbackPauseStartedAt: Date?
    private var pausedMediaIdentity: MediaControlIdentity?
    private var audioOutputNotificationDismissTask: Task<Void, Never>?
    private var seekRefreshTask: Task<Void, Never>?
    private var audioOutputDevicesRefreshTask: Task<Void, Never>?
    private var paletteTask: Task<Void, Never>?
    private var paletteGeneration: UInt64 = 0
    private let refreshScheduler = CoalescingAsyncTask()
    private var playbackProgress = PlaybackProgressReconciler()
    private var mediaControlIdentity: MediaControlIdentity?
    /// 横幅幂等表：key → 最近一次真正弹出的时间（窗口外的会被顺手清掉）。
    /// 原先是只记「上一条」的单槽，同key 的重复靠它挡不住：图标兜底那条弹完、
    /// 真封面几秒后才到，单槽已被别的歌覆盖 → 又弹一条。
    private var presentedSongBannerAt: [String: Date] = [:]
    private var shuffleStateSourceIdentifier: String?
    private var lastShuffleStateRefreshAt: Date?
    private var isShuffleCommandInFlight = false
    private var isFavoriteCommandInFlight = false
    private var isAudioOutputPickerPresented = false
    /// 防止多个 MediaRemote 通知触发的异步 refresh 乱序完成后，用旧快照覆盖较新的 UI。
    private var refreshRequestID: UInt64 = 0
    private var lastLoggedRefreshSignature: String?
    private var notificationSuppressionGeneration: UInt64 = 0
    private var monitoringSettings: MediaMonitoringSettings?
    private var monitoringSettingsCancellable: AnyCancellable?
    private var monitoringSettingsCancellables = Set<AnyCancellable>()
    private var notificationSettingsCancellables = Set<AnyCancellable>()
    private var expansionStateCancellable: AnyCancellable?
    /// 权限改为「岛上首次真正用到时才申请」，且每个 App 会话最多触发一次，避免反复弹窗与重复探测。
    private var didRequestMusicControlThisSession = false
    private var didRequestSystemAudioThisSession = false

    private var areNotificationsSuppressed: Bool {
        notchViewModel?.isExpanded == true
    }

    public convenience init(service: MediaRemoteProviding = MediaRemoteService()) {
        self.init(
            service: service,
            monitoringSettings: MediaMonitoringSettings(),
            notificationSettings: IslandNotificationSettings()
        )
    }

    public init(
        service: MediaRemoteProviding = MediaRemoteService(),
        monitoringSettings: MediaMonitoringSettings,
        notificationSettings: IslandNotificationSettings? = nil,
        notchViewModel: NotchViewModel? = nil,
        mediaStateReconciliationInterval: TimeInterval = 10
    ) {
        let notificationSettings = notificationSettings ?? IslandNotificationSettings()
        self.service = service
        self.notificationSettings = notificationSettings
        self.notchViewModel = notchViewModel
        self.isRealtimeMusicMonitoringEnabled = monitoringSettings.isRealtimeMusicMonitoringEnabled
        self.musicSpectrumConfiguration = monitoringSettings.musicSpectrumConfiguration
        // 启动时恢复运行时能力：系统音频捕获仅在系统已授权时使用真实 tap，否则用模拟源。
        // TCC 授权持久，已授权的能力跨启动自动恢复，无需重启应用。
        let captureRestored = monitoringSettings.isSystemAudioCaptureEnabled && isSystemAudioCaptureAuthorized
        if #available(macOS 14.4, *) {
            PocketNotchLog.media.notice(
                "Spectrum restore captureEnabled=\(monitoringSettings.isSystemAudioCaptureEnabled, privacy: .public) granted=\(systemAudioRecordingAuthorization() == .granted, privacy: .public) restored=\(captureRestored, privacy: .public)"
            )
        }
        self.spectrumProvider = makeSpectrumProvider(
            isCaptureEnabled: captureRestored,
            updateRate: monitoringSettings.musicSpectrumUpdateRate
        )
        let volumeService = SystemAudioOutputVolumeService()
        self.volumeService = volumeService
        self.bluetoothConnectionService = SystemBluetoothDeviceConnectionService()
        self.volumeKeyInterceptor = SystemVolumeKeyInterceptorService(volumeController: volumeService)
        self.shuffleStateRefreshInterval = 1
        self.mediaStateReconciliationInterval = max(mediaStateReconciliationInterval, 0)
        self.playbackResumePresentationDelay = DevicePresentationTiming.playbackResumePresentationDelay
        self.now = Date.init
        self.monitoringSettings = monitoringSettings
        observeMonitoringSettings(monitoringSettings)
        observeNotificationSettings(notificationSettings)
        observeExpansionState()
    }

    init(
        service: MediaRemoteProviding,
        spectrumProvider: AudioSpectrumProviding,
        volumeService: AudioOutputVolumeProviding = SystemAudioOutputVolumeService(),
        bluetoothConnectionService: BluetoothDeviceConnectionProviding = SystemBluetoothDeviceConnectionService(),
        realtimeMusicMonitoringEnabled: Bool = true,
        shuffleStateRefreshInterval: TimeInterval = 1,
        playbackResumePresentationDelay: TimeInterval = DevicePresentationTiming.playbackResumePresentationDelay,
        mediaStateReconciliationInterval: TimeInterval = 10,
        now: @escaping () -> Date = Date.init,
        notificationSettings: IslandNotificationSettings? = nil,
        notchViewModel: NotchViewModel? = nil
    ) {
        let notificationSettings = notificationSettings ?? IslandNotificationSettings(defaults: nil)
        self.service = service
        self.notificationSettings = notificationSettings
        self.notchViewModel = notchViewModel
        self.isRealtimeMusicMonitoringEnabled = realtimeMusicMonitoringEnabled
        self.musicSpectrumConfiguration = MusicSpectrumConfiguration(
            style: .five,
            sensitivity: 0.5,
            attackTime: 0.5,
            releaseTime: 0.5
        )
        self.spectrumProvider = spectrumProvider
        self.volumeService = volumeService
        self.bluetoothConnectionService = bluetoothConnectionService
        self.volumeKeyInterceptor = SystemVolumeKeyInterceptorService(volumeController: volumeService)
        self.shuffleStateRefreshInterval = shuffleStateRefreshInterval
        self.mediaStateReconciliationInterval = max(mediaStateReconciliationInterval, 0)
        self.playbackResumePresentationDelay = playbackResumePresentationDelay
        self.now = now
        observeNotificationSettings(notificationSettings)
        observeExpansionState()
    }

    init(
        service: MediaRemoteProviding,
        spectrumProvider: AudioSpectrumProviding,
        volumeService: AudioOutputVolumeProviding = SystemAudioOutputVolumeService(),
        bluetoothConnectionService: BluetoothDeviceConnectionProviding = SystemBluetoothDeviceConnectionService(),
        monitoringSettings: MediaMonitoringSettings,
        shuffleStateRefreshInterval: TimeInterval = 1,
        mediaStateReconciliationInterval: TimeInterval = 10,
        notificationSettings: IslandNotificationSettings? = nil,
        notchViewModel: NotchViewModel? = nil
    ) {
        let notificationSettings = notificationSettings ?? IslandNotificationSettings(defaults: nil)
        self.service = service
        self.notificationSettings = notificationSettings
        self.notchViewModel = notchViewModel
        self.isRealtimeMusicMonitoringEnabled = monitoringSettings.isRealtimeMusicMonitoringEnabled
        self.musicSpectrumConfiguration = monitoringSettings.musicSpectrumConfiguration
        self.spectrumProvider = spectrumProvider
        self.volumeService = volumeService
        self.bluetoothConnectionService = bluetoothConnectionService
        self.volumeKeyInterceptor = SystemVolumeKeyInterceptorService(volumeController: volumeService)
        self.shuffleStateRefreshInterval = shuffleStateRefreshInterval
        self.mediaStateReconciliationInterval = max(mediaStateReconciliationInterval, 0)
        self.playbackResumePresentationDelay = DevicePresentationTiming.playbackResumePresentationDelay
        self.now = Date.init
        self.monitoringSettings = monitoringSettings
        observeMonitoringSettings(monitoringSettings)
        observeNotificationSettings(notificationSettings)
        observeExpansionState()
    }

    public func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        // 蓝牙监听启动时恢复：已开启且系统已授权则直接恢复监听（TCC 授权持久，重启后无需再点）。
        if monitoringSettings?.isBluetoothDeviceMonitoringEnabled == true {
            bluetoothConnectionService.startObserving { [weak self] snapshot in
                Task { @MainActor [weak self] in
                    self?.handleBluetoothDeviceConnection(snapshot)
                }
            }
        }
        isInitialMediaStateResolved = false
        volumeService.setOutputDevicesChangeHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleAudioOutputDevicesRefresh()
            }
        }
        service.startObserving { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleObservedRefresh()
            }
        }
        volumeService.startObserving(
            onVolumeChange: { [weak self] snapshot in
                Task { @MainActor [weak self] in
                    self?.handleVolumeChange(snapshot)
                }
            },
            onOutputDeviceChange: { [weak self] snapshot in
                Task { @MainActor [weak self] in
                    self?.handleAudioOutputDeviceChange(snapshot)
                }
            }
        )
        currentAudioOutput = volumeService.currentOutputDevice()
        refreshAudioOutputDevices()
        refreshAudioOutputVolume()
        reconcileVolumeKeyInterception()
        scheduleRefresh()
        startMediaStateReconciliation()
    }

    public func stopObserving() {
        guard isObserving else { return }
        setAudioOutputPickerPresented(false)
        service.stopObserving()
        volumeKeyInterceptor.stop()
        volumeService.stopObserving()
        bluetoothConnectionService.stopObserving()
        mediaStateReconciliationTask?.cancel()
        mediaStateReconciliationTask = nil
        volumePresentationDismissTask?.cancel()
        volumePresentationDismissTask = nil
        headphonePresentationDismissTask?.cancel()
        headphonePresentationDismissTask = nil
        playbackDeviceBatteryTask?.cancel()
        playbackDeviceBatteryTask = nil
        audioOutputNotificationDismissTask?.cancel()
        audioOutputNotificationDismissTask = nil
        seekRefreshTask?.cancel()
        seekRefreshTask = nil
        audioOutputDevicesRefreshTask?.cancel()
        audioOutputDevicesRefreshTask = nil
        refreshScheduler.cancel()
        cancelPaletteTask()
        playbackProgress.reset()
        mediaControlIdentity = nil
        presentedSongBannerAt.removeAll()
        shuffleStateSourceIdentifier = nil
        lastShuffleStateRefreshAt = nil
        isShuffleEnabled = false
        isCurrentTrackFavorited = false
        volumePresentation = nil
        headphoneConnectionPresentation = nil
        isHeadphoneConnectionDismissing = false
        devicePresentationSource = nil
        playbackPauseStartedAt = nil
        pausedMediaIdentity = nil
        isCompactMediaDisplayActive = false
        isInitialMediaStateResolved = false
        audioOutputNotification = nil
        currentAudioOutput = nil
        availableAudioOutputs = []
        currentAudioOutputVolume = nil
        isCurrentAudioOutputMuted = false
        isAudioOutputNotificationDismissing = false
        isObserving = false
        refreshRequestID &+= 1
        lastLoggedRefreshSignature = nil
        stopSpectrum(clearing: true)
        pendingSongArtworkTask?.cancel()
        pendingSongArtworkTask = nil
        displayArtwork = nil
        sourceApplicationIcon = nil
        isUsingAppIconFallback = false
        isSongArtworkPending = false
        displayedArtworkSongKey = nil
        pendingArtworkSongKey = nil
        lastPaletteArtwork = nil
        songChangeDetector.reset()
        applicationIconProvider.reset()
        clearSongNotification()
    }

    public func refresh() async {
        refreshRequestID &+= 1
        let requestID = refreshRequestID
        let suppressionGeneration = notificationSuppressionGeneration
        let wasSuppressed = areNotificationsSuppressed
        let snapshot = await service.currentSnapshot()
        guard !Task.isCancelled, requestID == refreshRequestID else { return }
        let shouldSuppressNotification = wasSuppressed
            || areNotificationsSuppressed
            || suppressionGeneration != notificationSuppressionGeneration

        let reconciliation = playbackProgress.reconcile(
            snapshot.info,
            currentInfo: info,
            at: Date()
        )
        if reconciliation.didFinishPendingSeek {
            cancelSeekRefreshTask()
        }
        let previousInfo = info
        let resolvedInfo = reconciliation.info
        let refreshSignature = "status=\(snapshot.status)|previousPid=\(previousInfo?.appPID ?? 0)|previousPlaying=\(previousInfo?.isPlaying == true)|nextPid=\(resolvedInfo?.appPID ?? 0)|nextPlaying=\(resolvedInfo?.isPlaying == true)"
        if refreshSignature != lastLoggedRefreshSignature {
            lastLoggedRefreshSignature = refreshSignature
            PocketNotchLog.media.debug("NowPlaying refresh id=\(requestID) \(refreshSignature)")
        }
        info = resolvedInfo
        updateCompactMediaDisplay(for: resolvedInfo)
        isInitialMediaStateResolved = true
        syncFavoriteState(from: resolvedInfo)
        statusText = snapshot.status
        let mediaArtwork = resolvedInfo?.artworkData
        let applicationIcon = applicationIconProvider.iconData(forPID: resolvedInfo?.appPID)
        if sourceApplicationIcon != applicationIcon {
            sourceApplicationIcon = applicationIcon
        }
        applyDisplayArtwork(
            mediaArtwork: mediaArtwork,
            applicationIcon: applicationIcon,
            songKey: resolvedInfo.map(songNotificationKey) ?? ""
        )
        syncSpectrum(isPlaying: resolvedInfo?.isPlaying == true)
        updatePalette(for: displayArtwork)
        detectSongChange(from: resolvedInfo, suppressingNotification: shouldSuppressNotification)
        handlePlaybackTransition(
            from: previousInfo,
            to: resolvedInfo,
            suppressingNotification: shouldSuppressNotification
        )
        await refreshShuffleStateIfNeeded(
            sourceBundleIdentifier: resolvedInfo?.sourceBundleIdentifier
        )
    }

    /// 展示图更新策略（对齐 iOS：切歌立刻换封面，不留上一首）：
    /// - 封面就绪：一次落位新封面并关闭兜底，取消等待计时。
    /// - 切到新歌但封面未到：先真等一个短窗口，期间保留上一张封面 ——
    ///   绝大多数歌曲的封面就在下一批快照里，等到就只翻一次面；
    ///   等不到才翻到 App 图标，图标即该歌的最终封面。
    /// - 同一首歌的封面瞬时缺失（暂停等空报）：不动画面，避免封面闪跳。
    private func applyDisplayArtwork(
        mediaArtwork: Data?,
        applicationIcon: Data?,
        songKey: String
    ) {
        if let mediaArtwork {
            // 切歌那批快照的封面与切歌前显示的字节完全一样：先不下定论，等下一批确认
            // （见 resolveSuspectedStaleCover）。否则「新标题 + 上一首的封面」会直接进横幅。
            if let suspected = suspectedStaleArtwork, songKey == pendingArtworkSongKey {
                if mediaArtwork == suspected {
                    resolveSuspectedStaleCover(songKey: songKey, artwork: mediaArtwork)
                    return
                }
                suspectedStaleArtwork = nil
            } else if isSuspectedStaleCover(songKey: songKey, artwork: mediaArtwork) {
                suspectedStaleArtwork = mediaArtwork
                PocketNotchLog.media.debug(
                    "Artwork stale-cover suspected key=\(songKey) artwork=\(self.artworkFingerprint(mediaArtwork)) display=\(self.artworkFingerprint(self.displayArtwork))"
                )
                beginArtworkWaitWindow(songKey: songKey, interval: songArtworkWaitInterval)
                return
            }

            pendingSongArtworkTask?.cancel()
            pendingSongArtworkTask = nil
            pendingArtworkSongKey = nil
            if displayArtwork != mediaArtwork {
                displayArtwork = mediaArtwork
            }
            if isUsingAppIconFallback {
                isUsingAppIconFallback = false
            }
            displayedArtworkSongKey = songKey
            syncBannerArtwork(songKey: songKey, artwork: mediaArtwork)
            if isSongArtworkPending {
                isSongArtworkPending = false
                // 封面到了：横幅可以起表落定。
                armSongBannerTimer()
            }
            return
        }

        // 展示图仍属于当前这首歌（暂停等空报），或已经在等它的封面：画面不动，
        // 也不重起等待窗口 —— 快照刷新很密，重起会把窗口无限拖长。
        let waitingForSameSong = pendingArtworkSongKey == songKey
        guard !(songKey == displayedArtworkSongKey && !songKey.isEmpty), !waitingForSameSong else {
            return
        }

        guard !songKey.isEmpty else {
            // 会话已结束：没有横幅要等，直接以图标收尾。
            showFallbackIcon(applicationIcon)
            return
        }

        beginArtworkWaitWindow(songKey: songKey, interval: songArtworkWaitInterval)
    }

    /// 切歌时的封面与切歌前显示的字节完全相同 → 极可能是封面滞后一批
    /// （MediaRemote 先推歌名/歌手）。此时画面本来就没变化，多等一会儿不花钱，
    /// 错配（新标题配旧封面）才花钱。
    private func isSuspectedStaleCover(songKey: String, artwork: Data) -> Bool {
        guard let displayed = displayArtwork, !displayed.isEmpty else { return false }
        guard !songKey.isEmpty, songKey != displayedArtworkSongKey else { return false }
        return displayed == artwork
    }

    /// 下一批快照仍是同一张图：确认这就是这首歌的封面（同一张专辑图连播的情况），
    /// 直接认下 —— 不换图、不翻面、不进图标兜底，横照常用这张图。
    private func resolveSuspectedStaleCover(songKey: String, artwork: Data) {
        PocketNotchLog.media.debug(
            "Artwork stale-cover confirmed same cover key=\(songKey) artwork=\(self.artworkFingerprint(artwork))"
        )
        suspectedStaleArtwork = nil
        pendingSongArtworkTask?.cancel()
        pendingSongArtworkTask = nil
        pendingArtworkSongKey = nil
        isUsingAppIconFallback = false
        displayedArtworkSongKey = songKey
        if displayArtwork != artwork {
            displayArtwork = artwork
        }
        if isSongArtworkPending {
            isSongArtworkPending = false
            armSongBannerTimer()
        }
        syncBannerArtwork(songKey: songKey, artwork: artwork)
    }

    private func beginArtworkWaitWindow(songKey: String, interval: TimeInterval) {
        pendingArtworkSongKey = songKey
        isSongArtworkPending = true
        pendingSongArtworkTask?.cancel()
        PocketNotchLog.media.debug(
            "Artwork wait start key=\(songKey) interval=\(interval)s display=\(self.artworkFingerprint(self.displayArtwork))"
        )
        pendingSongArtworkTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(interval))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.pendingSongArtworkTask = nil
            guard self.isSongArtworkPending, self.pendingArtworkSongKey == songKey else { return }
            // 等待窗口到期。此处与 MediaRemoteService 的 180ms 事件防抖存在竞态：
            // 窗口只有 songArtworkWaitInterval(80ms)，比能带来确认的防抖还短，
            // 一旦事件风暴被防抖切开，本计时器必然先于确认快照到期并翻成 App 图标。
            self.suspectedStaleArtwork = nil
            // 窗口内封面始终未到：翻到 App 图标，图标就是这首歌的封面，横照弹。
            self.showFallbackIcon(self.sourceApplicationIcon)
            self.displayedArtworkSongKey = songKey
            self.isSongArtworkPending = false
            PocketNotchLog.media.debug(
                "Artwork wait timeout key=\(songKey) icon=\(self.artworkFingerprint(self.displayArtwork))"
            )
            guard let info = self.info,
                  info.isPlaying,
                  self.notificationSettings.isSongChangeEnabled,
                  !self.areNotificationsSuppressed,
                  self.isUsingAppIconFallback,
                  let icon = self.displayArtwork else {
                self.armSongBannerTimer()
                return
            }
            self.publishSongNotification(from: info, artwork: icon)
        }
    }

    private func showFallbackIcon(_ applicationIcon: Data?) {
        // 这是闪屏的落点：displayArtwork 从真封面换成 App 图标。此前完全无埋点，
        // 所以现场只看得到「闪了一下」而查不到是谁换的。
        pendingArtworkSongKey = nil
        suspectedStaleArtwork = nil
        pendingSongArtworkTask?.cancel()
        pendingSongArtworkTask = nil
        if displayArtwork != applicationIcon {
            displayArtwork = applicationIcon
        }
        isUsingAppIconFallback = applicationIcon != nil
    }

    private func handleVolumeChange(_ snapshot: AudioOutputVolumeSnapshot) {
        syncAudioOutputVolume(from: snapshot)
        currentAudioOutput = AudioOutputDeviceSnapshot(
            deviceName: snapshot.deviceName,
            deviceSymbolName: snapshot.deviceSymbolName
        )
        guard notificationSettings.isVolumeAdjustmentEnabled, !areNotificationsSuppressed else {
            clearVolumePresentation()
            return
        }
        volumePresentation = snapshot
        volumePresentationDismissTask?.cancel()
        volumePresentationDismissTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.volumePresentation = nil
            self?.volumePresentationDismissTask = nil
        }
    }

    private func clearVolumePresentation() {
        volumePresentationDismissTask?.cancel()
        volumePresentationDismissTask = nil
        volumePresentation = nil
    }

    /// 默认音频输出路由变化：不再展示下方面板；只有切到耳机类设备时用 compact 灵动态提示。
    func handleAudioOutputDeviceChange(_ snapshot: AudioOutputDeviceSnapshot) {
        currentAudioOutput = snapshot
        refreshAudioOutputDevices()
        refreshAudioOutputVolume()

        guard notificationSettings.isAudioOutputChangeEnabled,
              !areNotificationsSuppressed,
              snapshot.isHeadphones else {
            if devicePresentationSource == .audioOutputSwitch {
                clearHeadphoneConnectionPresentation()
            }
            return
        }

        showDevicePresentation(
            ConnectedHeadphonesSnapshot(
                deviceName: snapshot.deviceName,
                deviceSymbolName: snapshot.deviceSymbolName,
                batteryPercentage: nil
            ),
            source: .audioOutputSwitch
        )
        guard snapshot.supportsBatteryStatus else { return }
        playbackDeviceBatteryTask = Task { [weak self, snapshot] in
            guard let self else { return }
            let percentage = await self.bluetoothConnectionService.batteryPercentage(
                for: snapshot.deviceName
            )
            guard !Task.isCancelled,
                  self.devicePresentationSource == .audioOutputSwitch,
                  self.headphoneConnectionPresentation?.deviceName == snapshot.deviceName else {
                return
            }
            self.headphoneConnectionPresentation = ConnectedHeadphonesSnapshot(
                deviceName: snapshot.deviceName,
                deviceSymbolName: snapshot.deviceSymbolName,
                batteryPercentage: percentage
            )
            self.playbackDeviceBatteryTask = nil
        }
    }

    /// 真实蓝牙连接事件：展示下方面板“已连接”。后续系统输出路由变化由 compact 灵动态单独处理。
    func handleBluetoothDeviceConnection(_ snapshot: ConnectedHeadphonesSnapshot) {
        guard !areNotificationsSuppressed else {
            clearHeadphoneConnectionPresentation()
            clearAudioOutputNotification()
            return
        }
        guard notificationSettings.isBluetoothConnectionEnabled else {
            if devicePresentationSource == .bluetoothConnection {
                clearHeadphoneConnectionPresentation()
            }
            clearAudioOutputNotification()
            return
        }

        showAudioOutputNotification(
            AudioOutputDeviceSnapshot(
                deviceName: snapshot.deviceName,
                deviceSymbolName: snapshot.deviceSymbolName,
                notificationStatusText: "已连接"
            )
        )
    }

    private func handlePlaybackTransition(
        from previousInfo: NowPlayingInfo?,
        to currentInfo: NowPlayingInfo?,
        suppressingNotification: Bool
    ) {
        guard let currentInfo else {
            playbackPauseStartedAt = nil
            pausedMediaIdentity = nil
            return
        }

        let currentIdentity = mediaIdentity(for: currentInfo)
        guard currentInfo.isPlaying else {
            if let previousInfo, previousInfo.isPlaying,
               mediaIdentity(for: previousInfo) == currentIdentity {
                playbackPauseStartedAt = now()
                pausedMediaIdentity = currentIdentity
            } else if pausedMediaIdentity != currentIdentity {
                // 自动切歌会在暂停快照中换曲；一旦内容变化，就不再视为用户暂停。
                playbackPauseStartedAt = nil
                pausedMediaIdentity = nil
            }
            return
        }

        defer {
            playbackPauseStartedAt = nil
            pausedMediaIdentity = nil
        }
        guard previousInfo?.isPlaying != true,
              let playbackPauseStartedAt,
              pausedMediaIdentity == currentIdentity,
              now().timeIntervalSince(playbackPauseStartedAt) >= playbackResumePresentationDelay,
              !suppressingNotification else { return }
        showCurrentPlaybackDevicePresentation()
    }

    private func updateCompactMediaDisplay(for currentInfo: NowPlayingInfo?) {
        isCompactMediaDisplayActive = isRealtimeMusicMonitoringEnabled && currentInfo != nil
    }

    private func mediaIdentity(for info: NowPlayingInfo) -> MediaControlIdentity {
        MediaControlIdentity(
            title: info.title,
            artist: info.artist,
            album: info.album,
            sourceBundleIdentifier: info.sourceBundleIdentifier
        )
    }

    private func showCurrentPlaybackDevicePresentation() {
        guard !areNotificationsSuppressed,
              let output = currentAudioOutput ?? volumeService.currentOutputDevice() else { return }
        currentAudioOutput = output
        clearVolumePresentation()

        let snapshot = ConnectedHeadphonesSnapshot(
            deviceName: output.deviceName,
            deviceSymbolName: output.deviceSymbolName,
            batteryPercentage: nil
        )
        guard output.isHeadphones else { return }
        showDevicePresentation(snapshot, source: .playbackResumed, schedulesDismissal: false)

        guard output.supportsBatteryStatus else {
            scheduleDevicePresentationDismissal(for: snapshot, source: .playbackResumed)
            return
        }
        playbackDeviceBatteryTask?.cancel()
        playbackDeviceBatteryTask = Task { [weak self, output] in
            guard let self else { return }
            let percentage = await self.bluetoothConnectionService.batteryPercentage(
                for: output.deviceName
            )
            guard !Task.isCancelled,
                  self.devicePresentationSource == .playbackResumed,
                  self.headphoneConnectionPresentation?.deviceName == output.deviceName else {
                return
            }
            let updatedSnapshot = ConnectedHeadphonesSnapshot(
                deviceName: output.deviceName,
                deviceSymbolName: output.deviceSymbolName,
                batteryPercentage: percentage
            )
            self.headphoneConnectionPresentation = updatedSnapshot
            self.playbackDeviceBatteryTask = nil
            self.scheduleDevicePresentationDismissal(
                for: updatedSnapshot,
                source: .playbackResumed
            )
        }
    }

    private func showDevicePresentation(
        _ snapshot: ConnectedHeadphonesSnapshot,
        source: DevicePresentationSource,
        schedulesDismissal: Bool = true
    ) {
        playbackDeviceBatteryTask?.cancel()
        playbackDeviceBatteryTask = nil
        devicePresentationSource = source
        isHeadphoneConnectionDismissing = false
        headphoneConnectionPresentation = snapshot
        headphonePresentationDismissTask?.cancel()
        guard schedulesDismissal else { return }
        scheduleDevicePresentationDismissal(for: snapshot, source: source)
    }

    private func scheduleDevicePresentationDismissal(
        for snapshot: ConnectedHeadphonesSnapshot,
        source: DevicePresentationSource
    ) {
        let isAirPods = AudioOutputDeviceSymbol.isAirPods(
            deviceName: snapshot.deviceName,
            symbolName: snapshot.deviceSymbolName
        )
        headphonePresentationDismissTask?.cancel()
        headphonePresentationDismissTask = Task { [weak self] in
            do {
                // AirPods 保留更充分的模型展示时间；普通设备沿用原有展示时长。
                let duration: Int
                if isAirPods {
                    duration = DevicePresentationTiming.airPodsDisplayDurationMilliseconds
                } else if source == .playbackResumed {
                    duration = DevicePresentationTiming.playbackResumedDisplayDurationMilliseconds
                } else {
                    duration = DevicePresentationTiming.defaultDisplayDurationMilliseconds
                }
                try await Task.sleep(for: .milliseconds(duration))
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.isHeadphoneConnectionDismissing = true

            do {
                try await Task.sleep(
                    for: .seconds(
                        IslandCompactModuleTransitionConfiguration.standard.exitDuration
                    )
                )
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.headphoneConnectionPresentation = nil
            self.isHeadphoneConnectionDismissing = false
            self.devicePresentationSource = nil
            self.headphonePresentationDismissTask = nil
        }
    }

    private func clearHeadphoneConnectionPresentation() {
        headphonePresentationDismissTask?.cancel()
        headphonePresentationDismissTask = nil
        playbackDeviceBatteryTask?.cancel()
        playbackDeviceBatteryTask = nil
        headphoneConnectionPresentation = nil
        isHeadphoneConnectionDismissing = false
        devicePresentationSource = nil
    }

    private func showAudioOutputNotification(_ snapshot: AudioOutputDeviceSnapshot) {
        // 设备事件属于较新的系统事件，应接管尚未结束的切歌通知。
        clearSongNotification()
        audioOutputNotificationDismissTask?.cancel()
        isAudioOutputNotificationDismissing = false
        audioOutputNotification = snapshot
        let dismissalEffect = notificationSettings.audioOutputChangeDismissalEffect
        let dismissalDelay: Duration = dismissalEffect == .standard
            ? .milliseconds(700)
            : dismissalEffect.completionDelay(reduceMotion: false)
        let displayDuration = snapshot.displayDuration
        audioOutputNotificationDismissTask = Task { [weak self, dismissalDelay, displayDuration] in
            do {
                try await Task.sleep(for: .seconds(displayDuration))
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.isAudioOutputNotificationDismissing = true

            do {
                try await Task.sleep(for: dismissalDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.audioOutputNotification = nil
            self.isAudioOutputNotificationDismissing = false
            self.audioOutputNotificationDismissTask = nil
        }
    }

    private func clearAudioOutputNotification() {
        audioOutputNotificationDismissTask?.cancel()
        audioOutputNotificationDismissTask = nil
        audioOutputNotification = nil
        isAudioOutputNotificationDismissing = false
    }

    private func detectSongChange(
        from info: NowPlayingInfo?,
        suppressingNotification: Bool = false
    ) {
        let update = songChangeDetector.update(with: info)
        guard info?.isPlaying == true,
              notificationSettings.isSongChangeEnabled,
              !areNotificationsSuppressed,
              !suppressingNotification else {
            clearSongNotification()
            return
        }

        switch update {
        case .none:
            break
        case .dismiss:
            songNotification = nil
        case .publish(let info, let artwork):
            publishSongNotification(from: info, artwork: artwork)
        }
    }

    private func publishSongNotification(from info: NowPlayingInfo, artwork: Data) {
        let key = songNotificationKey(for: info)
        if let pending = pendingSongBanner, pending.key == key {
            // 同一首歌已有一条在等封面落定的横幅：封面换了就换图并重新起表，
            // 让横幅弹出时就是最终封面；图没变则不重复排程。
            guard pending.artwork != artwork else { return }
            pendingSongBanner = PendingSongBanner(key: key, info: info, artwork: artwork)
            armSongBannerTimer()
            return
        }
        pendingSongBanner = PendingSongBanner(key: key, info: info, artwork: artwork)
        armSongBannerTimer()
    }

    /// 横幅落定计时：仍在等新歌封面（画面已切到 App 图标）时不起表 ——
    /// 此时弹出横幅会显示「新歌标题 + 图标封面」。等封面到达（或等待超时、
    /// 认定该歌没有封面）后再等一个落定缓冲，让横幅与封面翻转 / 磨砂揭示
    /// 的定格帧对齐。
    private func armSongBannerTimer() {
        pendingSongBannerTask?.cancel()
        pendingSongBannerTask = nil
        guard let pendingSongBanner, !isSongArtworkPending else { return }
        let delay = songBannerSettleDelay ?? songArtworkWaitInterval
        // 0 为同步发布（测试等关闭落定等待的场景）。
        guard delay > 0 else {
            self.pendingSongBanner = nil
            presentSongNotification(
                from: pendingSongBanner.info,
                artwork: pendingSongBanner.artwork,
                key: pendingSongBanner.key
            )
            return
        }
        pendingSongBannerTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.pendingSongBannerTask = nil
            guard let banner = self.pendingSongBanner else { return }
            self.pendingSongBanner = nil
            self.presentSongNotification(from: banner.info, artwork: banner.artwork, key: banner.key)
        }
    }

    /// 横幅落地的唯一入口。同一首歌只允许存在**一条**横幅：屏幕上的那条只更正封面，
    /// 幂等窗口内的重复发布直接丢弃 —— 横幅永不重复创建，只会被更正。
    private func presentSongNotification(from info: NowPlayingInfo, artwork: Data, key: String) {
        let current = now()
        prunePresentedSongBanners(at: current)
        // 屏幕上正是这一首：只更正封面，绝不重播出现动画。
        if let banner = songNotification, songNotificationKey(for: banner) == key {
            PocketNotchLog.media.debug(
                "Song banner correct-in-place key=\(key) artwork=\(self.artworkFingerprint(artwork))"
            )
            syncBannerArtwork(songKey: key, artwork: artwork)
            return
        }
        if let presentedAt = presentedSongBannerAt[key],
           current.timeIntervalSince(presentedAt) < songBannerIdempotencyWindow {
            PocketNotchLog.media.debug(
                "Song banner suppressed duplicate key=\(key) since=\(self.songBannerIdempotencyWindow)s"
            )
            return
        }

        // 新歌曲属于更晚发生的事件，此时才接管岛下通知（与封面落定同帧）。
        clearAudioOutputNotification()
        presentedSongBannerAt[key] = current
        songNotification = SongNotification(
            id: UUID(),
            title: info.title,
            artist: info.artist,
            album: info.album,
            artworkData: artwork
        )
        PocketNotchLog.media.debug(
            "Song banner presented key=\(key) artwork=\(self.artworkFingerprint(artwork))"
        )
    }

    private func prunePresentedSongBanners(at date: Date) {
        guard !presentedSongBannerAt.isEmpty else { return }
        presentedSongBannerAt = presentedSongBannerAt.filter {
            date.timeIntervalSince($0.value) < songBannerIdempotencyWindow
        }
    }

    /// 日志用封面指纹：字节数 + 头部字节摘要。够分辨「同一张图」（封面滞后）
    /// 与「换了新图」，又不用把整张封面写进日志。
    private func artworkFingerprint(_ data: Data?) -> String {
        guard let data, !data.isEmpty else { return "nil" }
        let head = data.prefix(4).map { String(format: "%02x", $0) }.joined()
        return "\(data.count)B/\(head)"
    }

    private func songNotificationKey(for info: NowPlayingInfo) -> String {
        "\(info.title)\u{1}\(info.artist)"
    }

    private func songNotificationKey(for banner: SongNotification) -> String {
        "\(banner.title)\u{1}\(banner.artist)"
    }

    /// 封面定稿时，把同一首歌的横幅对齐到这张图：等待落定的直接换图，已经弹出的
    /// 就地改正图（id 不变 → 不重播出现动画）。
    /// MediaRemote 常见「先推歌名 / 歌手、封面还停在上一首」，那批快照里横幅会带着
    /// 旧封面弹出，而 SongChangeDetector 对同一首歌的后续封面不再发事件 ——
    /// 结果横幅整段生命周期都挂着上一首的图。
    private func syncBannerArtwork(songKey: String, artwork: Data) {
        guard !songKey.isEmpty else { return }
        // 落定计时不为 0 时横幅已经起表，封面此刻定稿不必重新起表（会多等一整轮）。
        if let pending = pendingSongBanner, pending.key == songKey, pending.artwork != artwork {
            pendingSongBanner = PendingSongBanner(key: pending.key, info: pending.info, artwork: artwork)
        }
        if let banner = songNotification,
           songNotificationKey(for: banner) == songKey,
           banner.artworkData != artwork {
            songNotification = banner.withArtwork(artwork)
        }
    }

    /// 轮播结束由视图调用，关闭弹窗（窗口随之缩回）。
    public func dismissSongNotification() {
        songNotification = nil
    }

    private func clearSongNotification() {
        songChangeDetector.clearPendingNotification()
        pendingSongBannerTask?.cancel()
        pendingSongBannerTask = nil
        pendingSongBanner = nil
        songNotification = nil
    }

    /// 封面变化时后台提取主色，跳主线程赋值。同一封面只算一次；封面消失不清色（避免切歌闪白）。
    private func updatePalette(for artwork: Data?) {
        guard let artwork, artwork != lastPaletteArtwork else { return }
        lastPaletteArtwork = artwork
        paletteTask?.cancel()
        paletteGeneration &+= 1
        let generation = paletteGeneration
        let colorMode = monitoringSettings?.spectrumBarColorMode ?? .anchor
        paletteTask = Task.detached(priority: .utility) { [weak self] in
            guard !Task.isCancelled else { return }
            let colors = ArtworkPalette.colors(from: artwork)
            let edge = ArtworkPalette.edgeColors(from: artwork)
            let provider = colorMode.makeProvider()
            let barGradients = Dictionary(
                uniqueKeysWithValues: MusicSpectrumBarStyle.allCases.map { style in
                    (style.barCount, provider.barGradients(artwork: artwork, count: style.barCount))
                }
            )
            let side = 24
            let stripRGBA = ArtworkPalette.edgeProfileRGBA(from: artwork, side: side, edgeColumns: 6)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self,
                      self.paletteGeneration == generation else { return }
                self.paletteTask = nil
                guard self.lastPaletteArtwork == artwork else { return }
                if !colors.isEmpty {
                    self.spectrumColors = colors
                }
                if !barGradients.isEmpty {
                    self.spectrumBarGradientsByBarCount = barGradients
                }
                if !edge.isEmpty {
                    self.edgeColors = edge
                }
                if let stripRGBA {
                    self.edgeProfile = ArtworkPalette.stripImage(fromStripRGBA: stripRGBA, side: side)
                }
            }
        }
    }

    private func cancelPaletteTask() {
        paletteGeneration &+= 1
        paletteTask?.cancel()
        paletteTask = nil
    }

    private func observeMonitoringSettings(_ settings: MediaMonitoringSettings) {
        monitoringSettingsCancellable = settings.$isRealtimeMusicMonitoringEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                self.isRealtimeMusicMonitoringEnabled = enabled
                if enabled {
                    self.startObserving()
                    self.syncSpectrum(isPlaying: self.info?.isPlaying == true)
                }
                // 开关只控制是否上岛；监听与频谱采样保持运行以支撑展开态与锁屏显示。
                self.updateCompactMediaDisplay(for: self.info)
            }

        settings.$musicControlAuthorizedApps
            .sink { [weak self] targets in
                guard let self else { return }
                let gainedFirstTarget = !targets.isEmpty && self.previousAuthorizedTargets.isEmpty
                self.previousAuthorizedTargets = Set(targets)
                self.service.setMusicControlAuthorizedTargets(Set(targets))
                // 授权目标刚被更新（用户开启灵动音乐时完成 Apple Events 授权）后，
                // 立即用 fallback 读取一次当前曲目，避免必须等到下一次媒体状态变化
                // （切歌）才在灵动岛上显示音乐。
                if gainedFirstTarget {
                    self.refreshImmediately()
                }
            }
            .store(in: &monitoringSettingsCancellables)

        settings.$spectrumBarColorMode
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] mode in
                guard let self else { return }
                guard let artwork = self.lastPaletteArtwork ?? self.info?.artworkData else { return }
                let provider = mode.makeProvider()
                let barGradients = Dictionary(
                    uniqueKeysWithValues: MusicSpectrumBarStyle.allCases.map { style in
                        (style.barCount, provider.barGradients(artwork: artwork, count: style.barCount))
                    }
                )
                if !barGradients.isEmpty {
                    self.spectrumBarGradientsByBarCount = barGradients
                }
            }
            .store(in: &monitoringSettingsCancellables)

        let fourBarTuple = Publishers.CombineLatest4(
            settings.$fourBarSpectrumSensitivity.removeDuplicates(),
            settings.$fourBarSpectrumAttackTime.removeDuplicates(),
            settings.$fourBarSpectrumReleaseTime.removeDuplicates(),
            settings.$musicSpectrumBarWidthScale.removeDuplicates()
        )
        .combineLatest(settings.$musicSpectrumBarSpacingScale.removeDuplicates())

        let fiveBarTuple = Publishers.CombineLatest4(
            settings.$fiveBarSpectrumSensitivity.removeDuplicates(),
            settings.$fiveBarSpectrumAttackTime.removeDuplicates(),
            settings.$fiveBarSpectrumReleaseTime.removeDuplicates(),
            settings.$musicSpectrumBarWidthScale.removeDuplicates()
        )
        .combineLatest(settings.$musicSpectrumBarSpacingScale.removeDuplicates())

        let sevenBarTuple = Publishers.CombineLatest4(
            settings.$sevenBarSpectrumSensitivity.removeDuplicates(),
            settings.$sevenBarSpectrumAttackTime.removeDuplicates(),
            settings.$sevenBarSpectrumReleaseTime.removeDuplicates(),
            settings.$musicSpectrumBarWidthScale.removeDuplicates()
        )
        .combineLatest(settings.$musicSpectrumBarSpacingScale.removeDuplicates())

        let liveTuning = Publishers.CombineLatest3(
            settings.$musicSpectrumUpdateRate.removeDuplicates(),
            settings.$musicSpectrumRhythmDetail.removeDuplicates(),
            settings.$musicSpectrumCornerRadiusScale.removeDuplicates()
        )

        Publishers.CombineLatest4(
            settings.$musicSpectrumBarStyle.removeDuplicates(),
            fourBarTuple,
            fiveBarTuple,
            sevenBarTuple
        )
        .combineLatest(liveTuning)
        .map { bars, live in
            let (style, fourBar, fiveBar, sevenBar) = bars
            let (updateRate, rhythmDetail, cornerRadiusScale) = live
            switch style {
            case .four:
                let ((sensitivity, attackTime, releaseTime, widthScale), spacingScale) = fourBar
                return MusicSpectrumConfiguration(
                    style: .four,
                    updateRate: updateRate,
                    sensitivity: sensitivity,
                    attackTime: attackTime,
                    releaseTime: releaseTime,
                    rhythmDetail: rhythmDetail,
                    barWidthScale: widthScale,
                    barSpacingScale: spacingScale,
                    barCornerRadiusScale: cornerRadiusScale
                )
            case .five:
                let ((sensitivity, attackTime, releaseTime, widthScale), spacingScale) = fiveBar
                return MusicSpectrumConfiguration(
                    style: .five,
                    updateRate: updateRate,
                    sensitivity: sensitivity,
                    attackTime: attackTime,
                    releaseTime: releaseTime,
                    rhythmDetail: rhythmDetail,
                    barWidthScale: widthScale,
                    barSpacingScale: spacingScale,
                    barCornerRadiusScale: cornerRadiusScale
                )
            case .seven:
                let ((sensitivity, attackTime, releaseTime, widthScale), spacingScale) = sevenBar
                return MusicSpectrumConfiguration(
                    style: .seven,
                    updateRate: updateRate,
                    sensitivity: sensitivity,
                    attackTime: attackTime,
                    releaseTime: releaseTime,
                    rhythmDetail: rhythmDetail,
                    barWidthScale: widthScale,
                    barSpacingScale: spacingScale,
                    barCornerRadiusScale: cornerRadiusScale
                )
            }
        }
        .removeDuplicates()
        .receive(on: RunLoop.main)
        .sink { [weak self] configuration in
            self?.musicSpectrumConfiguration = configuration
        }
        .store(in: &monitoringSettingsCancellables)

        // 音频捕获与蓝牙监听：dropFirst 丢弃启动时恢复的历史值，只在用户开启后才启用，
        // 保证启动/监听过程绝不触发系统隐私弹窗。授权申请不在此处进行——留到岛上首次
        // 真正开始律动采样时按需触发（见 ensureSystemAudioAuthorizationIfNeeded），
        // 拒绝/未授权期间用静态占位源，不模拟假律动。
        settings.$isSystemAudioCaptureEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                let isPlaying = self.info?.isPlaying == true
                if isPlaying {
                    self.stopSpectrum(clearing: false)
                }
                self.spectrumProvider = makeSpectrumProvider(
                    isCaptureEnabled: enabled,
                    updateRate: settings.musicSpectrumUpdateRate
                )
                if isPlaying {
                    self.startSpectrum()
                }
            }
            .store(in: &monitoringSettingsCancellables)

        settings.$musicSpectrumUpdateRate
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] updateRate in
                guard let self else { return }
                // 只调整真实 Tap 内部的 FFT 定时器，不重建 provider，避免重建失败后回落模拟源。
                self.spectrumProvider.updateRate(updateRate)
            }
            .store(in: &monitoringSettingsCancellables)

        settings.$isBluetoothDeviceMonitoringEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self, self.isObserving else { return }
                if enabled {
                    self.bluetoothConnectionService.startObserving { [weak self] snapshot in
                        Task { @MainActor [weak self] in
                            self?.handleBluetoothDeviceConnection(snapshot)
                        }
                    }
                } else {
                    self.bluetoothConnectionService.stopObserving()
                }
            }
            .store(in: &monitoringSettingsCancellables)
    }


    private func observeExpansionState() {
        expansionStateCancellable = notchViewModel?.isExpandedPublisher
            .removeDuplicates()
            .sink { [weak self] isExpanded in
                guard isExpanded, let self else { return }
                self.notificationSuppressionGeneration &+= 1
                self.clearNotificationPresentations()
            }
    }

    private func clearNotificationPresentations() {
        clearVolumePresentation()
        clearHeadphoneConnectionPresentation()
        clearAudioOutputNotification()
        clearSongNotification()
    }

    /// 只有「隐藏系统音量提示」且音量提醒都开启时才接管音量键；任一关闭后按键交回
    /// macOS，原生 OSD 照常出现。PocketNotch 自己的提醒走 CoreAudio 属性监听，
    /// 与接管无关，因此不受这个开关影响。
    /// sink 入参是刚写入的新值——`@Published` 在 willSet 阶段发值，直接读属性会拿到旧值。
    private func reconcileVolumeKeyInterception(
        isSystemVolumeHUDHidden: Bool? = nil,
        isVolumeAdjustmentEnabled: Bool? = nil
    ) {
        let hideSystemHUD = isSystemVolumeHUDHidden ?? notificationSettings.isSystemVolumeHUDHidden
        let adjustmentEnabled = isVolumeAdjustmentEnabled ?? notificationSettings.isVolumeAdjustmentEnabled
        guard isObserving, hideSystemHUD, adjustmentEnabled else {
            volumeKeyInterceptor.stop()
            return
        }
        volumeKeyInterceptor.start()
    }

    private func observeNotificationSettings(_ settings: IslandNotificationSettings) {
        settings.$isSystemVolumeHUDHidden
            .removeDuplicates()
            .sink { [weak self] isHidden in
                self?.reconcileVolumeKeyInterception(isSystemVolumeHUDHidden: isHidden)
            }
            .store(in: &notificationSettingsCancellables)

        settings.$isVolumeAdjustmentEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                self.reconcileVolumeKeyInterception(isVolumeAdjustmentEnabled: enabled)
                if !enabled { self.clearVolumePresentation() }
            }
            .store(in: &notificationSettingsCancellables)

        settings.$volumeIconStyle
            .removeDuplicates()
            .sink { [weak self] style in
                self?.volumeIconStyle = style
            }
            .store(in: &notificationSettingsCancellables)

        settings.$isBluetoothConnectionEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard !enabled, self?.devicePresentationSource == .bluetoothConnection else { return }
                self?.clearHeadphoneConnectionPresentation()
            }
            .store(in: &notificationSettingsCancellables)

        settings.$isAudioOutputChangeEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                if !enabled { self?.clearAudioOutputNotification() }
            }
            .store(in: &notificationSettingsCancellables)

        settings.$isSongChangeEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                if !enabled { self?.clearSongNotification() }
            }
            .store(in: &notificationSettingsCancellables)
    }

    /// 开启音频捕获后按需保证真实 Tap 可用：已授权直接重建真实源；未决定则先请求授权，
    /// 成功再重建。已拒绝保持占位，不再重复弹窗。静默失败（拒绝/未知）不打断播放。
    private func ensureAudioCaptureAuthorizationIfNeeded(
        enabled: Bool,
        updateRate: MusicSpectrumUpdateRate
    ) {
        guard enabled, #available(macOS 14.4, *) else { return }
        switch systemAudioRecordingAuthorization() {
        case .granted:
            applyRealAudioCaptureProvider(updateRate: updateRate)
        case .notDetermined:
            Task { [weak self] in
                let established = await requestSystemAudioRecordingAccess()
                guard let self, established else { return }
                self.applyRealAudioCaptureProvider(updateRate: updateRate)
            }
        case .denied:
            return
        }
    }

    /// 播放中则先停采样，替换为真实 Tap 源后再恢复采样，并记录升级诊断日志。
    private func applyRealAudioCaptureProvider(updateRate: MusicSpectrumUpdateRate) {
        let isPlaying = info?.isPlaying == true
        if isPlaying {
            stopSpectrum(clearing: false)
        }
        spectrumProvider = makeSpectrumProvider(
            isCaptureEnabled: true,
            updateRate: updateRate
        )
        if isPlaying {
            startSpectrum()
        }
        if #available(macOS 14.4, *) {
            PocketNotchLog.media.notice(
                "Spectrum upgrade applied granted=\(systemAudioRecordingAuthorization() == .granted, privacy: .public) real=\(self.spectrumProvider.isRealAudioCapture, privacy: .public)"
            )
        }
    }

    /// 仅播放时跑频谱采样；暂停立即停采样并将频柱归零。
    private func syncSpectrum(isPlaying: Bool) {
        PocketNotchLog.media.debug(
            "Spectrum sync requested active=\(isPlaying) running=\(self.isSpectrumRunning) pid=\(self.info?.appPID ?? 0)"
        )
        if isPlaying {
            ensureSystemAudioAuthorizationIfNeeded()
            startSpectrum()
        } else {
            stopSpectrum(clearing: false)
        }
    }

    /// 岛上首次真正开始律动采样时才申请系统音频录制授权，且每个 App 会话最多一次，
    /// 避免暂停/恢复播放时反复弹窗或重复探测。
    /// 门槛以「当前是否已用上真实捕获」为准而非授权枚举：重启后 init 可能因授权探测
    /// 抖动选了占位源，若之后读到已授权却因枚举分支跳过升级，就会一直无律动。
    private func ensureSystemAudioAuthorizationIfNeeded() {
        guard !didRequestSystemAudioThisSession else { return }
        guard let monitoringSettings, monitoringSettings.isSystemAudioCaptureEnabled else { return }
        guard #available(macOS 14.4, *) else { return }
        guard !spectrumProvider.isRealAudioCapture else { return }
        didRequestSystemAudioThisSession = true
        ensureAudioCaptureAuthorizationIfNeeded(
            enabled: true,
            updateRate: monitoringSettings.musicSpectrumUpdateRate
        )
    }

    private func startSpectrum() {
        guard !isSpectrumRunning else { return }
        isSpectrumRunning = true
        PocketNotchLog.media.debug("Spectrum provider start pid=\(self.info?.appPID ?? 0)")
        let buffer = spectrumBuffer
        spectrumProvider.start { [weak self] values in
            buffer.write(values)
            self?.spectrumDeliveryGate.enqueue(values) { [weak self] values in
                guard let self, self.hasSwiftUISpectrumConsumer else { return }
                self.spectrum = values
            }
        }
    }

    /// 有 SwiftUI 端（展开页 / 锁屏小组件）在消费 `@Published spectrum` 时才发布，
    /// 否则频谱仅写入共享 `SpectrumBuffer` 供 CVDisplayLink 渲染端直读，避免逐帧触发视图无效化。
    private var hasSwiftUISpectrumConsumer: Bool {
        isLockScreenSpectrumConsumerActive || (notchViewModel?.isExpanded ?? false)
    }

    /// 锁屏音乐小组件可见时置 true（其 MelodyBars 直读 `spectrum`），不可见置 false。
    func setLockScreenSpectrumConsumerActive(_ isActive: Bool) {
        isLockScreenSpectrumConsumerActive = isActive
    }

    /// clearing=false：暂停停采样，渲染器将频柱归零；clearing=true：面板关闭，清空频谱。
    private func stopSpectrum(clearing: Bool) {
        if isSpectrumRunning {
            isSpectrumRunning = false
            PocketNotchLog.media.debug(
                "Spectrum provider stop clearing=\(clearing) pid=\(self.info?.appPID ?? 0)"
            )
            spectrumProvider.stop()
        }
        spectrumDeliveryGate.reset()
        if clearing {
            spectrum = []
            spectrumBuffer.clear()
        }
    }

    /// 岛上首次真正发起播放控制时才申请媒体控制（Apple Events）授权，且每个 App 会话
    /// 最多一次，避免重复探测与反复弹窗。仅在目标音乐 App 正在运行时才请求（否则系统
    /// 无法发起授权）；已授权时静默通过。
    private func ensureMusicControlAuthorizationIfNeeded() {
        guard !didRequestMusicControlThisSession else { return }
        guard let monitoringSettings, MusicControlAuthorization.isAnyMusicAppRunning() else { return }
        didRequestMusicControlThisSession = true
        Task { await MusicControlAuthorization.requestAuthorization(for: monitoringSettings) }
    }

    public func togglePlay() {
        ensureMusicControlAuthorizationIfNeeded()
        playbackProgress.discardProtectedProgress()
        service.togglePlay()
        refreshImmediately()
    }

    public func toggleShuffle() async {
        NSLog("[DEBUG_SHUF] NowPlayingViewModel.toggleShuffle called, canShuffle=\(playbackCapabilities.canShuffle), inFlight=\(isShuffleCommandInFlight)")
        guard playbackCapabilities.canShuffle, !isShuffleCommandInFlight else { return }
        let sourceBundleIdentifier = info?.sourceBundleIdentifier
        NSLog("[DEBUG_SHUF] NowPlayingViewModel.toggleShuffle source=\(String(describing: sourceBundleIdentifier))")
        playbackProgress.protect(info)
        isShuffleCommandInFlight = true
        defer { isShuffleCommandInFlight = false }
        _ = await service.toggleShuffle()
        if info?.sourceBundleIdentifier == sourceBundleIdentifier {
            if let isEnabled = await service.shuffleState() {
                NSLog("[DEBUG_SHUF] NowPlayingViewModel.toggleShuffle got state=\(isEnabled)")
                isShuffleEnabled = isEnabled
                shuffleStateSourceIdentifier = sourceBundleIdentifier
                lastShuffleStateRefreshAt = Date()
            } else {
                NSLog("[DEBUG_SHUF] NowPlayingViewModel.toggleShuffle shuffleState returned nil")
            }
        }
    }

    private func fileLog(_ message: String) {
        let path = "/tmp/pn_shuffle_debug.log"
        let line = "[\(Date())] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: path) {
            if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    public func toggleFavorite() async {
        guard playbackCapabilities.canFavorite, !isFavoriteCommandInFlight else { return }
        playbackProgress.protect(info)
        isFavoriteCommandInFlight = true
        defer { isFavoriteCommandInFlight = false }
        guard let isFavorited = await service.toggleFavorite() else {
            return
        }
        isCurrentTrackFavorited = isFavorited
    }

    public func seek(to position: TimeInterval) {
        guard let currentInfo = info,
              let duration = currentInfo.duration,
              duration > 0,
              position.isFinite else {
            return
        }
        let clampedPosition = min(max(position, 0), duration)
        refreshRequestID &+= 1
        let requestedAt = Date()
        info = playbackProgress.beginSeek(
            from: currentInfo,
            to: clampedPosition,
            at: requestedAt
        )
        service.seek(to: clampedPosition)
        seekRefreshTask?.cancel()
        seekRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                await self?.refresh()

                try await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                await self?.refresh()
            } catch {
                return
            }
        }
    }

    public func next() {
        ensureMusicControlAuthorizationIfNeeded()
        playbackProgress.discardProtectedProgress()
        clearPendingSeek()
        clearSongNotification()
        service.next()
        refreshImmediately()
    }

    public func previous() {
        ensureMusicControlAuthorizationIfNeeded()
        playbackProgress.discardProtectedProgress()
        clearPendingSeek()
        clearSongNotification()
        service.previous()
        refreshImmediately()
    }

    public func openCurrentMediaApplication() {
        if let pid = info?.appPID,
           let application = NSRunningApplication(processIdentifier: pid),
           !application.isTerminated {
            application.activate(options: [.activateAllWindows])
            return
        }

        guard let bundleIdentifier = info?.sourceBundleIdentifier,
              let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
              ) else {
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration
        )
    }

    func refreshAudioOutputDevices() {
        let devices = volumeService.availableOutputDevices()
        guard devices != availableAudioOutputs else { return }
        availableAudioOutputs = devices
    }

    private func scheduleAudioOutputDevicesRefresh() {
        audioOutputDevicesRefreshTask?.cancel()
        audioOutputDevicesRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
            guard !Task.isCancelled, let self, self.isObserving else { return }
            self.refreshAudioOutputDevices()
            self.audioOutputDevicesRefreshTask = nil
        }
    }

    func refreshAudioOutputVolume() {
        guard let snapshot = volumeService.currentVolumeSnapshot() else {
            currentAudioOutputVolume = nil
            isCurrentAudioOutputMuted = false
            return
        }
        syncAudioOutputVolume(from: snapshot)
    }

    func setAudioOutputVolume(_ volume: Double) {
        let target = min(max(volume, 0), 1)
        let previousVolume = currentAudioOutputVolume
        let previousMutedState = isCurrentAudioOutputMuted
        currentAudioOutputVolume = target
        if target > 0 {
            isCurrentAudioOutputMuted = false
        }

        guard volumeService.setOutputVolume(Float(target)) else {
            currentAudioOutputVolume = previousVolume
            isCurrentAudioOutputMuted = previousMutedState
            return
        }
    }

    func selectAudioOutputDevice(_ device: AudioOutputDevice) {
        guard !device.isCurrent else { return }
        guard volumeService.selectOutputDevice(id: device.id) else {
            PocketNotchLog.media.warning("Failed to select audio output device: \(device.deviceName)")
            refreshAudioOutputDevices()
            return
        }

        currentAudioOutput = device.snapshot
        availableAudioOutputs = availableAudioOutputs.map { candidate in
            AudioOutputDevice(
                id: candidate.id,
                deviceName: candidate.deviceName,
                deviceSymbolName: candidate.deviceSymbolName,
                isCurrent: candidate.id == device.id
            )
        }
        refreshAudioOutputVolume()
    }

    func setAudioOutputPickerPresented(_ isPresented: Bool) {
        guard isPresented != isAudioOutputPickerPresented else { return }
        isAudioOutputPickerPresented = isPresented
        if isPresented {
            notchViewModel?.beginExpandedContentInteraction()
        } else {
            notchViewModel?.endExpandedContentInteraction()
        }
    }

    private func syncAudioOutputVolume(from snapshot: AudioOutputVolumeSnapshot) {
        currentAudioOutputVolume = Double(min(max(snapshot.volume, 0), 1))
        isCurrentAudioOutputMuted = snapshot.isMuted
    }

    /// 控制命令发出后立即读取一次，不做延迟补刷。
    private func refreshImmediately() {
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        refreshScheduler.schedule { [weak self] in
            await self?.refresh()
        }
    }

    private func scheduleObservedRefresh() {
        guard isObserving else { return }
        scheduleRefresh()
    }

    /// 事件通知负责低延迟更新，周期校准负责最终一致性。
    /// MediaRemote 的通知来自私有框架，系统负载高或多个播放器同时切换时可能丢失；
    /// 该任务只负责触发已有的合并刷新器，不直接读取状态，因此不会并发堆积请求。
    private func startMediaStateReconciliation() {
        mediaStateReconciliationTask?.cancel()
        guard mediaStateReconciliationInterval > 0 else { return }

        let intervalNanoseconds = UInt64(
            max(mediaStateReconciliationInterval, 0.01) * 1_000_000_000
        )
        mediaStateReconciliationTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: intervalNanoseconds)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                guard let self, self.isObserving else { return }
                self.scheduleRefresh()
            }
        }
    }

    private func syncFavoriteState(from info: NowPlayingInfo?) {
        let identity = info.map {
            MediaControlIdentity(
                title: $0.title,
                artist: $0.artist,
                album: $0.album,
                sourceBundleIdentifier: $0.sourceBundleIdentifier
            )
        }
        if identity != mediaControlIdentity {
            mediaControlIdentity = identity
            isCurrentTrackFavorited = info?.isFavorited ?? false
        } else if let isFavorited = info?.isFavorited {
            isCurrentTrackFavorited = isFavorited
        }
    }

    private func refreshShuffleStateIfNeeded(
        sourceBundleIdentifier: String?
    ) async {
        let sourceChanged = sourceBundleIdentifier != shuffleStateSourceIdentifier
        if sourceChanged {
            shuffleStateSourceIdentifier = sourceBundleIdentifier
            lastShuffleStateRefreshAt = nil
            isShuffleEnabled = false
        }

        let capabilities = MediaPlaybackCapabilities.resolve(
            sourceBundleIdentifier: sourceBundleIdentifier
        )
        guard capabilities.canShuffle,
              !isShuffleCommandInFlight else {
            return
        }

        let now = Date()
        if let lastShuffleStateRefreshAt,
           now.timeIntervalSince(lastShuffleStateRefreshAt) < shuffleStateRefreshInterval {
            return
        }
        self.lastShuffleStateRefreshAt = now

        guard let isEnabled = await service.shuffleState(),
              !isShuffleCommandInFlight,
              info?.sourceBundleIdentifier == sourceBundleIdentifier,
              shuffleStateSourceIdentifier == sourceBundleIdentifier else {
            return
        }
        isShuffleEnabled = isEnabled
    }

    private func clearPendingSeek() {
        playbackProgress.clearPendingSeek()
        cancelSeekRefreshTask()
    }

    private func cancelSeekRefreshTask() {
        seekRefreshTask?.cancel()
        seekRefreshTask = nil
    }
}
