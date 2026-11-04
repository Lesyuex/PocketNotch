# CLAUDE.md — PocketNotch 项目 AI 上下文

本文件供 AI 编码助手（Claude Code 等）在每次会话开始时自动读取。
> 目标：让 AI 无需重新摸索即可理解项目定位、架构约束与代码规范。
> 人类贡献者同样应先读本文件。

## 一句话定位

**PocketNotch** 是一款常驻 macOS 菜单栏的刘海（Notch）增强工具：把 MacBook 刘海区做成一块可交互的「岛」，闲时收起、悬停/点击展开，承载媒体控制、文件暂存、系统状态等模块。对标 AiCove、NotchBook。

## 技术栈（不要擅自更换）

- 语言：Swift 5.9+（使用 `@Observable`、async/await、宏）
- UI：SwiftUI 为主，AppKit 负责窗口与全局事件
- 窗口：无边框 `NSPanel`（floating、non-activating）
- 依赖管理：Swift Package Manager（逻辑全在 `Packages/PocketNotchKit`，App 壳极薄）
- 常驻：`LSUIElement = YES` + `NSStatusItem`（无 Dock 图标）
- 最低系统：macOS 14 Sonoma
- 更新分发：Sparkle；签名走 Developer ID + 公证

## 架构铁律（改动前必读）

1. **模块化插件架构**。每个功能是一个实现 `PocketNotchModule` 协议的模块，彼此不依赖。
   新增功能 = 新增一个 `XxxModule`，在 `App` 启动时 `registry.register(...)`，**不改核心层**。
2. **依赖倒置**。`PocketNotchCore` 只依赖 `PocketNotchModule` 协议，绝不 import 任何具体 Feature 模块。
   反向依赖（Core → Feature）视为架构违规。
3. **私有框架隔离**。MediaRemote 等私有/脆弱 API 只能出现在 `MediaRemoteService` 内，
   其余代码通过其暴露的接口访问。API 失效时只需改这一处。
4. **App 壳保持极薄**。`App/` 只做：生命周期、依赖注入、模块注册、菜单栏图标。无业务逻辑。
5. **Shared 无业务**。`PocketNotchShared` 只放纯工具/扩展，禁止引入业务或反向依赖，避免循环依赖。
6. **Island 永久贴顶**。不论任何时间、状态或事件（包括切歌通知、Hover、模块切换、窗口自适应尺寸、动画和显示器变化），Island 顶边都必须始终与目标屏幕顶边重合；不得出现任何瞬间下沉、上跳、留缝或抖动。所有窗口布局与动画必须保持顶部锚点不变，尺寸扩缩只允许向下或向左右发生。
7. **UI 设计必须达到可交付的高级产品水准**。设计目标不是“完成界面”，而是创造具有高级感、秩序感、品牌感和视觉愉悦感的产品。任何 UI 新增或修改都必须遵循下方「UI 设计铁律」；每一个像素都应有设计理由，不得为了填满空间而增加元素。
8. **Island 尺寸配置必须端到端同步**。修改隐藏态或灵动态的长度/高度默认值、范围或安全下限时，必须同步更新运行时约束、布局解析、设置面板预览/滑块文案以及相关测试断言；不得只改 Core 或只改设置页。


## UI 设计铁律（设计与实现前必读）

### 总体目标

- 优先保证：视觉秩序、信息层级、美观、高级感、一致性、可读性与交互流畅。
- 整体风格对标 Apple、Linear、Arc Browser、Raycast、Vercel、Stripe Dashboard 的现代高级设计语言。
- 追求高级感、未来感、科技感、极简主义、精致细节、留白美学、节奏感、呼吸感与视觉平衡。
- 设计与实现质量应以 Apple Design Award、Google Material 3、Microsoft Fluent、Human Interface Guidelines、Dribbble Top Designer、Behance Featured 级别为目标。

### 刘海交互质感（Dynamic Island Principle）

- PocketNotch 的目标不是“把 View 从 A 变到 B”，而是让用户感觉刘海本身活了，像一块具有弹性的连续材质。
- Apple Dynamic Island 的高级感来自连续性（Continuity），不是来自更快的动画或更多的动效。
- 所有刘海 / Island 动画都必须同时满足四个连续性原则：
  - **Shape Continuity**：形状拓扑、圆角语义、肩部曲率和路径命令保持连续；禁止不同状态之间突然换形、跳边或硬切路径。
  - **Motion Continuity**：位置、尺寸、速度和加速度连续变化；动画需要有自然惯性、回弹和收敛，避免线性机械移动。
  - **Material Continuity**：背景材质、模糊、阴影、描边、透明度和高光应像同一块材质在形变；禁止状态切换时材质层级突然替换。
  - **Interaction Continuity**：Hover、Press、Click、Drag、展开、收起、模块切换必须共享同一个状态机语义；用户输入应被动画吸收和延续，而不是打断当前运动。
