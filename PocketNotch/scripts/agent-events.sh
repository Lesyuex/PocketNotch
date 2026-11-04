#!/usr/bin/env bash
# PocketNotch Agent Event 上报脚本（Phase 1 调试/采集工具）
#
# 作用：把 CLI Agent 的 Hook 以统一 JSON 上报到 PocketNotch Agent Bridge
#       （默认 http://127.0.0.1:58421/api/agent/event）。
#
# 用法：
#   agent-events.sh health                      本地健康检查
#   agent-events.sh emit <agent> <type> [..可选..]  上报单条事件
#   agent-events.sh self-test                   跑通一次完整链路（需 App 已在运行）
#   agent-events.sh samples                     打印三个 CLI 的 Hook 配置样例（Claude / Codex / Gemini）
#
# emit 可选：--session --tool --file --command --message --timestamp --port
#   type 兼容 snake/camel/kebab：session_start  session_end  thinking  agent_start  tool_start
#        tool_end  command_start  command_end  waiting_approval  completed  failed

set -uo pipefail

POCKETNOTCH_AGENT_SCRIPT_VERSION=1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_PORT=58421

die() { echo "error: $*" >&2; exit 1; }

usage_short() { echo "用法: agent-events.sh {version|health|emit|self-test|samples} ...（详见文件头）" >&2; }

debug_enabled() {
  [ "${POCKETNOTCH_AGENT_DEBUG:-0}" = "1" ] || [ -f "${BASH_SOURCE[0]}.debug" ]
}

normalize_type() {
  case "$1" in
    session_start|sessionStart) echo "session_start" ;;
    session_end|sessionEnd)     echo "session_end" ;;
    agent_start|agentStart)     echo "agent_start" ;;
    thinking|think)             echo "thinking" ;;
    tool_start|toolStart)       echo "tool_start" ;;
    tool_end|toolEnd)           echo "tool_end" ;;
    command_start|commandStart) echo "command_start" ;;
    command_end|commandEnd)     echo "command_end" ;;
    waiting_approval|waitingApproval|waiting|ask) echo "waiting_approval" ;;
    completed|done)             echo "completed" ;;
    failed|error)               echo "failed" ;;
    *) echo "unknown" ;;
  esac
}

