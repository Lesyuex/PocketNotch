import AppKit

// 预览工具：把 hidden 态刘海形状渲染成放大 PNG，直观检查四个角。
// 坐标系与源码一致：y=0 在顶部（贴屏幕），y 向下为正，y=height 为底部。
// 用法：swiftc Tools/preview_notch.swift -o /tmp/preview_notch && /tmp/preview_notch

func clampv(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), hi) }

// ---- 当前实现（从 NotchShape.swift 逐字复制，用于对比）----
func makeHiddenPathOld(width: CGFloat, height: CGFloat,
                       shoulderWidthRatio: CGFloat = 0.12,
                       shoulderDepthRatio: CGFloat = 0.38,
                       topCornerRatio: CGFloat = 0.46) -> CGPath {
    let shoulderWidth = clampv(width * max(shoulderWidthRatio, 0.16), 64, min(width * 0.30, 128))
    let shoulderDepth = clampv(height * topCornerRatio, 15, min(height * 0.78, 30))
    let sideX = shoulderWidth
    let sideBottomY = height * 0.70
    let bottomRadius = clampv(height * 0.34, 10, min(height * 0.44, 17))
    let k: CGFloat = 0.5522847498
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: 0))
    path.addLine(to: CGPoint(x: width, y: 0))
    path.addCurve(to: CGPoint(x: width - sideX, y: shoulderDepth),
                  control1: CGPoint(x: width - shoulderWidth * 0.12, y: 0),
                  control2: CGPoint(x: width - shoulderWidth * 0.92, y: shoulderDepth * 0.08))
    path.addCurve(to: CGPoint(x: width - sideX, y: sideBottomY),
                  control1: CGPoint(x: width - sideX - shoulderWidth * 0.04, y: shoulderDepth + height * 0.10),
                  control2: CGPoint(x: width - sideX, y: sideBottomY - height * 0.12))
    path.addCurve(to: CGPoint(x: width - sideX - bottomRadius, y: height),
                  control1: CGPoint(x: width - sideX, y: height - bottomRadius * (1 - k)),
                  control2: CGPoint(x: width - sideX - bottomRadius * (1 - k), y: height))
    path.addLine(to: CGPoint(x: sideX + bottomRadius, y: height))
    path.addCurve(to: CGPoint(x: sideX, y: sideBottomY),
                  control1: CGPoint(x: sideX + bottomRadius * (1 - k), y: height),
                  control2: CGPoint(x: sideX, y: height - bottomRadius * (1 - k)))
    path.addCurve(to: CGPoint(x: sideX, y: shoulderDepth),
                  control1: CGPoint(x: sideX, y: sideBottomY - height * 0.12),
                  control2: CGPoint(x: sideX - shoulderWidth * 0.04, y: shoulderDepth + height * 0.10))
    path.addCurve(to: CGPoint(x: 0, y: 0),
                  control1: CGPoint(x: shoulderWidth * 0.92, y: shoulderDepth * 0.08),
                  control2: CGPoint(x: shoulderWidth * 0.12, y: 0))
    path.closeSubpath()
    return path
}

