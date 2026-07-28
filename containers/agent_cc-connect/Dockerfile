# syntax=docker/dockerfile:1.7
# 启用 Docker BuildKit 1.7+ 语法特性（支持高级缓存挂载与 COPY 权限直接指定）

# ==========================================
# 阶段 1: Builder 阶段 (工具下载与离线打包)
# ==========================================
FROM debian:bookworm-slim AS builder

ARG CC_VERSION=1.4.0
# 自动获取当前构建目标架构 (amd64 / arm64)
ARG TARGETARCH

# 挂载 APT 缓存，避免重复拉取 deb 包
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git tar

WORKDIR /build

# 一键下载并打包 opencode, multica 与 cc-connect
RUN mkdir -p /build/out_bin && \
    curl -fsSL https://opencode.ai/install | bash && \
    curl -fsSL https://raw.githubusercontent.com/multica-ai/multica/main/scripts/install.sh | bash && \
    ARCH="${TARGETARCH:-amd64}" && \
    echo "[Builder] 当前构建架构: ${ARCH}" && \
    curl -fsSL -o /build/out_bin/cc-connect https://github.com/chenhg5/cc-connect/releases/download/v${CC_VERSION}/cc-connect-v${CC_VERSION}-linux-${ARCH}.tar.gz && \
    # 校验文件是否为合法的 Linux ELF 可执行文件
    if ! head -c 4 /build/out_bin/cc-connect | grep -q $'^\x7fELF'; then \
        echo "[Error] 下载的 cc-connect 不是有效的二进制文件，请检查下载链接或架构！"; \
        cat /build/out_bin/cc-connect; exit 1; \
    fi && \
    find /root /usr/local /tmp -maxdepth 4 -type f \( -name "opencode" -o -name "multica" \) -exec cp {} /build/out_bin/ \; && \
    chmod +x /build/out_bin/*

# ==========================================
# 阶段 2: 最终生产运行镜像
# ==========================================
FROM debian:bookworm-slim

# 1. 安装运行期最小依赖并建立非 root 用户 agents
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates libssl3 procps curl git tar jq && \
    useradd -m -s /bin/bash agents

# 2. 复制二进制执行文件（低变动层置前，最大化利用镜像层缓存）
COPY --from=builder /build/out_bin/* /usr/local/bin/

# 3. 将配置模板备份至系统级只读目录（关键：隔离于 /home/agents 外，规避挂载覆盖问题）
RUN mkdir -p /etc/cc-connect
COPY --chmod=644 config.template.toml /etc/cc-connect/config.template.toml

# 4. 复制入口脚本并设置 755 执行权限
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

# 5. 遵循最小权限原则，切换至非 root 用户 agents
USER agents
WORKDIR /home/agents

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"]