# PocketNotch 开发路线图 (ROADMAP)

按「先啃地基，再叠功能」排序。时间为单人业余节奏的粗略估算，可自行压缩。

## MVP 范围

三大功能：**媒体控制**、**文件暂存架 Shelf**、**电池/系统状态**。

## 阶段里程碑

### Phase 0 · 脚手架（2–3 天）
- [ ] 建 Xcode 工程 + `PocketNotchKit` Package，配好 `LSUIElement`、菜单栏图标
- [ ] 定义 `PocketNotchModule` 协议与 `ModuleRegistry`
- 里程碑：App 常驻菜单栏，菜单可退出

### Phase 1 · 刘海窗口（地基，最难，4–6 天）
- [ ] `NotchWindow`：无边框、置顶、不抢焦点的 NSPanel
- [ ] `NotchPositioner`：读取刘海尺寸精确定位；无刘海机型/外接屏降级为顶部悬浮胶囊
- [ ] `NotchShape`：贴合真实刘海的圆角形状
- 里程碑：屏幕顶部出现贴合刘海的黑色岛

### Phase 2 · 交互状态机与动效（3–4 天）
- [ ] `NotchState` 状态机：收起 → 悬停展开 → 点击展开 → 拖拽态
- [ ] 统一 spring 动画（`Animations.swift`）
- 里程碑：移入平滑展开、移出收起，手感顺滑

### Phase 3 · 媒体控制模块（3–4 天）
- [ ] `MediaRemoteService` 封装私有框架，取 Now Playing / 播放态
- [ ] 收起态：封面 + 波形；展开态：进度条、上/下一首、播放暂停
- 里程碑：播放音乐时岛内实时显示并可控

### Phase 4 · 文件暂存架 Shelf（4–5 天）
- [ ] `ShelfDropReceiver` 接收拖入（NSItemProvider）
- [ ] `ShelfStore` 暂存（复制到沙箱），列表展示
- [ ] 支持拖出到 Finder/其他 App、删除
- 里程碑：文件拖入拖出闭环可用

### Phase 5 · 电池/系统状态模块（2–3 天）
- [ ] `SystemBatteryService`（IOKit）：电量、充电动画、剩余时间
- [ ] 可选 CPU/内存、AirPods 电量
- 里程碑：插拔充电器时岛内有反馈动画

### Phase 6 · 设置与持久化（2–3 天）
- [ ] 偏好窗口：模块启停、开机自启（`SMAppService`）、外观
- [ ] 模块开关驱动 `ModuleRegistry`
- 里程碑：设置项持久生效

### Phase 7 · 打磨与适配（持续）
- [ ] 多屏切换、合盖、分辨率变化、深浅色
- [ ] 性能：空闲 CPU 接近 0、内存稳定
- 里程碑：日常挂机稳定无异常

### Phase 8 · 分发（2–3 天）
- [ ] Developer ID 签名 + 公证
- [ ] 集成 Sparkle 自动更新
- 里程碑：可分发的 `.dmg`

## 后续可扩展模块（非 MVP）

剪贴板历史、倒计时/计时器、日历事件、AirDrop 快捷、摄像头镜像、快捷动作面板。
每个都按 `docs/CONTRIBUTING-MODULE.md` 作为独立模块接入。

## 关键风险与对策

| 风险 | 说明 | 对策 |
|---|---|---|
| MediaRemote 私有框架 | 不允许上架，新系统可能改动 | 隔离在 `MediaRemoteService`；上架需另寻方案 |
| 刘海定位不准 | 各机型/外接屏尺寸不同 | `NotchPositioner` 机型探测 + 无刘海降级 |
| 权限 | 拖拽、辅助功能可能需授权 | 首启引导授权，无权限优雅降级 |
| 空闲耗电 | 常驻 + 动画易吃 CPU | 收起态停动画、事件驱动、Instruments 定期测 |
