import AppKit
import PocketNotchCore
import SwiftUI

enum MediaMetadataStyle {
    static let titleNSFont = NSFont.preferredFont(forTextStyle: .headline)
    static let expandedTitleNSFont = NSFont.systemFont(
        ofSize: titleNSFont.pointSize + 2,
        weight: .semibold
    )
    static let detailNSFont = NSFont.preferredFont(forTextStyle: .subheadline)
    static let titleFont = Font(titleNSFont)
    static let expandedTitleFont = Font(expandedTitleNSFont)
    static let detailFont = Font(detailNSFont)
    static let titleColor = Color.white.opacity(0.97)
    static let detailColor = Color.white.opacity(0.56)
    static let lineGap = IslandNotificationDesign.textLineGap
}
