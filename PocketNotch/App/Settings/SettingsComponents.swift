import AppKit
import Foundation
import MediaModule
import SwiftUI
import PocketNotchCore

struct SystemMaterialBackdrop: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    init(
        material: NSVisualEffectView.Material,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
    }
}

/// 与设置中心同一套材质决策：macOS 26+ 且系统玻璃可用时用液态玻璃（regular），
/// 否则回退到系统毛玻璃。让弹层/卡片无需各自重复可用性判断。
struct SystemLiquidBackdrop: View {
    let cornerRadius: CGFloat
    let opacity: Double

    init(cornerRadius: CGFloat, opacity: Double = 1) {
        self.cornerRadius = cornerRadius
        self.opacity = opacity
    }

    var body: some View {
        if LiquidGlassSupport.isAvailable {
            LiquidGlassBackdrop(
                material: .regular,
                cornerRadius: cornerRadius,
                opacity: opacity
            )
        } else {
            SystemMaterialBackdrop(material: .underWindowBackground)
        }
    }
}

struct SettingsSurfacePalette {
    let sidebarBackground: Color
    let detailBackground: Color
    let cardBackground: Color
    let searchBackground: Color
    let selectedSidebarBackground: Color
    let cardBorder: Color
    let divider: Color
    let labelPrimary: Color

    init(scheme: ColorScheme) {
        let isLight = scheme == .light

        if isLight {
            // Liquid Glass - Light
            sidebarBackground = Color.white.opacity(0.65)
            detailBackground = Color(nsColor: Self.rgb(1, 1, 1))
            cardBackground = Color.white.opacity(0.38)
            searchBackground = Color.white.opacity(0.35)
            selectedSidebarBackground = Color.accentColor
            cardBorder = Color.black.opacity(0.06)
            divider = Color.black.opacity(0.03)
            labelPrimary = Color(red: 0.10, green: 0.10, blue: 0.10)
        } else {
            // Liquid Glass - Dark
            sidebarBackground = Color.white.opacity(0.08)
            detailBackground = Color(red: 40 / 255, green: 43 / 255, blue: 45 / 255)
            cardBackground = Color.white.opacity(0.07)
            searchBackground = Color.white.opacity(0.06)
            selectedSidebarBackground = Color.accentColor
            cardBorder = Color.white.opacity(0.10)
            divider = Color.white.opacity(0.04)
            labelPrimary = Color(red: 0.90, green: 0.90, blue: 0.90)
        }
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    private static func white(_ alpha: CGFloat) -> NSColor {
        NSColor(calibratedWhite: 1, alpha: alpha)
    }

    private static func black(_ alpha: CGFloat) -> NSColor {
        NSColor(calibratedWhite: 0, alpha: alpha)
    }
}

/// 按当前深浅直接选择一端颜色，避免 `Color(nsColor:)` 在首次解析后被缓存、
/// 导致切换主题时面板内容不换肤的问题。
extension Color {
    init(light isLight: Bool, nsColor lightColor: NSColor, dark darkColor: NSColor) {
        self = isLight ? Color(nsColor: lightColor) : Color(nsColor: darkColor)
    }
}

struct SettingsSurfaceKey: EnvironmentKey {
    static let defaultValue = SettingsSurfacePalette(scheme: .dark)
}

extension EnvironmentValues {
    var haloSurface: SettingsSurfacePalette {
        get { self[SettingsSurfaceKey.self] }
        set { self[SettingsSurfaceKey.self] = newValue }
    }
}

enum SettingsTypography {
    static let note: Font = .system(size: 10.5)
}

/// 设置菜单卡片的统一四边内局。卡片内容、分隔线与预览区域都应优先引用此值，
/// 避免同一张卡片出现上下或左右留白不一致。
enum AppearanceCardLayout {
    static let contentInset: CGFloat = 16
}

/// 设置中心右侧面板的统一卡片容器（全局公用）。
///
/// 卡片负责两件事：
/// - 圆角「液态玻璃」背景（复用 `appearanceCardStyle` 的材质）；
/// - 统一的 16pt 左右内边距（`AppearanceCardLayout.contentInset`）。
///
/// 往卡片里塞元素时，元素（设置行、分隔线、预览区等）无需再自行添加内边距：
/// 第一个元素直接贴卡片顶部、最后一个元素直接贴卡片底部，左右两侧统一留
/// 16pt，避免卡片出现上下留白过宽的问题。
struct SettingsCard<Content: View>: View {
    let alignment: HorizontalAlignment
    let content: Content

