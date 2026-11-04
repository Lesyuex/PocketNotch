# PocketNotch 代码规范 (CODING STANDARDS)

本规范约束 PocketNotch 全体代码（含 AI 生成的代码）。目标：可读、可测、可扩展、低耗电。

## 1. 语言与版本

- Swift 5.9+，充分使用 `async/await`、`@Observable`、结构化并发。
- 最低系统 macOS 14，可直接使用 Sonoma 及以下的稳定 API，无需为旧系统写兼容分支。

## 2. 架构约束（硬性）

- 遵守 `docs/ARCHITECTURE.md` 的依赖方向。**禁止** `PocketNotchCore` import 任何 Feature 模块。
- **禁止** Feature 模块之间互相 import；需要通信时通过 Core 提供的机制。
- 私有框架（MediaRemote 等）**只能**出现在 `MediaRemoteService`，其余通过其接口访问。
- 新功能优先做成独立模块，而不是往现有模块堆代码。

## 3. SwiftUI / MVVM

- View 只负责布局与展示，保持小而专；一个文件一个主要 View。
- 业务状态放 `@Observable` 的 ViewModel，**不在 View 里写业务逻辑**。
- 副作用（网络、系统调用、定时器）放 Service/ViewModel，不放 View。
- 优先组合小视图，避免出现几百行的巨型 `body`。

```swift
// Good
@Observable
final class NowPlayingViewModel {
    private(set) var track: Track?
    private let service: MediaRemoteService
    init(service: MediaRemoteService) { self.service = service }
    func togglePlay() { service.togglePlay() }
}

struct NowPlayingExpandedView: View {
    let vm: NowPlayingViewModel
    var body: some View { /* 只做布局 */ }
}
```

## 4. 命名

- 类型 `UpperCamelCase`，方法/属性 `lowerCamelCase`。
- 名字自解释，宁长勿缩写：`notchPositioner` 而非 `np`。
- 模块 `id` 用简短小写字符串常量：`"media"`、`"shelf"`、`"systemStats"`。
- 布尔量用 `is/has/should` 前缀：`isExpanded`、`hasNotch`。
- 类型后缀必须表达职责：
  - UI 状态与交互编排：`XxxViewModel`
  - 系统/外部能力实现：`XxxService`；直接封装 macOS 实现时优先 `SystemXxxService`
  - 能力协议：`XxxProviding`；不可变采样结果：`XxxSnapshot`
  - 持久状态容器：`XxxStore`；窗口协调：`XxxWindowController`
  - 单一事件入口或上报器：使用明确语义的 `XxxReceiver` / `XxxReporter`，禁止无上下文的泛化名称
- `Fake`、`Stub` 仅用于测试代码；生产替代实现使用 `SimulatedXxx` 或 `XxxFallbackService`。

## 5. 注释

- 默认**不写**注释——命名清晰即可。
- 只在「为什么这么做」不明显时写一行：隐藏约束、绕过的系统 bug、反直觉的取舍。
- 不写「这段代码做了什么」（好命名已表达），不写引用当前任务/调用方的临时性注释。
- 公开 API（`public`）可加一行文档注释说明用途。

## 6. 错误处理

- 只在系统边界（系统 API、文件、外部输入）做校验和错误处理。
- 内部代码信任类型系统，不写「不可能发生」的防御性分支。
- 系统调用失败要优雅降级（如无刘海→悬浮胶囊，无权限→提示引导），不崩溃。

## 7. 性能与耗电（核心质量指标）

- **收起（collapsed）态必须停止所有动画与轮询**，改用事件驱动刷新。
- 电量/系统状态用系统通知或低频拉取，避免高频 `Timer`。
- 拖拽、悬停检测做防抖（`Debouncer`）。
- 定期用 Instruments 检查：空闲 CPU 接近 0、内存无增长。

## 8. 测试

- 每个模块的核心逻辑（状态机、定位算法、Store）要有单元测试，放 `Packages/PocketNotchKit/Tests/`。
- ViewModel 可测；Service 用协议抽象以便 mock。
- UI 手感类改动无法自动测的，需在真机跑一遍并说明测了哪些路径。

## 9. 文件组织

- 一个类型一个文件，文件名与主类型同名。
- Feature 模块内部统一为 `XxxModule.swift + XxxService + XxxViewModel + Views/`。
- 通用工具进 `PocketNotchShared`，禁止把工具散落在各模块内重复实现。

## 10. Git 提交（若启用版本管理）

- 小步提交，一次提交聚焦一件事。
- 提交信息说明「为什么」而非罗列「改了什么文件」。
- 不提交密钥、签名证书、`.env` 等敏感文件。

## 11. 给 AI 助手的额外约定

- 改代码前先读目标模块目录，遵循既有分层与命名。
- 不把逻辑塞进 View 或 App 壳。
- 涉及私有框架只改 `MediaRemoteService`。
- 不主动新建 `.md` 文档，除非被明确要求。
- 不确定边界时回到 `CLAUDE.md`「架构铁律」核对。
