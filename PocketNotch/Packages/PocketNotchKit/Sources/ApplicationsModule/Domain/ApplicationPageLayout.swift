import CoreGraphics

enum ApplicationPageLayout {
    static let rowCount = 5
    static let columnCount = 7
    static let itemsPerPage = rowCount * columnCount
    static let iconSize: CGFloat = 60
    static let iconLabelSpacing: CGFloat = 4
    static let labelHeight: CGFloat = 12
    static let tileHeight = iconSize + iconLabelSpacing + labelHeight
    static let rowSpacing: CGFloat = 16
    static let columnSpacing: CGFloat = 16
    static let topInset: CGFloat = 8
    static let footerSpacing: CGFloat = 8
    static let footerHeight: CGFloat = 38
    static let gridHeight = CGFloat(rowCount) * tileHeight
        + CGFloat(rowCount - 1) * rowSpacing
    static let contentHeight = topInset + gridHeight + footerSpacing + footerHeight

    static func pages(for applications: [ApplicationItem]) -> [[ApplicationItem]] {
        stride(from: 0, to: applications.count, by: itemsPerPage).map { start in
            Array(applications[start..<min(start + itemsPerPage, applications.count)])
        }
    }

    static func destination(
        originalOffset: CGFloat,
        proposedOffset: CGFloat,
        velocity: CGFloat,
        pageWidth: CGFloat,
        pageCount: Int
    ) -> Int {
        guard pageWidth > 0, pageWidth.isFinite, pageCount > 0,
              originalOffset.isFinite, proposedOffset.isFinite, velocity.isFinite
        else { return 0 }

        let lastPage = pageCount - 1
        let originalPage = Int(min(max((originalOffset / pageWidth).rounded(), 0), CGFloat(lastPage)))
        let distance = proposedOffset - CGFloat(originalPage) * pageWidth
        let threshold = min(pageWidth * 0.18, 96)
        let direction: Int
        if abs(distance) >= threshold {
            direction = distance > 0 ? 1 : -1
        } else if abs(distance) > 8, abs(velocity) >= 320 {
            direction = velocity > 0 ? 1 : -1
        } else {
            direction = 0
        }
        return min(max(originalPage + direction, 0), lastPage)
    }

    static func swipeDirection(horizontal: CGFloat, vertical: CGFloat) -> Int? {
        guard horizontal.isFinite, vertical.isFinite,
              abs(horizontal) > abs(vertical)
        else { return nil }
        return horizontal > 0 ? 1 : -1
    }
}