    init(
        alignment: HorizontalAlignment = .leading,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppearanceCardLayout.contentInset)
        .appearanceCardStyle()
    }
}

enum SettingsHeaderLayout {
    static let detailTopInset: CGFloat = 16
    static let sidebarCategoryTopInset: CGFloat = 44
    static let placeholderHeight: CGFloat = 24
    static let categoryLabelHeight: CGFloat = 14
    static let resetButtonOffset = sidebarCategoryTopInset - detailTopInset

    /// 设置中心卡片之间的统一间距。
    static let cardSpacing: CGFloat = 8
    /// 卡片与顶部标题区 / 底部说明之间保留的间距（顶部需容纳浮动重置按钮）。
    static let surroundingSpacing: CGFloat = 24
    /// 外层容器间距改为 cardSpacing 后，标题区 / 说明需要补足的上下内边距。
    static let surroundingPadding: CGFloat = surroundingSpacing - cardSpacing
}

struct SettingsNoteTextStyle: ViewModifier {
    let fixedSize: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if fixedSize {
            content
                .font(SettingsTypography.note)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            content
                .font(SettingsTypography.note)
                .foregroundStyle(.secondary)
        }
    }
}

/// 设置中心统一的「添加」胶囊按钮（accent 色底 + 悬停加深 + 禁用降透明）。
struct SettingsAddCapsuleButton: View {
    let title: String
    var systemImage: String = "plus"
    var isDisabled = false
    var help: String = ""
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHovering ? Color.primary : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    Capsule()
                        .fill(
                            isHovering
                                ? Color.primary.opacity(0.14)
                                : Color.primary.opacity(0.08)
                        )
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .onHover { isHovering = $0 }
        .help(help)
    }
}

/// 排序模式行内的上移/下移图标按钮：与删除按钮同尺寸同视觉（12pt 符号、
/// 28×28 悬浮圆底、44×44 命中区）。
struct SettingsMoveArrowButton: View {
    let systemImage: String
    var help: String = ""
    var xOffset: CGFloat = 0

    @State private var isHovering = false

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isHovering ? Color.primary : Color.secondary)
                .frame(width: 28, height: 28)
                .background {
                    Circle()
                        .fill(Color.primary.opacity(isHovering ? 0.10 : 0))
                }
                .offset(x: xOffset)
        }
        .buttonStyle(.borderless)
        .frame(width: 44, height: 44, alignment: .center)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

enum AppearanceRowLayout {
    static let contentPadding: CGFloat = AppearanceCardLayout.contentInset
    static let moduleContentTopInset: CGFloat = AppearanceCardLayout.contentInset
    static let titleDescriptionSpacing: CGFloat = 8
    static let rangeTextWidth: CGFloat = 34
    static let sliderWidth: CGFloat = 170
    static let valueSliderWidth: CGFloat = 168
    static let rangeControlWidth: CGFloat = rangeTextWidth * 2 + sliderWidth + 12
    static let actionWidth: CGFloat = 32
    static let controlSpacing: CGFloat = 6
    static let moduleRowHeight: CGFloat = 48
    static let dividerHeight: CGFloat = 1
    static let dividerLightOpacity: Double = 0.060
    static let dividerDarkOpacity: Double = 0.050
}

struct ModuleSettingRow<Control: View>: View {
    let title: String
    let description: String?
    var controlWidth: CGFloat? = nil
    @ViewBuilder var control: () -> Control
    var height: CGFloat = AppearanceRowLayout.moduleRowHeight

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .accessibilityHint(description ?? "")
                .frame(maxWidth: .infinity, alignment: .leading)

control()
            .frame(width: controlWidth, alignment: .trailing)
    }
    .frame(height: height, alignment: .center)
    }
}

struct AppearanceRowDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(colorScheme == .light
                ? Color.black.opacity(AppearanceRowLayout.dividerLightOpacity)
                : Color.white.opacity(AppearanceRowLayout.dividerDarkOpacity))
            .frame(height: AppearanceRowLayout.dividerHeight)
    }
}

/// 「更多设置」展开行：点击后展开/收起其下的高级设置项，带悬浮反馈与箭头旋转动画。
struct SettingsDisclosureRow: View {
    let title: String
    @Binding var isExpanded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isHovered ? Color.primary : Color.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0), anchor: .center)
            }
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: AppearanceRowLayout.moduleRowHeight, alignment: .center)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded ? NSLocalizedString("settings.common.expanded", comment: "") : NSLocalizedString("settings.common.collapsed", comment: ""))
    }
}

