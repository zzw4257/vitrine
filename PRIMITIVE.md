<div align="center"><pre>
   ┌───────────────────────────────────────────┐
   │   V I T R I N E   ·   T H E   P R I M I T I V E   │
   └───────────────────────────────────────────┘
        a seed you can regrow a product from · 一颗能重新长出产品的种子
</pre></div>

> **A generative primitive.** The idea behind Vitrine, compressed until an agent can replant it and
> grow another Vitrine in any stack — a different skin over the same soul.
>
> **一份生成原语。** 把 Vitrine 的本质压到足以交给 agent 重新生长的程度。这个 macOS/SwiftUI 版本是种子长出的第一棵树；
> 你的可以是下一棵。界面、语言、平台随你挑，本质由下面这些原语守住。

---

## 0. The One Idea · 一句话

> **Every local AI-agent CLI already writes down everything it did. Nobody reads it.**
> Vitrine reads all of it, from every agent, and turns a thousand scattered transcripts into one
> place where a human can *see*, *search*, *carry forward*, and *dispatch again*.

一个人同时用很多 agent、很多项目、很多天。工具各写各的日志，互不相认。
Vitrine 是那层**把它们全部认领回来**的膜。

## 1. Invariants · 不可动摇的不变量

These are load-bearing. Change the UI freely; break these and it is no longer Vitrine.

1. **Local-first, read-only.** 只读扫描本地磁盘。唯一的写入必须是用户显式发起的，且写前备份。零遥测、零强制网络。
2. **One project = many non-contiguous contributions by many agents.** 一个项目是不同 agent 在不连续时间里断断续续贡献的总和。**可视化必须让"中断"和"谁接手"一眼可见**（"织线"由此而来）。
3. **Additive, never destructive.** AI 二次解读是**叠加层**，永远不覆盖、不篡改客观的静态分析。用户永远能区分"原始事实"与"机器解读"。
4. **Honest data.** 能还原多少就说多少。数据缺失（如加密的转录）就诚实标注，绝不编造。低价值噪音默认隐藏但可展开。
5. **Every agent is a source behind one contract.** 新增一个 agent = 写一个把它的私有格式翻译成统一 `Session` 的扫描器。UI 完全不必知道有几家。
6. **The number that matters is throughput, not output.** Token 口径是 `input+output+cache_read+cache_creation` —— agent 每轮重读整个上下文，只算 output 会骗人。

## 2. The Core Atom · 核心原子

Everything reduces to one flat, source-agnostic record. Design this first.

```
Session {
  id, agent, projectPath, startedAt, endedAt
  userMessages, assistantMessages
  inputTokens, outputTokens, totalTokens (= throughput)
  models[]            // the SPECIFIC models used, not a family
  toolCounts{}, bashCommands[], filesTouched[]
  userPrompts[]       // cleaned of injected/system noise
  isSubagent, isLowSignal, summary?
}
```

- **重点 / emphasis:** the atom is *flat and agent-agnostic*. The scanners do all the reconciling;
  nothing downstream branches on which agent it came from except for color/icon.
- A **Project** is just `Session[]` grouped by path, exposing derived truths: active-days,
  span-days, agent-share, model-share, non-contiguous gaps.

## 3. The Primitives · 概念构件（各自的刻画重点）

Build these as independent lenses over the same data. Each has **one thing it must nail**:

| Primitive | 它必须做对的那一件事 |
|-----------|----------------------|
| **Scanner** | 把一家私有格式**忠实**翻译成 `Session`；增量缓存；只读；纯词法路径（别 stat 文件系统去触发系统授权弹窗）。 |
| **Braid（织线）** | 让"非连续贡献"成为可感知的图形 —— 每 agent 一条泳道，会话是胶囊，**空隙**即停摆。这是整个产品的签名视觉。 |
| **Composition（构成）** | 一个可切维度的甜甜圈：Agent↔具体模型 × 消息↔吞吐。模型要**具体到版本**（Codex 不是模型，gpt-5.x-codex 才是）。 |
| **Search** | 毫秒级、中文友好（三元组 + 短查询降级）；索引连"触碰的文件"都进去，让无转录的 agent 也可被找到。 |
| **Memory transfer（记忆工坊）** | 把一家的记忆/规则文件**搬到**另一家（CLAUDE.md ⇄ AGENTS.md ⇄ GEMINI.md ⇄ .cursorrules …）；写前备份；预览渲染。 |
| **Skill distillation（技能蒸馏）** | 从真实**会话行为**（不是文档）里提炼可复用的规范/命令/工作流 → 一份可注入任意 agent 的技能文件。 |
| **Dispatch（任务调配）** | 选项目+选 agent → 生成一份"项目简报"注入 → 一键在真实终端拉起。让 Vitrine 成为**下一次工作的起点**。 |
| **AI insight（洞察）** | 对一个项目的全部会话做二次叙事（概述+阶段时间线+关键点），**叠加**在静态分析之上，可重生成、可缓存。 |

