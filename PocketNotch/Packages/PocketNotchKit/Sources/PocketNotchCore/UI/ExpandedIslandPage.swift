import AppKit
import PocketNotchShared
import SwiftUI

/// 完整展开态的内容层。
///
/// 背景占据完整分栏高度，模块内容则避开顶部菜单栏衔接区；两者共享同一套
/// 权重宽度，确保 6.8:3.2 的材质边界、分隔线与内容对齐。
struct ExpandedIslandPage: View {
    @Binding var selectedTab: ExpandedIslandTab
    let modules: [any PocketNotchModule]
    @ObservedObject var tabSettings: ExpandedTabSettings
    var contentTopInset: CGFloat = 0
    var contentBottomInset: CGFloat = 0
    var minimalContentTopInset: CGFloat = 0
    var isMinimalModeEnabled: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.notchRestingIslandSize) private var notchRestingIslandSize
    @Environment(\.notchPhysicalWidth) private var notchPhysicalWidth
    @State private var hoveredTab: ExpandedIslandTab?
    @State private var isSettingsHovering = false
    @State private var searchModel = ExpandedIslandSearchModel()
    @State private var searchKeyMonitor: Any?
    /// 普通标签页内容区相对岛左右两侧圆角肩部的对称避让留白。
    /// 与此刻页一致（=`expandedCornerRadius`），让任何标签页的内容都恰好占满
    /// 两个肩部之间的主体宽度并居中。
    private static let horizontalInset: CGFloat = NotchShapeSpec.expandedCornerRadius
    private static let dividerGap: CGFloat = 24
    private static let tabItemWidth: CGFloat = 36
    private static let settingsTrailingInset: CGFloat = 16

    private var expandedModules: [any PocketNotchModule] {
        if isMinimalModeEnabled {
            return modules.filter(\.supportsMinimalExpandedView)
        }
        return modules.filter(\.showsInExpandedPage)
    }

    var body: some View {
        Group {
            if isMinimalModeEnabled, !expandedModules.isEmpty {
                minimalPage
            } else if expandedModules.isEmpty {
                emptyState
            } else {
                GeometryReader { geo in
                    let pageModules = modules(for: selectedTab)
                    let widths = contentWidths(for: geo.size.width, modules: pageModules)
                    let contentHeight = max(
                        geo.size.height - contentTopInset - contentBottomInset,
                        0
                    )

                    ZStack(alignment: .topLeading) {
                    // 此刻页背景透明：不再渲染模块背景列。
                    if selectedTab != .now {
                        backgroundColumns(
                            modules: pageModules,
                            widths: widths,
                            height: geo.size.height
                        )
                        .id(selectedTab)
                    }

                    if selectedTab == .now {
                        nowTwoBlockPage
                            .id(selectedTab)
                    } else {
                        selectedPage(
                            modules: pageModules,
                            widths: widths,
                            height: contentHeight
                        )
                            .id(selectedTab)
                            .padding(.horizontal, Self.horizontalInset)
                            .offset(y: contentTopInset)

                        tabBar
                    }
                }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(searchModel)
        .background {
            ExpandedPageWindowAccessor { searchModel.attach(window: $0) }
        }
        .onAppear {
            syncSearch(for: selectedTab)
            installSearchKeyMonitor()
        }
        .onDisappear(perform: removeSearchKeyMonitor)
        .onChange(of: selectedTab) { _, newValue in
            syncSearch(for: newValue)
        }
        .onChange(of: tabSettings.visibleTabs) { _, visibleTabs in
            // 当前标签被禁用或移除时，回退到第一个可见标签，避免停留在空页面。
            guard !visibleTabs.contains(selectedTab), let firstTab = visibleTabs.first else {
                return
            }
            selectedTab = firstTab
        }
    }

    /// 简约模式：只展示声明了简约视图的模块（如音乐），内容横向居中、顶部锚定，
    /// 隐藏标签栏与多分栏背景，其余元素一概不显示。
    private var minimalPage: some View {
        ZStack(alignment: .top) {
            ForEach(Array(expandedModules.enumerated()), id: \.element.id) { _, module in
                module.expandedMinimalView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, minimalContentTopInset)
        .padding(.bottom, IslandLayoutToken.expandedMinimalContentBottomInset)
        .padding(.horizontal, IslandLayoutToken.expandedMinimalContentHorizontalInset)
    }

    /// 「此刻」页：整体拆成上下两块——顶部刘海块 + 下面内容块，二者无缝衔接。
    private var nowTwoBlockPage: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                topNotchBlock

NowSnapshotView(
                    accessory: nowPageLeadingAccessory,
                    midAccessory: nowPageMidAccessory,
                    centerAccessory: nowPageCenterAccessory,
                    folderAccessory: nowPageFolderAccessory,
                    trailingAccessory: nowPageTrailingAccessory,
                    timerAccessory: nowPageTimerAccessory,
                    rightAccessory: nowPageRightAccessory,
                    rightmostAccessory: nowPageRightmostAccessory
                )
                .padding(.horizontal, NotchShapeSpec.expandedCornerRadius)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// 顶部刘海块：仅「刘海条」本身（标签栏 + 顶部隐藏命中区），不含与内容的间距。
    private var topNotchBlock: some View {
        tabBar
            .frame(height: menuBarHeight)
    }

    @ViewBuilder
    private func selectedPage(
        modules: [any PocketNotchModule],
        widths: [CGFloat],
        height: CGFloat
    ) -> some View {
        if modules.isEmpty {
            if selectedTab == .now {
                NowSnapshotView(
                        accessory: nowPageLeadingAccessory,
                        midAccessory: nowPageMidAccessory,
                        centerAccessory: nowPageCenterAccessory,
                        folderAccessory: nowPageFolderAccessory,
                        trailingAccessory: nowPageTrailingAccessory,
                        timerAccessory: nowPageTimerAccessory,
                            rightAccessory: nowPageRightAccessory,
                        rightmostAccessory: nowPageRightmostAccessory
                    )
            } else {
                emptyState
            }
        } else {
            contentColumns(modules: modules, widths: widths, height: height)
        }
    }

    /// 「此刻」页左侧文件夹卡之后的模块附件：取第一个提供了居中附件的模块
    /// （目前仅待办模块）。
    private var nowPageCenterAccessory: AnyView? {
        modules.compactMap { $0.nowPageCenterAccessoryView() }.first
    }

    /// 「此刻」页计时器卡之后、右区系统信息卡之前的模块附件：取第一个提供了附件的模块
    /// （目前仅常用文件夹模块）。
    private var nowPageFolderAccessory: AnyView? {
        modules.compactMap { $0.nowPageFolderAccessoryView() }.first
    }

    /// 「此刻」页待办卡之后、计时器卡之前的模块附件：取第一个提供了附件的模块
    /// （目前仅剪贴板模块）。
    private var nowPageTrailingAccessory: AnyView? {
        modules.compactMap { $0.nowPageTrailingAccessoryView() }.first
    }

    /// 「此刻」页剪贴板卡之后、常用文件夹卡之前的模块附件：取第一个提供了附件的模块
    /// （目前仅计时器模块）。
    private var nowPageTimerAccessory: AnyView? {
        modules.compactMap { $0.nowPageTimerAccessoryView() }.first
    }

    /// 「此刻」页的模块附件：取第一个提供了附件的模块（目前仅媒体模块）。
    private var nowPageLeadingAccessory: AnyView? {
        modules.compactMap { $0.nowPageLeadingAccessoryView() }.first
    }

    /// 「此刻」页左侧音乐卡后的模块附件：取第一个提供了附件的模块（目前仅媒体模块）。
    private var nowPageMidAccessory: AnyView? {
        modules.compactMap { $0.nowPageMidAccessoryView() }.first
    }

    /// 「此刻」页右区最右侧的模块附件：取第一个提供了附件的模块（目前仅系统状态模块）。
    private var nowPageRightAccessory: AnyView? {
        modules.compactMap { $0.nowPageRightAccessoryView() }.first
    }

    /// 「此刻」页右区系统信息卡之后的系统状态卡：取第一个提供了附件的模块（目前仅系统状态模块）。
    private var nowPageRightmostAccessory: AnyView? {
        modules.compactMap { $0.nowPageRightmostAccessoryView() }.first
    }

    private var tabBar: some View {
        GeometryReader { geometry in
            let shoulderInset = NotchShapeSpec.expandedCornerRadius
            let bodyWidth = max(geometry.size.width - shoulderInset * 2, 0)
            let sideRegionWidth = max(
                (bodyWidth - hiddenNotchWidth) / 2,
                0
            )
            let trailingInset = Self.horizontalInset
            let settingsButtonWidth = Self.tabItemWidth + Self.settingsTrailingInset
            let trailingContentWidth = max(sideRegionWidth - settingsButtonWidth, 0)

            ZStack {
                tabStrip(
                    tabs: [.now] + tabSettings.visibleTabs,
                    width: sideRegionWidth,
                    height: menuBarHeight
                )
                .frame(width: sideRegionWidth, height: menuBarHeight, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 0) {
                    if let headerAccessory = selectedHeaderAccessory {
                        headerAccessory
                            .frame(
                                width: trailingContentWidth,
                                height: menuBarHeight,
                                alignment: .trailing
                            )
                    } else {
                        Spacer(minLength: 0)

                        if selectedTab == .applications {
                            applicationSearchField(
                                width: min(max(trailingContentWidth - trailingInset, 0), 150)
                            )
                            .padding(.trailing, 4)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .opacity.combined(
                                        with: .scale(scale: 0.92, anchor: .trailing)
                                    )
                            )
                        }
                    }

                    settingsButton
                }
                .frame(width: sideRegionWidth, height: menuBarHeight, alignment: .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)

                centerSettingsButton
            }
            .padding(.horizontal, shoulderInset)
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.9),
            value: selectedTab
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.9),
            value: tabSettings.visibleTabs
        )
        .frame(
            maxWidth: .infinity,
            minHeight: menuBarHeight,
            maxHeight: menuBarHeight,
            alignment: .leading
        )
    }

    private static func icon(for tab: ExpandedIslandTab) -> ExpandedTabIcon {
        switch tab {
        case .home: .symbol("house.fill")
        case .applications: .appStore
        case .transfer: .symbol("tray.full.fill")
        case .folders: .symbol("folder.fill")
        case .agentSessions: .aiChipRobot
        case .clipboard: .symbol("wallet.pass.fill")
        case .stocks: .symbol("chart.line.uptrend.xyaxis")
        case .ai: .aiChipRobot
        case .now: .symbol("house.fill")

        // 临时假标签，确认后删除。
        case .demoWeather: .symbol("cloud.sun.fill")
        case .demoCalendar: .symbol("calendar")
        case .demoMusic: .symbol("music.note")
        case .demoNotes: .symbol("note.text")
        case .demoGallery: .symbol("photo.on.rectangle.angled")
        case .demoMail: .symbol("envelope.fill")
        case .demoMessages: .symbol("bubble.left.and.bubble.right.fill")
        case .demoTimer: .symbol("timer")
        case .demoTV: .symbol("play.tv.fill")
        case .demoWallet: .symbol("wallet.pass.fill")
        }
    }


    private func applicationSearchField(width: CGFloat) -> some View {
        let rounded = RoundedRectangle(cornerRadius: 7, style: .continuous)

        return HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.52))

            TextField("island.searchApplications", text: $searchModel.text)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))

            if !searchModel.text.isEmpty {
                Button {
                    searchModel.text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .help("island.clearSearch")
                .accessibilityLabel("island.clearSearch")
            }
        }
        .padding(.horizontal, 9)
        .frame(width: width, height: 26, alignment: .leading)
        .background {
            rounded.fill(.white.opacity(0.06))
        }
        .overlay {
            rounded.strokeBorder(.white.opacity(0.08), lineWidth: 0.8)
        }
        .help("island.searchFieldHelp")
        .accessibilityLabel("island.searchApplications")
    }

    /// 顶部标签栏最右侧的设置中心入口。
    private var settingsButton: some View {
        let hitSize = CGSize(width: Self.tabItemWidth, height: menuBarHeight)
        return Button {
            NotificationCenter.default.post(name: .openSettings, object: nil)
        } label: {
            ExpandedTabItem(
                icon: .symbol("gearshape"),
                isSelected: false,
                isHovering: isSettingsHovering,
                hitSize: hitSize
            )
        }
        .buttonStyle(ExpandedTabButtonStyle())
        .contentShape(Rectangle())
        .onHover { isSettingsHovering = $0 }
        .help("island.settingsCenter")
        .accessibilityLabel("island.settingsCenter")
        .frame(width: hitSize.width, height: hitSize.height)
        .padding(.trailing, Self.settingsTrailingInset)
    }

    /// 顶部中间（刘海衔接区）的隐形命中区域：点击进入设置中心。
    private var centerSettingsButton: some View {
        Button {
            NotificationCenter.default.post(name: .openSettings, object: nil)
        } label: {
            Color.clear
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: hiddenNotchWidth, height: menuBarHeight)
        .contentShape(Rectangle())
        .help("island.settings")
        .accessibilityLabel("island.settings")
    }

    private func tabButton(
        _ tab: ExpandedIslandTab,
        icon: ExpandedTabIcon,
        label: String
    ) -> some View {
        let hitSize = CGSize(
            width: Self.tabItemWidth,
            height: menuBarHeight
        )
        return Button {
            select(tab)
        } label: {
            ExpandedTabItem(
                icon: icon,
                isSelected: selectedTab == tab,
                isHovering: hoveredTab == tab,
                hitSize: hitSize
            )
        }
        .buttonStyle(ExpandedTabButtonStyle())
        .contentShape(Rectangle())
        .onHover { isHovering in
            hoveredTab = isHovering ? tab : (hoveredTab == tab ? nil : hoveredTab)
        }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
        .frame(width: hitSize.width, height: hitSize.height)
        .id(tab)
    }

    private func select(_ tab: ExpandedIslandTab) {
        selectedTab = tab
    }

    /// 标签条。标签数超出侧区宽度时自动切换为可横向滚动，并让选中项居中。
    private func tabStrip(
        tabs: [ExpandedIslandTab],
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        guard let first = tabs.first else {
            return AnyView(Spacer(minLength: 0))
        }
        let rest = Array(tabs.dropFirst())

        let strip = HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                tabButton(tab, icon: Self.icon(for: tab), label: tab.displayName)
            }

            Spacer(minLength: 0)
        }

        let overflows = CGFloat(tabs.count) * Self.tabItemWidth > width
        if overflows {
            // 溢出时第一个标签（「此刻」）粘性固定，其余标签在剩余区域横向滚动。
            return AnyView(
                ScrollViewReader { proxy in
                    HStack(spacing: 0) {
                        tabButton(first, icon: Self.icon(for: first), label: first.displayName)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 0) {
                                ForEach(rest, id: \.self) { tab in
                                    tabButton(tab, icon: Self.icon(for: tab), label: tab.displayName)
                                }

                                Spacer(minLength: 0)
                            }
                        }
                        .mask(horizontalEdgeFade)
                        .onChange(of: selectedTab) { _, newValue in
                            guard newValue != first else { return }
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            )
        } else {
            return AnyView(strip)
        }
    }

    private var horizontalEdgeFade: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.05),
                .init(color: .black, location: 0.95),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func syncSearch(for tab: ExpandedIslandTab) {
        searchModel.isVisible = tab == .applications
        if tab != .applications {
            searchModel.reset()
        }
    }

    private func installSearchKeyMonitor() {
        guard searchKeyMonitor == nil else { return }
        searchKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [searchModel] event in
            handleSearchKeyDown(event) ? nil : event
        }
    }

    private func removeSearchKeyMonitor() {
        if let searchKeyMonitor {
            NSEvent.removeMonitor(searchKeyMonitor)
        }
        searchKeyMonitor = nil
    }

    /// 焦点不在任何文本控件时，把窗口内按键直接送入搜索框（即输即搜）。
    private func handleSearchKeyDown(_ event: NSEvent) -> Bool {
        guard searchModel.isVisible,
              let window = searchModel.hostWindow,
              window === NSApp.keyWindow,
              !(window.firstResponder is NSTextView)
        else { return false }

        switch ExpandedSearchKeyResolver.resolve(
            characters: event.characters?.first,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers?.first,
            keyCode: event.keyCode,
            modifiers: event.modifierFlags
        ) {
        case .insert(let character):
            searchModel.text.append(character)
            return true
        case .deleteBackward:
            guard !searchModel.text.isEmpty else { return false }
            searchModel.text.removeLast()
            return true
        case .clear:
            guard !searchModel.text.isEmpty else { return false }
            searchModel.reset()
            return true
        case .submit:
            guard !searchModel.text.isEmpty else { return false }
            searchModel.onSubmit?()
            return true
        case .paste:
            guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
                return false
            }
            searchModel.text += text.replacingOccurrences(of: "\n", with: " ")
            return true
        case .ignored:
            return false
        }
    }

    private var menuBarHeight: CGFloat {
        max(notchRestingIslandSize.height, IslandAppearanceConstraints.defaultFloatingRestingHeight)
    }

    /// 中间隐藏刘海区域的宽度：优先使用物理刘海宽度（不含肩部），
    /// 无刘海屏（外接屏/无刘海机型）才回落至浮动隐藏岛主体宽度。
    private var hiddenNotchWidth: CGFloat {
        notchPhysicalWidth > 0 ? notchPhysicalWidth : notchRestingIslandSize.width
    }

    private var selectedHeaderAccessory: AnyView? {
        modules(for: selectedTab)
            .compactMap { $0.expandedHeaderAccessoryView() }
            .first
    }

    private func modules(for tab: ExpandedIslandTab) -> [any PocketNotchModule] {
        expandedModules.filter { $0.expandedIslandTab == tab }
    }

    private func contentWidths(
        for totalWidth: CGFloat,
        modules: [any PocketNotchModule]
    ) -> [CGFloat] {
        let totalWeight = modules.map(\.expandedPageWeight).reduce(0, +)
        let dividerCount = CGFloat(max(modules.count - 1, 0))
        let usableWidth = max(
            totalWidth
                - Self.horizontalInset * 2
                - dividerCount * Self.dividerGap,
            0
        )
        return modules.map { module in
            guard totalWeight > 0 else {
                return usableWidth / max(CGFloat(modules.count), 1)
            }
            return usableWidth * (module.expandedPageWeight / totalWeight)
        }
    }

    private func backgroundColumns(
        modules: [any PocketNotchModule],
        widths: [CGFloat],
        height: CGFloat
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(modules.enumerated()), id: \.element.id) { index, module in
                module.expandedBackgroundView()
                    .frame(
                        width: backgroundWidth(
                            contentWidth: widths[index],
                            at: index,
                            moduleCount: modules.count
                        ),
                        height: height
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func contentColumns(
        modules: [any PocketNotchModule],
        widths: [CGFloat],
        height: CGFloat
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(modules.enumerated()), id: \.element.id) { index, module in
                module.expandedView()
                    .frame(width: widths[index], height: height, alignment: .center)

                if index < modules.count - 1 {
                    moduleDivider
                }
            }
        }
        .frame(height: height, alignment: .top)
    }

    private func backgroundWidth(
        contentWidth: CGFloat,
        at index: Int,
        moduleCount: Int
    ) -> CGFloat {
        let leadingExtension = index == 0
            ? Self.horizontalInset
            : Self.dividerGap / 2
        let trailingExtension = index == moduleCount - 1
            ? Self.horizontalInset
            : Self.dividerGap / 2
        return contentWidth + leadingExtension + trailingExtension
    }

    private var moduleDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .padding(.vertical, 4)
            .padding(.horizontal, (Self.dividerGap - 1) / 2)
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: "rectangle.expand.vertical")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))

            Text("island.emptyStateTitle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))

            Text("island.emptyStateSubtitle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AppStoreIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / 340
        let scaleY = rect.height / 300
        let scale = min(scaleX, scaleY)
        let offsetX = (rect.width - 340 * scale) / 2
        let offsetY = (rect.height - 300 * scale) / 2

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: offsetX + (x - 150) * scale, y: offsetY + (y - 150) * scale)
        }

        var path = Path()

        path.move(to: p(319.9, 184.9))
        path.addLine(to: p(329, 169.2))
        path.addCurve(to: p(356.9, 161.7), control1: p(334.6, 159.4), control2: p(347.1, 156.1))
        path.addCurve(to: p(364.4, 189.6), control1: p(366.7, 167.3), control2: p(370, 179.8))
        path.addLine(to: p(276.9, 341.1))
        path.addLine(to: p(340.2, 341.1))
        path.addCurve(to: p(363.3, 381.9), control1: p(360.7, 341.1), control2: p(372.2, 365.2))
        path.addLine(to: p(177.8, 381.9))
        path.addCurve(to: p(157.4, 361.5), control1: p(166.5, 381.9), control2: p(157.4, 372.8))
        path.addCurve(to: p(177.8, 341.1), control1: p(157.4, 350.2), control2: p(166.5, 341.1))
        path.addLine(to: p(229.8, 341.1))
        path.addLine(to: p(296.4, 225.7))
        path.addLine(to: p(275.6, 189.6))
        path.addCurve(to: p(283.1, 161.7), control1: p(270, 179.8), control2: p(273.3, 167.4))
        path.addCurve(to: p(311, 169.2), control1: p(292.9, 156.1), control2: p(305.3, 159.4))
        path.addLine(to: p(319.9, 184.9))
        path.closeSubpath()

        path.move(to: p(241.2, 402.9))
        path.addLine(to: p(221.6, 436.9))
        path.addCurve(to: p(193.7, 444.4), control1: p(216, 446.7), control2: p(203.5, 450))
        path.addCurve(to: p(186.2, 416.5), control1: p(183.9, 438.8), control2: p(180.6, 426.3))
        path.addLine(to: p(200.8, 391.3))
        path.addCurve(to: p(241.2, 402.9), control1: p(217.2, 386.2), control2: p(230.6, 390.1))
        path.closeSubpath()

        path.move(to: p(410.1, 341.2))
        path.addLine(to: p(463.2, 341.2))
        path.addCurve(to: p(483.6, 361.6), control1: p(474.5, 341.2), control2: p(483.6, 350.3))
        path.addCurve(to: p(463.2, 382), control1: p(483.6, 372.9), control2: p(474.5, 382))
        path.addLine(to: p(433.7, 382))
        path.addLine(to: p(453.6, 416.5))
        path.addCurve(to: p(446.1, 444.4), control1: p(459.2, 426.3), control2: p(455.9, 438.7))
        path.addCurve(to: p(418.2, 436.9), control1: p(436.3, 450), control2: p(423.9, 446.7))
        path.addCurve(to: p(342.8, 306.3), control1: p(384.7, 378.8), control2: p(359.5, 335.3))
        path.addCurve(to: p(350, 237.2), control1: p(325.7, 276.8), control2: p(337.9, 247.2))
        path.addCurve(to: p(410.1, 341.2), control1: p(363.4, 260.2), control2: p(383.4, 294.9))
        path.closeSubpath()

        return path
    }
}

