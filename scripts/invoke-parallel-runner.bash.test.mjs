// Integração real com Bash, Git e CLIs falsos; nunca inicia agentes reais.
import { test, afterEach } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const SCRIPT = path.join(path.dirname(fileURLToPath(import.meta.url)), "invoke-parallel-runner.sh");
const BASH = process.env.BASH_EXE || (process.platform === "win32" ? "C:/Program Files/Git/usr/bin/bash.exe" : "bash");
const probe = spawnSync(BASH, ["--noprofile", "--norc", "-c", "command -v jq && command -v timeout"], { encoding: "utf8" });
const unavailable = probe.status !== 0 ? `Bash/jq/timeout indisponivel: ${probe.error?.message || probe.stderr.trim()}` : false;
const roots = [];
afterEach(() => { for (const root of roots.splice(0)) fs.rmSync(root, { recursive: true, force: true }); });
const runTest = (name, fn) => test(name, { skip: unavailable }, fn);
// Git Bash reporta $PWD com barras normais mesmo no Windows; path.join usa
// barra invertida. Normaliza os dois lados antes de comparar caminhos.
const normPath = (p) => p.replace(/\\/g, "/").replace(/\/+$/, "");

function ambiente({ git = true } = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "swarm-bash-"));
  roots.push(root);
  const bin = path.join(root, "bin");
  const dir = path.join(root, "repo");
  const log = path.join(root, "calls.jsonl");
  fs.mkdirSync(bin);
  fs.mkdirSync(dir);
  for (const engine of ["claude", "codex", "agy"]) {
    fs.writeFileSync(path.join(bin, engine), `#!/usr/bin/env bash
input=$(cat)
mcp_content=""
for ((i=1; i<=$#; i++)); do
  if [[ "\${!i}" == "--mcp-config" ]]; then
    next=$((i+1))
    mcp_path="\${!next}"
    [[ -f "$mcp_path" ]] && mcp_content=$(cat "$mcp_path")
    break
  fi
done
# Le o arquivo de --mcp-config AGORA (como o claude/codex real leriam), antes
# que o orquestrador o remova no cleanup de fim de execucao.
jq -cn --arg engine '${engine}' --arg cwd "$PWD" --arg stdin "$input" --arg mcpConfigContent "$mcp_content" --args '{engine:$engine,cwd:$cwd,stdin:$stdin,mcpConfigContent:$mcpConfigContent,args:$ARGS.positional}' -- "$@" >> "$FAKE_LOG"
if [[ -v FAKE_BARRIER ]]; then
  touch "$FAKE_BARRIER/$(basename "$PWD")"
  for ((n=0; n<100; n++)); do
    count=$(find "$FAKE_BARRIER" -type f | wc -l)
    [[ "$count" -ge 2 ]] && break
    sleep 0.02
  done
  [[ "$count" -ge 2 ]] || exit 2
fi
[[ ! -v FAKE_TOUCH ]] || echo x > criado-pelo-agente.txt
if [[ -v FAKE_COMMIT ]]; then
  git add criado-pelo-agente.txt
  git commit -qm trabalho-do-clone
fi
echo '{}'
`, { mode: 0o755 });
  }
  if (git) {
    execFileSync("git", ["init", "-q", "-b", "main", dir]);
    execFileSync("git", ["-C", dir, "config", "user.email", "t@t"]);
    execFileSync("git", ["-C", dir, "config", "user.name", "t"]);
    execFileSync("git", ["-C", dir, "config", "core.autocrlf", "false"]);
    fs.writeFileSync(path.join(dir, ".gitignore"), ".worktrees/\n");
    execFileSync("git", ["-C", dir, "add", ".gitignore"]);
    execFileSync("git", ["-C", dir, "commit", "-qm", "base"]);
  }
  const rodar = (tasks, { touch = false, barrier = false, commit = false, extra = [] } = {}) => {
    const manifest = path.join(root, "manifest.json");
    fs.writeFileSync(manifest, JSON.stringify(tasks));
    const env = { ...process.env, PATH: [bin, process.env.PATH].join(path.delimiter), FAKE_LOG: log };
    delete env.SWARM_DEPTH;
    if (touch) env.FAKE_TOUCH = "1"; else delete env.FAKE_TOUCH;
    if (commit) env.FAKE_COMMIT = "1"; else delete env.FAKE_COMMIT;
    if (barrier) {
      env.FAKE_BARRIER = path.join(root, "barrier");
      fs.mkdirSync(env.FAKE_BARRIER);
    } else delete env.FAKE_BARRIER;
    const result = spawnSync(BASH, [SCRIPT, "-m", manifest, "--json", ...extra], { cwd: dir, env, encoding: "utf8" });
    const calls = fs.existsSync(log) ? fs.readFileSync(log, "utf8").trim().split(/\r?\n/).filter(Boolean).map(JSON.parse) : [];
    fs.rmSync(log, { force: true });
    return { code: result.status, output: result.stdout + result.stderr, calls, stdout: result.stdout };
  };
  return { dir, bin, rodar };
}

