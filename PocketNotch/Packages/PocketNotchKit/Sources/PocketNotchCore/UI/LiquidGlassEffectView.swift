import AppKit
import PocketNotchShared
import ObjectiveC
import SwiftUI

/// Material variants for Apple's private `NSGlassEffectView`.
///
/// The material enum must be passed through as a raw integer at runtime: 11
/// is literally `11`, nowhere else. Reaching for a Swift enum compiled against
/// the private class would introduce a compile-time coupling we cannot afford,
/// so the value is carried as `Int` and forwarded to `set_variant:`.
///
/// The raw scale is the private `_variant` backing of the system Dock/media
/// surfaces (community names: 0 Regular, 1 Clear, 2 Dock, 11 Bubbles). Only
/// the private selector accepts the full range — the public `style` property
/// clamps to Regular/Clear.
public enum LiquidGlassMaterial: Int, CaseIterable, Identifiable, Sendable {
    /// 常规玻璃（raw 0，通用默认）。
    case regular = 0
    /// 清澈玻璃（raw 1，透明、折射最明显，文字场景不推荐）。
    case clear = 1
    /// Dock 同款玻璃（raw 2，多层、高光/反射突出）。
    case dock = 2
    /// 桌面应用图标（raw 3，多层透亮、带 specular 高光）。
    case appIcons = 3
    /// 桌面小组件（raw 4，同 App Icons 的多层玻璃）。
    case widgets = 4
    /// 文字内容（raw 5，强调前景可读性，模糊更精细）。
    case text = 5
    /// 媒体播放器（raw 6，覆盖视频，偏透明弱化干扰）。
    case avPlayer = 6
    /// 视频通话（raw 7，覆盖人像，平衡透亮与主体焦点）。
    case faceTime = 7
    /// 控制中心（raw 8，悬浮操控层）。
    case controlCenter = 8
    /// 通知中心（raw 9，覆盖壁纸，注重内容可读性）。
    case notificationCenter = 9
    /// 头像/字母徽章（raw 10，简洁圆角小玻璃）。
    case monogram = 10
    /// 气泡玻璃（raw 11，社区逆向名 Bubbles）——消息气泡，圆润波形，
    /// 折射 + 高光；当前岛与锁屏组件默认材质。
    case bubbles = 11
    /// 账户/身份卡片（raw 12，侧重内容聚焦）。
    case identity = 12
    /// 焦点描边（raw 13，突出选中态的描边材质）。
    case focusBorder = 13
    /// 焦点底板（raw 14，强化焦点的底板玻璃）。
    case focusPlatter = 14
    /// 键盘按键（raw 15，每键独立玻璃）。
    case keyboard = 15
    /// 侧边栏（raw 16，长条材质，折射背后内容）。
    case sidebar = 16
    /// 相邻侧边栏（raw 17，与其它玻璃无缝贴合）。
    case abuttedSidebar = 17
    /// 检查器面板（raw 18，窄条属性面板玻璃）。
    case inspector = 18
    /// 控件（raw 19，独立按钮等控件的玻璃）。
    case control = 19
    /// 放大镜（raw 20，透镜效果）。
    case loupe = 20
    /// 滑杆（raw 21，条状玻璃）。
    case slider = 21
    /// 相机界面（raw 22，覆盖取景、保持通透）。
    case camera = 22
    /// 弹层/气泡卡（raw 23，弹出提示的 varnish）。
    case cartouchePopover = 23

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .regular: "Regular"
        case .clear: "Clear"
        case .dock: "Dock"
        case .appIcons: "App Icons"
        case .widgets: "Widgets"
        case .text: "Text"
        case .avPlayer: "AVPlayer"
        case .faceTime: "FaceTime"
        case .controlCenter: "Control Center"
        case .notificationCenter: "Notification Center"
        case .monogram: "Monogram"
        case .bubbles: "Bubbles"
        case .identity: "Identity"
        case .focusBorder: "Focus Border"
        case .focusPlatter: "Focus Platter"
        case .keyboard: "Keyboard"
        case .sidebar: "Sidebar"
        case .abuttedSidebar: "Abutted Sidebar"
        case .inspector: "Inspector"
        case .control: "Control"
        case .loupe: "Loupe"
        case .slider: "Slider"
        case .camera: "Camera"
        case .cartouchePopover: "Cartouche Popover"
        }
    }
}

/// 液态玻璃在运行时是否可用：需要 macOS 26+（版本判断走 `SystemVersionService`，
/// 支持设置中心模拟版本）且能解析私有 `NSGlassEffectView`。
/// 供「优先液态玻璃、低版本回退毛玻璃」的一类宿主（如设置中心）做一次门控。
public enum LiquidGlassSupport {
    public static var isAvailable: Bool {
        guard SystemVersionService.shared.isMacOS26OrLater else { return false }
        return NSClassFromString("NSGlassEffectView") != nil
    }
}

