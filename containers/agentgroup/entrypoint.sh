#!/bin/bash
set -e

TOKEN="${MUL_TOKEN:-$MULTICA_TOKEN}"
CONFIG_FILE="${HOME}/.multica/config.json"

check_auth_status() {
    if [ ! -f "$CONFIG_FILE" ]; then
        return 1
    fi
    local local_token=""
    local_token=$(grep -i '"token"' "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f4 || true)

    if [ -z "$local_token" ]; then
        return 1
    fi

    if multica auth status >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# ----------------- 鉴权与配置 -----------------
echo "Checking multica authentication status..."

if check_auth_status; then
    echo "Already logged in and authenticated with multica."
else
    echo "Not authenticated. Starting configuration and login..."

    if [ -n "$MULTICA_SERVER_URL" ]; then
        multica config set server_url "$MULTICA_SERVER_URL"
    fi

    if [ -n "$MULTICA_APP_URL" ]; then
        multica config set app_url "$MULTICA_APP_URL"
    fi

    if [ -n "$TOKEN" ]; then
        multica login --token "$TOKEN"
    else
        echo "Error: Not authenticated — provide a token in MUL_TOKEN / MULTICA_TOKEN." >&2
        exit 1
    fi
fi

# ----------------- 启动守护进程 -----------------
echo "Starting multica daemon..."
multica daemon start || echo "Failed to start multica daemon, continuing..."

# ----------------- 信号捕获与优雅退出 -----------------
# 定义清理函数
cleanup() {
    echo "Received shutdown signal, stopping multica daemon..."
    multica daemon stop 2>/dev/null || true
    exit 0
}

# 捕获 SIGTERM 和 SIGINT 信号并执行 cleanup
trap 'cleanup' SIGTERM SIGINT

# 如果传入的是阻塞指令（如 tail -f /dev/null），改用 wait 循环挂起，使 trap 能够实时响应
if [ "$1" = "tail" ] && [ "$2" = "-f" ]; then
    echo "Container ready and running in background..."
    while true; do
        sleep 1 &
        wait $!
    done
else
    # 如果用户自定义传入了其他前台命令，则正常替换进程
    exec "$@"
fi