// ---- 改进版：上方对称内凹角 + 竖直侧壁 + 标准外凸底角 ----
func makeHiddenPathNew(width: CGFloat, height: CGFloat,
                       shoulderWidthRatio: CGFloat = 0.12,
                       shoulderDepthRatio: CGFloat = 0.38,
                       topCornerRatio: CGFloat = 0.46) -> CGPath {
    // 顶部每侧收进量（喇叭口水平跨度）
    let inset = clampv(width * max(shoulderWidthRatio, 0.16), 64, min(width * 0.30, 128))
    // 内凹角垂直跨度
    let topDepth = clampv(height * topCornerRatio, 14, min(height * 0.90, 34))
    // 下方外凸圆角
    let bottomR = clampv(height * 0.34, 10, min(height * 0.50, 18))
    let cf: CGFloat = 0.62          // 内凹角饱满度（控制点比例）
    let k: CGFloat = 0.5522847498   // 1/4 圆贝塞尔常数

    let leftX = inset
    let rightX = width - inset

    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: 0))
    path.addLine(to: CGPoint(x: width, y: 0))                       // 顶边
    // 右上内凹角：顶边 -> 侧壁，上端水平相切、下端垂直相切
    path.addCurve(to: CGPoint(x: rightX, y: topDepth),
                  control1: CGPoint(x: width - inset * cf, y: 0),
                  control2: CGPoint(x: rightX, y: topDepth * (1 - cf)))
    path.addLine(to: CGPoint(x: rightX, y: height - bottomR))       // 右侧壁（竖直）
    // 右下外凸圆角
    path.addCurve(to: CGPoint(x: rightX - bottomR, y: height),
                  control1: CGPoint(x: rightX, y: height - bottomR * (1 - k)),
                  control2: CGPoint(x: rightX - bottomR * (1 - k), y: height))
    path.addLine(to: CGPoint(x: leftX + bottomR, y: height))        // 底边
    // 左下外凸圆角
    path.addCurve(to: CGPoint(x: leftX, y: height - bottomR),
                  control1: CGPoint(x: leftX + bottomR * (1 - k), y: height),
                  control2: CGPoint(x: leftX, y: height - bottomR * (1 - k)))
    path.addLine(to: CGPoint(x: leftX, y: topDepth))                // 左侧壁（竖直）
    // 左上内凹角：侧壁 -> 顶边
    path.addCurve(to: CGPoint(x: 0, y: 0),
                  control1: CGPoint(x: leftX, y: topDepth * (1 - cf)),
                  control2: CGPoint(x: inset * cf, y: 0))
    path.closeSubpath()
    return path
}

// ---- 改进版 2：竖直侧壁 + 上下四个小圆角（内凹/外凸对称）----
// 目标形状：
//   ────────╮        ╭────────
//           ╰────────╯
// 侧壁近垂直，四角半径都小；上两角内凹（融入屏幕），下两角外凸。
func makeHiddenPathNew2(width: CGFloat, height: CGFloat,
                        shoulderWidthRatio: CGFloat = 0.12,
                        shoulderDepthRatio: CGFloat = 0.38,
                        topCornerRatio: CGFloat = 0.46) -> CGPath {
    let sideInset = clampv(width * max(shoulderWidthRatio, 0.13), 44, min(width * 0.24, 96))
    let topR = clampv(height * 0.42, 10, min(height * 0.55, 20))   // 上方内凹角半径
    let botR = clampv(height * 0.34, 8, min(height * 0.48, 16))    // 下方外凸角半径
    let k: CGFloat = 0.5522847498

    let leftX = sideInset
    let rightX = width - sideInset
    let topLeftOuter = leftX - topR
    let topRightOuter = rightX + topR

    let path = CGMutablePath()
    path.move(to: CGPoint(x: topLeftOuter, y: 0))
    path.addLine(to: CGPoint(x: topRightOuter, y: 0))                 // 顶边
    // 右上内凹角（圆心在右壁顶 rightX,0）
    path.addCurve(to: CGPoint(x: rightX, y: topR),
                  control1: CGPoint(x: topRightOuter, y: topR * k),
                  control2: CGPoint(x: rightX + topR * k, y: topR))
    path.addLine(to: CGPoint(x: rightX, y: height - botR))            // 右侧壁（竖直）
    // 右下外凸角
    path.addCurve(to: CGPoint(x: rightX - botR, y: height),
                  control1: CGPoint(x: rightX, y: height - botR * (1 - k)),
                  control2: CGPoint(x: rightX - botR * (1 - k), y: height))
    path.addLine(to: CGPoint(x: leftX + botR, y: height))            // 底边
    // 左下外凸角
    path.addCurve(to: CGPoint(x: leftX, y: height - botR),
                  control1: CGPoint(x: leftX + botR * (1 - k), y: height),
                  control2: CGPoint(x: leftX, y: height - botR * (1 - k)))
    path.addLine(to: CGPoint(x: leftX, y: topR))                     // 左侧壁（竖直）
    // 左上内凹角（圆心在左壁顶 leftX,0）
    path.addCurve(to: CGPoint(x: topLeftOuter, y: 0),
                  control1: CGPoint(x: leftX - topR * k, y: topR),
                  control2: CGPoint(x: topLeftOuter, y: topR * k))
    path.closeSubpath()
    return path
}