/// A SwiftUI bridge that hosts arbitrary content inside a real liquid-glass
/// surface (`NSGlassEffectView`).
///
/// Unlike a frosted `NSVisualEffectView` that sits *behind* a Stack, this is a
/// pure liquid-glass background layer that samples the WindowServer-composited
/// pixels behind the panel without any screen-capture entitlement.
///
/// The music content is intentionally NOT hosted inside the glass: lowering the
/// glass opacity (transparency) must reveal the wallpaper behind while the info
/// elements stay fully clear on top.
public struct LiquidGlassBackdrop: NSViewRepresentable {
    let material: LiquidGlassMaterial
    let cornerRadius: CGFloat
    let tintColor: NSColor?
    let opacity: Double
    let covered: Bool

    public init(
        material: LiquidGlassMaterial,
        cornerRadius: CGFloat,
        tintColor: NSColor? = nil,
        opacity: Double = 1,
        covered: Bool = false
    ) {
        self.material = material
        self.cornerRadius = cornerRadius
        self.tintColor = tintColor
        self.opacity = min(max(opacity, 0), 1)
        self.covered = covered
    }

    public func makeNSView(context: Context) -> NSView {
        let view = LiquidGlassEffectView(
            material: material,
            cornerRadius: cornerRadius,
            tintColor: tintColor
        )
        view.setOpacity(opacity)
        view.setBackdropCovered(covered)
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let nsView = nsView as? LiquidGlassEffectView else { return }
        nsView.update(material: material)
        nsView.update(cornerRadius: cornerRadius)
        nsView.setOpacity(opacity)
        nsView.setBackdropCovered(covered)
    }
}

/// Runtime-only wrapper around Apple's private `NSGlassEffectView`.
///
/// `NSGlassEffectView` has no public Swift header on macOS 26, so the class,
/// its material `set_variant:` and the `CABackdropLayer` sampling flags are all
/// resolved dynamically. Every private symbol is invoked through the
/// Objective-C runtime; a compile-time fallback to a transparent pass keeps the
/// whole view harmless when any private step is unavailable on a given build.
///
/// Known pitfalls honored here:
/// - Materials differ only in the integer forwarded to `set_variant:` (raw
///   `_variant` scale: Regular 0, Clear 1, Dock 2, Bubbles 11).
/// - Do NOT KVC-write `style`: it only honors 0/1 and triggers an internal
///   reconfig that re-rasterizes the glass and fuzzes it. Appearance is left
///   on native.
/// - Opacity is driven through `layer.opacity`; there is no public alpha setter.
final class LiquidGlassEffectView: NSView {
    private let containerView = NSView()
    private var glassView: NSView?

    private let material: LiquidGlassMaterial
    private var cornerRadius: CGFloat
    private let tintColor: NSColor?
    private var opacity: Double = 1

    /// 已应用到玻璃上的值。SwiftUI 在更新事务内会反复调用 `updateNSView`；
    /// 以这些值做去重，避免对私有玻璃类做无谓的 KVC/`set_variant:` 写操作
    /// （这类写在事务中间触发会报 "Publishing changes from within view updates"）。
    private var appliedMaterial: LiquidGlassMaterial?
    private var appliedCornerRadius: CGFloat?

    /// 玻璃是否被黑色背板完全盖住（收起态）。盖住时宿主隐藏并关闭 WindowServer
    /// 采样，展开时再恢复——玻璃视图常驻（不重建、不闪帧），但不再空转。
    private var isCovered = false

    /// Track backdrop sampling flags so they can be re-applied after
    /// WindowServer resets them (lock/sleep/wake).
    private var observedBackdropLayers: [CALayer] = []
    private static var backdropKVOContext = 0

    init(
        material: LiquidGlassMaterial,
        cornerRadius: CGFloat,
        tintColor: NSColor? = nil
    ) {
        self.material = material
        self.cornerRadius = cornerRadius
        self.tintColor = tintColor
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true

        containerView.wantsLayer = true
        containerView.layer?.masksToBounds = true
        addSubview(containerView)
        containerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        installGlass()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        removeBackdropObservers()
    }

