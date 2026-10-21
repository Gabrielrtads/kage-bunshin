---
name: parallel-agent-runner
description: High-performance concurrent runner and watchdog for Claude Code, OpenAI Codex, and Antigravity CLIs. Run multi-agent batch tasks, parallel code reviews, and JSON manifests without terminal deadlocks or zombie processes.
category: orchestration
---

# Parallel Agent Runner (`parallel-agent-runner`)

> **Concurrent CLI Agent Execution Engine with Anti-Deadlock Watchdogs & Isolated Worktrees.**  
> Orchestrate multiple **Claude Code**, **OpenAI Codex**, and **Antigravity CLI** instances in parallel directly from your terminal or AI workflows.

---

## ⚡ When to Use

- When you have **2 or more independent tasks** that can run simultaneously without sequential dependencies.
- To execute multi-perspective code audits (Security + Performance + Accessibility) in parallel.
- To run batch migrations, code translations, or multi-component generation across isolated Git worktrees.
- To collect structured JSON-RPC output from multiple agent executions into a unified summary.

---

## 🚀 Quick Usage

### 1. Running from a JSON Manifest

```bash
# PowerShell (Windows)
pwsh -File scripts/invoke-parallel-runner.ps1 -ManifestPath examples/manifest-parallel-tasks.json

# Bash (Linux/macOS)
bash scripts/invoke-parallel-runner.sh --manifest examples/manifest-parallel-tasks.json
```

### 2. Passing Tasks Directly via JSON

```bash
pwsh -File scripts/invoke-parallel-runner.ps1 -ManifestJson '[
  {"id": "task1", "engine": "claude", "prompt": "Audit src/auth.ts"},
  {"id": "task2", "engine": "codex", "prompt": "Audit src/database.ts"}
]'
```

### 3. Parallel Execution with Isolated Git Worktrees

For tasks that edit or generate code (`mode: "execute"`), enable worktree isolation to avoid file write collisions:

```bash
pwsh -File scripts/invoke-parallel-runner.ps1 -ManifestPath tasks.json -UseWorktreeForEdits
```

---

## 📋 Parameter Reference

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-ManifestPath` | `string` | `$null` | Path to a UTF-8 JSON manifest file containing an array of tasks. |
| `-ManifestJson` | `string` | `$null` | Raw JSON string representing the task array. |
| `-Engine` | `string` | `'agy'` | Default engine (`claude`, `codex`, `agy`) when not specified per task. |
| `-MaxConcurrency` | `int` | `8` | Maximum number of simultaneous agent processes running concurrently. |
| `-TimeoutSeconds` | `int` | `900` | Global watchdog timeout in seconds before aborting stuck tasks. |
| `-UseWorktreeForEdits`| `switch` | `false` | Automatically creates isolated Git worktrees for tasks in `execute` mode. |
| `-Json` | `switch` | `false` | Output final report in clean structured JSON format. |

---

## 🛡️ Core Guardrails

1. **Anti-Deadlock Stdin:** Standard input (`stdin`) is closed immediately after passing the prompt, preventing terminal freezes and hanging prompts.
2. **Worktree Hygiene:** Ephemeral worktrees that remain untouched (zero commits and zero unstaged diffs) are automatically pruned upon completion.
3. **Fail-Closed Validation:** Duplicate task IDs, path traversals, or invalid engine declarations are rejected before spawning any background processes.
