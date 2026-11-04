import AppKit
import Combine
import PocketNotchCore
import SwiftUI

/// 音量胶囊 HUD 的常量。
enum VolumeHUDDesign {
    /// 胶囊尺寸（iOS 侧边音量指示器的比例）。
    static let capsuleSize = CGSize(width: 38, height: 136)
    /// 胶囊距屏幕右缘的距离。
    static let edgeInset: CGFloat = 26
    /// 音量停止变化后多久淡出。
    static let autoHideInterval: TimeInterval = 1.4
}

/// HUD 内容的状态模型：只承载最新音量快照。
@MainActor
final class VolumeHUDModel: ObservableObject {
    @Published var snapshot = SystemVolumeSnapshot(level: 0, isMuted: true)
    /// 拖动中：填充改为紧跟指针，收敛动画留到松手。
    @Published var isAdjusting = false
}

/// 屏幕右侧居中的音量胶囊 HUD。
///
/// 灵动态的音量提醒由灵动岛双耳承担（`IslandNotificationSettings.isVolumeAdjustmentEnabled`），
/// 本控制器只负责展开态：收起时胶囊不出席，展开时音量/静音变化才让它浮现，
/// 停止变化约 1.4s 后淡出。收起瞬间不强制撤除，让已浮现的胶囊走完自然淡出。
@MainActor
final class VolumeHUDController {
    private let notificationSettings: IslandNotificationSettings
    private let notchViewModel: NotchViewModel
    private let model = VolumeHUDModel()
    private var observer: SystemVolumeObserver?
    private var changeCancellable: AnyCancellable?
    private var expansionCancellable: AnyCancellable?
    private var hideTask: Task<Void, Never>?
    private var panel: VolumeHUDPanel?
    private var isVisible = false
    /// 拖动调节进行中：写回音量会触发监听回环，此期间不重复排自动隐藏。
    private var isAdjusting = false
    /// 任一屏幕的刘海处于展开态。收起不撤除已浮现的胶囊，只是不再接受新的浮现请求。
    private var isIslandExpanded = false

    init(
        notificationSettings: IslandNotificationSettings,
        notchViewModel: NotchViewModel
    ) {
        self.notificationSettings = notificationSettings
        self.notchViewModel = notchViewModel
    }

    private var isVolumeReminderEnabled: Bool {
        notificationSettings.isVolumeAdjustmentEnabled
    }

    func start() {
        guard changeCancellable == nil else { return }
        expansionCancellable = notchViewModel.isExpandedPublisher
            .removeDuplicates()
            .sink { [weak self] isExpanded in
                self?.isIslandExpanded = isExpanded
            }
        let observer = SystemVolumeObserver()
        self.observer = observer
        observer.start()
        changeCancellable = observer.changes
            .sink { [weak self] snapshot in
                self?.handleChange(snapshot)
            }
    }

    func stop() {
        changeCancellable?.cancel()
        changeCancellable = nil
        expansionCancellable?.cancel()
        expansionCancellable = nil
        observer?.stop()
        observer = nil
        hideTask?.cancel()
        hideTask = nil
        dismissPanel(immediately: true)
    }

