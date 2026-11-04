import Foundation

/// 独立 helper 进程的源码。与主服务隔离，便于替换私有框架桥接策略。
///
/// 重要：`MRMediaRemoteGetNowPlayingInfo` 等回调若使用 `.main` 回调队列，需要主线程空闲地
/// 驱动 runloop 才会派发；在命令行 helper 进程里 runloop 不常驻空闲时回调可能不触发，导致
/// 拿不到含封面的字典。因此这里一律改用独立的后台 `DispatchQueue` 作为回调队列，回调会在
/// 后台线程直接执行，无需 runloop 即可稳定拿到封面数据。
enum MediaRemoteHelperSource {
    static let monitor = """
        import Foundation
        import ImageIO
        import UniformTypeIdentifiers

        typealias InfoFunction = @convention(c) (DispatchQueue, @escaping @convention(block) (NSDictionary?) -> Void) -> Void
        typealias PlayingFunction = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
        typealias PIDFunction = @convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void
        typealias RegisterFunction = @convention(c) (DispatchQueue) -> Void
        typealias SetWantsFunction = @convention(c) (Bool) -> Void

        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW),
              let infoSymbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") else {
            FileHandle.standardError.write(Data("MediaRemote monitor load failed\\n".utf8))
            exit(2)
        }

        let getInfo = unsafeBitCast(infoSymbol, to: InfoFunction.self)
        let getPlaying = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying").map {
            unsafeBitCast($0, to: PlayingFunction.self)
        }
        let getPID = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID").map {
            unsafeBitCast($0, to: PIDFunction.self)
        }
        let register = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications").map {
            unsafeBitCast($0, to: RegisterFunction.self)
        }
        let setWants = dlsym(handle, "MRMediaRemoteSetWantsNowPlayingNotifications").map {
            unsafeBitCast($0, to: SetWantsFunction.self)
        }

        // 后台回调队列：回调在此线程直接执行，无需主 runloop。
        let callbackQueue = DispatchQueue(label: "pocketnotch.helper.callback", qos: .userInitiated)

        @Sendable func clean(_ value: Any?) -> String {
            String(describing: value ?? "")
                .replacingOccurrences(of: "\\n", with: " ")
                .replacingOccurrences(of: "|||", with: " ")
        }

        // helper 输出经 stdout 传给主 App，超大原图（数 MB）会生成超长 base64 行，且在主 App
        // 渲染时可能超出安全像素导致闪烁。这里在源头把超过 512KB 的封面缩放到 768px 并 JPEG
        // 重编码，与主进程 ArtworkDataNormalizer 的阈值/上限保持一致；常规封面（如 Spotify 的
        // 600x600 JPEG）透传，不做无谓重编码。
        func normalizeArtwork(_ data: Data?) -> Data? {
            guard let data, !data.isEmpty else { return nil }
            if data.count <= 512 * 1024 { return data }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(
                    source,
                    0,
                    [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 768,
                        kCGImageSourceShouldCacheImmediately: true
                    ] as CFDictionary
                  ) else {
                return data
            }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                output,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            ) else { return data }
            CGImageDestinationAddImage(
                destination,
                image,
                [kCGImageDestinationLossyCompressionQuality: 0.84] as CFDictionary
            )
            guard CGImageDestinationFinalize(destination) else { return data }
            return output as Data
        }

        var requestGeneration: UInt64 = 0
        var lastKnownPlaying: Bool?
        var lastKnownPID: Int32 = 0

        func requestSnapshot() {
            requestGeneration &+= 1
            let generation = requestGeneration
            var dictionary: NSDictionary?
            var isPlaying = lastKnownPlaying
            var pid = lastKnownPID
            // info / playing / pid 三个回调都到齐才算快照完整；主 App 依赖单行
            // 完整快照做仲裁，绝不能输出 playing/pid 还是上一首旧值的部分行。
            var pendingCallbacks = 2
            var published = false
            let flushQueue = DispatchQueue(label: "pocketnotch.helper.flush", qos: .userInitiated)

            // info 内含封面，是 UI 解锁的关键数据。playing / pid 到齐后一次性输出
            // 完整快照；若个别回调失联，300ms 后强制兜底输出，绝不阻塞封面。
            func publishIfReady(force: Bool) {
                guard generation == requestGeneration,
                      !published,
                      let dictionary else { return }
                guard force || pendingCallbacks == 0 else { return }
                published = true

                let title = clean(dictionary["kMRMediaRemoteNowPlayingInfoTitle"])
                let artist = clean(dictionary["kMRMediaRemoteNowPlayingInfoArtist"])
                let album = clean(dictionary["kMRMediaRemoteNowPlayingInfoAlbum"])
                let elapsed = clean(dictionary["kMRMediaRemoteNowPlayingInfoElapsedTime"])
                let duration = clean(dictionary["kMRMediaRemoteNowPlayingInfoDuration"])
                let timestamp = clean(dictionary["kMRMediaRemoteNowPlayingInfoTimestamp"])
                let artworkData = normalizeArtwork((dictionary["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data)
                    ?? (dictionary["artworkData"] as? Data))
                let artwork = artworkData?.base64EncodedString() ?? ""
                let rate = Double(clean(dictionary["kMRMediaRemoteNowPlayingInfoPlaybackRate"]))
                // 此 helper 只读取 MediaRemote 的当前会话；当字典不提供 rate 时，
                // 使用同一当前会话的 playing 回调补全播放状态。
                let playing = rate.map { $0 > 0 } ?? isPlaying ?? false

                guard !title.isEmpty || !artist.isEmpty else {
                    FileHandle.standardError.write(Data("MediaRemote monitor missing title/artist; keys=\\(dictionary.count)\\n".utf8))
                    return
                }

                let line = [title, artist, album, elapsed, duration, playing ? "playing" : "paused", timestamp, artwork, String(pid)].joined(separator: "|||") + "\\n"
                FileHandle.standardOutput.write(Data(line.utf8))
            }

            getInfo(callbackQueue) { value in
                guard generation == requestGeneration else { return }
                dictionary = value
                if value == nil {
                    FileHandle.standardError.write(Data("MediaRemote monitor nil dictionary\\n".utf8))
                }
                // 兜底刷新：playing/pid 回调失联时也能输出已到手的封面数据。
                flushQueue.asyncAfter(deadline: .now() + 0.3) {
                    publishIfReady(force: true)
                }
                publishIfReady(force: false)
            }

            getPlaying?(callbackQueue) { value in
                guard generation == requestGeneration else { return }
                pendingCallbacks -= 1
                isPlaying = value
                lastKnownPlaying = value
                publishIfReady(force: false)
            }

            getPID?(callbackQueue) { value in
                guard generation == requestGeneration else { return }
                pendingCallbacks -= 1
                pid = value
                if value > 0 {
                    lastKnownPID = value
                }
                publishIfReady(force: false)
            }
        }

        let notificationNames = [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemotePlaybackStateDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"
        ]

        setWants?(true)
        // 通知注册走主 runloop（monitor 通过 RunLoop.main.run() 常驻并驱动派发），
        // 确保切歌/播放状态变化时能收到回调并触发 requestSnapshot；
        // 而 getInfo/getPlaying/getPID 一律用后台 callbackQueue，保证拿到含封面的字典。
        register?(.main)
        for name in notificationNames {
            NotificationCenter.default.addObserver(
                forName: Notification.Name(name),
                object: nil,
                queue: nil
            ) { _ in
                requestSnapshot()
            }
        }

        requestSnapshot()
        RunLoop.main.run()
        """