- 整个生命周期只能有一个 Island：不要隐藏一个 View 再显示另一个 View，而是让同一个 Island 连续修改 Shape、Size、Corner、Blur、Shadow 与内容布局。
- Island 状态机不能只表达“收起 / 展开”，必须至少具备以下语义状态，并允许每个状态绑定不同动画参数：
  - **Hidden**：完全不可见或未进入可交互区域。
  - **Idle**：默认刘海态，贴顶、低能耗、等待输入。
  - **Hover**：鼠标靠近或进入热区，材质和轮廓先给出轻微响应。
  - **Prepare**：准备展开，预热尺寸、曲率、阴影与内容可见性，但不突然切换视图。
  - **Expand**：展开过程，形状和材质沿同一拓扑连续生长。
  - **Interactive**：可交互态，响应点击、拖拽、模块切换和内容变化。
  - **Collapse**：收起过程，沿展开路径反向回收，保留速度和材质连续性。
  - **Idle**：回到默认刘海态。
- 展开动画禁止默认使用 `easeInOut`。Apple 级别的展开质感应优先使用 Spring：先快进入、随后减速、接近目标时出现轻微回弹，最后稳定停止。
- Spring 回弹必须克制，只用于表达材质弹性；禁止夸张弹跳、反复振荡或让顶部锚点产生可见位移。
- 展开态必须从隐藏态 / 灵动态的 Hover 膨胀形状继续生长，不能先切回未 Hover 尺寸，也不能先隐藏当前 View 再显示展开 View。
- 判断一段交互是否合格：用户应感到“刘海在响应我”，而不是“一个浮层被显示 / 隐藏了”。

### 视觉（Visual）

- 运用黄金比例（Golden Ratio，`1:1.618`）控制整体布局比例，并结合 8pt Grid System。
- 保持一致的留白（Whitespace），建立清晰的视觉层级（Visual Hierarchy），控制信息密度并强调呼吸感。
- 所有对齐必须精准；圆角、阴影和视觉重量必须属于统一体系。
- 主动减少视觉噪音，避免无意义装饰和冗余元素。

### 布局（Layout）

- 根据内容和阅读路径合理运用 F Pattern、Z Pattern、Rule of Thirds（三分法）、Golden Ratio 与 Visual Weight Balance。
- 所有元素保持左右平衡、上下节奏、视觉重心稳定和阅读路径自然。
- 禁止元素拥挤、边距不一致、尺寸关系混乱和信息堆积。
- Island 的紧凑形态必须同时满足本项目“永久贴顶”的架构约束，不得为追求视觉效果破坏顶部锚点稳定性。

### 色彩（Color）

- 采用低饱和、高质感、克制的现代配色，并按 `60% / 30% / 10%` 建立主色、辅助色和强调色关系。
- 保持统一品牌色、自然过渡、柔和对比和舒适阅读。
- 禁止高饱和、廉价渐变、刺眼颜色和花哨配色。
- 同时支持 Light Mode 与 Dark Mode，并保持优秀、可访问的对比度。

### 字体（Typography）

- 建立稳定的 Display、Title、Headline、Body、Caption 字体层级。
- 系统化控制字号、字重、行高和字间距，保证阅读舒适且信息层级明确。
- 禁止字号混乱、字重随意和密集排版。

### 组件（Components）

- 按钮、输入框、卡片、列表、菜单、弹窗、Tab、Segment、Tooltip、Popover、Badge、Tag 必须使用统一设计语言。
- 统一圆角、阴影、间距和交互反馈。
- 所有交互组件必须完整设计 Hover、Pressed、Focused、Disabled 状态，不得只实现隐藏态。

### 空间（Spacing）

- 布局间距统一使用 `8 / 16 / 24 / 32 / 40 / 48 / 64` Spacing Scale。
- 禁止使用 `11px`、`17px`、`23px` 等无规律布局间距。
- 细线、图标光学修正、字体度量和系统物理尺寸不属于布局间距；如确需偏离间距标尺，必须有明确的光学或系统约束理由，并保持同类场景一致。

### 层级（Depth）

- 适当使用 Blur、Elevation、Shadow、Border 建立清晰而克制的空间层级。
- 禁止过重阴影、厚边框和过度玻璃效果。
- 深度效果必须服务于层级和可读性，不得仅作为装饰。

### 动画（Motion）

