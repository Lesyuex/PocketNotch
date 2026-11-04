import AppKit
import SwiftUI

/// 「此刻」页用户区行：左边时间 + 问候语·用户名，右侧圆形头像。
/// 供 mini 卡上方使用；数据读写由 `NowPageUserContent` 提供。
public struct UserIdentityBlock: View {
    public var avatarSize: CGFloat = 56
    /// 紧凑版：更小的字号，配合 mini 卡上方的有限空间。
    public var compact: Bool = false
    @State private var avatar: NSImage?
    @State private var avatarData: Data?

    public init(avatarSize: CGFloat = 56, compact: Bool = false) {
        self.avatarSize = avatarSize
        self.compact = compact
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let date = context.date

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NowPageUserContent.timeText(date))
                        .font(.system(size: compact ? 13 : 18, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.95))

                    Text(NowPageUserContent.greeting(for: date))
                        .font(.system(size: compact ? 10 : 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)

                avatarView
            }
            .frame(maxWidth: .infinity)
            .task { await loadAvatarIfNeeded() }
        }
    }

    private var avatarView: some View {
        Group {
            if let avatar {
                Image(nsImage: avatar)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: avatarSize * 0.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(RoundedRectangle(cornerRadius: avatarSize * 0.25, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: avatarSize * 0.25, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .accessibilityLabel("当前用户头像")
    }

    /// 每次进入时重读账户照片，只有数据有变化才替换（避免闪动与无谓刷新）。
    private func loadAvatarIfNeeded() async {
        let fresh = await Task.detached(priority: .utility) {
            NowPageUserContent.avatarData()
        }.value
        guard let fresh, fresh != avatarData else { return }
        guard let image = NSImage(data: fresh) else { return }
        avatarData = fresh
        avatar = image
    }
}