// ---- 改进版 3：竖直侧壁 + 四个角全外凸（去掉顶部内凹）----
// 目标形状：一个上下都是外凸圆角的胶囊/圆角矩形，顶边不外扩。
//   ╭────────────────────╮
//   ╰────────────────────╯
func makeHiddenPathConvex(width: CGFloat, height: CGFloat,
                          shoulderWidthRatio: CGFloat = 0.12,
                          shoulderDepthRatio: CGFloat = 0.38,
                          topCornerRatio: CGFloat = 0.46) -> CGPath {
    let sideInset = clampv(width * max(shoulderWidthRatio, 0.13), 44, min(width * 0.24, 96))
    let topR = clampv(height * 0.34, 8, min(height * 0.48, 16))    // 上方外凸角半径
    let botR = clampv(height * 0.34, 8, min(height * 0.48, 16))    // 下方外凸角半径
    let k: CGFloat = 0.5522847498

    let leftX = sideInset
    let rightX = width - sideInset

    let path = CGMutablePath()
    path.move(to: CGPoint(x: leftX + topR, y: 0))
    path.addLine(to: CGPoint(x: rightX - topR, y: 0))                // 顶边
    // 右上外凸角
    path.addCurve(to: CGPoint(x: rightX, y: topR),
                  control1: CGPoint(x: rightX - topR * (1 - k), y: 0),
                  control2: CGPoint(x: rightX, y: topR * (1 - k)))
    path.addLine(to: CGPoint(x: rightX, y: height - botR))           // 右侧壁（竖直）
    // 右下外凸角
    path.addCurve(to: CGPoint(x: rightX - botR, y: height),
                  control1: CGPoint(x: rightX, y: height - botR * (1 - k)),
                  control2: CGPoint(x: rightX - botR * (1 - k), y: height))
    path.addLine(to: CGPoint(x: leftX + botR, y: height))            // 底边
    // 左下外凸角
    path.addCurve(to: CGPoint(x: leftX, y: height - botR),
                  control1: CGPoint(x: leftX + botR * (1 - k), y: height),
                  control2: CGPoint(x: leftX, y: height - botR * (1 - k)))
    path.addLine(to: CGPoint(x: leftX, y: topR))                     // 左侧壁（竖直）
    // 左上外凸角
    path.addCurve(to: CGPoint(x: leftX + topR, y: 0),
                  control1: CGPoint(x: leftX, y: topR * (1 - k)),
                  control2: CGPoint(x: leftX + topR * (1 - k), y: 0))
    path.closeSubpath()
    return path
}