    private func installGlass() {
        // 1. Resolve the private class without a compile-time dependency.
        guard let glassType = NSClassFromString("NSGlassEffectView") as? NSView.Type else {
            PocketNotchLog.media.warning("NSGlassEffectView unavailable; keeping transparent pass")
            return
        }
        let glass = glassType.init(frame: .zero)
        glass.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            glass.topAnchor.constraint(equalTo: containerView.topAnchor),
            glass.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
        self.glassView = glass

        // 2. Base appearance through KVC.
        setValueIfSupported(cornerRadius, key: "cornerRadius", on: glass)
        appliedCornerRadius = cornerRadius

        // 3. Material variant through the private setter.
        applyMaterialVariant(material.rawValue, to: glass)
        appliedMaterial = material

        // 6. Optional lightweight tint. A low-alpha (e.g. white@0.08) wash keeps
        // the glass translucent; omitting it preserves the native look.
        if let tintColor {
            setValueIfSupported(tintColor, key: "tintColor", on: glass)
        }

        // The backing layer tree is only built once the glass is in a window and
        // has laid out. Resolve it there, and again on any wake.
        scheduleBackdropInstall(in: glass)

        // Establish transparency from the start. The host root layer is what
        // the glass honors; overlaid music content stays above it and clear.
        let float = Float(opacity)
        layer?.opacity = float
        containerView.layer?.opacity = float
        glass.layer?.opacity = float
    }

    /// Forward a variant to the private `set_variant:` selector.
    ///
    /// The IMP is promoted to a `@convention(c)` function so we can invoke it
    /// with the integer variant (`0` Regular, `11` Bubbles), matching the
    /// instance's class as resolved at runtime. If the selector is missing we
    /// fall back to the default variant and log.
    private func applyMaterialVariant(_ variant: Int, to glass: NSView) {
        let selector = NSSelectorFromString("set_variant:")
        guard let method = class_getInstanceMethod(object_getClass(glass), selector) else {
            PocketNotchLog.media.warning(
                "set_variant: unavailable on NSGlassEffectView; using default variant"
            )
            return
        }

        typealias VariantMethod = @convention(c) (AnyObject, Selector, Int) -> Void
        let apply = unsafeBitCast(method_getImplementation(method), to: VariantMethod.self)
        apply(glass, selector, variant)
        PocketNotchLog.media.debug(
            "LiquidGlass applied variant=\(variant, privacy: .public) (0=Regular, 1=Clear, 2=Dock, 11=Bubbles)"
        )
    }

    /// 切换材质。`set_variant:` 会让玻璃就地重建材质层，绝不能在 SwiftUI 的更新
    /// 事务内同步调用（会触发 "Publishing changes from within view updates"）。
    /// 这里先记录目标值去重，实际写入推迟到下一 RunLoop，让本次视图更新先完成。
    func update(material newMaterial: LiquidGlassMaterial) {
        guard newMaterial != appliedMaterial else { return }
        appliedMaterial = newMaterial
        let variant = newMaterial.rawValue
        DispatchQueue.main.async { [weak self] in
            guard let self, let glass = self.glassView else { return }
            self.applyMaterialVariant(variant, to: glass)
        }
    }

    func update(cornerRadius: CGFloat) {
        guard cornerRadius != appliedCornerRadius else { return }
        appliedCornerRadius = cornerRadius
        self.cornerRadius = cornerRadius
        guard let glassView,
              glassView.responds(to: NSSelectorFromString("setCornerRadius:")) else {
            return
        }
        glassView.setValue(cornerRadius, forKey: "cornerRadius")
        scheduleBackdropInstall(in: glassView)
    }

    /// Drive glass transparency through `layer.opacity`; there is no public
    /// alpha setter on the private class. Value is passed already reversed by
    /// the caller (higher transparency -> lower opacity).
    ///
    /// `NSGlassEffectView` ignores opacity written to its own `glassView.layer`
    /// (its material composites through a backing/backdrop path), but honors it
    /// on the host root layer. Music content is a separate SwiftUI overlay
    /// above this view, so fading the host root only fades the glass and the
    /// info elements stay fully clear.
    func setOpacity(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        guard clamped != opacity else { return }
        opacity = clamped
        let float = Float(clamped)
        layer?.opacity = float
        containerView.layer?.opacity = float
        glassView?.layer?.opacity = float
    }

