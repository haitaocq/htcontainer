# syntax=docker/dockerfile:1.7

# ==========================================
# 基础镜像，用于开发测试
# ==========================================
FROM debian:bookworm-slim AS builder

# 1. 移除 Debian 默认的清理机制，保证 BuildKit apt 缓存真正生效
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    tar \


# 前台常驻阻塞
CMD ["tail", "-f", "/dev/null"]