- 动画优先采用 Ease Out、Spring 与 Material Motion 所体现的自然运动原则。
- 所有出现、消失、尺寸变化和状态切换都必须具有连续性、物理感和适当惯性。
- 禁止突兀出现或突然消失；动画不得破坏布局锚点、阅读稳定性和操作反馈。
- 必须尊重 Reduce Motion 等系统辅助功能设置。

### 一致性（Consistency）

- 所有页面和模块必须复用 Design Token，统一颜色、字体、圆角、间距、阴影与图标。
- 禁止多个设计风格混搭；新增视觉规则前优先复用或扩展现有 Token，而不是在局部硬编码另一套体系。

### 可用性（UX）

- 界面必须易学、易懂、易操作，并符合 Nielsen 十大可用性原则。
- 可交互点击区域不得小于 `44pt × 44pt`；紧凑界面可扩大隐形命中区域，但不得牺牲视觉精度。
- 主要操作必须突出，次要操作适当弱化，危险操作必须有明确提示和防误触设计。
- 美观不得以牺牲可发现性、反馈、容错、可访问性或操作效率为代价。

### 图标（Icon）

- 统一使用 SF Symbols、Lucide 或 Phosphor 风格；macOS 原生界面优先 SF Symbols。
- 同一界面内保持图标线宽、视觉重量和尺寸一致，禁止无理由混用多套图标语言。

### 最终验收

- 每一个像素都必须有设计理由，不为了填满页面而增加元素。
- UI 方案在开发前应能说明布局比例、对齐基准、间距 Token、视觉层级、色彩角色、状态反馈和动画逻辑。
- 最终输出必须达到可直接交付开发的设计质量；若“功能完整”和“视觉秩序”冲突，应先重构信息与交互，而不是继续堆叠元素。

## 目录速查（在哪找代码）

| 我要改… | 去这里 |
|---|---|
| 刘海窗口/定位/形状 | `Packages/PocketNotchKit/Sources/PocketNotchCore/Window/` |
| 展开/收起交互与状态机 | `PocketNotchCore/State/` |
| 模块协议与注册中心 | `PocketNotchCore/Module/` |
| 颜色/圆角/动画常量 | `PocketNotchCore/Theme/` |
| 媒体/Now Playing | `Packages/PocketNotchKit/Sources/MediaModule/` |
| 文件暂存架 Shelf | `Packages/PocketNotchKit/Sources/ShelfModule/` |
| 电池/系统状态 | `Packages/PocketNotchKit/Sources/SystemStatsModule/` |
| 通用工具/扩展 | `Packages/PocketNotchKit/Sources/PocketNotchShared/` |
| App 壳/菜单栏/入口 | `App/` |

完整结构见 `docs/ARCHITECTURE.md`。

## 如何新增一个功能模块

见 `docs/CONTRIBUTING-MODULE.md`（含分步清单与模板）。核心：实现 `PocketNotchModule`，自带
`Views/ + Service + ViewModel`，在入口注册，禁止让 Core 反向依赖你的模块。

## 代码规范

完整规范见 `docs/CODING-STANDARDS.md`。要点：
- SwiftUI 视图小而专，业务逻辑放 ViewModel（`@Observable`），不写进 View。
- 命名清晰自解释；默认不写注释，只在「为什么这么做」不明显时写一行。
- 每个模块的核心逻辑要有单元测试（`Tests/`）。
- 空闲态必须停止动画与轮询，用事件驱动刷新（耗电是核心质量指标）。

## 开发路线

见 `docs/ROADMAP.md`。当前 MVP 三大功能：媒体控制、文件暂存架 Shelf、电池/系统状态。
开发顺序：先攻刘海窗口地基（Phase 1），再叠功能模块。

## 给 AI 的工作约定

- 改代码前先读对应模块目录，遵循既有分层，不要把逻辑塞进 View 或 App 壳。
- 涉及私有框架，只在 `MediaRemoteService` 内操作。
- 新增功能优先做成独立模块，而不是往现有模块堆代码。
- 不确定架构边界时，回到本文件「架构铁律」核对。
- 文档类文件（`.md`）除非被明确要求，否则不主动新建。
- **验证铁律：每次完成代码改动后，只验证项目 Build 通过即可；不启动应用、不截图、不操作 UI，也不代替维护者验证实际运行、视觉或交互效果。实际效果统一由维护者本人验证，除非维护者当次明确要求额外验证。**
- 仅调整已有常量、尺寸、间距等简单数值且不涉及编译报错风险时，可跳过 Build，由维护者直接重启运行验证。
- 与本项目维护者对话一律用中文（含解释、方案讨论、提交说明）。代码标识符与英文技术术语保持原样。
