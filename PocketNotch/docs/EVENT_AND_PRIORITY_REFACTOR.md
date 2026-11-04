# 灵动刘海「常驻 / 临时」消息与优先级重构文档

> 本文档是**设计稿**，用于对齐方向，不是已落地的现状。
> 目标：把当前分散在渲染层/数据层的「谁上岛、谁优先」仲裁，归并成一个清晰、
> 可维护的「常驻 / 临时」二分模型，并解决多 Agent 同时运行的展示问题。

---

## 1. 动机与现状问题

当前灵动岛上消息/动画的来源和优先级散落在**三个各管各的机制**里，导致：

| 机制 | 位置 | 负责的事 |
|---|---|---|
| `CompactResidentSettings.activeModule` | PocketNotchCore/State | 硬编码 `if-else` 顺序决定常驻（Agent > 股票 > 媒体 > 天气），**用代码顺序隐含优先级** |
| `IslandContentLayer` 的 ZStack 叠层 | PocketNotchCore/UI | 全模块 `compactNotification…View()` 堆叠，**无优先级队列**，临时通知都往上一盖 |
| `AgentWorkingPresentationController` | AgentEventModule | Agent 运行展示，**只显示一个**，多 Agent 时「最近活跃者独占」，不轮播 |
| `DisplayScheduler / DisplayPolicy`（新管线） | Display | 已有「Notification > Agent > Activity」与轮换代码，**但决策没接进渲染层**，形同摆设 |

### 核心问题

1. **优先级不是集中仲裁**：真正的裁决散在 `activeModule` 的 if-else + ZStack 叠层，而新管线的
   `DisplayScheduler` 决策（`DisplayCoordinator.decision` / `shouldShow`）在 `PocketNotchCore` 里**根本没人消费**。
2. **常驻优先级靠文件顺序隐含**，加一项常驻就要改 if-else 链，且不可配置。
3. **多 Agent 运行不轮播**：`selectActivity()` 取 `max(priority, sequence)`，两个普通运行 Agent
   会「最后发事件的独占」，另一个完全看不见。
4. **「临时通知」内部没有优先级**：等待授权/失败不能插队到比普通通知更前。

---

## 2. 目标模型：只分「常驻」「临时」两类

```
灵动岛当前内容 =
    临时（Transient）      —— 出现即盖住常驻，看完即走
        或
    常驻（Resident）       —— 持续存在，一次只显一个，按优先级裁决
```

### 2.1 常驻（Resident）

用户持续关注、生命周期长。**一次只显示一个**：常驻之间用**优先级裁决**；
而多 Agent 运行态之间则用**按时间轮播**（两者都遵守「一次显一个」这个约束）。

| 常驻项 | 载体（左右耳） | 优先级（从高到低） |
|---|---|---|
| **Agent 运行中** | 左耳宠物 + **右耳按 hook 动态替换图标** | **1（最高）** |
| 股票（交易时段优先） | `StockHiddenLeading/TrailingView` | 2 |
| 音乐（实时监控） | `NowPlayingHidden…View(role: .resident)` | 3 |
| 天气 | `WeatherHidden…View` | 4 |

> **关键语义（已确认）**：Agent 优先级最高，**交易时段股票也不压 Agent**；
> 当所有 Agent 都不在运行时，才回落到股票 / 音乐 / 天气等次级常驻。

**多 Agent 运行态的展示**：多个 Agent 同时处于「活动中」（运行 / 等待授权 / 思考 / 启动）时，
右耳只能放一个，因此**按固定轮播周期（默认 10 秒）轮流露脸**；
完成 / 失败等终态反馈优先展示、不参与轮播。详见 3.2 分组轮播。

### 2.2 临时（Transient）

瞬时反馈、出现即盖住常驻、看完即走，内部也分优先级。

| 临时项 | 载体 | 优先级（可打断） |
|---|---|---|
| Agent 等待授权 / 失败 | `compactNotification…View` + `notificationView()` | 高（可打断） |
| Agent 完成 / 停止 | 同上 | 中 |
| 切歌 / 音频输出切换 | `MediaNotificationHostView` | 中 |
| Agent 创建会话文字版 | `AgentWorking…View(isFullDetail)` | 中 |

> 临时与常驻的关系固定为：**临时存在 → 常驻让位**；临时结束 → 常驻恢复（重新裁决）。

---

## 3. 改造设计

### 3.1 常驻仲裁：显式优先级表

把 `activeModule` 的隐式 if-else 提炼为显式优先级模型。

