import Foundation
import PocketNotchShared

/// 解析 helper 进程的稳定文本协议，避免进程管理代码了解媒体字段细节。
enum MediaRemoteHelperOutputParser {
    static func parse(_ output: String, status: String) -> MediaRemoteSnapshot? {
        let parts = output.components(separatedBy: "|||")
        guard parts.count >= 6 else { return nil }

        let timestamp = MediaRemoteDictionaryParser.timestampDate(from: parts.count >= 7 ? parts[6] : nil)
        let artworkPartIndex = parts.count >= 8 ? 7 : 6
        // Data(base64Encoded: "") 会返回空 Data；空字段必须显式视为无封面。
        let artworkField = parts.count > artworkPartIndex ? parts[artworkPartIndex] : ""
        let artworkData = artworkField.isEmpty
            ? nil
            : ArtworkDataNormalizer.normalized(Data(base64Encoded: artworkField))
        let pid = parts.count >= 9 ? Int32(parts[8]) : nil
        let info = NowPlayingInfo(
            title: parts[0].isEmpty ? L10n.tr("media.unknownTitle") : parts[0],
            artist: parts[1],
            album: parts[2].isEmpty ? nil : parts[2],
            artworkData: artworkData,
            appPID: pid,
            elapsedTime: TimeInterval(parts[3]),
            duration: TimeInterval(parts[4]),
            isPlaying: parts[5] == "playing",
            updatedAt: timestamp ?? Date()
        )

        PocketNotchLog.media.debug(
            "helper parsed: title=\(info.title, privacy: .public) hasArt=\(info.artworkData != nil) appPID=\(info.appPID ?? -1) parts=\(parts.count)"
        )
        return MediaRemoteSnapshot(info: info, status: status)    }
}
