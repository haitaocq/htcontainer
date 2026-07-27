# syntax=docker/dockerfile:1.7

# ==========================================
# 阶段 1: 依赖与 Node.js 二进制下载阶段 (Builder)
# ==========================================
FROM debian:bookworm-slim AS builder

ARG NODE_VERSION=24.18.0

# 1. 安装基础工具（使用 BuildKit 缓存挂载）
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    tar \
    xz-utils

WORKDIR /build

# 2. 下载并按需解压官方 Node.js 运行时（去除头文件与不常用工具）
RUN curl -fsSL https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz | \
    tar -xJ -C /build --strip-components=1 && \
    rm -rf /build/include /build/share /build/bin/corepack

# 3. 安装第三方 CLI 工具
RUN curl -fsSL https://opencode.ai/install | bash && \
    curl -fsSL https://raw.githubusercontent.com/multica-ai/multica/main/scripts/install.sh | bash

# 4. 方案一：定向搜寻 /root 与 /usr/local/bin，并使用 cp -t ... {} + 批量汇总
RUN mkdir -p /build/out_bin && \
    find /root /usr/local/bin -type f \( -name "opencode" -o -name "multica" \) \
    -exec cp -t /build/out_bin/ {} + && \
    chmod +x /build/out_bin/*


# ==========================================
# 阶段 2: 最终运行镜像 (Final Stage)
# ==========================================
FROM debian:bookworm-slim

# 安装运行期系统依赖
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates libssl3 procps curl git tar jq && \
    useradd -m -s /bin/bash agents

# 从 Builder 复制最小化的 Node.js 运行环境
COPY --from=builder /build/bin /usr/local/bin
COPY --from=builder /build/lib /usr/local/lib

# 从 Builder 复制汇总好的 CLI 工具
COPY --from=builder /build/out_bin/* /usr/local/bin/

# 复制入口脚本并设置 755 可执行权限（变动频率相对较高，置于靠后层级）
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

USER agents
WORKDIR /home/agents

ENTRYPOINT ["entrypoint.sh"]

# 前台常驻阻塞，避免容器退出
CMD ["tail", "-f", "/dev/null"]