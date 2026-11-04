import Foundation

public struct MediaPlaybackCapabilities: Equatable, Sendable {
    public let canShuffle: Bool
    public let canFavorite: Bool

    public static func resolve(sourceBundleIdentifier: String?) -> Self {
        switch sourceBundleIdentifier {
        case "com.apple.Music":
            Self(canShuffle: true, canFavorite: true)
        case "com.spotify.client":
            Self(canShuffle: true, canFavorite: false)
        default:
            Self(canShuffle: false, canFavorite: false)
        }
    }
}
