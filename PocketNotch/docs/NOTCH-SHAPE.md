# 刘海/背板形状规则（NOTCH-SHAPE）

本文件定义 PocketNotch 所有「岛/背板」路径的统一几何规则。收起态分为无媒体隐藏态与有媒体灵动态两种；两种紧凑形态共享同一套收紧肩部曲率。
展开态继续复用相同的路径拓扑，并让肩部与底角从各自的紧凑态半径连续过渡到更大的平缓半径。

> 唯一真相来源：`PocketNotchCore/Window/NotchShape.swift` 里的 `NotchShapeSpec`（比例常量）
> 与 `makeHiddenScreenNotchPath`（路径构造）。改规则改这里，不要在各处散落硬编码。

## 形状语言（记住这三条，别再反复试）

```
────────╮        ╭────────    ← 顶部：满宽略宽平顶，两侧【内凹】收进侧壁
        ╰────────╯            ← 底部：两角【外凸】圆角
```

1. **顶部两角 = 内凹（concave）**。周围「屏幕」表面向刘海内部凹进，让刘海平滑融入屏幕顶边。
   不是直角，也不是外凸圆角。历史上这里反复调错，认准「内凹」。
2. **底部两角 = 外凸（convex）**。就是常规的可见圆角。
3. **侧壁竖直**。顶内凹角下端、底外凸角上端都竖直相切接入侧壁，**全程无折点（G1 连续）**。

坐标系：`y = 0` 在顶部（贴屏幕），`y` 向下为正，`y = height` 是底部。

## 几何构造（顶内凹 + 底外凸）

平顶每侧比侧壁再外扩一个 `topR`，用一段 **二次贝塞尔（quadCurve）** 把平顶端点收进侧壁顶，
控制点落在「侧壁 x、顶边 y=0」这个角点上 —— 这自动得到内凹圆弧（圆心在角点）：

- 平顶：`(wallL - topR, 0) → (wallR + topR, 0)`
- 右上内凹：`quad to (wallR, topR), control (wallR, 0)`
- 右侧壁：直线到 `(wallR, height - bottomR)`
- 右下外凸：`quad to (wallR - bottomR, height), control (wallR, height)`
- 底边：直线到 `(wallL + bottomR, height)`
- 左下外凸：`quad to (wallL, height - bottomR), control (wallL, height)`
- 左侧壁：直线到 `(wallL, topR)`
- 左上内凹：`quad to (wallL - topR, 0), control (wallL, 0)`

其中 `wallL = inset`，`wallR = width - inset`。

## 无媒体紧凑遮罩

系统没有媒体会话时（暂停仍算有媒体），左右耳不渲染。背板使用 `makeCompactNotchMaskPath`：

- 高度与系统刘海高度一致；
- **顶部内凹肩部和底部外凸圆角与有媒体态完全共用同一套半径计算及二次贝塞尔构造**，无媒体态不能退化成直角顶；
- 竖直主体宽度为实测刘海宽度加 `compactMaskHorizontalOverscan = 8pt`，即左右各多 4pt；
- 总路径宽度为 `主体宽度 + 2 × topR`，两侧 `topR` 只用于让肩部向外展开，不占用主体遮盖宽度；
- 这 8pt 主体余量用于覆盖不同机型曲率无法 1:1 复刻产生的漏边。

紧凑态取 `wallL = topR`、`wallR = width - topR`；有媒体态按 `insetRatio` 计算侧壁位置。
两者最终都进入同一个 `makeConcaveShoulderNotchPath`，因此肩部曲率和路径命令不会漂移。

## 三态曲率参数

| 语义 | Token | 数值 | 视觉目标 |
|---|---|---|---|
| 隐藏态 / 灵动态肩部半径 | `compactCornerRadius` | 8 pt | 收紧、利落，内容出现时曲率不漂移 |
| 隐藏态 / 灵动态底部圆角 | `compactBottomCornerRadius` | 13 pt | 底边保持更柔和的圆角，不跟随肩部调参 |
| 展开态肩部 / 底部半径 | `expandedCornerRadius` | 16 pt | 两组半径最终汇合，展开轮廓更平缓 |
| 灵动态侧壁边距 | `insetRatio` | `width × 0.0545`，限制 18–28 pt | 保留左右耳内容空间 |

肩部内凹与底部外凸独立插值：肩部按 8 → 16 pt、底部按 12 → 16 pt 变化。
两者与展开尺寸共用同一条弹簧的原始进度（`makePath` 里直接取 `rawProgress`），不再叠平滑
曲线，避免「尺寸已到、圆角还拖后腿」的拉丝感；收起严格沿同一曲线反向插值。
（`easedExpansionProgress` 保留但仅供外部急停使用，不再参与常规动画造型。）
隐藏态切入展开几何的首帧不会换形；灵动态的额外侧壁内缩会在展开过程中逐步释放，
最终让肩部外缘贴到展开画布边界，避免总宽越大反而向内挖得越深。

选型经过：从直角顶 / 外凸顶依次否掉，最终确认**顶内凹**才是参考图（`隐藏态.png`）的形态。

> ⚠️ 调参必须在真机尺寸下看。均匀放大保持比例，但不保持小圆角在 Retina 屏上的可辨识度。
> `Tools/preview_notch.swift` 使用真机点尺寸和 2× 渲染；不要只看大倍率预览判断肩部松紧。

## 坐标系与翻转（渲染时的隐坑）

路径一律**以 y-down 编写**：`y = 0` 在顶部（贴屏幕、放内凹角），`y = height` 在底部（放外凸角）。
两处消费这条路径，坐标系必须都保持「单次 y-down 翻转」，否则形状会上下颠倒（顶内凹渲染成顶外凸）：

- SwiftUI `clipShape(NotchShape)`：SwiftUI 本身就是 y-down，直接吃 `makePath`，正确。
- AppKit 填充层 `IslandBackgroundLayerView.IslandBackgroundShapeView`：**只在父 `layer` 设一次
  `isGeometryFlipped = true`**。不要再给 `shapeLayer` 设 `isGeometryFlipped`——两次翻转相互抵消，
  会把 y-down 路径倒过来画，顶部就变外凸。（曾因此上屏顶部是外凸，排查见此。）

规则：净翻转次数必须是奇数（正好一次）。改这块前先数清楚 view.isFlipped / layer / shapeLayer 各自的翻转。

## 展开态背板复用约定

当前 hidden / collapsed / expanded 都通过统一的 `makeConcaveShoulderNotchPath` 生成。维护展开背板时：

- 直接复用 `NotchShapeSpec` 的比例常量与 `makeHiddenScreenNotchPath` 的「顶内凹 + 底外凸 + 竖直壁」构造，
  只把 `width/height` 换成展开尺寸；**不要**新造一套角的画法。
- 若展开态需要更高的机身，主体主要向下拉长；肩部按 8 → 16 pt、底角按 12 → 16 pt 连续平缓化。
- 隐藏态与灵动态禁止通过非等比 `scaleEffect` 拉伸路径，必须按每帧真实宽高重建路径，否则圆弧会变成椭圆。
- 三态之间做形变动画时，顶内凹 ↔ 顶内凹、底外凸 ↔ 底外凸一一对应，路径命令数保持一致，避免插值跳变。

## 离线预览

改任何形状前，先用 `Tools/preview_notch.swift` 渲染 PNG 对比再定，不要只在文字里讨论参数：

```
cd "/Users/jobeth/study/xcode/Halo"
swiftc Tools/preview_notch.swift -o /tmp/preview_notch && /tmp/preview_notch   # 输出 /tmp/notch_preview.png
```