private enum ExpandedTabIcon {
    case symbol(String)
    case appStore
    case agent
    case aiChipRobot
}

private struct ExpandedTabItem: View {
    let icon: ExpandedTabIcon
    let isSelected: Bool
    let isHovering: Bool
    var hitSize: CGSize = CGSize(width: 36, height: 44)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        iconView
            .accessibilityHidden(true)
            .foregroundStyle(.white.opacity(isSelected ? 1 : (isHovering ? 0.85 : 0.55)))
            .frame(width: 26, height: 26)
            .frame(width: hitSize.width, height: hitSize.height)
            .offset(x: Self.iconLeftInset - (hitSize.width - 26) / 2)
            .contentShape(Rectangle())
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.14),
                value: isHovering
            )
            .animation(
                .easeOut(duration: 0.14),
                value: isSelected
            )
    }

    /// 图标相对命中框左缘的光学内距（26pt 容器在 36pt 命中框内居中时为 5）。
    static let iconLeftInset: CGFloat = 12

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.monochrome)
        case .appStore:
            ZStack {
                AppStoreIconShape()
                    .fill()
                    .frame(width: 15, height: 15)
            }
        case .agent:
            Image("AgentIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 15, height: 15)
        case .aiChipRobot:
            AIChipRobotIcon()
                .frame(width: 18.5, height: 18.5)
        }
    }
}

private struct ExpandedTabButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.94)
            .animation(
                reduceMotion ? nil : .spring(response: 0.15, dampingFraction: 0.92),
                value: configuration.isPressed
            )
    }
}

private struct ExpandedPageWindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowCaptureNSView {
        WindowCaptureNSView(onWindow: onWindow)
    }

    func updateNSView(_ nsView: WindowCaptureNSView, context: Context) {}

    final class WindowCaptureNSView: NSView {
        var onWindow: (NSWindow?) -> Void

        init(onWindow: @escaping (NSWindow?) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            onWindow = { _ in }
            super.init(coder: coder)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow(window)
        }
    }
}
