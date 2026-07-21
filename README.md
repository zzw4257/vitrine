<div align="center"><pre>
██╗   ██╗██╗████████╗██████╗ ██╗███╗   ██╗███████╗
██║   ██║██║╚══██╔══╝██╔══██╗██║████╗  ██║██╔════╝
██║   ██║██║   ██║   ██████╔╝██║██╔██╗ ██║█████╗
╚██╗ ██╔╝██║   ██║   ██╔══██╗██║██║╚██╗██║██╔══╝
 ╚████╔╝ ██║   ██║   ██║  ██║██║██║ ╚████║███████╗
  ╚═══╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝╚══════╝
        a glass cockpit for every local AI agent
</pre></div>

<p align="center"><strong>6 CLI agents · one command center · local-first · read-only · zero third-party deps</strong></p>

<p align="center">
把散落在 <code>~/.claude</code> · <code>~/.codex</code> · <code>~/.gemini</code> · <code>~/.codeium</code> · opencode · Cursor 里的
成百上千个 AI-agent 会话，聚合成一个玻璃质感、可检索、可视化、可调配的统一指挥中心。
</p>

<p align="center">
  <img alt="platform" src="https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white">
  <img alt="swift" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <img alt="ui" src="https://img.shields.io/badge/SwiftUI-Liquid%20Glass-1E90FF">
  <a href="https://github.com/zzw4257/vitrine/actions/workflows/build.yml"><img alt="build" src="https://github.com/zzw4257/vitrine/actions/workflows/build.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="license" src="https://img.shields.io/badge/license-MIT-green"></a>
  <img alt="deps" src="https://img.shields.io/badge/dependencies-0-brightgreen">
</p>

<p align="center">
  <a href="#快速开始--quick-start"><strong>快速开始</strong></a> ·
  <a href="#支持的-agent-源--agent-sources"><strong>Agent 源</strong></a> ·
  <a href="#面板闭环--panels"><strong>面板</strong></a> ·
  <a href="#主题系统--themes"><strong>主题</strong></a> ·
  <a href="PRIMITIVE.md"><strong>🧬 原语 / Primitive</strong></a> ·
  <a href="#架构与设计要点--architecture"><strong>架构</strong></a>
</p>

---

**Vitrine** 是一个原生 macOS 应用（纯 SwiftUI + Liquid Glass，macOS 26+，**零第三方依赖**）。
你每天在终端里用 Claude Code、Codex、Gemini CLI、opencode……跑出的会话散落在各自的目录里，谁也不认识谁。
Vitrine 只读地把它们**全部**扫进来，按项目重组，告诉你：*哪个 agent、在哪个项目、什么时候、做了什么、烧了多少 token、用了哪个模型* —— 并让你检索它、迁移它的记忆、蒸馏它的技能、再从这里把下一个任务派出去。

> 🧬 这个仓库还开源了一份特别的东西：[**PRIMITIVE.md**](PRIMITIVE.md) —— 不是设计文档，而是 Vitrine 的**生成原语**。
> 它把"这个产品的本质是什么、每块的重点在哪"压缩成一份可以直接喂给 agent 的种子，让另一个 agent 用它长出**另一个** Vitrine。我的实现只是其中一种实现。

## 支持的 Agent 源 · Agent sources

只读扫描，各家格式不同，Vitrine 统一成同一种"会话"。

| Agent | 来源 | 提取 |
|-------|------|------|
| **Claude Code** | `~/.claude/projects/**/*.jsonl` | cwd·分支·模型·逐轮 token·工具/命令·提问 |
| **Codex** | `~/.codex/sessions/**/rollout-*.jsonl` | cwd·model·token_count·shell 命令·子代理 |
| **Gemini CLI** | `~/.gemini/tmp/<sha256(cwd)>/chats/*.json` | 每条消息的 model + tokens（哈希目录反查项目） |
| **opencode** | `~/.local/share/opencode/storage/{session,message}` | 会话元数据·消息计数 |
| **Cursor** | `~/.cursor/ai-tracking/ai-code-tracking.db` | conversation_summaries（title/overview/model，只读 SQLite） |
| **Windsurf** | `~/.codeium/windsurf/code_tracker/` | 活动足迹（转录本地加密，仅还原触碰的文件） |

