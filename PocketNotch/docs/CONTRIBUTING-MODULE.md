# 如何新增一个功能模块 (CONTRIBUTING A MODULE)

本指南教你（或 AI 助手）把一个新功能接入 PocketNotch，而**不改动核心层**。这是 PocketNotch 可扩展性的落地方式。

## 原则

- 一个功能 = 一个实现 `PocketNotchModule` 协议的独立模块。
- 模块自包含：自带 View、Service、ViewModel。
- 禁止让 `PocketNotchCore` 依赖你的模块；禁止依赖其他 Feature 模块。

## 分步清单

以新增「计时器 TimerModule」为例。

### 1. 建目录

```
Packages/PocketNotchKit/Sources/TimerModule/
├── TimerModule.swift        # 实现 PocketNotchModule
├── TimerService.swift       # 计时逻辑（可选）
├── TimerViewModel.swift     # @Observable 状态
└── Views/
    ├── TimerCollapsedView.swift
    └── TimerExpandedView.swift
```

### 2. 在 `Package.swift` 注册 target

```swift
.target(name: "TimerModule", dependencies: ["PocketNotchCore", "PocketNotchShared"]),
```

（依赖只能是 `PocketNotchCore` 和 `PocketNotchShared`，不能是别的 Feature 模块。）

### 3. 实现 `PocketNotchModule`

```swift
import SwiftUI
import PocketNotchCore

public struct TimerModule: PocketNotchModule {
    public let id = "timer"
    public let title: LocalizedStringKey = "计时器"
    public let priority = 40

    private let vm = TimerViewModel()

    public init() {}

    public func collapsedView() -> AnyView {
        AnyView(TimerCollapsedView(vm: vm))
    }
    public func expandedView() -> AnyView {
        AnyView(TimerExpandedView(vm: vm))
    }

    public func activate()   { vm.start() }
    public func deactivate() { vm.stop() }   // 关闭时务必停掉定时器（耗电铁律）
}
```

### 4. 在 App 壳注册

`App/PocketNotchApp.swift`（或 `AppDelegate`）里：

```swift
registry.register(TimerModule())
```

完成。核心层零改动，模块即出现在岛内（按 `priority` 排序）。

### 5. 加测试

`Packages/PocketNotchKit/Tests/TimerModuleTests/`，覆盖 `TimerViewModel`/`TimerService` 的核心逻辑。

## priority 约定（数值越小越靠前）

| 模块 | priority |
|---|---|
| MediaModule | 10 |
| ShelfModule | 20 |
| SystemStatsModule | 30 |
| （新模块自行取值，留出间隔便于插入） | 40, 50… |

## 检查清单（提交前自查）

- [ ] 只依赖 `PocketNotchCore` / `PocketNotchShared`，未依赖其他 Feature 模块
- [ ] 未修改 `PocketNotchCore`（若必须改，说明为何这是通用能力而非模块特例）
- [ ] `deactivate()` 已停止所有定时器/轮询/动画
- [ ] 收起态视图轻量，无持续动画
- [ ] 核心逻辑有单元测试
- [ ] 命名清晰、无多余注释（见 `docs/CODING-STANDARDS.md`）
