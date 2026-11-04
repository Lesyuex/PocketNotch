#!/bin/zsh
# 一键采集 PocketNotch 媒体渲染链路日志（v2.4 采样用）
#
# 用法：
#   ./capture_media_render.sh [秒数]   # 默认 60 秒
#
# 开始前请保证：音乐播放 + 封面旋转 + 实时频谱 + 灵动岛显示
# 运行后立即连续执行 ⌘+Tab / Dock 切换 / Mission Control / Spotlight
# 结束自动输出 ./media-render-capture-<时间戳>.log

set -uo pipefail

SECONDS="${1:-60}"
OUT="media-render-capture-$(date +%Y%m%d-%H%M%S).log"

echo "开始采集 ${SECONDS}s → ${OUT}"
echo "请立刻开始连续 ⌘+Tab / Dock / Mission Control / Spotlight 操作…"

# log 是 zsh 内置命令，必须用绝对路径；log stream 无 --timeout，用后台采集 + 定时结束。
# --info --debug 让 .debug 摘要（avg interval / dropped / render delay）不被系统默认过滤。
/usr/bin/log stream \
  --predicate 'subsystem == "com.pocketnotch.app"' \
  --style compact \
  --info \
  --debug \
  >"$OUT" 2>&1 &

COLLECTOR_PID=$!

# 结束时间一到就终止采集，避免挂起。
(
  sleep "$SECONDS"
  kill "$COLLECTOR_PID" 2>/dev/null
) &
WATCHDOG_PID=$!

# 等采集器结束。
wait "$COLLECTOR_PID" 2>/dev/null
kill "$WATCHDOG_PID" 2>/dev/null

echo "采集完成：${OUT}"
echo "行数：$(wc -l < "$OUT" | tr -d ' ')"