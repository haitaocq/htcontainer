#!/bin/bash
# 严格执行模式：遇到非零状态码、未定义变量或管道失败时立即终止
set -eo pipefail

TOKEN="${MUL_TOKEN:-$MULTICA_TOKEN}"
MULTICA_CONFIG_FILE="${HOME}/.multica/config.json"

# --------------------------------------------------
# 1. OpenCode 第三方 LLM 配置注入（支持多模型逗号分隔）
# --------------------------------------------------
OPENCODE_CONFIG_DIR="${HOME}/.config/opencode"
OPENCODE_CONFIG_FILE="${OPENCODE_CONFIG_DIR}/opencode.json"

mkdir -p "$OPENCODE_CONFIG_DIR"

# 获取环境变量参数（提供合理缺省值）
PROVIDER_ID="${OPENCODE_PROVIDER:-custom-provider}"
MODELS_IDS="${OPENCODE_MODEL:-default-model}"
API_KEY="${OPENCODE_API_TOKEN:-$OPENAI_API_KEY}"
BASE_URL="${OPENCODE_BASE_URL:-$OPENAI_BASE_URL}"
MODEL_DEFAULT="${OPENCODE_MODEL_DEFAULT:-}"

# 仅当设置了 LLM 相关的环境变量时动态生成/更新配置
if [ -n "$OPENCODE_MODEL" ] || [ -n "$OPENCODE_BASE_URL" ] || [ -n "$OPENCODE_API_TOKEN" ]; then
    echo "[OpenCode] Injecting third-party LLM config (Provider: $PROVIDER_ID, Models: $MODELS_IDS)..."

    # 使用 jq 构建符合 OpenCode 官方 Schema 的 JSON 配置文件
    jq -n \
      --arg schema "https://opencode.ai/config.json" \
      --arg provider_id "$PROVIDER_ID" \
      --arg models_ids "$MODELS_IDS" \
      --arg api_key "${API_KEY:-}" \
      --arg base_url "${BASE_URL:-}" \
      --arg model_default "${MODEL_DEFAULT:-}" \
      '
      # 1. 拆分逗号分隔的模型列表，并清空首尾多余空格
      ($models_ids | split(",") | map(gsub("^\\s+|\\s+$"; ""))) as $model_list
      # 2. 将列表中的首个模型设置为主默认模型
      # | $model_list[0] as $model_default
      # 3. 构造模型映射字典 { "model_a": { "name": "model_a" }, ... }
      | ($model_list | map({ key: ., value: { name: . } }) | from_entries) as $models_map
      | {
        "$schema": $schema,
        "provider": {
          ($provider_id): {
            "npm": "@ai-sdk/openai-compatible",
            "name": $provider_id,
            "options": (
              (if $base_url != "" then {"baseURL": $base_url} else {} end) +
              (if $api_key != "" then {"apiKey": $api_key} else {} end)
            ),
            "models": $models_map
          }
        }
      }
      # 4. 判断 model_default 是否为空，不为空则拼接 model 字段，为空则拼接空对象（即不生成该字段）
      + (if $model_default != "" then { "model": "\($provider_id)/\($model_default)" } else {} end)
      ' > "$OPENCODE_CONFIG_FILE"
fi

# --------------------------------------------------
# 2. Multica 鉴权与配置初始化
# --------------------------------------------------
check_auth_status() {
    if [ ! -f "$MULTICA_CONFIG_FILE" ]; then
        return 1
    fi
    local local_token=""
    local_token=$(grep -i '"token"' "$MULTICA_CONFIG_FILE" 2>/dev/null | cut -d'"' -f4 || true)

    if [ -z "$local_token" ]; then
        return 1
    fi

    if multica auth status >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

echo "[Multica] Checking authentication status..."

if check_auth_status; then
    echo "[Multica] Already authenticated."
else
    echo "[Multica] Not authenticated. Starting configuration and login..."

    if [ -n "$MULTICA_SERVER_URL" ]; then
        multica config set server_url "$MULTICA_SERVER_URL"
    fi

    if [ -n "$MULTICA_APP_URL" ]; then
        multica config set app_url "$MULTICA_APP_URL"
    fi

    if [ -n "$TOKEN" ]; then
        multica login --token "$TOKEN"
    else
        echo "[Error] Authentication failed — MUL_TOKEN / MULTICA_TOKEN is required." >&2
        exit 1
    fi
fi

# --------------------------------------------------
# 3. 启动Multica守护进程
# --------------------------------------------------
# 新增：后台重试启动函数
retry_start_daemon() {
    local max_retries=30      # 最大重试次数
    local retry_interval=5    # 重试间隔(秒)
    local count=0
 
    while [ $count -lt $max_retries ]; do
        count=$((count + 1))
        echo "[Multica Daemon Retry] Attempt $count/$max_retries. Waiting ${retry_interval}s for server to be ready..."
        sleep $retry_interval
        
        if multica daemon start; then
            echo "[Multica Daemon Retry] Daemon started successfully on attempt $count."
            return 0
        fi 
    done
 
    echo "[Error] Multica daemon failed to start after $max_retries retries." >&2
    return 1
}
 
echo "[Multica] Starting background daemon..."
if multica daemon start; then
    echo "[Multica] Daemon started successfully."
else
    echo "[Warning] Daemon failed to start initially. Spawning background retry process..."
    # 将重试逻辑放入后台执行，不阻塞主进程
    retry_start_daemon &
fi 

# --------------------------------------------------
# 4. 信号捕获与优雅退出处理 (Graceful Shutdown)
# --------------------------------------------------
cleanup() {
    echo "[System] Received termination signal, stopping multica daemon..."
    multica daemon stop 2>/dev/null || true
    exit 0
}

# 注册操作系统级 SIGTERM / SIGINT 信号拦截
trap 'cleanup' SIGTERM SIGINT

# 运行模式判断
if [ "$1" = "tail" ] && [ "$2" = "-f" ]; then
    echo "[System] Container is ready and running in background..."
    while true; do
        sleep 1 &
        # 使用 wait $! || true 避免信号中断触发 set -e 导致容器异常退出
        wait $! || true
    done
else
    # 用户传入自定义前台命令时，替换进程以保持信号透传
    exec "$@"
fi