struct AppearanceSliderRow: View {
    let title: String
    let subtitle: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let valueText: String
    /// 值为整数型时把拖拽结果归整；比例类值（如毛玻璃区域
    /// 0–1）应设为 false 保留连续精度，否则拖动只会跳到两端。
    var isIntegerValue: Bool = true
    @Environment(\.haloSurface) private var surface

    private var roundedValue: Binding<Double> {
        Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = $0.rounded() }
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .accessibilityHint(subtitle)
                .frame(maxWidth: .infinity, alignment: .leading)

            LabeledValueSlider(
                value: isIntegerValue ? roundedValue : value,
                range: range,
                width: AppearanceRowLayout.valueSliderWidth,
                valueText: valueText,
                sliderLabel: title,
                sliderHint: subtitle
            )
        }
        .frame(height: AppearanceRowLayout.moduleRowHeight, alignment: .center)
    }
}

@ViewBuilder
func appearanceSafetyNote(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
        Image(systemName: "shield.checkered")
            .foregroundStyle(.secondary)
            .frame(width: 18)
        Text(text)
            .settingsNoteStyle()
    }
    .padding(.horizontal, 2)
}

extension View {
    func settingsNoteStyle(fixedSize: Bool = true) -> some View {
        modifier(SettingsNoteTextStyle(fixedSize: fixedSize))
    }

    func appearanceCardStyle() -> some View {
        modifier(AppearanceCardStyleModifier())
    }

    func appearanceCardStyle(if enabled: Bool) -> some View {
        modifier(AppearanceCardStyleModifier(enabled: enabled))
    }
}

struct AppearanceCardStyleModifier: ViewModifier {
    var enabled = true

    func body(content: Content) -> some View {
        if enabled {
            content
                .background {
                    SettingsCardMaterialBackground(cornerRadius: 16)
                }
        } else {
            content
        }
    }
}

private struct SettingsCardMaterialBackground: View {
    let cornerRadius: CGFloat
    @Environment(\.haloSurface) private var surface

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(surface.cardBackground)
    }
}

/// 设置页通用文字分段选择器：统一尺寸、圆角、选中态、悬停反馈与轻微呼吸效果。
struct SettingsSegmentedControl<Option: Hashable & Identifiable>: View {
    @Binding var selection: Option
    let options: [Option]
    let title: (Option) -> String
    let accessibilityTitle: String
    var onSelect: ((Option) -> Void)? = nil
    var onHover: ((Option, Bool) -> Void)? = nil
    /// 选项左侧的 SF Symbol 名称；为 nil 时仅显示文字，保持与音量条等纯文字场景一致。
    var symbolName: ((Option) -> String?)? = nil
    /// 为 true 时选项等宽铺满可用宽度，文字居中，避免被压缩成省略号。
    var fillsAvailableWidth = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredOption: Option?
    @State private var isBreathing = false
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                optionButton(option)
            }
        }
        .padding(2)
        .frame(height: 30)
        .frame(maxWidth: fillsAvailableWidth ? .infinity : nil)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    colorScheme == .light
                        ? Color.black.opacity(0.04)
                        : Color.white.opacity(0.08)
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityTitle)
        .onAppear {
            startBreathing()
        }
        .onChange(of: reduceMotion) { _, _ in
            startBreathing()
        }
    }

    private func optionButton(_ option: Option) -> some View {
        let isSelected = selection == option

        return Button {
            selection = option
            onSelect?(option)
        } label: {
            HStack(spacing: symbolName?(option) == nil ? 0 : 4) {
                if let symbol = symbolName?(option) {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                }
                Text(title(option))
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(
                isSelected
                    ? Color.white
                    : (hoveredOption == option ? Color.primary : Color.secondary)
            )
            .padding(.horizontal, 10)
            .frame(height: 26)
            .frame(maxWidth: fillsAvailableWidth ? .infinity : nil)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor)
                            .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                            .shadow(
                                color: isSelected && isBreathing && !reduceMotion
                                    ? Color.accentColor.opacity(0.45)
                                    : Color.accentColor.opacity(0.12),
                                radius: isSelected && isBreathing && !reduceMotion ? 5 : 1.5
                            )
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .brightness(isSelected && isBreathing && !reduceMotion ? 0.08 : 0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title(option))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .onHover { isInside in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredOption = isInside ? option : nil
            }
            onHover?(option, isInside)
        }
    }

    private func startBreathing() {
        guard !reduceMotion else {
            isBreathing = false
            return
        }

        isBreathing = false
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            isBreathing = true
        }
    }
}