    static let snapshot = """
        import Foundation
        import ImageIO
        import UniformTypeIdentifiers

        typealias InfoFunction = @convention(c) (DispatchQueue, @escaping @convention(block) (NSDictionary?) -> Void) -> Void
        typealias PlayingFunction = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
        typealias PIDFunction = @convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void

        let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)
        guard let handle,
              let infoSymbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") else {
            FileHandle.standardError.write(Data("MediaRemote helper load failed".utf8))
            exit(2)
        }

        let getInfo = unsafeBitCast(infoSymbol, to: InfoFunction.self)
        let getPlaying = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying").map {
            unsafeBitCast($0, to: PlayingFunction.self)
        }
        let getPID = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID").map {
            unsafeBitCast($0, to: PIDFunction.self)
        }

        // 后台回调队列：回调在后台线程直接执行，无需主 runloop，能可靠拿到封面。
        let callbackQueue = DispatchQueue(label: "pocketnotch.helper.callback", qos: .userInitiated)

        func readPID() -> Int32 {
            guard let getPID else { return 0 }
            var value: Int32 = 0
            let semaphore = DispatchSemaphore(value: 0)
            getPID(callbackQueue) {
                value = $0
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 2)
            return value
        }

        func readInfo() -> NSDictionary? {
            var value: NSDictionary?
            let semaphore = DispatchSemaphore(value: 0)
            getInfo(callbackQueue) {
                value = $0
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 2)
            return value
        }

        func readPlaying() -> Bool? {
            guard let getPlaying else { return nil }
            var value: Bool?
            let semaphore = DispatchSemaphore(value: 0)
            getPlaying(callbackQueue) {
                value = $0
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 2)
            return value
        }

        let leadingPID = readPID()
        let dictionary = readInfo()
        let isPlaying = readPlaying()
        let trailingPID = readPID()
        guard leadingPID <= 0 || trailingPID <= 0 || leadingPID == trailingPID else {
            FileHandle.standardError.write(Data("MediaRemote helper source changed while reading".utf8))
            exit(5)
        }
        let pid = trailingPID > 0 ? trailingPID : leadingPID

        guard let dictionary else {
            FileHandle.standardError.write(Data("MediaRemote helper returned nil dictionary".utf8))
            exit(3)
        }

        func text(_ key: String) -> String {
            let value = dictionary[key].map { String(describing: $0) } ?? ""
            return value
                .replacingOccurrences(of: "\\n", with: " ")
                .replacingOccurrences(of: "|||", with: " ")
        }

        // 与 monitor 一致：超大原图（>512KB）在源头缩放到 768px 并 JPEG 重编码，避免超长
        // stdout 行与主 App 渲染闪烁；常规封面透传。
        func normalizeArtwork(_ data: Data?) -> Data? {
            guard let data, !data.isEmpty else { return nil }
            if data.count <= 512 * 1024 { return data }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(
                    source,
                    0,
                    [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 768,
                        kCGImageSourceShouldCacheImmediately: true
                    ] as CFDictionary
                  ) else {
                return data
            }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                output,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            ) else { return data }
            CGImageDestinationAddImage(
                destination,
                image,
                [kCGImageDestinationLossyCompressionQuality: 0.84] as CFDictionary
            )
            guard CGImageDestinationFinalize(destination) else { return data }
            return output as Data
        }

        let title = text("kMRMediaRemoteNowPlayingInfoTitle")
        let artist = text("kMRMediaRemoteNowPlayingInfoArtist")
        let album = text("kMRMediaRemoteNowPlayingInfoAlbum")
        let elapsed = text("kMRMediaRemoteNowPlayingInfoElapsedTime")
        let duration = text("kMRMediaRemoteNowPlayingInfoDuration")
        let timestamp = text("kMRMediaRemoteNowPlayingInfoTimestamp")
        let artworkData = normalizeArtwork((dictionary["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data)
            ?? (dictionary["artworkData"] as? Data))
        let artwork = artworkData?.base64EncodedString() ?? ""
        let rate = Double(text("kMRMediaRemoteNowPlayingInfoPlaybackRate"))
        // 当前会话字典没有 rate 时，用 MediaRemote 当前会话的 playing 回调补全。
        let playing = rate.map { $0 > 0 } ?? isPlaying ?? false

        guard !title.isEmpty || !artist.isEmpty else {
            FileHandle.standardError.write(Data("MediaRemote helper dictionary missing title/artist; keys=\\(dictionary.count)".utf8))
            exit(4)
        }

        print([title, artist, album, elapsed, duration, playing ? "playing" : "paused", timestamp, artwork, String(pid)].joined(separator: "|||"))
        """
}