<sub>诚实原则：Windsurf 的对话在本地加密（实测 8.0 bits/byte 熵），无法还原转录 —— Vitrine 只呈现能诚实还原的文件足迹，不编造内容。</sub>

## 面板闭环 · Panels

| 面板 | 能力 |
|------|------|
| **总览** | 项目/会话/消息/**总吞吐 tokens**/活跃天数聚合；半年活跃热力图（悬停读数）；**构成甜甜圈**可切 Agent↔模型、消息↔tokens 两个维度（交互式：悬停扇区弹出、圆心实时读数）；最近会话支持**列表 / 瀑布流 / 方格**三种展示 |
| **项目** | 一个项目下多 Agent 贡献的五视角：**织线**（每 agent 一条泳道，空隙即贡献中断 —— 解决"一个项目多对话、贡献不连续"）、**热力**、**构成**、**节律**、**AI 洞察** |
| **检索** | SQLite **FTS5 三元组**全文索引，中文友好；<3 字自动降级 LIKE；命中词高亮；按 agent 过滤 |
| **记忆工坊** | 跨 agent 记忆**提取 / 合并 / 迁移**：CLAUDE.md ⇄ AGENTS.md ⇄ GEMINI.md ⇄ .cursorrules ⇄ .windsurfrules；写入前自动 `.bak` 备份 |
| **技能蒸馏** | 从项目全部会话行为蒸馏规范/命令/工作流 → 可编辑 `SKILL.md`；启发式即时或 AI 深度蒸馏（可选**侧重**：全面/规范/命令/工作流）；一键注入 **7 类目标**（Claude 技能目录、Codex/Gemini 全局、项目级 AGENTS/.cursorrules/.windsurfrules） |
| **任务调配** | 选项目 + 选 agent + 注入项目记忆简报（`.vitrine-briefing.md`）→ 生成启动命令一键在终端拉起；实时检测运行中的 agent 进程 |

<sub>浏览列表与检索**默认屏蔽低信号会话**（工具自身产生的总结/蒸馏元会话、极小会话），一键可展开 —— 但绝不影响任何统计聚合。</sub>

## 30 秒看懂原理 · How it works

```
  ~/.claude  ~/.codex  ~/.gemini  ~/.codeium  opencode  ~/.cursor
      │         │         │          │           │         │
      └─────────┴────┬────┴──────────┴───────────┴─────────┘
                     ▼
        [ 增量扫描 ]  mtime+size 缓存 · 流式解析 · 只读
                     ▼
        [ 统一 SessionRecord ]  agent·项目·时间·token·模型·工具
                     ▼
   ┌─────────────┬──────────────┬─────────────┬──────────────┐
   ▼             ▼              ▼             ▼              ▼
 按项目聚合    FTS5 索引      记忆提取       技能蒸馏        任务简报
 (织线/热力)   (毫秒检索)    (跨 agent 迁移)  (→ SKILL.md)   (→ 终端拉起)
```

## 主题系统 · Themes

主题携带一整套结构令牌（表面材质 / 背景形态 / 圆角 / 边框 / 排版 / 纹理），是结构不同的设计，不是配色替换：

- **Vitrine 玻璃系**（星云·落日·深海·苔原·石墨）：Liquid Glass 卡片 + 漂移极光 + 各自的**背景纹理**（点阵/斜纹/等高线/十字网/网格）+ 缓慢漂浮的**环境光点**。
- **Apple**（深/浅）：vibrancy 半透明 + 顶部亮边 + 柔和投影 + 15px squircle + 平静桌面式 wash + systemBlue。
- **GitHub**（深/浅）：Primer 纯平画布 + 实心卡 + 1px 硬边框 + 8px 圆角 + 真实贡献图绿阶热力，无玻璃模糊。

外观设置里还有玻璃通透度 / 边框分离度 / 极光活跃度三个实时旋钮。全部动效兼容"减弱动效"辅助功能设置。

## 快速开始 · Quick Start

```sh
git clone https://github.com/zzw4257/vitrine.git
cd vitrine
./build.sh            # swift build -c release + 组装 Vitrine.app（含生成的棱镜图标）
open build/Vitrine.app
```