    private func handleChange(_ snapshot: SystemVolumeSnapshot) {
        guard isVolumeReminderEnabled else { return }
        if !isAdjusting {
            // 收起态不新起浮现，但快照照常更新，避免下次展开时显示旧音量。
            guard isIslandExpanded else {
                model.snapshot = snapshot
                return
            }
            hideTask?.cancel()
            hideTask = nil
            presentPanel()

            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(Int(VolumeHUDDesign.autoHideInterval * 1000)))
                guard !Task.isCancelled else { return }
                self?.dismissPanel(immediately: false)
            }
        }
        model.snapshot = snapshot
    }

    /// 拖动调节：写回系统音量（静音时自动解除），HUD 常驻到松手。
    /// 监听器会因写回而回环触发 handleChange，由 isAdjusting 挡住重复排隐。
    private func handleAdjust(_ level: Double) {
        guard isVolumeReminderEnabled else { return }
        isAdjusting = true
        model.isAdjusting = true
        hideTask?.cancel()
        hideTask = nil
        presentPanel()
        observer?.setLevel(level)
        model.snapshot.level = level
        model.snapshot.isMuted = false
    }

    private func handleAdjustEnd() {
        guard isAdjusting else { return }
        isAdjusting = false
        model.isAdjusting = false
        presentPanel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(VolumeHUDDesign.autoHideInterval * 1000)))
            guard !Task.isCancelled else { return }
            self?.dismissPanel(immediately: false)
        }
    }

    // MARK: - 面板

    private func presentPanel() {
        let panel = makePanelIfNeeded()
        guard positionPanel(panel) else { return }

        if !isVisible {
            isVisible = true
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            animateAlpha(panel, to: 1, duration: 0.2)
        }
    }

    private func dismissPanel(immediately: Bool) {
        guard let panel else { return }
        isVisible = false
        if immediately {
            panel.orderOut(nil)
            return
        }
        animateAlpha(panel, to: 0, duration: 0.22) { [weak self, weak panel] in
            // 淡出期间音量再次变化会重新拉起面板，此时不能再收掉。
            guard let panel, self?.isVisible != true else { return }
            panel.orderOut(nil)
        }
    }

    private func animateAlpha(_ panel: NSPanel, to value: CGFloat, duration: TimeInterval, completion: (() -> Void)? = nil) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = value
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 1.0, 0.35, 1.0)
            panel.animator().alphaValue = value
        }, completionHandler: completion)
    }

    private func makePanelIfNeeded() -> VolumeHUDPanel {
        if let panel { return panel }
        let size = VolumeHUDDesign.capsuleSize
        let panel = VolumeHUDPanel(contentRect: NSRect(origin: .zero, size: size))
        let hostingView = NSHostingView(
            rootView: VolumeCapsuleView(
                model: model,
                onAdjust: { [weak self] level in
                    self?.handleAdjust(level)
                },
                onDragEnd: { [weak self] in
                    self?.handleAdjustEnd()
                }
            )
                .frame(width: size.width, height: size.height)
        )
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        panel.contentView = hostingView
        self.panel = panel
        return panel
    }

    /// 落屏到鼠标所在屏幕右缘垂直居中，失败时退回主屏。
    @discardableResult
    private func positionPanel(_ panel: NSPanel) -> Bool {
        guard let screen = targetScreen() else { return false }
        let size = VolumeHUDDesign.capsuleSize
        let screenFrame = screen.frame
        let x = screenFrame.maxX - size.width - VolumeHUDDesign.edgeInset
        let y = screenFrame.midY - size.height / 2
        panel.setFrame(
            CGRect(origin: CGPoint(x: x.rounded(), y: y.rounded()), size: size),
            display: false
        )
        return true
    }

    private func targetScreen() -> NSScreen? {
        let cursor = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(cursor) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}

/// 右侧音量胶囊的无激活覆盖面板。
@MainActor
final class VolumeHUDPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// iOS 风格的音量胶囊：深色背板 + 自底向上的白色电平填充 + 底部扬声器图标。
/// 支持按住拖动（点按定位 + 上下滑动微调）直接调节系统音量。
struct VolumeCapsuleView: View {
    @ObservedObject var model: VolumeHUDModel
    /// 拖动产生的目标音量（0–1）。拖动期间由控制器负责写回系统并暂停自动隐藏。
    var onAdjust: ((Double) -> Void)?
    var onDragEnd: (() -> Void)?

    private static let volumeSymbols = [
        "speaker.slash.fill",
        "speaker.wave.2.fill"
    ]

