import AppKit
import SwiftUI

private enum WeatherExpandedLayout {
    static let primaryContentHeight: CGFloat = 44
    /// 定位名所在行的行高（subheadline 字号 + 内边距）。
    static let locationRowHeight: CGFloat = 16
    /// 头部各行之间的间距。
    static let rowSpacing: CGFloat = 4
    /// 时钟行行高：30pt semibold 圆体单行约 36pt。
    static let clockRowHeight: CGFloat = 36
    /// 换行排版下温度区需要的净高：36pt 温度行（≈43）+ 2pt 行距 + 高低温行（≈14）。
    static let stackedPrimaryContentHeight: CGFloat = 60
    static let pageIndicatorWidth: CGFloat = 6
    static let horizontalInset: CGFloat = 8
}

private enum WeatherHeaderTypography {
    static let detailSize = NSFont.preferredFont(forTextStyle: .subheadline).pointSize
}

private enum WeatherPagingAxis {
    case horizontal
    case vertical
}

struct WeatherExpandedPanelView: View {
    @ObservedObject var viewModel: WeatherViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDayIndex = 0
    @State private var carouselPosition = 0
    @State private var dragOffset: CGFloat = 0
    @State private var dragAxis: WeatherPagingAxis?
    @State private var isDragging = false
    @State private var autoplayGeneration = 0

    private static let carouselInterval: Duration = .seconds(10)