    /// 收起态（黑色背板完全盖住玻璃时）把宿主隐藏并停止 WindowServer 采样；
    /// 展开时恢复显示并重新启用采样。视图始终常驻，只切换「空转 / 工作」。
    func setBackdropCovered(_ covered: Bool) {
        guard covered != isCovered else { return }
        isCovered = covered
        isHidden = covered
        guard let glassView else { return }
        if covered {
            for layer in observedBackdropLayers {
                setValueIfSupported(false, key: "windowServerAware", on: layer)
            }
        } else {
            // 恢复：重新点亮采样开关，并重新扫描层树（展开期间的布局可能换了层）。
            for layer in observedBackdropLayers {
                setValueIfSupported(true, key: "windowServerAware", on: layer)
            }
            scheduleBackdropInstall(in: glassView)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let glassView else { return }
        scheduleBackdropInstall(in: glassView)
    }

    override func layout() {
        super.layout()
        guard let glassView else { return }
        scheduleBackdropInstall(in: glassView)
    }

    // MARK: - WindowServer backdrop sampling

    /// (Re)negotiate direct WindowServer sampling. Called after the layer tree
    /// is ready, and deferred once past the current runloop so the glass can
    /// build its backdrop layers before we scan for them.
    private func scheduleBackdropInstall(in glass: NSView) {
        DispatchQueue.main.async { [weak self, weak glass] in
            guard let self, let glass else { return }
            self.installWindowServerSampling(on: glass)
        }
    }

    /// 5. Recursively scan the glass layer tree for `CABackdropLayer` and make
    /// it sample the composited content behind the window, without calling the
    /// screen-recording API. Also register KVO so a WindowServer reset
    /// (lock/sleep/wake) re-applies the flags.
    private func installWindowServerSampling(on root: NSView) {
        guard let rootLayer = root.layer else { return }
        let backdropLayers = backdropLayers(in: rootLayer)
        guard !backdropLayers.isEmpty else { return }

        for backdropLayer in backdropLayers {
            configureWindowServerSampling(for: backdropLayer)
            observeBackdropLayer(backdropLayer)
        }
    }

    private func backdropLayers(in layer: CALayer) -> [CALayer] {
        var found: [CALayer] = []
        guard let layerClass = object_getClass(layer) else { return found }
        let name = NSStringFromClass(layerClass)
        if name.contains("CABackdropLayer") {
            found.append(layer)
        }
        if let sublayers = layer.sublayers {
            for sublayer in sublayers {
                found.append(contentsOf: backdropLayers(in: sublayer))
            }
        }
        return found
    }

    private func configureWindowServerSampling(for backdropLayer: CALayer) {
        setValueIfSupported(true, key: "windowServerAware", on: backdropLayer)
        setValueIfSupported(1.0, key: "scale", on: backdropLayer)
    }

    private func observeBackdropLayer(_ layer: CALayer) {
        guard !observedBackdropLayers.contains(where: { $0 === layer }) else { return }
        observedBackdropLayers.append(layer)
        if layer.responds(to: NSSelectorFromString("setWindowServerAware:")) {
            layer.addObserver(
                self,
                forKeyPath: "windowServerAware",
                options: [.new],
                context: &Self.backdropKVOContext
            )
        }
        if layer.responds(to: NSSelectorFromString("setScale:")) {
            layer.addObserver(
                self,
                forKeyPath: "scale",
                options: [.new],
                context: &Self.backdropKVOContext
            )
        }
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard context == &Self.backdropKVOContext,
              let layer = object as? CALayer,
              let rawKeyPath = keyPath,
              let newValue = change?[.newKey] as? NSNumber else {
            super.observeValue(
                forKeyPath: keyPath,
                of: object,
                change: change,
                context: context
            )
            return
        }
        // 被盖住期间是我们主动关掉采样的：忽略这类 KVO，避免与恢复逻辑打架；
        // 展开恢复时会重新点亮并重扫。
        guard !isCovered else { return }
        // 只在 WindowServer 把采样开关重置掉（而非已经是我们期望的值）时才写回。
        // 若对相同值反复 setValue，KVO 会再次触发本回调，形成主线程上的无限循环，
        // 冻结整个屏幕。true / 1.0 是目标状态，收到该值就什么都不做。
        let needsRestore: Bool
        if rawKeyPath == "windowServerAware" {
            needsRestore = !newValue.boolValue
        } else if rawKeyPath == "scale" {
            needsRestore = abs(newValue.doubleValue - 1.0) > 0.0001
        } else {
            return
        }
        if needsRestore {
            configureWindowServerSampling(for: layer)
        }
    }

    private func removeBackdropObservers() {
        guard !observedBackdropLayers.isEmpty else { return }
        for layer in observedBackdropLayers {
            if layer.responds(to: NSSelectorFromString("setWindowServerAware:")) {
                layer.removeObserver(self, forKeyPath: "windowServerAware", context: &Self.backdropKVOContext)
            }
            if layer.responds(to: NSSelectorFromString("setScale:")) {
                layer.removeObserver(self, forKeyPath: "scale", context: &Self.backdropKVOContext)
            }
        }
        observedBackdropLayers.removeAll()
    }

    /// Set a KVC key only when the exact setter exists on this runtime class.
    /// Guards against private properties that differ between releases.
    private func setValueIfSupported(_ value: Any, key: String, on object: NSObject) {
        let setterName = "set\(key.prefix(1).uppercased())\(key.dropFirst()):"
        let setter = NSSelectorFromString(setterName)
        guard object.responds(to: setter) else { return }
        object.setValue(value, forKey: key)
    }
}