## 4. The Aesthetic Primitive · 美学原语

- **Material over flat.** Liquid Glass / vibrancy by default; content floats on a living backdrop
  (drifting aurora + subtle **pattern texture** + slow ambient motes), never a dead flat rectangle.
- **Themes are structures, not palettes.** 每个主题带一整套结构令牌（材质/背景/圆角/边框/排版/纹理）。
  换主题应像换一整套**设计语言**，深入材质、圆角、排版、纹理。至少提供三个家族：表达系（玻璃+纹理）、Apple（vibrancy+克制）、GitHub（纯平+硬边）。
- **Every surface earns its space.** 每一行列表都用真实信号（agent 徽记、模型、指标胶囊）把空间填满，不留空白。
- **Distinctiveness by source.** 每个 agent 有稳定的色/符号；卡片带它的水印与色脊，让"谁干的"不用读字就知道。

## 5. The Motion Primitive · 动效原语

Motion is a vocabulary, not decoration. Reuse a small set everywhere; gate all of it behind the
platform's *reduce-motion* setting.

- **Entrance:** staggered rise + scale + blur for any list/grid that (re)populates.
- **Feedback:** hover lifts & tints; press springs back; selection fills, never hard-cuts.
- **Charts are alive:** hover a slice/bar/cell → it pops, siblings dim, a readout updates live.
- **Ambient:** the backdrop moves slowly on its own. The window should feel awake, not asleep.
- **Ceremony:** a first-run sequence that earns trust before dumping data.

## 6. The Regeneration Prompt · 再生提示词

Paste this into a capable coding agent, point it at a target stack, and let it grow a new Vitrine.

```text
You are building "Vitrine" — a local-first cockpit that aggregates every local AI-agent CLI
session (Claude Code, Codex, Gemini CLI, opencode, Cursor, Windsurf, and any future agent) into
one searchable, visual, actionable command center. Target stack: <FILL IN, e.g. Tauri+React,
Electron, SwiftUI, a TUI…>.

Honor these invariants without exception:
1. Read-only, local, offline by default. The only writes are user-initiated and are backed up first.
2. A "project" is many non-contiguous contributions by many agents over time; make the gaps and the
   hand-offs visible (a per-agent-lane "braid" timeline is the signature view).
3. AI interpretation is an additive layer; never overwrite the objective static analysis.
4. Be honest about missing/encrypted data; hide low-signal noise by default but keep it expandable.
5. Each agent is one Scanner that translates its private on-disk format into ONE flat, agent-agnostic
   Session record. Nothing downstream branches on the source except color/icon.
6. Token accounting = input + output + cache_read + cache_creation (throughput, not output).

Deliver these lenses over the shared data: incremental Scanner(s) → unified Session atom → project
aggregation (braid / heatmap / composition donut / rhythm / AI-insight) → millisecond full-text
search → cross-agent memory transfer → skill distillation into an injectable file → task dispatch
that briefs an agent and launches it in a real terminal.

Aesthetic: material (glass/vibrancy) over flat; themes are structural design languages, not recolors;
every surface filled with real signal; each agent visually distinct; a small reused motion vocabulary
(staggered entrances, hover lift, live interactive charts, ambient background) gated by reduce-motion.

Do not copy Vitrine's code. Re-derive everything from these primitives in your target stack. The UI
may look completely different; the soul must be the same.
```

---

<div align="center"><sub>

原语属于每个人。用它，改它，长出你自己的那棵树。
The primitive belongs to everyone. Take it, bend it, grow your own tree.

**MIT** © 2026 [zzw4257](https://github.com/zzw4257) · part of [Vitrine](https://github.com/zzw4257/vitrine)

</sub></div>