// ---- 肩部过渡曲线（正确版）：单段 cubic，无折点，中段向外扩 ----
// 顶边只到 topInset 处（不到最外沿）；肩部起点切线沿 +x 与顶边同向（无 cusp），
// 控制柄伸到顶边端点【外侧】(flareOut) 形成中段外扩，再竖直切入侧壁。
// topInset: 顶边端点距容器边（越小顶越宽）。flareOut: 外扩量(≤topInset)。vFrac: 竖直控制柄/topDepth。
func makeNotchFlare(width: CGFloat, height: CGFloat,
                    topInset: CGFloat, flareOut: CGFloat, vFrac: CGFloat) -> CGPath {
    let sideInset = clampv(width * 0.16, 64, min(width * 0.30, 128)) // 侧壁位置
    let topDepth = clampv(height * 0.55, 14, min(height * 0.72, 26)) // 肩部垂直跨度
    let botR = clampv(height * 0.30, 8, min(height * 0.45, 14))      // 底部外凸圆角
    let k: CGFloat = 0.5522847498
    let wallL = sideInset
    let wallR = width - sideInset
    let topL = topInset
    let topR = width - topInset

    let path = CGMutablePath()
    path.move(to: CGPoint(x: topL, y: 0))
    path.addLine(to: CGPoint(x: topR, y: 0))                        // 平顶
    // 右肩：顶边端点(水平、外扩) -> 右壁(竖直)
    path.addCurve(to: CGPoint(x: wallR, y: topDepth),
                  control1: CGPoint(x: topR + flareOut, y: 0),
                  control2: CGPoint(x: wallR, y: topDepth * (1 - vFrac)))
    path.addLine(to: CGPoint(x: wallR, y: height - botR))           // 右侧壁
    path.addCurve(to: CGPoint(x: wallR - botR, y: height),
                  control1: CGPoint(x: wallR, y: height - botR * (1 - k)),
                  control2: CGPoint(x: wallR - botR * (1 - k), y: height))
    path.addLine(to: CGPoint(x: wallL + botR, y: height))           // 底边
    path.addCurve(to: CGPoint(x: wallL, y: height - botR),
                  control1: CGPoint(x: wallL + botR * (1 - k), y: height),
                  control2: CGPoint(x: wallL, y: height - botR * (1 - k)))
    path.addLine(to: CGPoint(x: wallL, y: topDepth))                // 左侧壁
    // 左肩：左壁(竖直) -> 顶边端点(水平、外扩)
    path.addCurve(to: CGPoint(x: topL, y: 0),
                  control1: CGPoint(x: wallL, y: topDepth * (1 - vFrac)),
                  control2: CGPoint(x: topL - flareOut, y: 0))
    path.closeSubpath()
    return path
}

// ---- 顶角直角版：满宽平顶 + 顶部两角 90°直角(无圆角) + 肩部 cubic 收进侧壁 + 底外凸 ----
// 顶角处：顶边水平、肩部起点竖直向下 → 90°直角(无 radius)。肩部下端竖直切入侧壁(无折点)。
// sideInset: 侧壁位置(越大收腰越多)。cyTop: 顶角竖直控制柄/topDepth。cyBot: 侧壁竖直控制柄/topDepth。
func makeSharpTop(width: CGFloat, height: CGFloat,
                  sideInset: CGFloat, topDepthFrac: CGFloat,
                  cyTop: CGFloat, cyBot: CGFloat) -> CGPath {
    let topDepth = clampv(height * topDepthFrac, 10, height * 0.80)
    let botR = clampv(height * 0.30, 8, min(height * 0.45, 14))
    let k: CGFloat = 0.5522847498
    let wallL = sideInset
    let wallR = width - sideInset

    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: 0))
    path.addLine(to: CGPoint(x: width, y: 0))                       // 满宽平顶，两端 90°直角
    // 右肩：顶角(竖直向下) -> 右壁(竖直切入)
    path.addCurve(to: CGPoint(x: wallR, y: topDepth),
                  control1: CGPoint(x: width, y: topDepth * cyTop),
                  control2: CGPoint(x: wallR, y: topDepth * (1 - cyBot)))
    path.addLine(to: CGPoint(x: wallR, y: height - botR))           // 右侧壁
    path.addCurve(to: CGPoint(x: wallR - botR, y: height),
                  control1: CGPoint(x: wallR, y: height - botR * (1 - k)),
                  control2: CGPoint(x: wallR - botR * (1 - k), y: height))
    path.addLine(to: CGPoint(x: wallL + botR, y: height))           // 底边
    path.addCurve(to: CGPoint(x: wallL, y: height - botR),
                  control1: CGPoint(x: wallL + botR * (1 - k), y: height),
                  control2: CGPoint(x: wallL, y: height - botR * (1 - k)))
    path.addLine(to: CGPoint(x: wallL, y: topDepth))                // 左侧壁
    // 左肩：左壁(竖直) -> 顶角(竖直向上)
    path.addCurve(to: CGPoint(x: 0, y: 0),
                  control1: CGPoint(x: wallL, y: topDepth * (1 - cyBot)),
                  control2: CGPoint(x: 0, y: topDepth * cyTop))
    path.closeSubpath()
    return path
}