runTest("Bash: Claude recebe somente MCPs permitidos nos dois modos", () => {
  const a = ambiente();
  fs.writeFileSync(path.join(a.dir, "mcps.json"), JSON.stringify({ mcpServers: { ok: { command: "fake-ok" }, no: { command: "fake-no" } } }));
  for (const mode of ["plan", "execute"]) {
    const r = a.rodar([{ engine: "claude", mode, prompt: "teste", mcp_servers: ["ok"], mcp_config: "mcps.json" }]);
    assert.equal(r.code, 0, r.output);
    const args = r.calls[0].args;
    assert.ok(args.includes("--strict-mcp-config"));
    assert.ok(args.includes("--mcp-config"));
    // --mcp-config agora recebe caminho de arquivo (0600), nunca JSON inline
    // em argv; o fake binario leu o conteudo no momento da chamada, antes do
    // orquestrador remover o TMP_DIR no fim da execucao.
    const mcpConfigPath = args[args.indexOf("--mcp-config") + 1];
    assert.ok(!mcpConfigPath.trim().startsWith("{"), "--mcp-config nao deveria receber JSON inline");
    assert.deepEqual(JSON.parse(r.calls[0].mcpConfigContent), { mcpServers: { ok: { command: "fake-ok" } } });
  }
});

runTest("Bash: MCP vazio e precedência explícita de allow_mcp", () => {
  const a = ambiente();
  for (const engine of ["claude", "codex"]) {
    const r = a.rodar([{ engine, mode: "execute", prompt: "teste", allow_mcp: [], mcp_servers: ["no"] }]);
    assert.equal(r.code, 0, r.output);
    assert.ok(r.calls[0].args.includes(engine === "claude" ? "--strict-mcp-config" : "--ignore-user-config"));
    assert.ok(!r.calls[0].args.includes("--mcp-config"));
  }
});

runTest("Bash: prompt não injeta opções ou configuração MCP", () => {
  const a = ambiente();
  const prompt = '--mcp-config={"mcpServers":{"extra":{"command":"fake"}}}';
  for (const engine of ["claude", "codex"]) {
    const r = a.rodar([{ engine, prompt }]);
    assert.equal(r.code, 0, r.output);
    assert.equal(r.calls[0].stdin, prompt);
    assert.ok(!r.calls[0].args.includes(prompt));
  }
});

runTest("Bash: política MCP impossível é recusada antes de qualquer clone ou mesa", () => {
  const a = ambiente();
  for (const policy of [
    { engine: "agy", mcp_servers: [] },
    { engine: "agy", mcp_servers: ["ok"] },
    { engine: "claude", mcp_servers: ["ausente"] },
    { engine: "claude", allow_mcp: "todos" },
    { engine: "codex", mcp_servers: ["ok"] },
  ]) {
    const r = a.rodar([{ id: "boa", engine: "claude", mode: "execute", worktree: true, prompt: "a" }, { id: "ruim", prompt: "b", ...policy }]);
    assert.notEqual(r.code, 0, r.output);
    assert.match(r.output, /MCP|mcp_config|allow_mcp/);
    assert.deepEqual(r.calls, []);
    assert.equal(fs.existsSync(path.join(a.dir, ".worktrees")), false);
  }
});