/// 设置页统一的“恢复默认”按钮，和标题行保持同一基线与字号。
struct SettingsResetButton: View {
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button("settings.common.resetToDefault", action: action)
            .font(.caption2.weight(.semibold))
            .tracking(0.45)
            .foregroundStyle(isDisabled ? Color.secondary : Color.accentColor)
            .buttonStyle(.borderless)
            .frame(height: SettingsHeaderLayout.categoryLabelHeight, alignment: .center)
            .disabled(isDisabled)
            .accessibilityLabel("settings.common.resetToDefaultSettings")
    }
}

/// 详情面板的滚动配置：让后台 NSScrollView 在可行时使用浮层 overlay 滚动条，
/// 在强制 legacy 时干脆隐藏滚动条，从而无论哪种情况都不预留轨道宽度、不挤压内容。
///
/// 背景：legacy 样式滚动条会预留固定宽度轨道，把内容往右挤；只有 overlay 浮层样式
/// 才悬浮于内容之上、不占布局空间。但 AppKit 会根据系统「显示滚动条」设置和输入
/// 设备（连接鼠标时）自动决定 scrollerStyle，且对存在 accessory views / legacy
/// scroller 子类的 NSScrollView 会强制回 legacy。SwiftUI 的 ScrollView 在其后台
/// NSScrollView 上通常就满足这些会强制 legacy 的条件，所以 overlay 并不总能生效。
///
/// 处理策略（在 makeNSView / 每次 updateNSView 里异步反复断言，覆盖切换菜单时新建
/// 的每个 ScrollView）：
///  - 先要求 overlay + autohide（可行时保留下浮层滚动条）；
///  - 随即读取实际样式，若 AppKit 拒绝 overlay 落到 legacy，就把垂直滚动条隐藏并
///    重新 tile，使其 legacy 轨道不再预留宽度挤压内容（用户仍可用鼠标滚轮 / 触板
///    手势滚动）。
///
/// 刻意不替换自定义 scroller 子类：替换恰好会被 AppKit 当作「legacy scroller 子类」
/// 而强制回 legacy。用递归遍历（而非 enclosingScrollView）关联后台 NSScrollView。
struct SettingsScrollViewConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view] in
            SettingsScrollViewConfigurator.configureEnclosing(near: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            SettingsScrollViewConfigurator.configureEnclosing(near: nsView)
        }
    }

    private static func configureEnclosing(near view: NSView?) {
        guard let view, let root = view.window?.contentView ?? view.superview else { return }
        visit(root)
    }

    private static func visit(_ node: NSView) {
        if let scrollView = node as? NSScrollView {
            configure(scrollView)
        }
        for subview in node.subviews {
            visit(subview)
        }
    }

    private static func configure(_ scrollView: NSScrollView) {
        // 请求浮层样式，让 AppKit 尽量采用不占空间的 overlay。
        if scrollView.scrollerStyle != .overlay {
            scrollView.scrollerStyle = .overlay
        }
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false

        // 读回实际样式：overlay 可行则保留浮动垂直条；被强制回 legacy 则隐藏，
        // 以免其预留轨道宽度挤压内容。
        let isOverlay = scrollView.scrollerStyle == .overlay
        if scrollView.hasVerticalScroller && !isOverlay {
            scrollView.hasVerticalScroller = false
            // 隐藏滚动条不会自动回收原先被 legacy 轨道占用的内容宽度，需显式
            // 重新 tile 让 contentView 按无垂直条的情形重新布局，宽度才能恢复。
            scrollView.tile()
        }
    }
}

/// 全局把 `NSScrollView.setScrollerStyle:` 替换为「总是 overlay」的实现（swizzle）。
///
/// 这是社区验证过、能在「系统偏好 + 输入设备」自动回滚 legacy 时仍强制浮层样式的
/// 唯一可靠方式：AppKit 在 `+preferredScrollerStyle` 变化或 `tile` 时会向每个
/// NSScrollView 推送 `-setScrollerStyle:`，我们截获它并改写为 overlay，使滚动条永远
/// 不预留轨道宽度、不挤压内容。替换是幂等的，首次调用后缓存原始 IMP 并完成替换。
final class ForceOverlayScrollbars {
    typealias Setter = @convention(c) (AnyObject, Selector, Int) -> Void

    private static var originalSetter: Setter?
    private static var installed = false

