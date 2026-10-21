# 🐝⚡ Vibe Swarm (`vibe-swarm`)

[![skills.sh compatible](https://img.shields.io/badge/skills.sh-compatible-6366f1?style=for-the-badge)](https://skills.sh)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)](LICENSE)
[![Zero-Dependency](https://img.shields.io/badge/Dependencies-Zero-emerald?style=for-the-badge)](#)
[![Multi-CLI](https://img.shields.io/badge/Supports-Claude_|_Codex_|_Antigravity-orange?style=for-the-badge)](#)

> **High-Performance Concurrent Execution Engine & Anti-Deadlock Watchdog for Developer AI CLIs.**  
> Run batch tasks, multi-perspective code audits, and parallel feature branches across **Claude Code**, **OpenAI Codex**, and **Antigravity CLI** simultaneously — without hanging terminals or zombie processes.

---

## ⚡ The Problem: Sequential CLI Friction

Modern AI coding assistants (Claude Code, Codex, Antigravity) are designed as **interactive, single-turn terminal tools**.

When you need to:
- Run **multi-agent code reviews** (Security + Performance + Accessibility)
- Execute **parallel refactorings** or batch migrations
- Test competing model implementations side-by-side

Developers are forced to manually open multiple terminal tabs or resort to hacky background bash scripts (`&`) that **hang on interactive prompts**, **leak memory**, or **collide on shared files**.

---

## 💡 The Solution: Fan-Out / Fan-In Engine with Active Watchdogs

`vibe-swarm` treats your local CLI engines as headless concurrent workers. It provides process-level orchestration with strict safety controls:

```
                           ┌──> [Worker 1: Claude Code]   ──> Security Audit (Plan Mode)
                           │
[JSON Task Manifest] ──────┼──> [Worker 2: OpenAI Codex]  ──> SQL Optimization (Plan Mode)
 (Throttling: Max 8 Procs) │
                           └──> [Worker 3: Antigravity]   ──> Mobile Responsive Fix (Worktree)
                                           │
                                           ▼ (Fan-In Aggregator)
                           [Unified Structured JSON Output]
```

1. **Active Concurrency Throttling:** Configurable execution pool (`-MaxConcurrency 8` by default) prevents CPU spikes and upstream API saturation.
2. **Anti-Deadlock Stdin Contract:** Closes standard input (`stdin`) immediately after dispatching the prompt, eliminating infinite hangs on unprompted approvals.
3. **Collision-Free Git Worktrees:** Automatically isolates write tasks (`mode: "execute"`) into dedicated Git worktrees (`task/swarmv2-...`).
4. **Zero-Zombie Guarantee:** Process-tree watchdog terminates hanging subprocesses cleanly upon individual or global timeout. Untouched ephemeral worktrees are automatically cleaned up.

---

## 🚀 Quick Start (1-Click Install via `skills.sh`)

Install directly into your agent environment using the open Skills CLI:

```bash
npx skills add Gabrielrtads/vibe-swarm
```

Or install for specific agents:
```bash
# For Claude Code
npx skills add Gabrielrtads/vibe-swarm --agent claude-code

# For OpenAI Codex
npx skills add Gabrielrtads/vibe-swarm --agent codex

# For Google Antigravity
npx skills add Gabrielrtads/vibe-swarm --agent antigravity
```

---

## 💻 Usage & Examples

### 1. Run a Concurrent Multi-Perspective Audit

Create a manifest file (`manifest.json`):

```json
[
  {
    "id": "audit_security",
    "engine": "claude",
    "mode": "plan",
    "effort": "high",
    "prompt": "Audit src/auth.ts and Supabase RLS policies for privilege escalation."
  },
  {
    "id": "audit_perf",
    "engine": "codex",
    "mode": "plan",
    "effort": "medium",
    "prompt": "Analyze database queries in src/db/ and identify N+1 query bottlenecks."
  },
  {
    "id": "audit_a11y",
    "engine": "agy",
    "mode": "plan",
    "effort": "low",
    "prompt": "Verify WCAG 2.1 compliance for navigation components in src/components/."
  }
]
```

Execute the batch concurrently:

```bash
# Windows (PowerShell)
pwsh -File scripts/invoke-vibe-swarm.ps1 -ManifestPath manifest.json

# Linux / macOS (Bash)
bash scripts/invoke-vibe-swarm.sh --manifest manifest.json
```

---

### 2. Parallel Code Generation with Worktree Isolation

When tasks write to disk, enable `-UseWorktreeForEdits` to run each agent in an isolated Git worktree:

```json
[
  {
    "id": "ui_nav",
    "engine": "claude",
    "mode": "execute",
    "worktree": true,
    "prompt": "Create a responsive mobile navigation drawer in src/components/NavDrawer.tsx"
  },
  {
    "id": "api_checkout",
    "engine": "codex",
    "mode": "execute",
    "worktree": true,
    "prompt": "Implement the Stripe checkout session handler in src/api/checkout.ts"
  }
]
```

Run with isolated worktrees:

```bash
pwsh -File scripts/invoke-vibe-swarm.ps1 -ManifestPath manifest.json -UseWorktreeForEdits
```

Upon completion, each branch is ready for review or merging without git conflicts.

---

### 3. Pipeline Integration (Structured JSON Output)

Pass `-Json` to feed the aggregated result into CI/CD pipelines, dashboards, or parent orchestrators:

```bash
pwsh -File scripts/invoke-vibe-swarm.ps1 -ManifestPath manifest.json -Json
```

**Output schema:**
```json
{
  "summary": {
    "total_tasks": 3,
    "success": 3,
    "failed": 0,
    "timeout": 0,
    "duration_seconds": 14.82
  },
  "tasks": [
    {
      "id": "audit_security",
      "engine": "claude",
      "status": "success",
      "exit_code": 0,
      "duration_seconds": 12.3,
      "output": { ... }
    }
  ]
}
```

---

## 🛡️ Parameter Reference

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-ManifestPath` | `string` | `$null` | Path to a UTF-8 JSON manifest file containing task definitions. |
| `-ManifestJson` | `string` | `$null` | Raw JSON string representing the task array. |
| `-Engine` | `string` | `'agy'` | Default engine (`claude`, `codex`, `agy`) when omitted in a task. |
| `-MaxConcurrency` | `int` | `8` | Maximum number of processes running concurrently. |
| `-TimeoutSeconds` | `int` | `900` | Global watchdog timeout in seconds before aborting running tasks. |
| `-UseWorktreeForEdits`| `switch` | `false` | Automatically creates isolated Git worktrees for tasks in `execute` mode. |
| `-Json` | `switch` | `false` | Output aggregated report in clean structured JSON format. |

---

## 🇧🇷 Documentação em Português

### O que é o `vibe-swarm`?
É um motor de **execução concorrente e paralela para CLIs de inteligência artificial** (`claude`, `codex` e `agy`). Ele resolve o gargalo de rodar tarefas sequencialmente, permitindo disparar lotes de prompts, auditorias multi-modelo e refatorações simultâneas no seu terminal.

### Destaques:
- **Watchdog Anti-Deadlock:** Fecha o canal de entrada (`stdin`) logo após enviar o prompt, impedindo que os agentes travem aguardando inputs fantasmas.
- **Isolamento por Git Worktree:** Permite que 3 agentes editem o código ao mesmo tempo em pastas isoladas sem colisão na branch principal.
- **Throttling Inteligente:** Limita a concorrência (`MaxConcurrency: 8`) para não estourar a memória RAM ou as cotas de API.
- **Multiplataforma:** Suporte nativo para Windows (`.ps1`) e Linux/macOS (`.sh`).

---

## 📄 License

MIT © [Gabriel Toledo](https://github.com/Gabrielrtads)