- 引入 `ResidentKind` 枚举（`agent / stock / music / weather`），每种带 `priority`。
- `activeModule` 改为「**无 Agent 抢占时**，从 `isActive` 的常驻中取 `priority` 最高者」。
- **Agent 运行态独立为一个抢占信号**（`isAgentDisplayActive`），它在场 → `activeModule = .none`
  （常驻整体让位于 Agent 展示），与股票/媒体/天气不在同一槽竞争。
- 加项只需往表里加一行，优先级集中、可未来开放配置。

**文件**：`PocketNotchCore/State/CompactResidentSettings.swift`

```
输入：isAgentDisplayActive（Agent 抢占信号）
    + isStockCompactDisplayActive / isMediaCompactDisplayActive / isWeatherMonitoringEnabled
裁决：
  1. 若 Agent 运行中        → .none（Agent 独占，左耳宠物 + 右耳动态图标）
  2. 否则取 active 的常驻里 priority 最高者 → .stocks / .media / .weather
  3. 都无                  → .none
```

### 3.2 多 Agent 运行：分组轮播（本阶段重点）

问题：多个 Agent 同时在跑，右耳只有一个，必须轮流展示。

方案：`AgentWorkingPresentationController` 升级为「**同优先级分组 + 组内轮播**」。

```
selectActivity():
  1. 按 priority 降序分组，取「最高优先级组」；
  2. 若组内存在非活动终态/瞬时反馈（完成 jumping / 失败 failed / 停止 idle）：
       优先展示最近一则该反馈，不轮播；
  3. 否则（组内全为「活动中」成员）：
       用 rotationOffset 组内轮播，默认 offset=0 展示最近活跃。

「活动状态」定义（参与轮播）：
  running / runningLeft / runningRight（执行）、waiting（待授权）、review（思考）、waving（启动中）

「非活动状态」（不参与轮播，作为瞬时反馈优先展示）：
  jumping（完成）、failed（失败）、idle（停止）

具体规则：
  - 多个「活动中」agent（运行/等待授权/思考）→ 组内按固定时长（默认 10s）轮播；
  - 存在「完成/失败」终态反馈 → 优先展示该反馈（其自身 expiresAt 驱动时长），不轮播；
  - 组内单个活动 agent → 不轮播，恒显示它（与现状一致）。

scheduleNextBoundary():
  - 仅当最高优先级组内「全部为活动态」且成员数 > 1 时，安排「轮播 tick」（rotationInterval），
    到点推进 rotationOffset 并 refresh；
  - 存在终态反馈时不排轮播 tick，由其 expiry/transition 边界驱动；
  - 轮播 tick 让位于真实边界（过期 / 过渡 / 文字版结束先发生则先处理）。
```

**文件**：`AgentEventModule/Application/AgentWorkingPresentationController.swift`
**新状态**：`rotationOffset`（组内偏移，默认 0=最近活跃）、`rotationInterval`（默认 **10s**）、`isActiveActivity`（活动状态判定）

**不破坏的现有行为**（已有测试覆盖）：
- `testWaitingAndFailurePreemptRecentActiveAgent`：失败/等待仍高于普通运行 —— 高优分组保证高优组优先。
- `testHighPriorityEventPreemptsTextPhase`：失败可打断文字版 —— 终态反馈优先展示。
- `testAgentRemainsPresentedWhileAnotherSessionIsActive`：同一 Agent 多会话时显示活动的那个。
- `testTerminalFeedbackShowsOverActiveRotation`：完成反馈优先于活动轮播展示。
- `testFailedPreemptsActiveAndShowsFailedState`：失败优先于活动运行展示。

### 3.3 临时互斥：临时最高，同区只显一个临时（本阶段重点）

统一模型（已确认，勿再混）：**Agent 属常驻**，优先级 Agent > 股票 > 音乐 > 天气；
**临时 = 真正的几秒瞬时通知**（切歌 / 音量 / 音频输出 / 失败 / 等待授权 / 完成 / 停止），优先级**最高**，
来了盖住一切常驻（**含 Agent**），播完回到常驻。

问题（用户实测）：Agent 运行 + 切歌同时出现时，图标**叠在右耳同一区**。
根因：`IslandContentLayer` 的临时层对每个模块的 `compactNotification…View()` **无脑 ForEach 叠加**，
没有「同时只显一个临时」的互斥。且 Agent 被当临时挂在这一层，与切歌同区竞争。

方案：给临时层加「同区互斥」——同一时刻右耳/岛内临时区**只显示一个临时**：

```
临时优先级（从高到低）：
  1. 失败 / 等待授权         （越重要越踩上面）
  2. 切歌 / 音量 / 音频输出 / Agent完成 / 停止
  3. Agent 运行态（本次若仍走临时渲染通道，则作为临时里最低一档）

互斥规则：
  - 高优先临时在场 → 低优先临时隐藏；高优先消失 → 回到次高/原来的临时。
  - 临时整体的优先级仍高于所有常驻（含 Agent）：临时出现 → 常驻隐藏。
```

