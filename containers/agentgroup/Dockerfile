# syntax=docker/dockerfile:1.7
# 启用 Docker BuildKit 1.7+ 语法特性（支持高级缓存挂载与 COPY 权限直接指定）

# ==========================================
# 阶段 1: Builder 阶段 (依赖下载与工具打包)
# ==========================================
FROM debian:bookworm-slim AS builder

# 挂载 APT 软件包缓存，避免多次镜像构建时重复从网络拉取 deb 包
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git tar

WORKDIR /build

# 1. 一键安装 opencode 与 multica（已完全剔除 cc-switch）
# 2. 从安装目录精准复制可执行文件至临时输出目录，避免垃圾文件污染镜像
RUN curl -fsSL https://opencode.ai/install | bash && \
    curl -fsSL https://raw.githubusercontent.com/multica-ai/multica/main/scripts/install.sh | bash && \
    mkdir -p /build/out_bin && \
    find /root /usr/local /tmp -maxdepth 4 -type f \( -name "opencode" -o -name "multica" \) -exec cp {} /build/out_bin/ \; && \
    chmod +x /build/out_bin/*

# ==========================================
# 阶段 2: 最终生产运行镜像
# ==========================================
FROM debian:bookworm-slim

# 安装运行期最小依赖：
# - ca-certificates: 提供 HTTPS 证书校验
# - libssl3 / procps: 守护进程及系统进程控制支持
# - jq: 用于入口脚本中安全、无损地解析与更新 JSON 配置文件
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates libssl3 procps curl git tar jq && \
    useradd -m -s /bin/bash agents

# 优先复制二进制文件（构建变动频率低，置于前端以最大化利用镜像层缓存）
COPY --from=builder /build/out_bin/* /usr/local/bin/

# 复制入口脚本并设置 755 可执行权限（变动频率相对较高，置于靠后层级）
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

# 遵循最小权限安全原则，使用非 root 用户 agents 运行容器
USER agents
WORKDIR /home/agents

ENTRYPOINT ["entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"]