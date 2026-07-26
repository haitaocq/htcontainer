# syntax=docker/dockerfile:1.7

# ==========================================
# 阶段 1: Builder 阶段
# ==========================================
FROM debian:bookworm-slim AS builder

# 1. 使用 BuildKit 挂载 APT 缓存，避免重复下载
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git tar

WORKDIR /build

# 2. 精准限制 find 查找范围，避免扫描整盘拖慢构建
RUN curl -fsSL https://opencode.ai/install | bash && \
    curl -fsSL https://raw.githubusercontent.com/multica-ai/multica/main/scripts/install.sh | bash && \
    curl -fsSL https://github.com/SaladDay/cc-switch-cli/releases/latest/download/install.sh | bash && \
    mkdir -p /build/out_bin && \
    find /root /usr/local /tmp -maxdepth 4 -type f \( -name "opencode" -o -name "multica" -o -name "cc-switch*" \) -exec cp {} /build/out_bin/ \; && \
    chmod +x /build/out_bin/*

# ==========================================
# 阶段 2: 最终运行镜像
# ==========================================
FROM debian:bookworm-slim

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates libssl3 procps curl git tar && \
    useradd -m -s /bin/bash agents

# 3. 优先拷贝不常变动的二进制文件
COPY --from=builder /build/out_bin/* /usr/local/bin/

# 4. 直接设置权限，将频繁修改的入口脚本放在靠后层
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

USER agents
WORKDIR /home/agents

ENTRYPOINT ["entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"]