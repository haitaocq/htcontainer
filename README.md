# htcontainer

基于 GitHub Actions 自动构建并发布到 **GitHub Container Registry (GHCR)** 的 Docker 容器镜像集合。

项目集中管理多个用于 **AI 代理（Agent）环境** 的 Docker 镜像，内置 [opencode](https://opencode.ai)、[multica](https://github.com/multica-ai/multica) 与 [cc-connect](https://github.com/chenhg5/cc-connect) 等核心工具，支持一键注入第三方大模型（LLM）配置，开箱即用。

---

## 目录

- [镜像清单](#镜像清单)
- [公共特性](#公共特性)
- [快速开始](#快速开始)
- [环境变量说明](#环境变量说明)
- [镜像详细介绍](#镜像详细介绍)
- [目录结构](#目录结构)
- [CI/CD 自动构建](#cicd-自动构建)
- [本地构建](#本地构建)
- [常见问题](#常见问题)

---

## 镜像清单

| 镜像名称 | 基础镜像 | 内置工具 | 适用场景 |
| --- | --- | --- | --- |
| `agentgroup` | `debian:bookworm-slim` | opencode + multica | 通用 Agent 运行环境 |
| `agentgroup_node` | `debian:bookworm-slim`（自装 Node.js 24） | opencode + multica + Node.js | 需要 Node.js 运行时的 Agent 环境 |
| `agentgroup_python` | `python:3.11-slim-bookworm` | opencode + multica + Python 3.11 | 需要 Python 运行时的 Agent 环境 |
| `agent_cc-connect` | `debian:bookworm-slim` | opencode + multica + cc-connect | 接入飞书（Feishu）IM 的 Agent |
| `agent_dsh` | `node:24-bookworm-slim` | [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（dsh） | 内置 DeepSeek Harness Web UI / headless 任务的 Agent 环境 |
| `debian-slim-test` | `debian:bookworm-slim` | 基础工具（curl/git/tar） | 开发测试 |

> 所有镜像均发布至 `ghcr.io/<owner>/<image-name>`，`latest` 标签仅在 `main` 分支推送时更新。

---

## 公共特性

所有 Agent 镜像（除 `debian-slim-test`）的入口脚本 `entrypoint.sh` 均包含以下通用逻辑：

### 1. OpenCode 第三方 LLM 配置注入

当设置了 `OPENCODE_MODEL` / `OPENCODE_BASE_URL` / `OPENCODE_API_TOKEN` 任一变量时，入口脚本会使用 `jq` 动态生成 `~/.config/opencode/opencode.json`：

- 支持通过逗号分隔配置**多个模型**，自动生成模型映射字典；
- 通过 `OPENCODE_MODEL_DEFAULT` 指定默认模型；
- 通过 `OPENCODE_BASE_URL` 兼容任意 OpenAI 兼容协议的服务地址；
- 底层使用 `@ai-sdk/opencode-compatible` npm 包连接。

### 2. Multica 鉴权与登录

- 自动检查本地 `~/.multica/config.json` 中是否存在有效 token；
- 已认证则跳过，未认证时通过 `MULTICA_TOKEN` 执行 `multica login --token`；
- 支持通过 `MULTICA_SERVER_URL`、`MULTICA_APP_URL` 自定义服务地址。

### 3. Multica 守护进程启动

- 容器启动时自动拉起 `multica daemon`；
- 若首次启动失败，会在后台重试最多 **30 次**（每次间隔 5 秒），不阻塞主进程。

### 4. 优雅退出（Graceful Shutdown）

- 捕获 `SIGTERM` / `SIGINT` 信号，先停止 multica 守护进程再退出；
- 容器默认以 `tail -f /dev/null` 常驻后台运行，也可通过传入自定义命令替换入口进程（`exec "$@"`）。

### 5. 安全与构建优化

- 所有运行镜像均使用**非 root 用户** `agents` 运行；
- 采用 **Dockerfile 多阶段构建**，将二进制文件与入口脚本分层复制，最大化镜像层缓存复用；
- 使用 BuildKit `--mount=type=cache` 缓存 apt 软件包，加速重复构建。

---

## 快速开始

以 `agentgroup` 为例：

```bash
docker run -d --name agentgroup \
  -e MULTICA_TOKEN="your_multica_token" \
  -e MULTICA_SERVER_URL="https://your-multica-server" \
  -e OPENCODE_PROVIDER="my-provider" \
  -e OPENCODE_BASE_URL="https://api.your-llm.com/v1" \
  -e OPENCODE_API_TOKEN="your_llm_api_key" \
  -e OPENCODE_MODEL="model-a,model-b" \
  -e OPENCODE_MODEL_DEFAULT="model-a" \
  ghcr.io/<owner>/agentgroup:latest
```

拉取即可使用，无需额外配置：

```bash
docker pull ghcr.io/<owner>/agentgroup:latest
```

### agent_dsh（DeepSeek Harness Web UI）

```bash
docker run -d --name agent_dsh \
  -e DEEPSEEK_API_KEY="your_deepseek_key" \
  -p 3080:3080 \
  -v agent_dsh_data:/home/agents/.dsh \
  -v agent_dsh_ws:/home/agents/workspace \
  ghcr.io/<owner>/agent_dsh:latest
```

访问 `http://<host>:3080` 使用 Web UI；`dsh --profile headless "任务"` 一次性执行：

```bash
docker run --rm \
  -e DEEPSEEK_API_KEY="your_deepseek_key" \
  ghcr.io/<owner>/agent_dsh:latest \
  dsh --profile headless "请总结当前工作目录"
```

---

## 环境变量说明

| 变量名 | 必填 | 说明 |
| --- | --- | --- |
| `MULTICA_TOKEN` | 是* | Multica 认证 Token（也支持 `MUL_TOKEN` 别名） |
| `MULTICA_SERVER_URL` | 否 | 自定义 Multica 服务端地址 |
| `MULTICA_APP_URL` | 否 | 自定义 Multica App 地址 |
| `OPENCODE_PROVIDER` | 否 | LLM Provider 标识（默认 `custom-provider`） |
| `OPENCODE_BASE_URL` | 否 | LLM 服务地址（兼容 OpenAI 协议） |
| `OPENCODE_API_TOKEN` | 否 | LLM API Key（也支持 `OPENAI_API_KEY` 别名） |
| `OPENCODE_MODEL` | 否 | 模型 ID 列表，**逗号分隔**支持多模型 |
| `OPENCODE_MODEL_DEFAULT` | 否 | 指定默认模型（拼接到 `model` 字段） |

> `*`：仅当容器内尚未存在有效 Multica 配置时才需要 `MULTICA_TOKEN`；若已挂载已认证的配置目录则自动跳过登录。

### agent_cc-connect 额外变量

| 变量名 | 必填 | 说明 |
| --- | --- | --- |
| `CC_ADMIN_FROM` | 是 | 项目级管理员白名单（用户 ID 逗号分隔，个人环境可用 `*`） |
| `CC_WORK_DIR` | 否 | cc-connect 工作目录（不存在会自动创建） |
| `CC_MODE` | 否 | OpenCode 运行模式（`default` / `acceptEdits` / `plan` / `auto` / `yolo`） |
| `FEISHU_APP_ID` | 是 | 飞书应用 App ID |
| `FEISHU_APP_SECRET` | 是 | 飞书应用 App Secret |

### agent_dsh 额外变量

| 变量名 | 必填 | 说明 |
| --- | --- | --- |
| `DSH_HOME` | 否 | dsh 数据目录（默认 `~/.dsh`，建议挂载卷持久化） |
| `DSH_BIND_HOST` | 否 | Web 绑定地址（默认 `0.0.0.0`，通过 patch 覆盖 `webserver` 行实现，无需 CLI 支持） |
| `DSH_PORT` | 否 | Web UI 监听端口（默认 `3080`） |
| `DSH_TRUSTED_HOSTS` | 否* | 浏览器访问 Web UI 所用的地址（IP/域名，逗号或空格分隔）。非 localhost 访问时**必须**设置，否则 `/api` 信任栅栏返回 403（报 `transport failure for /api/...: HTTP 403`）。已测试 `192.168.1.50` 等宿主 IP |
| `DSH_TOOLS_MODE` | 否 | 工具沙箱模式：`native` \| `code` \| `both`（容器内默认 `code`，规避 Landlock 限制） |
| `DSH_WORKSPACE` | 否 | 工作目录（默认 `~/workspace`，不存在会自动创建） |
| `DEEPSEEK_API_KEY` | 是* | DeepSeek 原生 API Key（环境变量直接生效，无需配置文件） |
| `DSH_PROVIDER_ID` | 否 | 自定义 Provider ID（默认 `custom-provider`） |
| `DSH_BASE_URL` | 否 | 自定义 OpenAI 兼容服务地址 |
| `DSH_API_TOKEN` | 否 | 自定义 Provider API Key（也支持 `OPENAI_API_KEY` 别名） |
| `DSH_MODEL` | 否 | 模型 ID 列表，**逗号分隔**支持多模型 |
| `DSH_MODEL_DEFAULT` | 否 | 指定默认模型（未设置时自动取模型列表第一个，覆盖 headless 模式的 `deepseek-official` 默认值） |

> `*`：`DEEPSEEK_API_KEY` 与 `DSH_BASE_URL`+`DSH_API_TOKEN`+`DSH_MODEL` 两种 LLM 接入方式任选其一。

> `*`（`DSH_TRUSTED_HOSTS`）：必须与浏览器地址栏的 host 一致。用 `http://localhost:3080` 访问可免设置；用宿主机 IP/域名访问必须填入该地址。示例：`DSH_TRUSTED_HOSTS=192.168.1.50`

---

## 镜像详细介绍

### agentgroup（通用）

- **基础镜像**：`debian:bookworm-slim`
- **特性**：最精简的 Agent 环境，仅内置 opencode 与 multica；
- **默认命令**：`tail -f /dev/null` 常驻。

### agentgroup_node（Node.js 运行时）

- **基础镜像**：`debian:bookworm-slim`
- **特性**：
  - 内置 **Node.js v24.18.0**（可通过构建参数 `NODE_VERSION` 调整）；
  - 通过 `TARGETARCH` 自动适配 amd64 / arm64 架构（Apple Silicon 友好）；
  - 使用单层 `COPY` 导出全部产物，镜像层更精简。

### agentgroup_python（Python 运行时）

- **基础镜像**：`python:3.11-slim-bookworm`
- **特性**：直接使用官方 Python slim 镜像，内置 Python 3.11 与 pip，适合 Python 相关的 Agent 任务；
- 设置 `PYTHONUNBUFFERED=1`、`PYTHONDONTWRITEBYTECODE=1` 最佳实践。

### agent_cc-connect（飞书接入）

- **基础镜像**：`debian:bookworm-slim`
- **特性**：
  - 内置 **cc-connect v1.4.1**（可通过构建参数 `CC_VERSION` 调整），将 OpenCode 接入飞书 IM；
  - 提供 `config.template.toml` 配置模板，支持：飞书交互式卡片、话题隔离、图片合批、@解析、闲置自动开新会话、超时保护等；
  - 配置模板备份于 `/etc/cc-connect/config.template.toml`（系统级只读目录），容器启动时自动初始化 `~/.cc-connect/config.toml`，**规避宿主机挂载空目录覆盖问题**；
  - 支持环境变量占位符（`${CC_ADMIN_FROM}`、`${CC_WORK_DIR}` 等）由 cc-connect 运行时解析。

### agent_dsh（DeepSeek Harness）

- **基础镜像**：`node:24-bookworm-slim`（构建阶段使用 `node:24-bookworm` 编译原生依赖）
- **特性**：
  - 内置 **[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（`dsh`）**，可通过 `DSH_VERSION` 构建参数调整版本（当前默认 `0.1.0-rc.6`，开发者预览版请务必固定版本）；
  - 默认命令 `dsh web` 启动 Web UI（`http://<host>:3080`），也支持 `dsh --profile headless "任务"` 一次性执行；
  - **Web 绑定**：dsh CLI 故意拒绝 `--host 0.0.0.0`（防远程 RCE），镜像通过 `cordis.patch.yml` 覆盖 `webserver` 行实现默认绑定 `0.0.0.0`，支持容器端口映射直接访问；
  - **LLM 配置注入**：`DEEPSEEK_API_KEY` 原生接入，或通过 `DSH_*` 系列变量注入任意 OpenAI 兼容 provider（写入 `$DSH_HOME/settings.yaml`，凭证以 `apiKeyEnv` 引用环境变量、不进文件）；
  - 容器内默认 `DSH_TOOLS_MODE=code`（纯 JS worker-thread 沙箱），规避 Landlock 原生沙箱在 Docker seccomp 下的限制；
  - 数据目录 `$DSH_HOME`（默认 `~/.dsh`）建议挂载卷持久化；
  - 容器以非 root 用户 `agents` 运行（**固定 uid/gid 10001**），镜像已预建数据/工作目录并设置属主。使用具名卷可直接挂载；若 bind 挂载宿主机目录，请先 `chown -R 10001:10001 <host-dir>`。

### debian-slim-test（开发测试）

- **基础镜像**：`debian:bookworm-slim`
- **特性**：仅安装基础工具（curl/git/tar），`tail -f /dev/null` 常驻，用于镜像构建与开发测试。

---

## 目录结构

```text
htcontainer/
├── .github/
│   └── workflows/
│       └── docker-build.yml      # CI/CD：自动检测变更并构建推送镜像
├── containers/
│   ├── agentgroup/               # 通用 Agent 镜像
│   │   ├── Dockerfile
│   │   ├── entrypoint.sh
│   │   └── .env.example
│   ├── agentgroup_node/          # Node.js 运行时 Agent 镜像
│   │   ├── Dockerfile
│   │   ├── entrypoint.sh
│   │   └── .env.example
│   ├── agentgroup_python/        # Python 运行时 Agent 镜像
│   │   ├── Dockerfile
│   │   ├── entrypoint.sh
│   │   └── .env.example
│   ├── agent_cc-connect/         # 飞书接入 Agent 镜像
│   │   ├── Dockerfile
│   │   ├── entrypoint.sh
│   │   ├── config.template.toml
│   │   └── .env.example
│   ├── agent_dsh/                # DeepSeek Harness Agent 镜像
│   │   ├── Dockerfile
│   │   ├── entrypoint.sh
│   │   ├── docker-compose.yml
│   │   └── .env.example
│   └── debian-slim-test/         # 开发测试镜像
│       └── Dockerfile
└── README.md
```

每个容器目录下的 `.env.example` 提供了完整的可配置环境变量清单，部署时可参考。

---

## CI/CD 自动构建

工作流文件：`.github/workflows/docker-build.yml`

**触发条件**（支持 4 种方式）：

| 触发方式 | 触发条件 | 构建范围 |
| --- | --- | --- |
| 代码变更（push） | `main` 分支上 `containers/**` 路径有改动 | 仅变更的容器目录 |
| Pull Request | 针对 `main` 分支，涉及 `containers/**` | 仅变更的容器目录（只构建不推送） |
| 手动触发（workflow_dispatch） | 在 Actions 页面点击 "Run workflow" | 全部镜像 |
| 版本标签（tag） | 推送 `v*` 格式标签（如 `v1.2.0`） | 全部镜像 |

**流程**：

1. **detect-changes**：根据触发方式动态生成构建矩阵：
   - push / PR：通过 `git diff` 检测发生变更的容器目录（PR 对比目标分支，push 对比上次提交），失败则回退全量构建；
   - 手动触发 / 标签触发：固定全量构建所有容器；
2. **build-and-push**：对矩阵中的每个容器目录并行执行：
   - 使用 Docker Buildx 构建多架构缓存（`type=gha`）；
   - 登录 GHCR；
   - 通过 `docker/metadata-action` 生成镜像标签；
   - **push**：仅 push / 手动 / 标签事件推送镜像，PR 只构建不推送（验证可构建性）。

**镜像标签**：

- 版本标签触发（如 `v1.2.0`）：`<image>:v1.2.0`，同时更新 `<image>:latest`
- main 分支推送：`<image>:latest` 与 `<image>:<short-sha>`
- 手动触发：`<image>:latest` 与 `<image>:<short-sha>`

**手动触发操作步骤**：

```text
GitHub 仓库 → Actions → "Build and Push Docker Images" → Run workflow → Run workflow
```

---

## 本地构建

使用 BuildKit 构建（Dockerfile 使用了 `--mount=type=cache` 特性）：

```bash
# 通用镜像
docker build --tag local/agentgroup:test ./containers/agentgroup

# Node.js 镜像（指定架构）
docker build --build-arg TARGETARCH=amd64 \
  --tag local/agentgroup_node:test ./containers/agentgroup_node

# 飞书接入镜像（指定 cc-connect 版本）
docker build --build-arg CC_VERSION=1.4.1 \
  --tag local/agent_cc-connect:test ./containers/agent_cc-connect

# DeepSeek Harness 镜像（指定 dsh 版本）
docker build --build-arg DSH_VERSION=0.1.0-rc.6 \
  --tag local/agent_dsh:test ./containers/agent_dsh
```

> 提示：如遇 BuildKit 语法报错，请确认 Docker 版本 ≥ 23.0 且已启用 BuildKit（`DOCKER_BUILDKIT=1`）。

---

## 常见问题

**Q1：容器启动报错 "Authentication failed — MUL_TOKEN / MULTICA_TOKEN is required."**

未提供 Multica Token 且容器内无已认证配置。请设置 `MULTICA_TOKEN` 环境变量，或挂载包含有效 `~/.multica/config.json` 的卷。

**Q2：如何挂载宿主机目录而不丢失配置？**

`agent_cc-connect` 已将配置模板存放于系统级目录 `/etc/cc-connect/`，即使挂载全新的空目录到 `/home/agents`，启动时也会自动从模板初始化 `~/.cc-connect/config.toml`。

**Q3：Multica 守护进程启动失败？**

入口脚本会在后台自动重试最多 30 次（每次间隔 5 秒）。若仍失败，请确认 `MULTICA_SERVER_URL` 可达且 Token 有效。

**Q4：如何让容器执行自定义命令？**

直接传入命令即可，入口脚本会通过 `exec "$@"` 替换进程，并保持信号透传：

```bash
docker run ghcr.io/<owner>/agentgroup:latest your-command --with-args
```