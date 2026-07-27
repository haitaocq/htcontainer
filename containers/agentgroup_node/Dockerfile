# syntax=docker/dockerfile:1.7

# ==========================================
# 阶段 1: 依赖与 Node.js / CLI 构筑阶段 (Builder)
# ==========================================
FROM debian:bookworm-slim AS builder

ARG NODE_VERSION=24.18.0
# 自动接收 BuildKit 传入的目标 CPU 架构 (如 amd64, arm64)
ARG TARGETARCH

# 1. 移除 Debian 默认的清理机制，保证 BuildKit apt 缓存真正生效
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    tar \
    xz-utils

WORKDIR /build

# 2. 动态适配架构下载 Node.js（支持 x86_64 与 ARM64/Apple Silicon）
RUN set -eux; \
    case "${TARGETARCH}" in \
        "amd64") ARCH="x64" ;; \
        "arm64") ARCH="arm64" ;; \
        *) ARCH="x64" ;; \
    esac; \
    curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${ARCH}.tar.xz" | \
    tar -xJ -C /build --strip-components=1 && \
    rm -rf /build/include /build/share /build/bin/corepack

# 3. 安装第三方 CLI 工具
RUN curl -fsSL https://opencode.ai/install | bash && \
    curl -fsSL https://raw.githubusercontent.com/multica-ai/multica/main/scripts/install.sh | bash

# 4. 统一归集构建产物至 /build/dist，为最终阶段的单层 COPY 准备
RUN set -eux; \
    mkdir -p /build/dist/usr/local/bin /build/dist/usr/local/lib && \
    cp -r /build/bin/* /build/dist/usr/local/bin/ && \
    cp -r /build/lib/* /build/dist/usr/local/lib/ && \
    find /root /usr/local/bin -type f \( -name "opencode" -o -name "multica" \) \
    -exec cp -t /build/dist/usr/local/bin/ {} + && \
    chmod +x /build/dist/usr/local/bin/*


# ==========================================
# 阶段 2: 最终运行镜像 (Final Stage)
# ==========================================
FROM debian:bookworm-slim

# 1. 配置 Apt 缓存并显式指定系统用户 UID/GID (10001)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates libssl3 procps curl git tar jq && \
    groupadd -g 10001 agents && \
    useradd -u 10001 -g agents -m -s /bin/bash agents

# 2. 导出所有产物（仅产生 1 个 COPY 镜像层）
COPY --from=builder /build/dist/ /

# 3. 复制入口脚本并设置执行权限
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

# 4. 切换为非 root 用户运行
USER agents
WORKDIR /home/agents

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# 5. 前台常驻阻塞
CMD ["tail", "-f", "/dev/null"]