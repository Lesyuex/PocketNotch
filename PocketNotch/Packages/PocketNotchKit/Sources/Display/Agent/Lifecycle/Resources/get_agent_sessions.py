#!/usr/bin/env python3
import subprocess
import json
import os

# 市面主流 AI agent 产品（按可执行文件名 / 脚本名整词匹配，不做子串匹配）
# 与 AgentMetaRegistry 对齐：只含 PocketNotch 实际支持监听的 agent。
AGENT_PRODUCTS = [
    'codex',       # OpenAI Codex CLI
    'claude',      # Claude Code CLI
    'gemini',      # Gemini CLI
    'grok',        # Grok CLI
    'opencode',    # OpenCode
    'hermes',      # Hermes
    'pi',          # PI
]
AGENT_PRODUCTS_SET = set(AGENT_PRODUCTS)

# 解释器进程：需检查 args 里的脚本名（如 python3 -m pi、node claude.js）
INTERPRETERS = {'python', 'python3', 'node', 'nodejs', 'ruby', 'bash', 'sh', 'zsh'}


def _exec_name(path):
    """取路径 basename 去扩展名并小写，用于整词匹配。"""
    base = os.path.basename(path).lower()
    return os.path.splitext(base)[0]


def get_processes():
    result = subprocess.run(
        ['ps', '-eo', 'pid,ppid,comm,args'],
        capture_output=True, text=True
    )
    lines = result.stdout.strip().split('\n')[1:]
    processes = []
    for line in lines:
        parts = line.split(None, 3)
        if len(parts) < 3:
            continue
        pid = int(parts[0])
        ppid = int(parts[1])
        comm = parts[2]
        args = parts[3] if len(parts) > 3 else comm
        processes.append({
            'pid': pid,
            'ppid': ppid,
            'comm': comm,
            'args': args
        })
    return processes


def match_agent(comm, args):
    """返回匹配的产品名，未匹配返回 None。
    整词匹配可执行文件名，避免 'pi' 命中 'pip3'、'python' 等子串误伤。"""
    comm_base = os.path.basename(comm).lower()
    comm_name = os.path.splitext(comm_base)[0]
    # 1. 可执行名整词匹配
    if comm_name in AGENT_PRODUCTS_SET:
        return comm_name
    # 2. 解释器进程：检查 args 各 token 的整词匹配（如 python3 -m pi、node /path/claude.js）
    if comm_base in INTERPRETERS:
        tokens = args.split()
        for tok in tokens[1:]:  # 跳过解释器本身
            tok_name = _exec_name(tok)
            if tok_name in AGENT_PRODUCTS_SET:
                return tok_name
    return None


def get_top_app_parent(pid, proc_map):
    current = proc_map.get(pid)
    if current is None:
        return None
    visited = set()
    while True:
        ppid = current['ppid']
        if ppid in visited:
            return current
        visited.add(ppid)
        if ppid == 0 or ppid == 1:
            return current
        parent = proc_map.get(ppid)
        if parent is None:
            return current
        if '.app' in parent['comm'] or '.app' in parent.get('args', ''):
            return parent
        current = parent


def find_agent_processes(processes):
    proc_map = {p['pid']: p for p in processes}
    own_pid = os.getpid()
    agents = []
    seen_pids = set()

    for proc in processes:
        if proc['pid'] in seen_pids:
            continue
        # 排除自身
        if proc['pid'] == own_pid:
            continue
        if 'get_agent_sessions' in proc.get('args', ''):
            continue

        matched = match_agent(proc.get('comm', ''), proc.get('args', ''))
        if matched:
            top_parent = get_top_app_parent(proc['pid'], proc_map)
            # parent_name 取 args 的可执行路径（含 .app/），而非 comm（basename），
            # 以便上层正确提取 .app 包路径与本地化显示名。
            parent_name = ''
            if top_parent:
                parent_args = top_parent.get('args', '')
                parent_name = parent_args.split()[0] if parent_args else top_parent.get('comm', '')
            agents.append({
                'agent_name': matched,
                'session_name': proc['args'][:120],
                'pid': proc['pid'],
                'parent_pid': top_parent['pid'] if top_parent else proc['ppid'],
                'parent_name': parent_name,
            })
            seen_pids.add(proc['pid'])

    return agents


processes = get_processes()
agents = find_agent_processes(processes)
print(json.dumps(agents, indent=2))