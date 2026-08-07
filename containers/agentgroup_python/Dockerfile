# syntax=docker/dockerfile:1.7

# ==========================================
# 阶段 1: Builder 阶段 (保持不变)
# ==========================================
FROM debian:bookworm-slim AS builder

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git tar

WORKDIR /build

RUN curl -fsSL https://opencode.ai/install | bash && \
    curl -fsSL https://raw.githubusercontent.com/multica-ai/multica/main/scripts/install.sh | bash && \
    mkdir -p /build/out_bin && \
    find /root /usr/local /tmp -maxdepth 4 -type f \( -name "opencode" -o -name "multica" \) -exec cp {} /build/out_bin/ \; && \
    chmod +x /build/out_bin/*

# ==========================================
# 阶段 2: 最终运行镜像 (使用官方 Python 镜像)
# ==========================================
# 🎯 关键优化：直接使用官方 Python slim 镜像
FROM python:3.11-slim-bookworm

# 安装运行期最小依赖 (Python 已预装，无需再装)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl3 \
    procps \
    curl \
    git \
    tar \
    jq \
    && rm -rf /var/lib/apt/lists/*

# 设置 Python 环境变量 (最佳实践)
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# 创建非 root 用户
RUN useradd -m -s /bin/bash agents

# 复制二进制文件
COPY --from=builder /build/out_bin/* /usr/local/bin/

# 复制入口脚本
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

# 切换用户
USER agents
WORKDIR /home/agents

ENTRYPOINT ["entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"]