    /// 实际显示的电平。目标值变化时用 spring 追过来，让每一步音量都有连续运动。
    @State private var displayedLevel: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            // 用 scaleEffect(y:) 而不是 frame(height:)：后者每帧都要重排 VStack+Spacer 布局，
            // 快速连续调音量时会掉帧显得僵硬。缩放是 transform，交给渲染层跑。
            // scaleEffect 不依赖容器对齐，玻璃背板重新托管内容也不受影响。
            Rectangle()
                .fill(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(x: 1, y: clampedLevel, anchor: .bottom)

            icon
                .foregroundStyle(iconForeground)
                .padding(.bottom, 16)
        }
        .frame(
            width: VolumeHUDDesign.capsuleSize.width,
            height: VolumeHUDDesign.capsuleSize.height
        )
        // macOS 26+ Liquid Glass 背板；旧系统回退为纯黑 + 细描边（与灵动态一致）。
        .islandGlassBackground(in: Capsule())
        // 裁剪放在玻璃之后作为最终权威：glassEffect 会重新托管内容，
        // 之前的前置 clipShape 管不住填充的方形顶角，会在顶部圆角外露出。
        .clipShape(Capsule())
        .onAppear { displayedLevel = targetLevel }
        .onChange(of: targetLevel) { _, newValue in
            guard displayedLevel != newValue else { return }
            withAnimation(fillAnimation) { displayedLevel = newValue }
        }
        .animation(.easeOut(duration: 0.12), value: symbolName)
        .contentShape(Capsule())
        .gesture(dragGesture)
    }

    private var targetLevel: CGFloat {
        model.snapshot.isMuted ? 0 : CGFloat(model.snapshot.level)
    }

    /// spring 允许状态过冲，但显示必须夹在胶囊内，否则过冲瞬间白条会盖过顶部圆角。
    private var clampedLevel: CGFloat {
        min(max(displayedLevel, 0), 1)
    }

    private var fillAnimation: Animation {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            return .linear(duration: 0.01)
        }
        // 拖动时用短促的 interactive spring 抹平鼠标事件的抖动，同时不落后于指针；
        // blendDuration 归零，否则默认 0.25 的线性混合会让填充明显拖在指针后面。
        // 音量键等离散变化才给带轻微回弹的完整收敛，读起来有材质弹性而不是瞬移。
        return model.isAdjusting
            ? .interactiveSpring(duration: 0.12, extraBounce: 0, blendDuration: 0)
            : .spring(duration: 0.30, bounce: 0.16)
    }

    /// 点按定位 + 相对拖动：起手处音量直接跳到触点，之后按位移微调（上增下减）。
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let height = VolumeHUDDesign.capsuleSize.height
                let startLevel = 1 - min(max(value.startLocation.y / height, 0), 1)
                let level = startLevel - value.translation.height / height
                onAdjust?(min(max(level, 0), 1))
            }
            .onEnded { _ in
                onDragEnd?()
            }
    }

    private var fillHeight: CGFloat {
        VolumeHUDDesign.capsuleSize.height * clampedLevel
    }

    /// 双符号交叉淡化：固定扬声器主体位置，只切换静音与否，避免换符号时的闪跳。
    private var icon: some View {
        ZStack {
            ForEach(Self.volumeSymbols, id: \.self) { name in
                Image(systemName: name)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 24, alignment: .leading)
                    .opacity(name == symbolName ? 1 : 0)
            }
        }
        .animation(.easeOut(duration: 0.12), value: symbolName)
    }

    /// 只分静音与有声两档：胶囊只有 38pt 宽，四档阈值切换只带来无意义的闪动。
    private var symbolName: String {
        isSilent ? "speaker.slash.fill" : "speaker.wave.2.fill"
    }

    private var isSilent: Bool {
        model.snapshot.isMuted || model.snapshot.level <= 0
    }

    /// 图标贴近底部：电平盖过图标区域时纯黑（白底上要深）；
    /// 未盖过时用半透明深色——玻璃背板透出壁纸，白图标会看不清。
    /// 用显示电平而非目标电平，白条下落时配色是连续过渡而不是提前跳变。
    private var iconForeground: Color {
        let iconZoneTop = VolumeHUDDesign.capsuleSize.height - 42
        return fillHeight > iconZoneTop ? .black : .black.opacity(0.62)
    }
}
