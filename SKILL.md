---
name: kage-bunshin
description: Kage Bunshin no Jutsu (影分身の術) for AI coding agents. Spawn real headless CLI clones of the same agent (e.g. 3x Claude Code, 3x Codex, 3x Antigravity) or hybrid multi-model shinobis in isolated Git Worktrees with memory reintegration on dispel.
category: orchestration
tags: [kage-bunshin, multi-agent, swarm, git-worktrees, self-cloning, claude-code, codex, antigravity]
---

# 🥷⚡ Kage Bunshin (`kage-bunshin`)

> **影分身の術 (Shadow Clone Jutsu) for AI Coding Agents.**  
> Spawn physical headless CLI clones of the **exact same agent** (e.g., 3x Claude Code, 3x Codex, 3x Antigravity) or a hybrid Shinobi Alliance across isolated Git Worktrees. Reintegrate code and memory seamlessly on dispel without exhausting system chakra (RAM/Tokens).

---

## ⚡ When to Use

- **Mono-Engine Multi-Cloning (The True Kage Bunshin):** When you want a single agent CLI (like Claude Code) to spawn **3 clones of itself** to divide and conquer:
  - Clone 1: Test-Driven Development & unit suites (`tests/`).
  - Clone 2: Core component / business logic implementation (`src/`).
  - Clone 3: Documentation, TypeScript strict typing & styles.
- **Shinobi Alliance (Cost-Smart Hybrid Swarm):** Route high-volume scanning to zero/low-cost Gemini Flash (`agy`) and reserve Claude Code (`claude`) or Codex (`codex`) for deep reasoning and critical execution.
- **Parallel Code Audits:** Concurrently run Security + Performance + Accessibility reviews without terminal freezes.
- **Isolated Worktree Safety:** Ensure each clone works in its own physical Git branch/worktree, preventing merge conflicts and race conditions.

---

## 🚀 Quick Usage

### 1. The True Kage Bunshin: 3 Clones of the Same CLI

Spawn 3 clones of Claude Code (or Codex / Antigravity) running simultaneously in isolated worktrees:

```bash
# PowerShell (Windows)
pwsh -File scripts/invoke-kage-bunshin.ps1 -ManifestPath examples/manifest-self-cloning.json

# Bash (Linux/macOS)
bash scripts/invoke-kage-bunshin.sh --manifest examples/manifest-self-cloning.json
```

### 2. Passing Clones Directly via JSON

```bash
pwsh -File scripts/invoke-kage-bunshin.ps1 -ManifestJson '[
  {"id": "clone-1", "engine": "claude", "worktree": true, "prompt": "Write unit tests for auth service"},
  {"id": "clone-2", "engine": "claude", "worktree": true, "prompt": "Implement auth token validation logic"},
  {"id": "clone-3", "engine": "claude", "worktree": true, "prompt": "Update OpenAPI schema and documentation"}
]'
```

### 3. Shinobi Alliance: Cost-Smart Hybrid Swarm

```bash
pwsh -File scripts/invoke-kage-bunshin.ps1 -ManifestPath examples/manifest-cost-smart-swarm.json
```

---

## 📋 Parameter Reference

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-ManifestPath` | `string` | `$null` | Path to a UTF-8 JSON manifest file containing an array of clone tasks. |
| `-ManifestJson` | `string` | `$null` | Raw JSON string representing the clone task array. |
| `-Engine` | `string` | `'agy'` | Default engine (`claude`, `codex`, `agy`) when not specified per clone. |
| `-MaxConcurrency` | `int` | `8` | Maximum number of simultaneous clones running concurrently (prevents chakra exhaustion). |
| `-TimeoutSeconds` | `int` | `900` | Global watchdog timeout in seconds before terminating hung clones. |
| `-UseWorktreeForEdits`| `switch` | `false` | Automatically creates isolated Git worktrees for tasks in `execute` mode. |
| `-Json` | `switch` | `false` | Output final report in clean structured JSON format. |

---

## 🛡️ Shinobi Guardrails (Anti-Deadlock & Chakra Protection)

1. **Anti-Deadlock Stdin:** Standard input (`stdin`) is closed immediately after passing the mission prompt, preventing terminal freezes and prompt loops.
2. **Worktree Hygiene (Dispel):** Ephemeral worktrees that remain untouched (zero commits and zero diffs) are automatically pruned upon completion.
3. **Chakra Guard (Fail-Closed):** Duplicate task IDs, path traversals, or invalid engine declarations are rejected before spawning any background processes, protecting system memory and API limits.