    var body: some View {
        Group {
            if let snapshot = viewModel.snapshot {
                weatherContent(snapshot)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { viewModel.ensureActiveContent() }
    }

    private func weatherContent(_ snapshot: WeatherSnapshot) -> some View {
        let days = displayedDays(for: snapshot)
        let visibleDayIndex = min(max(selectedDayIndex, 0), days.count - 1)
        let carouselDays = days.count > 1 ? days + [days[0]] : days

        return GeometryReader { proxy in
            let pageWidth = proxy.size.width

            ZStack(alignment: .trailing) {
                Group {
                    if reduceMotion {
                        WeatherDayPage(
                            snapshot: snapshot,
                            locationName: viewModel.locationName,
                            day: days[visibleDayIndex],
                            index: visibleDayIndex
                        )
                        .id(visibleDayIndex)
                        .transition(.opacity)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(carouselDays.enumerated()), id: \.offset) { position, day in
                                let index = position % days.count
                                WeatherDayPage(
                                    snapshot: snapshot,
                                    locationName: viewModel.locationName,
                                    day: day,
                                    index: index
                                )
                                .frame(width: pageWidth, height: proxy.size.height)
                            }
                        }
                        .frame(
                            width: pageWidth,
                            height: proxy.size.height * CGFloat(carouselDays.count),
                            alignment: .topLeading
                        )
                        .offset(
                            y: -CGFloat(carouselPosition) * proxy.size.height + dragOffset
                        )
                    }
                }
                .frame(width: pageWidth, height: proxy.size.height, alignment: .topLeading)
                .clipped()
                .contentShape(Rectangle())
                .simultaneousGesture(
                    pageGesture(
                        pageHeight: proxy.size.height,
                        pageCount: days.count,
                        currentIndex: visibleDayIndex
                    )
                )

                WeatherPageIndicator(
                    selectedIndex: visibleDayIndex,
                    pageCount: days.count,
                    onSelect: { selectDay($0, pageCount: days.count) }
                )
                .frame(width: WeatherExpandedLayout.pageIndicatorWidth)
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            .onChange(of: days.count) { _, pageCount in
                selectedDayIndex = min(
                    max(selectedDayIndex, 0),
                    max(pageCount - 1, 0)
                )
                carouselPosition = selectedDayIndex
                dragOffset = 0
                dragAxis = nil
                isDragging = false
                autoplayGeneration += 1
            }
            .task(id: WeatherAutoplayID(
                generation: autoplayGeneration,
                pageCount: days.count,
                isDragging: isDragging,
                reduceMotion: reduceMotion
            )) {
                guard days.count > 1, !isDragging else { return }

                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: Self.carouselInterval)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled, !isDragging else { return }
                    await advanceAutomatically(pageCount: days.count)
                }
            }
        }
    }

    private func displayedDays(for snapshot: WeatherSnapshot) -> [WeatherForecastDay] {
        let today = localDateKey()
        let todayForecast = snapshot.forecast.first { $0.date == today }
        let upcomingForecast = snapshot.forecast
            .filter { $0.date > today }
            .sorted { $0.date < $1.date }

        if let todayForecast {
            return Array(([todayForecast] + upcomingForecast).prefix(3))
        }

        let currentDay = WeatherForecastDay(
            date: today,
            highTemperature: snapshot.temperature,
            lowTemperature: snapshot.temperature,
            weatherCode: snapshot.weatherCode
        )
        return Array(([currentDay] + upcomingForecast).prefix(3))
    }

    private func localDateKey(for date: Date = Date()) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return ""
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func pageGesture(
        pageHeight: CGFloat,
        pageCount: Int,
        currentIndex: Int
    ) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !reduceMotion else { return }

                if dragAxis == nil {
                    dragAxis = abs(value.translation.height) > abs(value.translation.width)
                        ? .vertical
                        : .horizontal
                }
                guard dragAxis == .vertical else { return }
                isDragging = true
                normalizeCarouselPositionIfNeeded(pageCount: pageCount)

                dragOffset = constrainedDragOffset(
                    value.translation.height,
                    pageHeight: pageHeight,
                    pageCount: pageCount,
                    currentIndex: currentIndex
                )
            }
            .onEnded { value in
                let completedAxis = dragAxis
                dragAxis = nil
                isDragging = false

                guard completedAxis == .vertical else {
                    withAnimation(pageAnimation) { dragOffset = 0 }
                    return
                }

                let distanceThreshold = min(max(pageHeight * 0.18, 24), 44)
                let projectedMomentum = value.predictedEndTranslation.height
                    - value.translation.height
                let momentumThreshold = min(max(pageHeight * 0.08, 12), 24)
                var targetIndex = currentIndex

                if abs(projectedMomentum) >= momentumThreshold {
                    targetIndex += projectedMomentum < 0 ? 1 : -1
                } else if abs(value.translation.height) >= distanceThreshold {
                    targetIndex += value.translation.height < 0 ? 1 : -1
                }
                selectDay(targetIndex, pageCount: pageCount, resetsAutoplay: true)
            }
    }

    private func selectDay(
        _ index: Int,
        pageCount: Int,
        resetsAutoplay: Bool = true
    ) {
        let targetIndex = min(max(index, 0), max(pageCount - 1, 0))
        normalizeCarouselPositionIfNeeded(pageCount: pageCount)
        if resetsAutoplay {
            autoplayGeneration += 1
        }
        withAnimation(pageAnimation) {
            selectedDayIndex = targetIndex
            carouselPosition = targetIndex
            dragOffset = 0
        }
    }

    @MainActor
    private func advanceAutomatically(pageCount: Int) async {
        guard pageCount > 1 else { return }

        if reduceMotion {
            let nextIndex = (selectedDayIndex + 1) % pageCount
            selectDay(nextIndex, pageCount: pageCount, resetsAutoplay: false)
            return
        }

        if selectedDayIndex < pageCount - 1 {
            withAnimation(automaticPageAnimation) {
                selectedDayIndex += 1
                carouselPosition += 1
                dragOffset = 0
            }
            return
        }

        withAnimation(automaticPageAnimation) {
            selectedDayIndex = 0
            carouselPosition = pageCount
            dragOffset = 0
        }

        do {
            try await Task.sleep(for: .milliseconds(700))
        } catch {
            normalizeCarouselPositionIfNeeded(pageCount: pageCount)
            return
        }
        normalizeCarouselPositionIfNeeded(pageCount: pageCount)
    }

    private func normalizeCarouselPositionIfNeeded(pageCount: Int) {
        guard carouselPosition == pageCount else { return }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            carouselPosition = 0
        }
    }

    private func rubberBanded(_ offset: CGFloat, dimension: CGFloat) -> CGFloat {
        let magnitude = abs(offset)
        let resisted = (magnitude * dimension * 0.5) / (dimension + 0.5 * magnitude)
        let maximumOvershoot = min(dimension * 0.12, 18)
        let bounded = min(resisted, maximumOvershoot)
        return offset < 0 ? -bounded : bounded
    }

    private func constrainedDragOffset(
        _ offset: CGFloat,
        pageHeight: CGFloat,
        pageCount: Int,
        currentIndex: Int
    ) -> CGFloat {
        let upperLimit = currentIndex > 0 ? pageHeight : 0
        let lowerLimit = currentIndex < pageCount - 1 ? -pageHeight : 0

        if offset > upperLimit {
            return upperLimit + rubberBanded(offset - upperLimit, dimension: pageHeight)
        }
        if offset < lowerLimit {
            return lowerLimit + rubberBanded(offset - lowerLimit, dimension: pageHeight)
        }
        return offset
    }

    private var pageAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.18)
            : .spring(response: 0.34, dampingFraction: 1)
    }

    private var automaticPageAnimation: Animation {
        .spring(response: 0.44, dampingFraction: 1)
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "location.fill")
                .font(.system(size: 24, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.32))
                .frame(width: 32, height: 36)

            Text("--°")
                .font(.system(size: 28, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.32))

            Text(viewModel.statusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct WeatherAutoplayID: Hashable {
    let generation: Int
    let pageCount: Int
    let isDragging: Bool
    let reduceMotion: Bool
}

/// 主页天气卡的单日页。主页面板按天轮播，「此刻」页天气卡固定复用 index 0（今天），
/// 故此处为包级可见而非文件私有。
struct WeatherDayPage: View {
    let snapshot: WeatherSnapshot
    let locationName: String?
    let day: WeatherForecastDay
    let index: Int
    /// 「此刻」页天气卡把日期/周几去掉（该页另有时间信息），定位贴行尾；
    /// 主页面板保留日期，靠左对齐。默认走主页排版。
    var headerLayout: WeatherHeroHeaderLayout = .dateOnTrailing
    /// 高低温是否换到当前温度下方一行。与 `headerLayout` 同理：
    /// 「此刻」页天气卡为 true，主页面板保持默认 false。
    var stacksHighLowOnSecondLine: Bool = false
    /// 底部四项指标（体感 / 湿度 / 降雨 / 风速）。「此刻」页天气卡不需要，
    /// 只留头部温度信息；主页面板保持默认 true。
    var showsMetricGrid: Bool = true
    /// 定位行与温度行之间插入大字时钟行（「此刻」页天气卡）。
    var showsClock: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WeatherHeroCard(
                locationName: locationName,
                dateText: day.dateAndWeekdayText,
                primaryTemperature: primaryTemperatureText,
                highTemperature: day.highTemperatureText,
                lowTemperature: day.lowTemperatureText,
                highTemperatureValue: day.highTemperature,
                lowTemperatureValue: day.lowTemperature,
                conditionText: weatherStatusText,
                symbolName: symbolName,
                symbolColor: symbolColor,
                showsCurrentTemperature: isToday,
                headerLayout: headerLayout,
                stacksHighLowOnSecondLine: stacksHighLowOnSecondLine,
                showsClock: showsClock
            )
            if showsMetricGrid {
                metricGrid
                    .layoutPriority(1)
            }
        }
        // 无指标网格时头部独占卡高，垂直居中避免底部留出大片空白。
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: showsMetricGrid ? .topLeading : .center
        )
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(dayTitle)，\(conditionText)")
    }

    private var metricGrid: some View {
        VStack(spacing: 4) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 22, alignment: .leading),
                    GridItem(.flexible(), spacing: 0, alignment: .leading),
                ],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(metrics) { metric in
                    WeatherMetricView(metric: metric)
                }
            }
            .padding(.horizontal, WeatherExpandedLayout.horizontalInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var metrics: [WeatherMetric] {
        if isToday {
            return [
                WeatherMetric(
                    id: "feels-like",
                    symbol: "thermometer.medium",
                    label: "体感",
                    value: "\(Int(snapshot.apparentTemperature.rounded()))°"
                ),
                WeatherMetric(
                    id: "humidity",
                    symbol: "drop.fill",
                    label: "湿度",
                    value: snapshot.humidity.map { "\($0)%" } ?? "--"
                ),
                WeatherMetric(
                    id: "precipitation",
                    symbol: "cloud.rain.fill",
                    label: "降雨",
                    value: day.precipitationProbabilityText
                ),
                windMetric,
            ]
        }

        return [
            WeatherMetric(
                id: "precipitation",
                symbol: "cloud.rain.fill",
                label: "降雨",
                value: day.precipitationProbabilityText
            ),
            windMetric,
            WeatherMetric(
                id: "sunrise",
                symbol: "sunrise.fill",
                label: "日出",
                value: day.sunriseTime ?? "--:--"
            ),
            WeatherMetric(
                id: "sunset",
                symbol: "sunset.fill",
                label: "日落",
                value: day.sunsetTime ?? "--:--"
            ),
        ]
    }

    private var windMetric: WeatherMetric {
        if isToday, let windGust = snapshot.windGust {
            return WeatherMetric(
                id: "wind-gust",
                symbol: "wind",
                label: "阵风",
                value: "\(Int(windGust.rounded()))km/h"
            )
        }

        return WeatherMetric(
            id: "wind",
            symbol: "wind",
            label: "风速",
            value: "\(day.maximumWindSpeedText)km/h"
        )
    }

    private var isToday: Bool {
        index == 0
    }

    private var dayTitle: String {
        switch index {
        case 0: "今天"
        case 1: "明天"
        default: "后天"
        }
    }

    private var primaryTemperatureText: String {
        isToday ? snapshot.roundedTemperatureText : day.highTemperatureText
    }

    private var conditionText: String {
        isToday ? snapshot.conditionText : day.conditionText
    }

    private var weatherStatusText: String {
        conditionText == "大致晴朗" ? "晴朗" : conditionText
    }

    private var symbolName: String {
        isToday ? snapshot.symbolName : day.symbolName
    }

    private var symbolColor: Color {
        let weatherCode = isToday ? snapshot.weatherCode : day.weatherCode
        switch weatherCode {
        case 0:
            return isToday && !snapshot.isDay ? .white : .yellow
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82:
            return .cyan.opacity(0.9)
        case 71, 73, 75, 77, 85, 86:
            return .blue.opacity(0.9)
        case 95, 96, 99:
            return .purple.opacity(0.9)
        default:
            return .white.opacity(0.86)
        }
    }
}

