# syntax=docker/dockerfile:1.7

# ==========================================
# 阶段 1: 依赖下载与工具安装阶段 (Builder)1
# ==========================================
FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    tar \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# 1. 安装 OpenCode
RUN curl -fsSL https://opencode.ai/install | bash

# 2. 安装 multica
RUN curl -fsSL https://raw.githubusercontent.com/multica-ai/multica/main/scripts/install.sh | bash

# 3. 安装 cc-switch-cli
RUN curl -fsSL https://github.com/SaladDay/cc-switch-cli/releases/latest/download/install.sh | bash

# 4. 自动捕获各脚本安装生成的二进制文件并汇总
RUN mkdir -p /build/out_bin && \
    find / -type f \( -name "opencode" -o -name "multica" -o -name "cc-switch*" \) -exec cp {} /build/out_bin/ \; && \
    chmod +x /build/out_bin/*


# ==========================================
# 阶段 2: 最终运行镜像 (Final Stage)
# ==========================================
FROM debian:bookworm-slim

# 仅保留必需的运行时库和常用命令行工具
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl3 \
    procps \
    curl \
    git \
    tar \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /var/cache/apt/* /var/log/* /tmp/* /var/tmp/*

# 创建非 root 开发者用户 agents
RUN useradd -m -s /bin/bash agents

# 从 Builder 阶段拷贝可执行程序
COPY --from=builder /build/out_bin/* /usr/local/bin/

# 复制并配置入口脚本
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER agents
WORKDIR /home/agents

ENTRYPOINT ["entrypoint.sh"]

# 前台常驻阻塞，避免容器在 Compose 启动时直接退出
CMD ["tail", "-f", "/dev/null"]
