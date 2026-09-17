# syntax=docker/dockerfile:1.7
# 启用 Docker BuildKit 1.7+ 语法特性（支持高级缓存挂载与 COPY 权限直接指定）

# ==========================================
# 阶段 1: Builder 阶段（安装 dsh 并编译原生依赖）
# ==========================================
# 使用完整版 node 镜像：自带 python3 / make / g++，
# 用于编译 node-pty 等缺少 linux 预编译产物的原生模块
FROM node:24-bookworm AS builder

# dsh 版本（当前为 developer preview，必须 pin 固定版本）
ARG DSH_VERSION=0.1.5-rc.1

# 全局安装 @deepseek-ai/dsh
# 安装完成后清理 node-pty 自带的其他平台预编译包（darwin/win32），缩减镜像体积。
# 注意：只能删除 darwin/win32 等非 Linux 预编译包，绝不能删除整个 prebuilds 目录，
# 否则 node-pty 缺少 prebuilds/linux-*/pty.node 原生模块，dsh 启动会直接报错
# （node-pty 的 install 脚本只检查 shipped prebuild，存在则不会重新编译）。
# 保留全部 linux-* 预编译包，兼顾 amd64 / arm64 多平台构建。
RUN npm install -g --no-audit --no-fund @deepseek-ai/dsh@${DSH_VERSION} && \
    find /usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/node-pty/prebuilds \
        -mindepth 1 -maxdepth 1 -type d ! -name 'linux-*' -exec rm -rf {} + && \
    curl -fsSL https://raw.githubusercontent.com/multica-ai/multica/main/scripts/install.sh | bash && \
    corepack enable && corepack prepare pnpm@12.4.2 --activate && \
    git clone --depth 1 https://github.com/multica-ai/dsh-multica-runtime.git /build/dsh-multica-runtime && \
    cd /build/dsh-multica-runtime && \
    git checkout e29aae228449dfe50e88af60ef4281e38ca44e2a && \
    pnpm install --frozen-lockfile && \
    pnpm build && \
    pnpm pack --pack-destination /build/

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

# 复制 multica 客户端（构建阶段下载的静态二进制）
COPY --from=builder /usr/local/bin/multica /usr/local/bin/multica

# 修复 dsh ≥0.1.5 远程浏览器设置/模型页不可用问题（客户端 loopback 判定补丁）：
# 0.1.5 起 settings.describe 等配置类 RPC 改为仅当浏览器自身地址为 loopback 时才可用，
# Caddy 改写 Host/Origin 已无法影响该客户端判定，远程浏览器报
# "settings are unavailable in this browser"。此处对下发到浏览器的 client bundle
# 强制 isLoopback=true，恢复远程设置能力（仍受浏览器令牌认证保护）
COPY patch-settings-loopback.mjs /tmp/patch-settings-loopback.mjs
RUN DSH_CONNECTION_CLIENT="/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-client-connection/lib/client.js" \
    node /tmp/patch-settings-loopback.mjs && \
    rm -f /tmp/patch-settings-loopback.mjs

# 内置 Caddy 作为 Web 前置反向代理（静态 Go 二进制，从官方镜像复制，随平台架构自动匹配；
# 版本锁定保证可复现构建）
COPY --from=caddy:2.11.4-alpine /usr/bin/caddy /usr/local/bin/caddy

# 注入 crypto.randomUUID polyfill（构建期）：修复非安全上下文（HTTP / 非 localhost）
# 访问 Web UI 时浏览器报 "crypto.randomUUID is not a function" 的问题
COPY patch-frontend.mjs /tmp/patch-frontend.mjs
RUN DSH_FRONTEND_INDEX="/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-web-frontend/dist/index.html" \
    node /tmp/patch-frontend.mjs && \
    rm -f /tmp/patch-frontend.mjs

# 建立 dsh 可执行入口软链接，并预创建数据/工作目录（关键）：
# 具名卷首次挂载会继承镜像中对应目录的属主，避免运行时目录为 root 属主导致写入失败
RUN ln -sf /usr/local/lib/node_modules/@deepseek-ai/dsh/lib/bin.js /usr/local/bin/dsh && \
    mkdir -p /home/agents/.dsh /home/agents/workspace && \
    chown -R 10001:10001 /home/agents

# 安装 multica 的 DSH runtime profile（dsh-multica-runtime 私有桥接包）：
# multica daemon 仅在 `dsh --profile multica --probe` 返回协议版本 1 时才注册
# DeepSeek Harness runtime；否则报 "DSH Multica runtime profile is not installed"
# 并因无法注册任何 runtime 而整体退出。
# 关键点：profile 先装入 $DSH_HOME（= /home/agents/.dsh/profiles/multica），再复制一份
# 到镜像内独立路径 /usr/local/share/dsh/multica-profile 作"出厂备份"。由于 /home/agents/.dsh
# 通常被具名卷挂载，若卷已是旧版本创建的，构建期写入 $DSH_HOME 的 profile 不会出现在卷内；
# 故 entrypoint 在启动 multica daemon 前会检测 profile 是否存在，缺失时从备份路径复制补齐，
# 从而兼容旧具名卷场景。
COPY --from=builder /build/multica-ai-dsh-runtime-0.1.0-private.1.tgz /tmp/multica-dsh-runtime.tgz
RUN corepack enable && corepack prepare pnpm@12.4.2 --activate && \
    DSH_HOME=/home/agents/.dsh dsh plugin --profile multica add /tmp/multica-dsh-runtime.tgz && \
    rm -f /tmp/multica-dsh-runtime.tgz && \
    mkdir -p /usr/local/share/dsh && \
    cp -a /home/agents/.dsh/profiles/multica /usr/local/share/dsh/multica-profile && \
    chown -R 10001:10001 /home/agents/.dsh /usr/local/share/dsh

# 复制入口脚本并设置 755 可执行权限
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

# 遵循最小权限安全原则，使用非 root 用户 agents 运行容器
USER agents
WORKDIR /home/agents/workspace

# dsh 数据目录（可挂载卷持久化）
ENV DSH_HOME=/home/agents/.dsh
# 内嵌 Caddy 前置反向代理（默认开启）：dsh 内部绑定 loopback，Caddy 对外监听
# DSH_PORT 并把 Host/Origin 改写为 localhost，从而放行 /api 中 loopback-only 的
# 特权 RPC（settings.describe / credentials.* / llm.discoverModels 等）
ENV DSH_CADDY=true
# 对外监听端口（Caddy）
ENV DSH_PORT=3080
# dsh 内部监听端口（仅 127.0.0.1，由 Caddy 反代）
ENV DSH_UPSTREAM_PORT=3081
# 容器内默认使用 ptc 模式沙箱（JS run_code 运行时，规避 Landlock 在 seccomp 下的限制）
# 注意：dsh ≥0.1.5 已将旧值 code 更名为 ptc，mode 可选值 native | ptc | both
ENV DSH_TOOLS_MODE=ptc

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["web"]