/// 天气卡头部排布：定位与日期/周几的相对位置。
enum WeatherHeroHeaderLayout {
    /// 定位贴左（图标在名后），日期/周几贴右（主页面板）。
    case dateOnTrailing
    /// 定位居中（图标在名前），不显示日期/周几（「此刻」页天气卡）。
    case locationCentered
}

private struct WeatherHeroCard: View {
    let locationName: String?
    let dateText: String
    let primaryTemperature: String
    let highTemperature: String
    let lowTemperature: String
    let highTemperatureValue: Double
    let lowTemperatureValue: Double
    let conditionText: String
    let symbolName: String
    let symbolColor: Color
    let showsCurrentTemperature: Bool
    var headerLayout: WeatherHeroHeaderLayout = .dateOnTrailing
    /// 「此刻」页天气卡把最高/最低温换到当前温度下方一行，
    /// 避免 36pt 大字旁挤两个温度胶囊；主页面板保持行内基线对齐。
    var stacksHighLowOnSecondLine: Bool = false
    /// 「此刻」页天气卡在定位行与温度行之间插入一行大字时钟。
    var showsClock: Bool = false

    /// 头部净高由各行高度累加得出，不写死常数：定位行 + 间距 × 行数
    /// + 时钟行（可选）+ 温度区（是否换行高低温决定）。
    private var heroHeight: CGFloat {
        WeatherExpandedLayout.locationRowHeight
            + WeatherExpandedLayout.rowSpacing
            + (showsClock ? WeatherExpandedLayout.clockRowHeight + WeatherExpandedLayout.rowSpacing : 0)
            + temperatureBlockHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            locationRow

            if showsClock {
                clockRow
            }

            HStack(alignment: .bottom, spacing: 4) {
                temperatureBlock

                weatherSymbol
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: heroHeight,
            maxHeight: heroHeight
        )
        .padding(.horizontal, WeatherExpandedLayout.horizontalInset)
    }

