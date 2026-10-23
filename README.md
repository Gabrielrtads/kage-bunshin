# 🥷⚡ Kage Bunshin (`kage-bunshin`)

[![skills.sh compatible](https://img.shields.io/badge/skills.sh-compatible-6366f1?style=for-the-badge)](https://skills.sh)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)](LICENSE)
[![Zero-Dependency](https://img.shields.io/badge/Dependencies-Zero-emerald?style=for-the-badge)](#)
[![Multi-CLI](https://img.shields.io/badge/Supports-Claude_|_Codex_|_Antigravity-orange?style=for-the-badge)](#)
[![Methodology](https://img.shields.io/badge/Jutsu-Kage_Bunshin_no_Jutsu-crimson?style=for-the-badge)](#)

[![GitHub stars](https://img.shields.io/github/stars/Gabrielrtads/kage-bunshin?style=social)](https://github.com/Gabrielrtads/kage-bunshin/stargazers)

> ⭐ **If this jutsu saved you time or empowered your AI coding agents, please star this repository! It helps more developers discover the project.**

> **影分身の術 (Shadow Clone Technique) for AI Coding Agents.**  
> Spawn physical headless CLI clones of the **exact same agent** (e.g. 3x Claude Code, 3x Codex, or 3x Antigravity) or orchestrate a hybrid Shinobi Alliance across isolated Git Worktrees — with automatic memory reintegration on dispel and zero zombie processes.

---

## ⚡ The Breakthrough: Self-Cloning vs. Sequential Single-Turn AI

Modern AI coding agents (Claude Code, OpenAI Codex, Antigravity) are designed as **single-turn, single-process tools**. When a complex feature demands:
- 🧪 **Test-Driven Development (TDD)** in `tests/`
- ⚙️ **Core Logic Implementation** in `src/`
- 📚 **Documentation, Typings & OpenAPI Schemas** in `docs/`

Developers usually watch a single agent work sequentially, bottlenecking development and filling the context window with too many unrelated concerns.

**`kage-bunshin` brings the legendary Shadow Clone Jutsu to software engineering:**

```
                                  ┌──> Clone Alpha [Claude Code]: Writes Unit & Regression Tests (Worktree A)
                                  │
[🥷 Developer / Hokage Agent] ────┼──> Clone Beta  [Claude Code]: Implements Business Logic (Worktree B)
   (Chakra & Watchdog Pool)       │
                                  └──> Clone Gamma [Claude Code]: Refines Types, Docs & Schema (Worktree C)
                                                    │
                                                    ▼ (Dispel & Memory Reintegration)
                                       [Single Clean, Fully-Tested Feature]
```

---

## 🌀 Two Execution Philosophies

### 1. 🥷 The True Kage Bunshin (Mono-Engine Self-Cloning)
The agent spawns **3 physical clones of itself**. If you only have access to Claude Code (or Codex, or Gemini Flash), you don't need external orchestrators. The engine creates 3 isolated CLI workers of the same model:
- **Clone 1 (Alpha):** Scaffolds tests and mocks.
- **Clone 2 (Beta):** Writes implementation code until all tests pass.
- **Clone 3 (Gamma):** Handles documentation, styling, and strict typing.

Each clone works in its own physical Git Worktree (`.worktrees/task-...`), preventing file write collisions, merge locks, or corrupted git trees.

### 2. 🏯 The Shinobi Alliance (Cost-Smart Tri-Model Swarm)
Route tasks according to **capability vs. cost profile** to save 80%+ on AI token expenses:

| Shinobi CLI | Model | Cost Tier | Best Suited Missions |
|---|---|---|---|
| **Antigravity (`agy`)** | Gemini 3.5 Flash | 🟢 **Ultra-Low / Free Tier** | High-volume scanning, JSDoc generation, accessibility (WCAG) checks, test drafting. |
| **OpenAI Codex (`codex`)** | GPT-5 / Codex | 🟡 **Cost-Effective** | Fast backend APIs, SQL optimization, data migrations, script automation. |
| **Claude Code (`claude`)** | Claude 3.7 / Sonnet | 🟣 **Elite Reasoning** | Mission-critical architecture reviews, adversarial security audits, complex refactoring. |

---

## 🍥 The Ninja Lore vs. Terminal Reality

| Naruto Lore (影分身) | Software Architecture Parallel | Terminal Reality |
|---|---|---|
| **Chakra Partitioning** | **Token & RAM Throttling** | Distributes system memory and API limits evenly. Prevents system crash (OOM). |
| **Physical Solid Clones** | **Isolated Git Worktrees** | Clones are not fake chat prompts; they are real headless CLI processes in dedicated directories. |
| **Memory Reintegration (Dispel)** | **Git Fast-Forward & Merge** | When a clone finishes its mission, all code and test results are reintegrated back into the main branch. |
| **Rasenshuriken Compression** | **Concurrent Multi-Processing** | Compresses days of sequential coding into parallel minutes. |
| **Kinjutsu Guard** | **Anti-Deadlock Watchdog** | Closes standard input (`stdin`) immediately to prevent interactive prompts from hanging in infinite loops. |

---

## 🚀 Quick Start (1-Click Install via `skills.sh`)

Install directly into your AI coding assistant with one command:

```bash
npx skills add Gabrielrtads/kage-bunshin
```

Or install for specific agents:
```bash
# For Claude Code
npx skills add Gabrielrtads/kage-bunshin --agent claude-code

# For OpenAI Codex
npx skills add Gabrielrtads/kage-bunshin --agent codex

# For Google Antigravity
npx skills add Gabrielrtads/kage-bunshin --agent antigravity
```

---

## 💻 Usage & Missions

### 1. The True Kage Bunshin: 3 Clones of the Same Engine

Spawn 3 clones of Claude Code dividing a complete feature across isolated worktrees:

```bash
# Windows (PowerShell)
pwsh -File scripts/invoke-kage-bunshin.ps1 -ManifestPath examples/manifest-self-cloning.json

# Linux / macOS (Bash)
bash scripts/invoke-kage-bunshin.sh --manifest examples/manifest-self-cloning.json
```

**Manifest (`examples/manifest-self-cloning.json`):**
```json
[
  {
    "id": "clone-alpha-tdd",
    "engine": "claude",
    "mode": "execute",
    "worktree": true,
    "prompt": "Clone 1: Implement unit and regression tests in tests/ for the payment service."
  },
  {
    "id": "clone-beta-logic",
    "engine": "claude",
    "mode": "execute",
    "worktree": true,
    "prompt": "Clone 2: Implement core business logic in src/payment.ts to satisfy all tests."
  },
  {
    "id": "clone-gamma-docs",
    "engine": "claude",
    "mode": "execute",
    "worktree": true,
    "prompt": "Clone 3: Update OpenAPI specs, TypeScript types, and documentation."
  }
]
```

---

### 2. The Shinobi Alliance (Cost-Smart Hybrid Swarm)

Run a tri-model swarm combining Gemini Flash, Codex, and Claude:

```bash
pwsh -File scripts/invoke-kage-bunshin.ps1 -ManifestPath examples/manifest-cost-smart-swarm.json
```

---

### 3. Direct JSON Invocation (Inline Jutsus)

```bash
pwsh -File scripts/invoke-kage-bunshin.ps1 -ManifestJson '[
  {"id": "c1", "engine": "claude", "worktree": true, "prompt": "Audit auth.ts"},
  {"id": "c2", "engine": "claude", "worktree": true, "prompt": "Audit stripe.ts"}
]'
```

---

## 📋 Parameter Reference

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-ManifestPath` | `string` | `$null` | Path to a UTF-8 JSON manifest file containing task definitions. |
| `-ManifestJson` | `string` | `$null` | Raw JSON string representing the task array. |
| `-Engine` | `string` | `'agy'` | Default engine (`claude`, `codex`, `agy`) when omitted in a task. |
| `-MaxConcurrency` | `int` | `8` | Maximum number of processes running concurrently (protects chakra / RAM). |
| `-TimeoutSeconds` | `int` | `900` | Global watchdog timeout in seconds before aborting stuck tasks. |
| `-UseWorktreeForEdits`| `switch` | `false` | Automatically creates isolated Git worktrees for tasks in `execute` mode. |
| `-Json` | `switch` | `false` | Output aggregated report in clean structured JSON format. |

---

## 🇧🇷 Documentação em Português

### O que é o `kage-bunshin`?
É um motor de **auto-clonagem e execução concorrente para CLIs de Inteligência Artificial** (`claude`, `codex` e `agy`). Inspirado no clássico *Kage Bunshin no Jutsu* de Naruto, ele resolve a lentidão das execuções sequenciais permitindo que um agente crie **3 clones físicos de si mesmo** (ou uma aliança com múltiplos motores) trabalhando simultaneamente em pastas isoladas via Git Worktrees.

### 🥷 Os Dois Modos de Operação:
1. **O Verdadeiro Kage Bunshin (Mono-Engine):** Você usa apenas o Claude Code (ou apenas Codex/Antigravity) e spawna 3 instâncias idênticas em paralelo. Um clone cuida dos testes, outro da lógica e o terceiro da documentação/tipos.
2. **Aliança Shinobi (Custo-Inteligente):** Distribui o trabalho por faixa de custo (Gemini Flash para varredura em massa a custo zero, Codex para scripts e backend, Claude para arquitetura e segurança crítica).

### 🛡️ Proteção de Chakra (Watchdog Anti-Deadlock):
- **Sem Travamentos:** O script fecha o `stdin` imediatamente após o disparo do prompt, impedindo que o terminal congele aguardando confirmações interativas.
- **Isolamento Total:** Cada clone edita seu próprio diretório físico (`.worktrees/`), eliminando conflitos de merge e arquivos sobrescritos.
- **Reintegração de Memória:** Ao concluir, o trabalho é integrado de volta à branch principal e as worktrees vazias são podadas automaticamente.

---

## 📄 License

MIT © [Gabriel Toledo](https://github.com/Gabrielrtads)