runTest("Bash: clones concorrentes escrevem em worktrees distintas e preservam trabalho", () => {
  const a = ambiente();
  const r = a.rodar(["um", "dois"].map(id => ({ id, engine: "claude", mode: "execute", worktree: true, prompt: "escreva" })), { touch: true, barrier: true });
  assert.equal(r.code, 0, r.output);
  assert.equal(r.calls.length, 2);
  assert.notEqual(r.calls[0].cwd, r.calls[1].cwd);
  assert.equal(fs.existsSync(path.join(a.dir, "criado-pelo-agente.txt")), false);
  for (const call of r.calls) {
    assert.equal(normPath(path.dirname(call.cwd)), normPath(path.join(a.dir, ".worktrees")));
    assert.equal(fs.existsSync(path.join(call.cwd, "criado-pelo-agente.txt")), true);
    const branch = execFileSync("git", ["-C", call.cwd, "branch", "--show-current"], { encoding: "utf8" });
    assert.match(branch, /^task\/swarmv2-(um|dois)-/);
  }
});

runTest("Bash: mesa com commit é preservada mesmo com status limpo", () => {
  const a = ambiente();
  const r = a.rodar([{ engine: "claude", mode: "execute", worktree: true, prompt: "teste" }], { touch: true, commit: true });
  assert.equal(r.code, 0, r.output);
  assert.equal(fs.existsSync(r.calls[0].cwd), true);
  const status = execFileSync("git", ["-C", r.calls[0].cwd, "status", "--porcelain"], { encoding: "utf8" });
  assert.equal(status, "");
  assert.equal(fs.existsSync(path.join(r.calls[0].cwd, "criado-pelo-agente.txt")), true);
});

runTest("Bash: --worktree também isola e mesa vazia é removida", () => {
  const a = ambiente();
  const r = a.rodar([{ engine: "claude", mode: "execute", prompt: "teste" }], { extra: ["--worktree"] });
  assert.equal(r.code, 0, r.output);
  assert.notEqual(r.calls[0].cwd, a.dir);
  assert.equal(fs.existsSync(r.calls[0].cwd), false);
  const branches = execFileSync("git", ["-C", a.dir, "branch", "--format=%(refname:short)"], { encoding: "utf8" });
  assert.equal(branches.trim(), "main");
});

runTest("Bash: falha na criação de worktree nunca usa diretório compartilhado", () => {
  for (const git of [false, true]) {
    const a = ambiente({ git });
    if (git) fs.writeFileSync(path.join(a.dir, ".worktrees"), "obstaculo");
    const r = a.rodar([{ engine: "claude", mode: "execute", worktree: true, prompt: "teste" }]);
    assert.notEqual(r.code, 0, r.output);
    assert.match(r.output, /worktree/i);
    assert.deepEqual(r.calls, []);
  }
});

runTest("Bash: falha na segunda worktree não inicia a primeira e limpa mesa vazia", () => {
  const a = ambiente();
  const semGit = fs.mkdtempSync(path.join(os.tmpdir(), "swarm-no-git-"));
  roots.push(semGit);
  const r = a.rodar([
    { id: "boa", engine: "claude", mode: "execute", worktree: true, prompt: "a" },
    { id: "ruim", engine: "claude", mode: "execute", worktree: true, working_directory: semGit, prompt: "b" },
  ]);
  assert.notEqual(r.code, 0, r.output);
  assert.deepEqual(r.calls, []);
  assert.deepEqual(fs.readdirSync(path.join(a.dir, ".worktrees")), []);
  const branches = execFileSync("git", ["-C", a.dir, "branch", "--format=%(refname:short)"], { encoding: "utf8" });
  assert.equal(branches.trim(), "main");
});