post_event() {
  local agent="$1" type="$2"
  shift 2
  local session= tool= file= command= message= port="$DEFAULT_PORT" timestamp
  local hook_pid="$$" hook_parent_pid="$PPID"
  local source_app="${POCKETNOTCH_SOURCE_APP:-${TERM_PROGRAM:-}}"
  local source_bundle_id="${POCKETNOTCH_SOURCE_BUNDLE_ID:-${__CFBundleIdentifier:-}}"

  [ -z "${type:-}" ] && die "缺少 type"
  timestamp="$(date +%s)"

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --session)  session="$2";  shift 2 ;;
      --tool)     tool="$2";     shift 2 ;;
      --file)     file="$2";     shift 2 ;;
      --command)  command="$2";  shift 2 ;;
      --message)  message="$2";  shift 2 ;;
      --source-app) source_app="$2"; shift 2 ;;
      --source-bundle-id) source_bundle_id="$2"; shift 2 ;;
      --timestamp) timestamp="$2"; shift 2 ;;
      --port)     port="$2";     shift 2 ;;
      *) die "未知参数: $1" ;;
    esac
  done

  # Codex / 其它 CLI 把 hook 事件以 JSON 通过 stdin 传入。
  # 若命令行没显式给出 session/tool/message，则从 stdin 提取。
  if [ -z "$session" ] || [ -z "$tool" ] || [ -z "$message" ]; then
    local stdin_json=""
    [ ! -t 0 ] && stdin_json="$(cat 2>/dev/null || true)"
    if [ -n "$stdin_json" ] && command -v jq >/dev/null 2>&1; then
      local sid tname msg hfile
      sid="$(printf '%s' "$stdin_json" | jq -r '[.session_id, .sessionId, .input.session_id, .input.sessionId] | map(select(type == "string" and length > 0)) | first // ""' 2>/dev/null || true)"
      tname="$(printf '%s' "$stdin_json" | jq -r '[.tool_name, .tool, .input.tool_name, .input.tool] | map(select(type == "string" and length > 0)) | first // ""' 2>/dev/null || true)"
      msg="$(printf '%s' "$stdin_json" | jq -r '[.prompt, .message, .text, .input.prompt] | map(select(type == "string" and length > 0)) | first // ""' 2>/dev/null || true)"
      hfile="$(printf '%s' "$stdin_json" | jq -r '[.file_path, .file, .path, .transcript_path, .input.file_path] | map(select(type == "string" and length > 0)) | first // ""' 2>/dev/null || true)"
      [ -z "$session" ] && [ -n "$sid" ] && session="$sid"
      [ -z "$tool" ] && [ -n "$tname" ] && tool="$tname"
      [ -z "$message" ] && [ -n "$msg" ] && message="$msg"
      [ -z "$file" ] && [ -n "$hfile" ] && file="$hfile"
    elif [ -n "$stdin_json" ]; then
      local sid tname msg hfile
      sid="$(printf '%s' "$stdin_json" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
      tname="$(printf '%s' "$stdin_json" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
      msg="$(printf '%s' "$stdin_json" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
      hfile="$(printf '%s' "$stdin_json" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
      [ -z "$session" ] && [ -n "$sid" ] && session="$sid"
      [ -z "$tool" ] && [ -n "$tname" ] && tool="$tname"
      [ -z "$message" ] && [ -n "$msg" ] && message="$msg"
      [ -z "$file" ] && [ -n "$hfile" ] && file="$hfile"
    fi
  fi
  [ -z "$session" ] && session="$RANDOM$RANDOM"

  local body
  if command -v jq >/dev/null 2>&1; then
    body="$(jq -cn \
      --arg agent "$agent" --arg sessionId "$session" --arg event "$type" --arg timestamp "$timestamp" \
      --arg tool "$tool" --arg file "$file" --arg command "$command" --arg message "$message" \
      --arg sourceApplication "$source_app" --arg sourceBundleIdentifier "$source_bundle_id" \
      --argjson pid "$hook_pid" --argjson parentPid "$hook_parent_pid" \
      '{agent:$agent,sessionId:$sessionId,event:$event,timestamp:$timestamp,tool:$tool,file:$file,command:$command,message:$message,sourceApplication:$sourceApplication,sourceBundleIdentifier:$sourceBundleIdentifier,pid:$pid,parentPid:$parentPid} | with_entries(select(.value != ""))')"
  else
    body="{\"agent\":\"$agent\",\"sessionId\":\"$session\",\"event\":\"$type\",\"timestamp\":\"$timestamp\",\"pid\":$hook_pid,\"parentPid\":$hook_parent_pid"
    [ -n "$tool" ]     && body="$body,\"tool\":\"$tool\""
    [ -n "$file" ]     && body="$body,\"file\":\"$file\""
    [ -n "$command" ]  && body="$body,\"command\":\"$command\""
    [ -n "$message" ]  && body="$body,\"message\":\"$message\""
    [ -n "$source_app" ] && body="$body,\"sourceApplication\":\"$source_app\""
    [ -n "$source_bundle_id" ] && body="$body,\"sourceBundleIdentifier\":\"$source_bundle_id\""
    body="$body}"
  fi

  local code
  code="$(curl -s -o /dev/null -w "%{http_code}" \
      -X POST "http://127.0.0.1:$port/api/agent/event" \
      -H "Content-Type: application/json" \
      -d "$body")"
  if [ "$code" = "200" ]; then
    # Codex treats stdout as the hook response. Keep successful hooks silent;
    # plain text would be parsed as invalid JSON by Stop and other lifecycle hooks.
    if debug_enabled; then
      printf 'ok [%s] session=%s type=%s\n' "$code" "$session" "$type" >&2
    fi
    return 0
  else
    if debug_enabled; then
      echo "fail[$code]: $body" >&2
      return 1
    fi
    # Event delivery is best-effort in packaged builds. A stopped PocketNotch app must
    # never surface as a failed hook or interrupt the user's CLI session.
    return 0
  fi
}

