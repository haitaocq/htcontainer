# syntax=docker/dockerfile:1.7
# 启用 Docker BuildKit 1.7+ 语法特性（支持高级缓存挂载与 COPY 权限直接指定）

# ==========================================
# 阶段 1: Builder 阶段（安装 dsh 并编译原生依赖）
# ==========================================
# 使用完整版 node 镜像：自带 python3 / make / g++，
# 用于编译 node-pty 等缺少 linux 预编译产物的原生模块
FROM node:24-bookworm AS builder

# dsh 版本（当前为 developer preview，必须 pin 固定版本）
ARG DSH_VERSION=0.1.0-rc.6

# 全局安装 @deepseek-ai/dsh
# 安装完成后清理 node-pty 自带的其他平台预编译包（darwin/win32），缩减镜像体积
RUN npm install -g --no-audit --no-fund @deepseek-ai/dsh@${DSH_VERSION} && \
    rm -rf /usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/node-pty/prebuilds

# ==========================================
# 阶段 2: 最终生产运行镜像
# ==========================================
FROM node:24-bookworm-slim

# 安装运行期最小依赖并建立非 root 用户 agents（固定 uid/gid 10001，
# 便于宿主目录 bind 挂载或具名卷的属主管理）
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git procps && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd -g 10001 agents && \
    useradd -u 10001 -g agents -m -s /bin/bash agents

# 复制已安装的 dsh 及其全部依赖（含编译好的 node-pty 二进制）
COPY --from=builder /usr/local/lib/node_modules/@deepseek-ai/dsh /usr/local/lib/node_modules/@deepseek-ai/dsh

# 建立 dsh 可执行入口软链接，并预创建数据/工作目录（关键）：
# 具名卷首次挂载会继承镜像中对应目录的属主，避免运行时目录为 root 属主导致写入失败
RUN ln -sf /usr/local/lib/node_modules/@deepseek-ai/dsh/lib/bin.js /usr/local/bin/dsh && \
    mkdir -p /home/agents/.dsh /home/agents/workspace && \
    chown -R 10001:10001 /home/agents

# 复制入口脚本并设置 755 可执行权限
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

# 遵循最小权限安全原则，使用非 root 用户 agents 运行容器
USER agents
WORKDIR /home/agents/workspace

# dsh 数据目录（可挂载卷持久化）
ENV DSH_HOME=/home/agents/.dsh
# 默认绑定 0.0.0.0（通过 cordis.patch.yml 覆盖 webserver 行，绕过 CLI 对 0.0.0.0 的限制）
ENV DSH_BIND_HOST=0.0.0.0
ENV DSH_PORT=3080
# 容器内默认使用 code 模式沙箱（纯 JS worker-thread，规避 Landlock 在 seccomp 下的限制）
ENV DSH_TOOLS_MODE=code

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["web"]
