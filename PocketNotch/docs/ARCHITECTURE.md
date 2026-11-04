# PocketNotch 架构文档 (ARCHITECTURE)

本文件描述 PocketNotch 的分层架构、模块协议与目录结构。改动架构前请先读 `CLAUDE.md` 的「架构铁律」。

## 1. 分层总览

```
┌─────────────────────────────────────────────┐
│                    App (壳)                    │
│  生命周期 · 依赖注入 · 注册模块 · 菜单栏图标      │
└───────────────┬───────────────────────────────┘
                │
┌───────────────▼───────────────────────────────┐
│              PocketNotchCore (核心层)                  │
│  · NotchWindow    刘海窗口管理/定位              │
│  · NotchState     交互状态机(收起/悬停/展开/拖拽) │
│  · ModuleRegistry 模块注册与调度                 │
│  · Theme/动效      统一动画与视觉                 │
└───────────────┬───────────────────────────────┘
                │  依赖倒置：Core 只认协议，不认具体模块
┌───────────────▼───────────────────────────────┐
│           Feature Modules (功能层)               │
│  MediaModule │ ShelfModule │ SystemStatsModule   │
│  ClipboardModule(future) │ TimerModule(future)…  │
└──────────────────┬──────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────┐
│              PocketNotchShared (共享层)                 │
│          纯工具/扩展，无业务，无反向依赖           │
└──────────────────────────────────────────────────┘
```

依赖方向（单向，禁止反向）：

```
App → PocketNotchCore → (只认 PocketNotchModule 协议)
App → Feature Modules → PocketNotchCore, PocketNotchShared
Feature Modules ─X→ 彼此 (禁止互相依赖)
PocketNotchCore ─X→ Feature Modules (禁止)
所有层 → PocketNotchShared (允许)
```

## 2. 各层职责

### App（壳，尽量薄）
- `@main` 入口、`AppDelegate`、`NSStatusItem` 菜单栏图标
- 组装依赖、创建 `ModuleRegistry` 并注册所有 Feature 模块
- 不含任何业务逻辑

### PocketNotchCore（核心）
- **Window**：`NotchWindow`（NSPanel 子类）、`NotchWindowController`、`NotchPositioner`（刘海尺寸探测 + 多屏/无刘海降级定位）、`NotchShape`（刘海圆角形状）
- **State**：`NotchState`（枚举：collapsed / hover / expanded / dragging）、`NotchViewModel`（`@Observable` 状态机）
- **Module**：`PocketNotchModule`（模块协议）、`ModuleRegistry`（注册、排序、启停）
- **Theme**：`PocketNotchTheme`（颜色/圆角/尺寸常量）、`Animations`（统一 spring 动效）
- **UI**：`NotchContainerView`（承载收起/展开切换）

### Island 顶部锚定不变量
- Island 的顶边在任何时间、状态和事件期间都必须与目标屏幕顶边重合。
- 切歌通知、Hover、模块切换、窗口自适应尺寸、动画、显示器变化都不得造成瞬间下沉、上跳、留缝或抖动。
- `NSPanel` 改变尺寸时必须固定顶部锚点；SwiftUI 根内容必须顶部对齐，尺寸扩缩只允许向下或向左右发生。

### Feature Modules（功能层）
每个模块自包含，实现 `PocketNotchModule`，内部结构统一为：
```
XxxModule/
├── XxxModule.swift        # 实现 PocketNotchModule
├── XxxService.swift       # 数据来源/系统交互（可选）
├── XxxViewModel.swift     # @Observable 状态
└── Views/                 # Collapsed / Expanded / 子视图
```

### PocketNotchShared（共享）
- `Extensions/`：如 `NSScreen+Notch`、`View+…`
- `Utilities/`：`Logger`、`Debouncer`、`FileHelper`
- `Models/`：跨模块通用数据模型
- 铁律：无业务、无反向依赖

## 3. 模块协议

```swift
public protocol PocketNotchModule: Identifiable {
    var id: String { get }              // 唯一标识，如 "media"
    var title: LocalizedStringKey { get }
    var priority: Int { get }           // 岛内排列/展示顺序

    @ViewBuilder func collapsedView() -> AnyView   // 收起态的一小块内容
    @ViewBuilder func expandedView() -> AnyView    // 展开态完整面板

    func activate()      // 模块被启用
    func deactivate()    // 模块被关闭
}
```

`ModuleRegistry` 负责：按 `priority` 排序、根据用户设置启停、向 `NotchContainerView` 提供当前激活模块列表。

## 4. 交互状态机

```
collapsed ──hover──▶ hover ──click──▶ expanded
    ▲                  │                  │
    └──────mouse out───┴──────close───────┘
                    │
             drag file in
                    ▼
                dragging (Shelf 接管高亮)
```

`NotchViewModel` 持有当前 `NotchState`，状态切换驱动 `NotchWindow` 尺寸与 SwiftUI 动画。空闲（collapsed）态必须停止一切动画与轮询。

## 5. 完整目录结构

```
PocketNotch/
├── CLAUDE.md                        # AI/人类首读的项目上下文
├── PocketNotch.xcodeproj                  # 只放 App 壳与签名配置
├── App/
│   ├── PocketNotchApp.swift               # @main, 注入依赖, 注册模块
│   ├── AppDelegate.swift            # NSStatusItem, 生命周期
│   ├── Info.plist                   # LSUIElement=YES
│   └── PocketNotch.entitlements
├── Packages/
│   └── PocketNotchKit/
│       ├── Package.swift
│       ├── Sources/
│       │   ├── PocketNotchCore/
│       │   │   ├── Window/ (NotchWindow, NotchWindowController, NotchPositioner, NotchShape)
│       │   │   ├── State/  (NotchState, NotchViewModel)
│       │   │   ├── Module/ (PocketNotchModule, ModuleRegistry)
│       │   │   ├── Theme/  (PocketNotchTheme, Animations)
│       │   │   └── UI/     (NotchContainerView, NotchShape 视图)
│       │   ├── PocketNotchShared/ (Extensions, Utilities, Models)
│       │   ├── MediaModule/ (MediaModule, MediaRemoteService, NowPlayingViewModel, Views/)
│       │   ├── ShelfModule/ (ShelfModule, ShelfStore, ShelfDropReceiver, Views/)
│       │   └── SystemStatsModule/ (SystemStatsModule, SystemBatteryService, SystemStatsViewModel, Views/)
│       └── Tests/ (PocketNotchCoreTests, ShelfModuleTests, SystemStatsModuleTests)
├── Resources/ (Assets.xcassets, Localizable zh-Hans/en)
├── docs/ (ARCHITECTURE.md, ROADMAP.md, CODING-STANDARDS.md, CONTRIBUTING-MODULE.md)
└── scripts/ (build.sh, notarize.sh)
```

## 6. 为什么这样设计

- **App 壳极薄** → 换 UI 框架、加测试、做多入口都不牵动逻辑。
- **Core 只依赖协议** → 功能模块可独立开发/删除，互不影响。
- **每个模块自带 View + Service + ViewModel** → 按功能定位代码，不在大文件里翻。
- **私有框架隔离** → API 失效或要上架只改一处。
- **Shared 无业务** → 防止循环依赖。