// ---- 宽条版：小侧边距(拐角贴边) + 独立上/下圆角 + 短连接线 ----
// inset: 侧边距(越小越贴边)。topR: 上两角半径。botR: 下两角半径。
func makeWideRR(width: CGFloat, height: CGFloat,
                inset: CGFloat, topR: CGFloat, botR: CGFloat) -> CGPath {
    let k: CGFloat = 0.5522847498
    let L = inset
    let R = width - inset
    let p = CGMutablePath()
    p.move(to: CGPoint(x: L + topR, y: 0))
    p.addLine(to: CGPoint(x: R - topR, y: 0))                 // 平顶
    p.addCurve(to: CGPoint(x: R, y: topR),                    // 右上外凸
               control1: CGPoint(x: R - topR * (1 - k), y: 0),
               control2: CGPoint(x: R, y: topR * (1 - k)))
    p.addLine(to: CGPoint(x: R, y: height - botR))            // 右壁
    p.addCurve(to: CGPoint(x: R - botR, y: height),           // 右下外凸
               control1: CGPoint(x: R, y: height - botR * (1 - k)),
               control2: CGPoint(x: R - botR * (1 - k), y: height))
    p.addLine(to: CGPoint(x: L + botR, y: height))            // 底边
    p.addCurve(to: CGPoint(x: L, y: height - botR),           // 左下外凸
               control1: CGPoint(x: L + botR * (1 - k), y: height),
               control2: CGPoint(x: L, y: height - botR * (1 - k)))
    p.addLine(to: CGPoint(x: L, y: topR))                     // 左壁
    p.addCurve(to: CGPoint(x: L + topR, y: 0),                // 左上外凸
               control1: CGPoint(x: L, y: topR * (1 - k)),
               control2: CGPoint(x: L + topR * (1 - k), y: 0))
    p.closeSubpath()
    return p
}

// ---- 宽条+收腰版：顶略宽(近直角顶角) + 短肩内收 + 竖直短壁 + 底外凸, 全程贴边 ----
// inset: 底壁侧边距。topExtra: 顶比底每侧宽出量。shoulderDepth: 肩垂直跨度。botR: 底圆角。
func makeWideNotch(width: CGFloat, height: CGFloat,
                   inset: CGFloat, topExtra: CGFloat,
                   shoulderDepth: CGFloat, botR: CGFloat) -> CGPath {
    let k: CGFloat = 0.5522847498
    let wallL = inset
    let wallR = width - inset
    let topL = inset - topExtra
    let topR = width - inset + topExtra
    let sd = shoulderDepth
    let p = CGMutablePath()
    p.move(to: CGPoint(x: topL, y: 0))
    p.addLine(to: CGPoint(x: topR, y: 0))                       // 平顶(略宽)
    // 右肩：顶角(竖直向下,近直角) -> 右壁(竖直切入)
    p.addCurve(to: CGPoint(x: wallR, y: sd),
               control1: CGPoint(x: topR, y: sd * 0.55),
               control2: CGPoint(x: wallR, y: sd * 0.45))
    p.addLine(to: CGPoint(x: wallR, y: height - botR))          // 右壁(短)
    p.addCurve(to: CGPoint(x: wallR - botR, y: height),         // 右下外凸
               control1: CGPoint(x: wallR, y: height - botR * (1 - k)),
               control2: CGPoint(x: wallR - botR * (1 - k), y: height))
    p.addLine(to: CGPoint(x: wallL + botR, y: height))          // 底边
    p.addCurve(to: CGPoint(x: wallL, y: height - botR),         // 左下外凸
               control1: CGPoint(x: wallL + botR * (1 - k), y: height),
               control2: CGPoint(x: wallL, y: height - botR * (1 - k)))
    p.addLine(to: CGPoint(x: wallL, y: sd))                     // 左壁(短)
    // 左肩：左壁(竖直) -> 顶角(竖直向上,近直角)
    p.addCurve(to: CGPoint(x: topL, y: 0),
               control1: CGPoint(x: wallL, y: sd * 0.45),
               control2: CGPoint(x: topL, y: sd * 0.55))
    p.closeSubpath()
    return p
}