    /// 「此刻」页天气卡的时钟行：区域时钟用 `TimelineView` 每分钟自刷新，
    /// 不常驻轮询（收起态不渲染此卡）。
    private var clockRow: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(Self.clockText(context.date))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.97))
                .lineLimit(1)
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private static func clockText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    @ViewBuilder
    private var locationRow: some View {
        switch headerLayout {
        case .dateOnTrailing:
            HStack(spacing: 0) {
                HStack(spacing: 3) {
                    locationNameText
                    locationIcon
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                Text(dateText)
                    .font(.system(size: WeatherHeaderTypography.detailSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .locationCentered:
            HStack(spacing: 3) {
                locationIcon
                locationNameText
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var locationIcon: some View {
        Image(systemName: "location.fill")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.white.opacity(0.52))
            .fixedSize()
            .accessibilityHidden(true)
    }

    private var locationNameText: some View {
        Text(locationName ?? "正在定位")
            .font(.system(size: WeatherHeaderTypography.detailSize, weight: .semibold))
            .foregroundStyle(.white.opacity(0.72))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
    }

    private var temperatureBlock: some View {
        Group {
            if showsCurrentTemperature {
                if stacksHighLowOnSecondLine {
                    VStack(alignment: .leading, spacing: 2) {
                        primaryTemperatureText
                        temperatureReadings
                    }
                } else {
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        primaryTemperatureText
                        temperatureReadings
                    }
                }
            } else {
                forecastTemperatureRange
                    .frame(height: 42, alignment: .leading)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: temperatureBlockHeight,
            maxHeight: temperatureBlockHeight,
            alignment: .bottomLeading
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("温度")
        .accessibilityValue(temperatureAccessibilityValue)
    }

    private var primaryTemperatureText: some View {
        Text(primaryTemperature)
            .font(.system(size: 36, weight: .light, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var temperatureBlockHeight: CGFloat {
        stacksHighLowOnSecondLine
            ? WeatherExpandedLayout.stackedPrimaryContentHeight
            : WeatherExpandedLayout.primaryContentHeight
    }

    private var temperatureReadings: some View {
        HStack(alignment: .lastTextBaseline, spacing: 3) {
            highTemperatureReading
            lowTemperatureReading
        }
        .layoutPriority(1)
    }

    private var highTemperatureReading: some View {
        WeatherTemperatureReading(
            symbolName: "arrow.up",
            temperatureText: highTemperature,
            temperature: highTemperatureValue
        )
    }

    private var lowTemperatureReading: some View {
        WeatherTemperatureReading(
            symbolName: "arrow.down",
            temperatureText: lowTemperature,
            temperature: lowTemperatureValue
        )
    }

    private var forecastTemperatureRange: some View {
        HStack(alignment: .lastTextBaseline, spacing: 3) {
            WeatherTemperatureReading(
                symbolName: "arrow.up",
                temperatureText: highTemperature,
                temperature: highTemperatureValue,
                fontSize: 22,
                fontWeight: .light,
                foregroundOpacity: 1
            )

            Text("/")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))

            WeatherTemperatureReading(
                symbolName: "arrow.down",
                temperatureText: lowTemperature,
                temperature: lowTemperatureValue,
                fontSize: 18,
                fontWeight: .light,
                foregroundOpacity: 0.62
            )
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }

    private var temperatureAccessibilityValue: String {
        if showsCurrentTemperature {
            return "\(primaryTemperature)，最高 \(highTemperature)，最低 \(lowTemperature)"
        }
        return "最高 \(highTemperature)，最低 \(lowTemperature)"
    }

    private var weatherSymbol: some View {
        VStack(spacing: 2) {
            Image(systemName: symbolName)
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white.opacity(0.96), symbolColor)
                .frame(width: 32, height: 32)

            Text(conditionText)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(height: 10)
        }
        .frame(
            width: 36,
            height: WeatherExpandedLayout.primaryContentHeight,
            alignment: .bottom
        )
        .accessibilityHidden(true)
    }
}

private struct WeatherTemperatureReading: View {
    let symbolName: String
    let temperatureText: String
    let temperature: Double
    var fontSize: CGFloat = 11
    var fontWeight: Font.Weight = .medium
    var foregroundOpacity: Double = 0.72

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            Image(systemName: symbolName)
                .font(.system(size: 5, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 11, height: 11)
                .background(temperatureColor, in: Circle())
                .alignmentGuide(.lastTextBaseline) { dimensions in
                    dimensions[.bottom]
                }

            Text(temperatureText)
                .font(.system(size: fontSize, weight: fontWeight, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(foregroundOpacity))
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var temperatureColor: Color {
        switch temperature {
        case ..<0:
            return Color(red: 0.2, green: 0.42, blue: 0.94)
        case 0..<12:
            return interpolatedColor(
                from: (0.2, 0.42, 0.94),
                to: (0.2, 0.7, 0.96),
                progress: temperature / 12
            )
        case 12..<22:
            return interpolatedColor(
                from: (0.2, 0.7, 0.96),
                to: (0.2, 0.78, 0.72),
                progress: (temperature - 12) / 10
            )
        case 22..<30:
            return interpolatedColor(
                from: (0.2, 0.78, 0.72),
                to: (0.98, 0.64, 0.16),
                progress: (temperature - 22) / 8
            )
        case 30..<38:
            return interpolatedColor(
                from: (0.98, 0.64, 0.16),
                to: (0.94, 0.24, 0.2),
                progress: (temperature - 30) / 8
            )
        default:
            return Color(red: 0.94, green: 0.24, blue: 0.2)
        }
    }

    private func interpolatedColor(
        from start: (red: Double, green: Double, blue: Double),
        to end: (red: Double, green: Double, blue: Double),
        progress: Double
    ) -> Color {
        let progress = min(max(progress, 0), 1)
        return Color(
            red: start.red + (end.red - start.red) * progress,
            green: start.green + (end.green - start.green) * progress,
            blue: start.blue + (end.blue - start.blue) * progress
        )
    }
}

private struct WeatherMetric: Identifiable {
    let id: String
    let symbol: String
    let label: String
    let value: String
}

private struct WeatherMetricView: View {
    let metric: WeatherMetric

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: metric.symbol)
                .font(.system(size: 11, weight: .medium))
                .symbolRenderingMode(
                    metric.id == "feels-like" ? .monochrome : .hierarchical
                )
                .foregroundStyle(
                    .white.opacity(metric.id == "feels-like" ? 0.6 : 0.62)
                )
                .frame(width: 14, alignment: .center)

            Text(metric.value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, minHeight: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.label)
        .accessibilityValue(metric.value)
    }
}

private struct WeatherPageIndicator: View {
    let selectedIndex: Int
    let pageCount: Int
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 1) {
            ForEach(0..<pageCount, id: \.self) { index in
                Button {
                    onSelect(index)
                } label: {
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.13), lineWidth: 1)
                            .frame(width: 4, height: 4)

                        if selectedIndex == index {
                            Circle()
                                .fill(.white.opacity(0.29))
                                .frame(width: 4, height: 4)
                        }
                    }
                    .frame(width: 6, height: 8)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help(pageLabel(for: index))
                .accessibilityLabel(pageLabel(for: index))
                .accessibilityAddTraits(selectedIndex == index ? .isSelected : [])
            }
        }
        .frame(
            width: WeatherExpandedLayout.pageIndicatorWidth,
            alignment: .center
        )
    }

    private func pageLabel(for index: Int) -> String {
        switch index {
        case 0: "今天"
        case 1: "明天"
        default: "后天"
        }
    }
}
