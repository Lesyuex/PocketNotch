# MediaRemote 私有 API 信息清单

> 本文档描述 PocketNotch 通过 MacOS 私有框架 **MediaRemote**（`/System/Library/PrivateFrameworks/MediaRemote.framework`）能获取与控制的媒体信息。
>
> 所有脆弱/私有 API 被隔离在 `MediaRemoteService.swift` 一个文件内，其余代码通过 `MediaRemoteProviding` 协议访问。API 失效时只需改这一处。
>
> 相关源码：
> - 主服务：`MediaModule/Services/MediaRemote/MediaRemoteService.swift`
> - 字典解析：`MediaModule/Services/MediaRemote/MediaRemoteDictionaryParser.swift`
> - 辅助进程（Helper）：`MediaModule/Services/MediaRemote/MediaRemoteHelperSource.swift` 等

## 方式：动态加载（dlsym）

框架通过 `dlopen` 打开，再 `dlsym` 逐个取出符号，因此无需链接私有框架，Xcode 构建不依赖它。

| 符号名 | 用途 | 已用 |
| --- | --- | --- |
| `MRMediaRemoteGetNowPlayingInfo` | 读取当前播放信息字典（NSDictionary） | ✅ |
| `MRMediaRemoteGetNowPlayingApplicationIsPlaying` | 读取当前是否正在播放 | ✅ |
| `MRMediaRemoteGetNowPlayingApplicationPID` | 读取当前播放应用 PID | ✅ |
| `MRMediaRemoteSendCommand` | 发送控制命令（播放/暂停/切歌/seek） | ✅ |
| `MRMediaRemoteRegisterForNowPlayingNotifications` | 注册播放通知 | ✅ |
| `MRMediaRemoteUnregisterForNowPlayingNotifications` | 注销播放通知 | ✅ |
| `MRMediaRemoteSetWantsNowPlayingNotifications` | 开启/关闭通知愿望 | ✅ |

## GetNowPlayingInfo 字典键（当前已读取）

`MRMediaRemoteGetNowPlayingInfo` 返回一个 `NSDictionary`，键为下表的 `kMRMediaRemoteNowPlayingInfo...` 字符串。

| 键 | 类型 | 说明 | PocketNotch 当前是否使用 |
| --- | --- | --- | --- |
| `kMRMediaRemoteNowPlayingInfoTitle` | String | 歌名 / 标题 | ✅ → `title` |
| `kMRMediaRemoteNowPlayingInfoArtist` | String | 歌手 / 作者 | ✅ → `artist` |
| `kMRMediaRemoteNowPlayingInfoAlbum` | String | 专辑名 | ✅ → `album` |
| `kMRMediaRemoteNowPlayingInfoElapsedTime` | TimeInterval | 已播放时间（秒） | ✅ → `elapsedTime` |
| `kMRMediaRemoteNowPlayingInfoDuration` | TimeInterval | 总时长（秒） | ✅ → `duration` |
| `kMRMediaRemoteNowPlayingInfoArtworkData` | Data | 封面图片（JPEG/TIFF） | ✅ → `artworkData` |
| `kMRMediaRemoteNowPlayingInfoTimestamp` | TimeInterval/String | 快照生成时间戳 | ✅ → `updatedAt` |
| `kMRMediaRemoteNowPlayingInfoPlaybackRate` | TimeInterval | 播放速率；>0 表示在播放 | ✅ → `isPlaying` |
| `kMRMediaRemoteNowPlayingInfoIsLiked` | Bool/NSNumber | 是否红心 / 喜欢 | ✅ → `isFavorited` |

此外，`MRMediaRemoteGetNowPlayingApplicationPID` 获取 PID 后，通过 `NSRunningApplication(processIdentifier:)` 反查 `bundleIdentifier`（用于来源标识）。

### NowPlayingInfo（Swift 结构体）映射

上述字段最终汇入 `NowPlayingInfo`：

- `title`（默认“未知歌曲”）
- `artist`
- `album`（空则 nil）
- `artworkData`
- `appPID`
- `sourceBundleIdentifier`
- `isFavorited`
- `elapsedTime`
- `duration`
- `isPlaying`（由 `playbackRate > 0` 判断，缺失时回退到全局播放状态）
- `updatedAt`（默认当前时间）

## 已支持的控制命令（MRMediaRemoteSendCommand）

| 命令 | 枚举值 | 说明 |
| --- | --- | --- |
| 播放 / 暂停 | `2` | `togglePlayPause` |
| 下一首 | `4` | `nextTrack` |
| 上一首 | `5` | `previousTrack` |
| 切换到下一随机模式 | `6` | `advanceShuffleMode` |
| 跳转到指定位置 | `24` | `seekToPlaybackPosition`，配合 option `kMRMediaRemoteOptionPlaybackPosition` |

## 订阅的通知

| 通知名 | 触发时机 |
| --- | --- |
| `kMRMediaRemoteNowPlayingInfoDidChangeNotification` | 播放信息变化 |
| `kMRMediaRemotePlaybackStateDidChangeNotification` | 播放状态变化 |
| `kMRMediaRemoteNowPlayingApplicationDidChangeNotification` | 播放应用切换 |
| `kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification` | 播放/暂停切换 |

## 还能拿到但当前未使用的信息

以下为 MediaRemote 私有框架常见、但 PocketNotch 暂未读取/接入的字段与接口（供后续扩展参考）。

### Now-Playing 字典中可扩展的键

- `kMRMediaRemoteNowPlayingInfoUniqueIdentifier` — 当前曲目唯一 ID（可用于去重 / 追踪同一曲目）
- `kMRMediaRemoteNowPlayingInfoMediaType` — 媒体类型（音乐 / 播客 / 有声书 / 视频）
- `kMRMediaRemoteNowPlayingInfoContentItemID` — 内容项 ID
- `kMRMediaRemoteNowPlayingInfoArtworkIdentifier` — 封面标识
- `kMRMediaRemoteNowPlayingInfoRadioStationName` — 电台名
- `kMRMediaRemoteNowPlayingInfoCollectionIdentifier` — 专辑 / 合集 ID
- `kMRMediaRemoteNowPlayingInfoDisplayName` / `kMRMediaRemoteNowPlayingInfoBundleIdentifier` — 应用显示名 / Bundle ID（当前仅从 PID 反查）
- `kMRMediaRemoteNowPlayingInfoSupportedCommands` — 当前曲目支持的控制命令集合（用于判断是否可点下一首 / 上一首等）
- `kMRMediaRemoteNowPlayingInfoIsPlaying` — 直接播放状态（当前用 `playbackRate` 间接判断）
- `kMRMediaRemoteNowPlayingInfoShuffleMode` / `kMRMediaRemoteNowPlayingInfoRepeatMode` — 随机 / 循环模式状态
- `kMRMediaRemoteNowPlayingInfoPlaybackRate` 扩展 — 变速播放（0.5x / 1.5x 等，用于播客 / 有声书）

### 可 dlsym 但当前未加载的接口

- `MRMediaRemoteGetNowPlayingApplicationDisplayName` — 播放应用显示名
- `MRMediaRemoteGetNowPlayingApplicationBundleIdentifier` — 播放应用 Bundle ID
- `MRMediaRemoteSetElapsedTime` — 直接设置播放位置（比 `seekToPlaybackPosition` 更直接）
- `MRMediaRemoteGetNowPlayingClient` — 当前客户端信息（PID / Bundle ID / Display Name 一次取回）
- `MRMediaRemoteGetPlaybackQueue` — 播放队列
- `MRMediaRemoteGetSupportedCommands` — 支持的命令集合
