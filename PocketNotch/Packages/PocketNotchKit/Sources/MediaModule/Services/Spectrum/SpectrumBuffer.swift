import Foundation
import os.lock

/// 频谱数据源统一契约：渲染端每帧读取最新频段幅值。
/// 读取可能来自 CVDisplayLink 回调线程 / 主线程，实现须保证线程安全。
protocol SpectrumDataSource: AnyObject {
    var bandCount: Int { get }
    /// 返回最新一帧 [0,1] 频段幅值。
    func readBands() -> [Float]
}

/// 线程安全的最新一帧频谱缓冲（FFT 发射线程写入、CVDisplayLink 渲染端每帧读取）。
/// 渲染端不订阅 @Published，直接读这里，避免 SwiftUI 每帧状态刷新。
final class SpectrumBuffer: SpectrumDataSource {
    let bandCount: Int
    private let bands: OSAllocatedUnfairLock<[Float]>

    init(bandCount: Int = AudioSpectrumConfiguration.sampledBandCount) {
        self.bandCount = bandCount
        self.bands = OSAllocatedUnfairLock(initialState: [Float](repeating: 0, count: bandCount))
    }

    func write(_ values: [Float]) {
        guard values.count == bandCount else { return }
        bands.withLock { $0 = values }
    }

    func clear() {
        bands.withLock { $0 = [Float](repeating: 0, count: bandCount) }
    }

    func readBands() -> [Float] {
        bands.withLock { $0 }
    }
}