    static func install() {
        guard !installed else { return }
        let selector = NSSelectorFromString("setScrollerStyle:")
        guard let method = class_getInstanceMethod(NSScrollView.self, selector) else { return }
        let original = method_getImplementation(method)
        originalSetter = unsafeBitCast(original, to: Setter.self)
        // 用字面闭包组成 C 函数指针：只引用静态成员（不构成捕获），可作为持久 IMP。
        let replacement: Setter = { receiver, selector, _ in
            // 无论系统/AppKit 想设成什么样式，都调用原始 setter 但强制 overlay，
            // 由 AppKit 完成 overlay 所需的重排。Overlay 不参与布局，不挤压内容。
            guard let original = ForceOverlayScrollbars.originalSetter else { return }
            original(receiver, selector, NSScroller.Style.overlay.rawValue)
        }
        let native = unsafeBitCast(replacement, to: OpaquePointer.self)
        _ = method_setImplementation(method, native)
        installed = true
    }
}

extension View {
    func settingsDetailScrolling() -> some View {
        DispatchQueue.main.async { ForceOverlayScrollbars.install() }
        return background(SettingsScrollViewConfigurator())
    }
}

struct LabeledValueSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let width: CGFloat
    var valueText: String = ""
    var sliderLabel: String = ""
    var sliderHint: String = ""
    var helpText: String? = nil
    @State private var isEditing = false

    private static let nativeThumbInset: CGFloat = 7

    private var progress: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    private var thumbCenterX: CGFloat {
        Self.nativeThumbInset + CGFloat(progress) * (width - Self.nativeThumbInset * 2)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Slider(
                value: $value,
                in: range,
                onEditingChanged: { isEditing = $0 }
            )
            .frame(width: width, height: AppearanceRowLayout.moduleRowHeight)
            .accessibilityLabel(sliderLabel)
            .accessibilityHint(sliderHint)
            .accessibilityValue(valueText)

            if isEditing {
                SliderValueBubble(text: valueText)
                    .position(
                        x: max(20, min(width - 20, thumbCenterX)),
                        y: 8
                    )
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .frame(width: width, height: AppearanceRowLayout.moduleRowHeight)
        .animation(.easeOut(duration: 0.12), value: isEditing)
        .help(helpText ?? sliderLabel)
        .accessibilityRepresentation {
            Slider(value: $value, in: range)
                .accessibilityLabel(sliderLabel)
                .accessibilityHint(sliderHint)
                .accessibilityValue(valueText)
        }
    }
}

struct SliderValueBubble: View {
    let text: String
    @Environment(\.haloSurface) private var surface

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(surface.labelPrimary)
            .padding(.horizontal, 4)
            .frame(minWidth: 32, minHeight: 16)
            .background(Capsule().fill(Color.secondary.opacity(0.14)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }
}

struct SettingsMenuPicker<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let optionTitle: (Option) -> String
    var currentTitle: String
    var accessibilityLabel: String = ""
    var onSelect: ((Option) -> Void)? = nil

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Toggle(
                    optionTitle(option),
                    isOn: Binding(
                        get: { selection == option },
                        set: { if $0 { selection = option; onSelect?(option) } }
                    )
                )
            }
        } label: {
            Text(currentTitle)
                .font(.system(size: 12))
                .frame(height: 24)
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

/// 紧凑开关样式：轨道高约 20pt，视觉比系统 Switch 更克制，命中区仍为 44×44。
struct SettingsCompactSwitchToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let trackWidth: CGFloat = 44
    private let trackHeight: CGFloat = 20
    private let thumbWidth: CGFloat = 25
    private let thumbHeight: CGFloat = 16

    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let inset: CGFloat = (trackHeight - thumbHeight) / 2
        let travel: CGFloat = (trackWidth - thumbWidth) / 2 - inset

        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack {
                Capsule()
                    .fill(trackFill(isOn: configuration.isOn))
                    .frame(width: trackWidth, height: trackHeight)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.20), value: configuration.isOn)

                Capsule()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                    .frame(width: thumbWidth, height: thumbHeight)
                    .offset(x: configuration.isOn ? travel : -travel)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.74),
                        value: configuration.isOn
                    )
            }
            .contentShape(Capsule().inset(by: 0))
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44, alignment: .center)
        .onHover { isHovering = $0 }
        .accessibilityLabel(NSLocalizedString("settings.common.switch", comment: ""))
        .accessibilityValue(configuration.isOn ? NSLocalizedString("settings.common.on", comment: "") : NSLocalizedString("settings.common.off", comment: ""))
    }

    private func trackFill(isOn: Bool) -> Color {
        guard isEnabled else {
            return Color.primary.opacity(0.08)
        }
        if isOn {
            return Color.accentColor.opacity(isHovering ? 0.85 : 1)
        }
        return Color.primary.opacity(isHovering ? 0.20 : 0.14)
    }
}