要求 **Xcode 26 / Swift 6 / macOS 26+**。首次启动会播放一段仪式感开屏引导（扫描足迹 → 选色调 → 接入 AI → 就绪）。
或直接从 [**Releases**](https://github.com/zzw4257/vitrine/releases) 下载打包好的 `Vitrine.app.zip`（ad-hoc 签名，首次打开右键 → 打开）。

## 🧬 原语 · The Primitive

在 AI 时代，一个产品最有价值的往往不是代码，而是**它的原语** —— 那套让它成为它的、可以被重新生长的本质。

[**PRIMITIVE.md**](PRIMITIVE.md) 就是 Vitrine 的这份原语：核心理念、不可动摇的不变量、每个概念构件的**刻画重点**、美学与动效哲学，以及一段**可直接使用的再生提示词**。把它交给任意 agent，就能在**任意技术栈**里长出另一个 Vitrine —— 界面可以完全不同，灵魂一致。这份文件本身是这个开源项目独立的一部分。

## 架构与设计要点 · Architecture

<details>
<summary><strong>展开：扫描 / 索引 / 渲染 / 隐私</strong></summary>

- **增量扫描**：按文件 mtime+size 缓存（`~/Library/Application Support/Vitrine/scan-cache-v2.json`），tombstone 记录无会话文件；首扫全量、之后秒开、新会话流式增量入表。
- **哈希项目反查**：Gemini 用 `sha256(cwd)` 命名目录，Vitrine 对已发现的所有项目路径求哈希建反查表还原归属。
- **Token 口径**：`总吞吐 = input + output + cache_read + cache_creation`。Agent 每轮从缓存重读整个上下文，只算 output 会严重低估 —— 单个大会话动辄上亿 token。
- **纯词法路径处理**：刻意不用 `standardizingPath`（它会 stat 文件系统、触发 Documents 授权弹窗），避免无谓的 TCC 打扰。
- **玻璃 + 极光 + 纹理**：`GlassEffectContainer` / `glassEffect` + `Canvas` 手绘漂移极光、背景纹理与环境光点；交互式图表（甜甜圈/条形/热力/节律）悬停高亮、圆心实时读数。
- **隐私**：一切**只读、离线、本地**。唯一的写入是你在记忆工坊/技能蒸馏里显式发起的，且写前 `.bak` 备份。无遥测、无网络（除非你自己配置了云端 AI 服务商）。

</details>

<details>
<summary><strong>展开：AI 接入（云端 / 本地 llama.cpp / 本地 Claude CLI）</strong></summary>

会话总结、技能深度蒸馏、项目洞察都走同一套 `AIClient`：

- **云端 OpenAI 兼容**（OpenAI/DeepSeek/Kimi/OpenRouter/Together/Groq/自定义）：`GET /models` 拉列表、`POST /chat/completions`、两步测试；Key 首次从 `OPENAI_API_KEY` 或 `~/.codex/auth.json` 预填。
- **本地 llama.cpp**：Ollama（`GET /api/tags` 列本地模型、`POST /api/pull` **流式拉取带进度**、一键 `ollama serve`）与 llama-server（指定 GGUF + 端口一键拉起、轮询 `/health`）。
- **本地 Claude CLI**：直接调用已登录的 `claude -p`，无需 API Key。

</details>

<details>
<summary><strong>展开：调试入口（环境变量）</strong></summary>

直接运行 bundle 内二进制并设环境变量可直达指定页面（便于截图/联调）：

```sh
BIN=build/Vitrine.app/Contents/MacOS/Vitrine
env VITRINE_SECTION=search VITRINE_QUERY=triton "$BIN"
env VITRINE_SECTION=dashboard VITRINE_COMPOSITION=model "$BIN"
```

`VITRINE_SECTION` ∈ `dashboard|projects|search|memory|distillery|dispatch`；其它：`VITRINE_QUERY` / `VITRINE_PROJECT` / `VITRINE_PERSPECTIVE` / `VITRINE_COMPOSITION=model` / `VITRINE_OPEN_SETTINGS=1` / `VITRINE_FLOAT=1`。

</details>

## License

[MIT](LICENSE) © 2026 [zzw4257](https://github.com/zzw4257)