health() {
  echo "-> GET http://127.0.0.1:$DEFAULT_PORT/"
  curl -s "http://127.0.0.1:$DEFAULT_PORT/" && echo
}

self_test() {
  echo "== 自检：需要 PocketNotch App 正在运行（监听 $DEFAULT_PORT）=="
  health
  echo
  echo "== 上报 4 条事件（session=self-test）=="
  post_event claude-code agent_start --session self-test
  post_event claude-code thinking    --session self-test --message "planning next step"
  post_event claude-code tool_start  --session self-test --tool Edit --file src/App.py
  post_event claude-code completed   --session self-test --message "done"
  echo
  echo "== 查看文件 =="
  echo "    ~/Library/Application Support/PocketNotch/agent-events.jsonl"
}

samples() {
  local bin="$SCRIPT_DIR/agent-events.sh" port="$DEFAULT_PORT"

  echo "############################################################"
  echo "# Claude Code          ~/.claude/settings.json"
  echo "############################################################"
  cat <<EOF
{
  "hooks": {
    "SessionStart": [
      { "type": "command", "command": "$bin emit claude-code session_start --session \$CLAUDE_SESSION_ID" }
    ],
    "PreToolUse": [
      { "type": "command", "command": "$bin emit claude-code tool_start --session \$CLAUDE_SESSION_ID --tool \"\$(echo \"\$CLAUDE_TOOL_NAME\" | jq -r .)\"" }
    ],
    "PostToolUse": [
      { "type": "command", "command": "$bin emit claude-code tool_end --session \$CLAUDE_SESSION_ID --tool \"\$(echo \"\$CLAUDE_TOOL_NAME\" | jq -r .)\"" }
    ],
    "PreCompact": [
      { "type": "command", "command": "$bin emit claude-code thinking --session \$CLAUDE_SESSION_ID" }
    ],
    "Stop": [
      { "type": "command", "command": "$bin emit claude-code completed --session \$CLAUDE_SESSION_ID" }
    ]
  }
}
EOF

  echo
  echo "############################################################"
  echo "# Codex CLI            ~/.codex/config.toml (# 注：事件名随版本   #)"
  echo "############################################################"
  cat <<EOF
[hooks]

# event 名（SessionStart / BeforeEdit / AfterEdit / WaitForApproval）
# 若你的 Codex 版本事件名不同，以 \`codex hooks list\` 或官方文档为准。
session_start = [
  { cmd = "$bin emit codex session_start --session \$session", matcher = "*", timeout = 5 },
]
before_edit = [
  { cmd = "$bin emit codex tool_start --session \$session --tool Edit", matcher = "Edit", timeout = 5 },
]
after_edit = [
  { cmd = "$bin emit codex tool_end --session \$session --tool Edit", matcher = "Edit", timeout = 5 },
]
wait_for_approval = [
  { cmd = "$bin emit codex waiting_approval --session \$session", matcher = "*", timeout = 5 },
]
EOF

  echo
  echo "############################################################"
  echo "# Gemini CLI           ~/.gemini/settings.json             #"
  echo "############################################################"
  cat <<EOF
{
  "hooks": {
"BeforeEdit": [
      { "cmd": "$bin emit gemini tool_start --file \"\$GEMINI_FILE\"", "matcher": "*" }
    ],
    "BeforeThink": [
      { "cmd": "$bin emit gemini thinking" }
    ],
    "AfterTool": [
      { "cmd": "$bin emit gemini tool_end --tool Edit" }
    ]
  }
}
EOF
}

main() {
  local cmd
  cmd="${1:-}"; [ -n "$cmd" ] || { usage_short; exit 1; }
  shift
  case "$cmd" in
    version)   echo "$POCKETNOTCH_AGENT_SCRIPT_VERSION" ;;
    health)    health ;;
    emit)      [ "$#" -ge 2 ] || die "emit 需要 agent 与 type"
               local agent="$1" type; shift
               type="$(normalize_type "$1")"; shift
               [ "$type" != "unknown" ] || die "未知事件类型: $1"
               post_event "$agent" "$type" "$@"
               ;;
    self-test) self_test ;;
    samples)   samples ;;
    *)         usage_short ;;
  esac
}

main "$@"