// ---- 宽条+收腰+顶角倒圆：顶外角用小凸圆角(不尖), 短肩内收, 竖直短壁, 底外凸 ----
// inset: 底壁侧边距。topExtra: 顶比底每侧宽出量。shoulderDepth: 肩垂直跨度(越小肩越贴顶)。
// topCornerR: 顶外角凸圆角半径(越大越不尖)。botR: 底圆角。要求 topCornerR < shoulderDepth。
func makeWideNotch2(width: CGFloat, height: CGFloat,
                    inset: CGFloat, topExtra: CGFloat,
                    shoulderDepth: CGFloat, topCornerR: CGFloat, botR: CGFloat) -> CGPath {
    let k: CGFloat = 0.5522847498
    let wallL = inset
    let wallR = width - inset
    let topL = inset - topExtra
    let topR = width - inset + topExtra
    let sd = shoulderDepth
    let r = min(topCornerR, sd - 0.5)
    let p = CGMutablePath()
    p.move(to: CGPoint(x: topL + r, y: 0))
    p.addLine(to: CGPoint(x: topR - r, y: 0))                  // 平顶(两端各缩 r)
    // 右上外凸圆角(倒角, 不尖)
    p.addCurve(to: CGPoint(x: topR, y: r),
               control1: CGPoint(x: topR - r * (1 - k), y: 0),
               control2: CGPoint(x: topR, y: r * (1 - k)))
    // 右肩：圆角末端 -> 右壁(竖直切入)
    p.addCurve(to: CGPoint(x: wallR, y: sd),
               control1: CGPoint(x: topR, y: r + (sd - r) * 0.55),
               control2: CGPoint(x: wallR, y: sd - (sd - r) * 0.45))
    p.addLine(to: CGPoint(x: wallR, y: height - botR))         // 右壁(短)
    p.addCurve(to: CGPoint(x: wallR - botR, y: height),        // 右下外凸
               control1: CGPoint(x: wallR, y: height - botR * (1 - k)),
               control2: CGPoint(x: wallR - botR * (1 - k), y: height))
    p.addLine(to: CGPoint(x: wallL + botR, y: height))         // 底边
    p.addCurve(to: CGPoint(x: wallL, y: height - botR),        // 左下外凸
               control1: CGPoint(x: wallL + botR * (1 - k), y: height),
               control2: CGPoint(x: wallL, y: height - botR * (1 - k)))
    p.addLine(to: CGPoint(x: wallL, y: sd))                    // 左壁(短)
    // 左肩：左壁(竖直) -> 圆角起点
    p.addCurve(to: CGPoint(x: topL, y: r),
               control1: CGPoint(x: wallL, y: sd - (sd - r) * 0.45),
               control2: CGPoint(x: topL, y: r + (sd - r) * 0.55))
    // 左上外凸圆角(倒角, 不尖)
    p.addCurve(to: CGPoint(x: topL + r, y: 0),
               control1: CGPoint(x: topL, y: r * (1 - k)),
               control2: CGPoint(x: topL + r * (1 - k), y: 0))
    p.closeSubpath()
    return p
}

// ---- 经典刘海：满宽平顶 + 顶部两角【内凹】过渡(非直角/非外凸) + 竖直壁 + 底外凸 ----
// inset: 侧壁位置(底部半宽边距)。topR: 顶内凹角半径(越小肩越贴顶)。botR: 底外凸圆角。
func makeConcaveNotch(width: CGFloat, height: CGFloat,
                      inset: CGFloat, topR: CGFloat, botR: CGFloat) -> CGPath {
    let wallL = inset
    let wallR = width - inset
    let p = CGMutablePath()
    p.move(to: CGPoint(x: wallL - topR, y: 0))
    p.addLine(to: CGPoint(x: wallR + topR, y: 0))                    // 平顶(比壁宽 topR/侧)
    p.addQuadCurve(to: CGPoint(x: wallR, y: topR),                   // 右上内凹
                   control: CGPoint(x: wallR, y: 0))
    p.addLine(to: CGPoint(x: wallR, y: height - botR))              // 右壁
    p.addQuadCurve(to: CGPoint(x: wallR - botR, y: height),         // 右下外凸
                   control: CGPoint(x: wallR, y: height))
    p.addLine(to: CGPoint(x: wallL + botR, y: height))             // 底边
    p.addQuadCurve(to: CGPoint(x: wallL, y: height - botR),        // 左下外凸
                   control: CGPoint(x: wallL, y: height))
    p.addLine(to: CGPoint(x: wallL, y: topR))                      // 左壁
    p.addQuadCurve(to: CGPoint(x: wallL - topR, y: 0),             // 左上内凹
                   control: CGPoint(x: wallL, y: 0))
    p.closeSubpath()
    return p
}

