---
name: kage-bunshin
description: Kage Bunshin no Jutsu (影分身の術) for AI coding agents. Spawn N real headless CLI clones of the same agent (e.g. Nx Claude Code, Nx Codex, Nx Antigravity) or hybrid multi-model shinobis in isolated Git Worktrees with memory reintegration on dispel.
category: orchestration
tags: [kage-bunshin, multi-agent, swarm, git-worktrees, self-cloning, claude-code, codex, antigravity]
---

# 🥷⚡ Kage Bunshin (`kage-bunshin`)

> **影分身の術 (Shadow Clone Jutsu) for AI Coding Agents.**  
> Spawn physical headless CLI clones of the **exact same agent** (e.g., $N$x Claude Code, $N$x Codex, $N$x Antigravity) or an extended Shinobi Alliance across isolated Git Worktrees. Reintegrate code and memory seamlessly on dispel without exhausting system chakra (RAM/Tokens).

---

## ⚡ When to Use & Team Sizing

- **Arbitrary $N$-Clone Scaling (The True Kage Bunshin):** Spawn as many parallel clones as your mission requires (2, 3, 5, 8+ clones), bounded only by your machine's CPU/RAM and API rate limits (`-MaxConcurrency`, default `8`, supports up to `32`).
  - **The Canonical Triad (Classic Example):**
    - Clone 1 (Alpha): Test-Driven Development & unit suites (`tests/`).
    - Clone 2 (Beta): Core component / business logic implementation (`src/`).
    - Clone 3 (Gamma): Documentation, OpenAPI schema & TypeScript strict typing.
  - **Full-Stack Squad ($N = 5+$ Clones):**
    - Clone 1: Data model & DB migrations / RLS policies.
    - Clone 2: Backend API endpoints & handlers.
    - Clone 3: Frontend UI components & Tailwind styles.
    - Clone 4: End-to-End & regression test suite.
    - Clone 5: Performance audit, accessibility & documentation.
- **Shinobi Alliance (Cost-Smart Hybrid Swarm):** Route high-volume scanning to zero/low-cost Gemini 3.8 Flash (`agy`), database optimization to GPT-6.1 Sol (`codex`), and reserve Claude Sonnet 5.5 / Opus 5.5 (`claude`) for deep architecture, adversarial security and critical execution.
- **Parallel Code Audits:** Concurrently run Security + Performance + Accessibility + Typings reviews without terminal freezes.
- **Isolated Worktree Safety:** Ensure each clone works in its own physical Git branch/worktree, preventing merge conflicts and race conditions.

---

## 🚀 Quick Usage

### 1. The True Kage Bunshin: $N$ Clones of the Same CLI

Spawn clones of Claude Code (or Codex / Antigravity) running simultaneously in isolated worktrees:

```bash
# PowerShell (Windows)
pwsh -File scripts/invoke-kage-bunshin.ps1 -ManifestPath examples/manifest-self-cloning.json

# Bash (Linux/macOS)
bash scripts/invoke-kage-bunshin.sh --manifest examples/manifest-self-cloning.json
```

### 2. Passing Arbitrary $N$-Clones Directly via JSON

```bash
pwsh -File scripts/invoke-kage-bunshin.ps1 -ManifestJson '[
  {"id": "c1-tdd", "engine": "claude", "worktree": true, "prompt": "Write unit tests for auth service in tests/"},
  {"id": "c2-logic", "engine": "claude", "worktree": true, "prompt": "Implement auth token validation in src/auth.ts"},
  {"id": "c3-ui", "engine": "claude", "worktree": true, "prompt": "Implement login modal and UI forms"},
  {"id": "c4-e2e", "engine": "claude", "worktree": true, "prompt": "Scaffold Playwright E2E browser tests"},
  {"id": "c5-docs", "engine": "claude", "worktree": true, "prompt": "Update OpenAPI schema and docs/auth.md"}
]'
```

### 3. Shinobi Alliance: Cost-Smart Frontier Hybrid Swarm

```bash
pwsh -File scripts/invoke-kage-bunshin.ps1 -ManifestPath examples/manifest-cost-smart-swarm.json
```

### 4. Surgical MCP Scoping per Clone (Tool Chakra Partitioning)

Assign only the necessary MCP servers per clone to eliminate tool confusion, prevent accidental mutations, and save 15,000–30,000 prompt tokens per clone:

```json
[
  { "id": "c1-db", "engine": "codex", "worktree": true, "mcp_servers": ["supabase"], "prompt": "Create database migration" },
  { "id": "c2-ui", "engine": "claude", "worktree": true, "mcp_servers": ["playwright"], "prompt": "Verify responsive UI layout" },
  { "id": "c3-audit", "engine": "agy", "worktree": false, "mcp_servers": [], "prompt": "Security audit (Zero MCPs needed)" }
]
```

---

## 📋 Parameter Reference

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-ManifestPath` | `string` | `$null` | Path to a UTF-8 JSON manifest file containing an array of clone tasks ($N$ tasks). |
| `-ManifestJson` | `string` | `$null` | Raw JSON string representing the clone task array ($N$ tasks). |
| `-Engine` | `string` | `'agy'` | Default engine (`claude`, `codex`, `agy`) when not specified per clone. |
| `-MaxConcurrency` | `int` | `8` | Maximum number of simultaneous clones running concurrently (range 1-32; protects chakra/RAM). |
| `-TimeoutSeconds` | `int` | `900` | Global watchdog timeout in seconds before terminating hung clones. |
| `-UseWorktreeForEdits`| `switch` | `false` | Automatically creates isolated Git worktrees for tasks in `execute` mode. |
| `-Json` | `switch` | `false` | Output final report in clean structured JSON format. |

---

## 🛡️ Shinobi Guardrails (Anti-Deadlock & Chakra Protection)

1. **Anti-Deadlock Stdin:** Standard input (`stdin`) is closed immediately after passing the mission prompt, preventing terminal freezes and prompt loops.
2. **Worktree Hygiene (Dispel):** Ephemeral worktrees that remain untouched (zero commits and zero diffs) are automatically pruned upon completion.
3. **Chakra Guard (Fail-Closed):** Duplicate task IDs, path traversals, or invalid engine declarations are rejected before spawning any background processes, protecting system memory and API limits.
4. **Controlled Concurrency Pool:** Even if a mission defines 20 clones, `-MaxConcurrency` (default 8) throttles execution so system RAM and OS process tables remain stable.
