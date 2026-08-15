#!/bin/bash
# 严格执行模式：遇到非零状态码、未定义变量或管道失败时立即终止
set -eo pipefail

# 若设置了代理环境变量，让 Node 22+ 自动遵守 HTTP(S)_PROXY
if [ -n "${HTTP_PROXY:-}" ] || [ -n "${HTTPS_PROXY:-}" ]; then
    export NODE_USE_ENV_PROXY=1
fi

# --------------------------------------------------
# 0. dsh 基础环境初始化
# --------------------------------------------------
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
mkdir -p "$DSH_HOME"

WORKSPACE="${DSH_WORKSPACE:-$HOME/workspace}"
mkdir -p "$WORKSPACE"
cd "$WORKSPACE"

echo "[dsh] DSH_HOME=$DSH_HOME"
echo "[dsh] Workspace=$WORKSPACE"

# --------------------------------------------------
# 1. LLM Provider 配置注入
# --------------------------------------------------
# DeepSeek 原生接入：dsh 基础层自带 DeepSeek 适配器，直接从环境变量读取
# DEEPSEEK_API_KEY，无需额外配置文件。
if [ -n "$DEEPSEEK_API_KEY" ]; then
    echo "[dsh] DeepSeek native provider detected via DEEPSEEK_API_KEY (no config file needed)."
fi

# 自定义 OpenAI 兼容 provider：生成 $DSH_HOME/settings.yaml
# 仅当设置了相关环境变量时才生成/覆盖，避免清空用户在 Web UI 中配置的 provider。
DSH_PROVIDER_ID="${DSH_PROVIDER_ID:-custom-provider}"
DSH_MODELS="${DSH_MODEL:-}"
# 凭证引用：优先 DSH_API_TOKEN，兼容 OPENAI_API_KEY 别名
if [ -n "$DSH_API_TOKEN" ]; then
    TOKEN_ENV_NAME="DSH_API_TOKEN"
elif [ -n "$OPENAI_API_KEY" ]; then
    TOKEN_ENV_NAME="OPENAI_API_KEY"
else
    TOKEN_ENV_NAME=""
fi

if [ -n "$DSH_BASE_URL" ] && [ -n "$DSH_MODELS" ] && [ -n "$TOKEN_ENV_NAME" ]; then
    SETTINGS_FILE="$DSH_HOME/settings.yaml"
    echo "[dsh] Injecting custom provider '$DSH_PROVIDER_ID' into $SETTINGS_FILE (models: $DSH_MODELS)..."

    # 转义 YAML 单引号
    yaml_quote() { printf '%s' "$1" | sed "s/'/''/g"; }

    # 默认模型：优先 DSH_MODEL_DEFAULT，未指定则取模型列表首个
    DEFAULT_MODEL="${DSH_MODEL_DEFAULT:-}"
    IFS=',' read -ra model_arr <<< "$DSH_MODELS"
    if [ -z "$DEFAULT_MODEL" ] && [ "${#model_arr[@]}" -gt 0 ]; then
        DEFAULT_MODEL="${model_arr[0]}"
    fi
    # 去除首尾空格
    DEFAULT_MODEL="${DEFAULT_MODEL#"${DEFAULT_MODEL%%[![:space:]]*}"}"
    DEFAULT_MODEL="${DEFAULT_MODEL%"${DEFAULT_MODEL##*[![:space:]]}"}"

    {
        echo "llm-pi-ai:"
        echo "  providers:"
        echo "    '$(yaml_quote "$DSH_PROVIDER_ID")':"
        echo "      apiKeyEnv: $TOKEN_ENV_NAME"
        echo "      api: openai-completions"
        echo "      baseURL: '$(yaml_quote "$DSH_BASE_URL")'"
        echo "      models:"
        for m in "${model_arr[@]}"; do
            m="${m#"${m%%[![:space:]]*}"}"
            m="${m%"${m##*[![:space:]]}"}"
            if [ -n "$m" ]; then
                echo "        - id: '$(yaml_quote "$m")'"
            fi
        done
        # 默认模型（含 headless 一次性模式），覆盖 base 层的 deepseek-official 默认值
        if [ -n "$DEFAULT_MODEL" ]; then
            echo "agent-default-model:"
            echo "  provider: '$(yaml_quote "$DSH_PROVIDER_ID")'"
            echo "  model: '$(yaml_quote "$DEFAULT_MODEL")'"
        fi
    } > "$SETTINGS_FILE"
elif [ -n "$DSH_BASE_URL" ] || [ -n "$DSH_MODELS" ] || [ -n "$DSH_API_TOKEN" ]; then
    echo "[dsh] Warning: custom provider injection skipped. "
    echo "[dsh]   DSH_BASE_URL / DSH_MODEL / token (DSH_API_TOKEN or OPENAI_API_KEY) must all be set." >&2
fi

# --------------------------------------------------
# 2. 生成 Web 绑定补丁（默认 0.0.0.0）
# --------------------------------------------------
# dsh web CLI 故意拒绝 --host 0.0.0.0（防远程 RCE），
# 这里通过 cordis.patch.yml 覆盖 webserver 行的 host 来绕过。
# 宿主可通过 DSH_BIND_HOST 改为 127.0.0.1 恢复安全默认。
BIND_HOST="${DSH_BIND_HOST:-0.0.0.0}"
BIND_PATCH="$DSH_HOME/cordis-bind.patch.yml"
cat > "$BIND_PATCH" <<EOF
- id: webserver
  config:
    host: $BIND_HOST
    port: !!js ctx.webStartup.port ?? 3080
EOF

# 构造 --trusted-host 参数（浏览器信任栅栏），逗号或空格分隔
TRUSTED_HOSTS_ARGS=()
if [ -n "${DSH_TRUSTED_HOSTS:-}" ]; then
    for h in $(echo "$DSH_TRUSTED_HOSTS" | tr ', ' ' '); do
        [ -n "$h" ] && TRUSTED_HOSTS_ARGS+=(--trusted-host "$h")
    done
fi

# --------------------------------------------------
# 3. 运行模式判断
# --------------------------------------------------
if [ "$1" = "web" ]; then
    shift
    echo "[dsh] Starting Web UI on ${BIND_HOST}:${DSH_PORT:-3080}..."
    exec dsh web \
        --patch "$BIND_PATCH" \
        --port "${DSH_PORT:-3080}" \
        "${TRUSTED_HOSTS_ARGS[@]}" \
        "$@"
elif [ "$1" = "--profile" ] && [ "$2" = "web" ]; then
    shift 2
    echo "[dsh] Starting Web UI on ${BIND_HOST}:${DSH_PORT:-3080}..."
    exec dsh --profile web \
        --patch "$BIND_PATCH" \
        --port "${DSH_PORT:-3080}" \
        "${TRUSTED_HOSTS_ARGS[@]}" \
        "$@"
elif [ "$1" = "tail" ] && [ "$2" = "-f" ]; then
    echo "[dsh] Container is ready and running in background..."
    while true; do
        sleep 1 &
        # 避免信号中断触发 set -e 导致容器异常退出
        wait $! || true
    done
else
    # 用户传入自定义命令时，替换进程以保持信号透传
    exec "$@"
fi