// ---- 落码形状（与 NotchShape.swift 的 makeHiddenScreenNotchPath 逐字同构）----
// NotchShapeSpec: inset=w*0.0545(18–28), topR=h*0.139(4–7), botR=h*0.25(7–12)
func makeCommitted(width: CGFloat, height: CGFloat) -> CGPath {
    let inset = clampv(width * 0.0545, 18, 28)
    let topR = clampv(height * 0.139, 4, 7)
    let botR = clampv(height * 0.25, 7, 12)
    return makeConcaveNotch(width: width, height: height, inset: inset, topR: topR, botR: botR)
}

// ---- 渲染：真实运行尺寸, 全部 2× (接近 retina 点→像素观感), 对比不同角大小 ----
// 之前在 4× 下调参导致真实 1× 看不出内凹。这次在接近真机的 2× 下, 加大角半径重新选。
let runW: CGFloat = 450   // 有媒体 hidden 宽（刘海宽 + 左右耳，clamp 到 300–460）
let runH: CGFloat = 34    // 真实 hidden 高（clamp 32–38）
struct Variant { let topR: CGFloat; let botR: CGFloat; let title: String }
let variants: [Variant] = [
    Variant(topR: 9,  botR: 14, title: "H1 顶内凹9 底凸14 (中等, 屏上可见)"),
    Variant(topR: 13, botR: 18, title: "H2 顶内凹13 底凸18 (明显)"),
    Variant(topR: 17, botR: 22, title: "H3 顶内凹17 底凸22 (强, 接近参考图观感)"),
]
let scale: CGFloat = 2

let pad: CGFloat = 40
let labelH: CGFloat = 26
let bandH: CGFloat = 24

let cellW = runW * scale + pad * 2
let cellH = runH * scale + bandH + labelH + pad
let canvasW = Int(cellW)
let canvasH = Int(cellH * CGFloat(variants.count))

guard let ctx = CGContext(data: nil, width: canvasW, height: canvasH,
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no ctx")
}
ctx.setFillColor(CGColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))

let inset = clampv(runW * 0.0545, 18, 28)

func drawCell(_ v: Variant, cellIndex: Int) {
    let cellTopY = CGFloat(canvasH) - CGFloat(cellIndex + 1) * cellH
    ctx.saveGState()
    ctx.translateBy(x: pad, y: cellTopY + pad)

    let bandRect = CGRect(x: 0, y: runH * scale, width: runW * scale, height: bandH)
    ctx.setFillColor(CGColor(red: 0.30, green: 0.55, blue: 0.95, alpha: 0.35))
    ctx.fill(bandRect)

    ctx.saveGState()
    ctx.translateBy(x: 0, y: runH * scale)
    ctx.scaleBy(x: scale, y: -scale)
    ctx.addPath(makeConcaveNotch(width: runW, height: runH, inset: inset, topR: v.topR, botR: v.botR))
    ctx.setFillColor(CGColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
        .foregroundColor: NSColor.white
    ]
    let line = NSAttributedString(string: v.title, attributes: attrs)
    let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ns
    line.draw(at: CGPoint(x: 2, y: runH * scale + bandH + 2))
    NSGraphicsContext.restoreGraphicsState()
    ctx.restoreGState()
}

for i in 0..<variants.count {
    drawCell(variants[i], cellIndex: i)
}

guard let img = ctx.makeImage() else { fatalError("no image") }
let rep = NSBitmapImageRep(cgImage: img)
guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
let out = URL(fileURLWithPath: "/tmp/notch_preview.png")
try data.write(to: out)
print("wrote \(out.path)")