**待办**：
- 明确 Agent 渲染通道：把 Agent 从「临时层」拨回「常驻层」（语义上它是常驻、走 `activeModule` 那条
  单选 + 右耳动态图标），临时(切歌等)出现再让它让位。这是消除「Agent 与切歌同区重叠」的治本方案。
- 若暂不重排通道，则至少在临时 ZStack 内做「同区互斥」，保证同一时刻只画一个临时。

### 3.4 快捷开关（已确认**本轮不做**）

「菜单栏图标设置加各项灵动功能的快捷开关」—— 用户确认本轮不实施，留待后续。

### 3.5 会话 → Agent 状态聚合（轮播以 Agent 为单位）

同一个 Agent（如 claude / codex）可能同时有多个会话（多个终端 / 多个工作目录各跑一个）。
**轮播的单位是「Agent」，不是「会话」**——同一 Agent 的所有会话聚合成一个状态展示
（左耳宠物 + 右耳对应状态图标），不同 Agent 之间才轮播。

会话状态 → Agent 状态的聚合规则（按确定性优先级）：

| 会话状态 | 是否持续 | Agent 级聚合 |
|---|---|---|
| **等待授权** | 持续 | **最高**：任一会话等待授权 → Agent 显示「等待授权」 |
| **运行中**（执行命令/思考/调用工具） | 持续 | 次之：无等待授权、但有会话运行中 → Agent 显示「运行中」 |
| **已完成 / 失败** | **瞬时**（几秒） | 不参与持续态聚合；作为一次瞬时反馈弹出，播完消失 |
| **空闲**（无任何运行中/等待授权会话） | — | Agent 空闲 → **退出轮播**、不占常驻位 |

要点：
- **非空持续态只有两档：`等待授权 > 运行中`**；已完成/失败是瞬时反馈，不算持续态、不参与轮播。
- 多会话取**最高级别**：任一待授权 → 整体待授权；否则任一运行中 → 整体运行中。
- 空闲 Agent 不进入 Agent 轮播池，占位让给次级常驻（股票/音乐/天气）。

**文件**：`AgentEventModule/Application/AgentWorkingPresentationController.swift`
**改动**：把会话级 activity 聚合为 Agent 级状态，`topPriorityGroup`/轮播以 Agent 为单位。

---

## 4. 改造范围与文件清单

| 文件 | 改动 |
|---|---|
| `PocketNotchCore/State/CompactResidentSettings.swift` | 常驻优先级表化 + Agent 独立抢占信号 |
| `AgentEventModule/Application/AgentWorkingPresentationController.swift` | 多 Agent 分组轮播（核心） |
| `AgentEventModule/…/AgentWorkingCompactViews.swift` | 右耳图标已支持动态替换，可能微调多 Agent 切换动画 |
| `AgentEventModuleTests/AgentWorkingPresentationControllerTests.swift` | 新增轮播相关测试 |
| `PocketNotchCoreTests/…`（如 `CompactIslandTierTests` 引用 `activeModule`） | 适配优先级表化后的常量变化 |

> 说明：`AppDelegate`、`StockModule`、`MediaModule`、`WeatherModule` 里对
> `activeModule` / `isAgentDisplayActive` / `isStockCompactDisplayActive` 的**引用点会被核对**，
> 确保优先级表化后行为不回归。

---

## 5. 风险与取舍

1. **新旧管线并存**：渲染层实际用的是「旧管线（AgentWorkingPresentationController）+ `activeModule`」。
   本轮改动集中在旧管线内，风险可控；新管线（`DisplayScheduler`）本轮不接入渲染，保持现状。
2. **轮播周期**：默认 **10s**，后续可配置。
3. **高优 Agent 不会「永久霸屏」**：高优组内也轮播，避免等待授权一直占着右耳、其它信息全丢。
4. **优先级固定 vs 可配置**：本轮先固定优先级表，配置能力后续开放（避免一次改太大）。

---

## 6. 待确认 / 决策记录

- [x] Agent 优先级最高，**交易时段股票也不压 Agent**。
- [x] 无 Agent 运行时回落到次级常驻（股票/音乐/天气）。
- [x] 菜单栏快捷开关本轮**不做**。
- [x] 多 Agent 轮播周期默认 **10s**。
- [x] 常驻优先级固定顺序 **Agent > 股票 > 音乐 > 天气**。
- [x] 轮播仅限「活动中」agent（运行 / 待授权 / 思考 / 启动）；完成 / 失败等终态反馈优先展示但不参与轮播。
