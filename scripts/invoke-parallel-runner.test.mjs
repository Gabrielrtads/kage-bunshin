// Testa o invoke-parallel-runner.ps1 com CLIs falsos que só registram os argumentos.
import { test, afterEach } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const SCRIPT = process.env.RUNNER_UNDER_TEST || path.join(path.dirname(fileURLToPath(import.meta.url)), "invoke-parallel-runner.ps1");
const onde = (exe) => path.dirname(execFileSync("where.exe", [exe], { encoding: "utf8" }).split(/\r?\n/)[0]);
const PATH_BASE = [onde("git"), onde("pwsh"), path.join(process.env.SystemRoot, "System32")];
const raizes = [];
afterEach(() => { for (const raiz of raizes.splice(0)) fs.rmSync(raiz, { recursive: true, force: true }); });

function ambiente() {
  const raiz = fs.mkdtempSync(path.join(os.tmpdir(), "swarmv2-"));
  raizes.push(raiz);
  const falsos = path.join(raiz, "bin");
  fs.mkdirSync(falsos);
  for (const nome of ["claude", "codex", "agy"]) {
    fs.writeFileSync(path.join(falsos, `${nome}.ps1`), [
      `$registro = @{ engine = '${nome}'; args = @($args); cwd = (Get-Location).Path; stdin = [Console]::In.ReadToEnd() }`,
      '$registro | ConvertTo-Json -Compress -Depth 10 | Set-Content -LiteralPath ($env:FAKE_LOG + "." + $PID + ".json")',
      'if ($env:FAKE_TOUCH) { Set-Content criado-pelo-agente.txt x }',
      "'{}'",
    ].join("\n"));
  }
  const log = path.join(raiz, "chamadas.log");
  const dir = path.join(raiz, "repo");
  execFileSync("git", ["init", "-q", "-b", "main", dir]);
  execFileSync("git", ["-C", dir, "config", "user.email", "t@t"]);
  execFileSync("git", ["-C", dir, "config", "user.name", "t"]);
  execFileSync("git", ["-C", dir, "config", "core.autocrlf", "false"]);
  fs.writeFileSync(path.join(dir, ".gitignore"), ".worktrees/\n");
  execFileSync("git", ["-C", dir, "add", "."]);
  execFileSync("git", ["-C", dir, "commit", "-qm", "base"]);
  const rodar = (tarefas, { tocar = false, extra = [] } = {}) => {
    const env = { ...process.env, PATH: [falsos, ...PATH_BASE].join(";"), FAKE_LOG: log };
    delete env.SWARM_DEPTH; // Os testes só iniciam os CLIs falsos desta fixture.
    if (tocar) env.FAKE_TOUCH = "1"; else delete env.FAKE_TOUCH;
    const r = spawnSync("pwsh", ["-NoProfile", "-NonInteractive", "-File", SCRIPT, "-ManifestJson", JSON.stringify(tarefas), "-WorkingDirectory", dir, "-Engine", "claude", "-Json", ...extra], { env, encoding: "utf8" });
    const arquivos = fs.readdirSync(raiz).filter(f => f.startsWith(path.basename(log)));
    const chamadas = arquivos.map(f => fs.readFileSync(path.join(raiz, f), "utf8").trim()).join("\n");
    for (const arquivo of arquivos) fs.unlinkSync(path.join(raiz, arquivo));
    return { codigo: r.status, saida: r.stdout + r.stderr, chamadas,
      registros: chamadas.trim() ? chamadas.trim().split(/\r?\n/).map(JSON.parse) : [] };
  };
  return { dir, falsos, rodar };
}

const branches = (dir) => execFileSync("git", ["-C", dir, "branch", "--format=%(refname:short)"], { encoding: "utf8" }).trim().split(/\r?\n/);

test("execute dos motores suportados sem desvio de segurança", () => {
  const a = ambiente();
  const r = a.rodar([
    { id: "c1", engine: "claude", mode: "execute", prompt: "teste" },
    { id: "c2", engine: "codex", mode: "execute", prompt: "teste" },
  ]);
  assert.equal(r.codigo, 0, r.saida);
  assert.match(r.registros.find(c => c.engine === "claude").args.join(" "), /--permission-mode acceptEdits/);
  assert.match(r.registros.find(c => c.engine === "codex").args.join(" "), /-s workspace-write/);
  assert.doesNotMatch(r.chamadas, /dangerously|approve-for-me|gpt-5\.6-luna/);
});

test("ids repetidos, motor e effort inválidos são recusados antes de rodar qualquer coisa", () => {
  const a = ambiente();
  for (const tarefas of [
    [{ id: "x", prompt: "a" }, { id: "x", prompt: "b" }],
    [{ id: "x", engine: "bash", prompt: "a" }],
    [{ id: "x", effort: "turbo", prompt: "a" }],
    [{ id: "../fora", prompt: "a" }],
    [{ id: "boa", mode: "execute", worktree: true, prompt: "a" }, { id: "ruim", engine: "bash", prompt: "b" }],
  ]) {
    const r = a.rodar(tarefas);
    assert.notEqual(r.codigo, 0, JSON.stringify(tarefas));
    assert.equal(r.chamadas, "", "nenhum agente foi chamado");
    assert.deepEqual(branches(a.dir), ["main"], "nenhuma mesa órfã");
  }
});

test("worktree: vazia é desmontada, com trabalho é preservada", () => {
  const a = ambiente();
  const vazia = a.rodar([{ id: "vazia", engine: "claude", mode: "execute", worktree: true, prompt: "teste" }]);
  assert.equal(vazia.codigo, 0, vazia.saida);
  assert.deepEqual(branches(a.dir), ["main"]);
  const cheia = a.rodar([{ id: "cheia", engine: "claude", mode: "execute", worktree: true, prompt: "teste" }], { tocar: true });
  assert.equal(cheia.codigo, 0, cheia.saida);
  assert.ok(branches(a.dir).some((b) => b.startsWith("task/swarmv2-cheia-")));
});

test("escopo cirurgico de mcp: mcp_servers e allow_mcp passam as flags corretas", () => {
  const a = ambiente();
  const r = a.rodar([
    { id: "c1", engine: "claude", mode: "execute", mcp_servers: [], prompt: "teste" },
    { id: "c2", engine: "codex", mode: "execute", mcp_servers: [], prompt: "teste" },
  ]);
  assert.equal(r.codigo, 0, r.saida);
  assert.ok(r.registros.find(c => c.engine === "claude").args.includes("--strict-mcp-config"));
  assert.ok(r.registros.find(c => c.engine === "codex").args.includes("--ignore-user-config"));
});

test("model malicioso é recusado antes de criar worktrees", () => {
  const a = ambiente();
  for (const model of ['" & calc & "', 'a|b', 'a%PATH%', 'x'.repeat(81), 'x\ny', 'x\n']) {
    const r = a.rodar([{ id: "boa", engine: "claude", mode: "execute", worktree: true, prompt: "a" },
      { id: "ruim", engine: "claude", prompt: "b", model }]);
    assert.notEqual(r.codigo, 0, r.saida);
    assert.match(r.saida, /model invalido/);
    assert.equal(r.chamadas, "");
    assert.deepEqual(branches(a.dir), ["main"]);
  }
});

test("shims cmd e bat são recusados, inclusive prompt com metacaracteres", () => {
  for (const ext of ["cmd", "bat"]) {
    const a = ambiente();
    fs.unlinkSync(path.join(a.falsos, "claude.ps1"));
    fs.writeFileSync(path.join(a.falsos, `claude.${ext}`), '@echo off\r\necho {}>"%FAKE_LOG%"\r\n');
    const r = a.rodar([{ engine: "claude", mode: "execute", worktree: true, prompt: '" & echo INJETADO & "' }]);
    assert.notEqual(r.codigo, 0, r.saida);
    assert.match(r.saida, /cmd\/bat.*binario nativo/i);
    assert.equal(r.chamadas, "");
    assert.deepEqual(branches(a.dir), ["main"]);
  }
});

test("prompt é preservado literalmente em launcher seguro", () => {
  const a = ambiente();
  const prompt = 'ação " & | < > ^ %PATH% ! ( )\nsegunda linha \\"';
  const r = a.rodar([{ engine: "claude", prompt, model: "claude-opus-5.5:latest" }]);
  assert.equal(r.codigo, 0, r.saida);
  assert.equal(r.registros[0].stdin, prompt);
});

test("prompt não pode injetar opções do CLI nem configuração MCP", () => {
  const a = ambiente();
  for (const prompt of ["--help", '--mcp-config={"mcpServers":{"extra":{"command":"fake"}}}']) {
    const r = a.rodar([{ engine: "claude", prompt }]);
    assert.equal(r.codigo, 0, r.saida);
    assert.equal(r.registros[0].stdin, prompt);
    assert.ok(!r.registros[0].args.includes(prompt));
  }
});

test("Claude recebe somente MCPs permitidos em plan e execute", () => {
  const a = ambiente();
  const config = path.join(a.dir, "mcps.json");
  fs.writeFileSync(config, JSON.stringify({ mcpServers: { permitido: { command: "fake-ok" }, proibido: { command: "fake-no" } } }));
  for (const mode of ["plan", "execute"]) {
    const r = a.rodar([{ engine: "claude", mode, prompt: "teste", mcp_servers: ["permitido"], mcp_config: config }]);
    assert.equal(r.codigo, 0, r.saida);
    const args = r.registros[0].args;
    assert.ok(args.includes("--strict-mcp-config"));
    assert.ok(args.includes("--mcp-config"));
    assert.deepEqual(JSON.parse(args[args.indexOf("--mcp-config") + 1]), { mcpServers: { permitido: { command: "fake-ok" } } });
  }
  const vazio = a.rodar([{ engine: "claude", prompt: "teste", allow_mcp: [], mcp_servers: ["proibido"] }]);
  assert.equal(vazio.codigo, 0, vazio.saida);
  assert.ok(vazio.registros[0].args.includes("--strict-mcp-config"));
  assert.ok(!vazio.registros[0].args.includes("--mcp-config"));
});

test("MCP sem definição ou engine sem isolamento falha antes de criar mesas", () => {
  const a = ambiente();
  for (const politica of [
    { engine: "claude", mcp_servers: ["ausente"] },
    { engine: "claude", allow_mcp: "todos" },
    { engine: "agy", mcp_servers: [] },
    { engine: "agy", allow_mcp: ["servidor"] },
  ]) {
    const r = a.rodar([{ engine: "claude", id: "boa", mode: "execute", worktree: true, prompt: "a" },
      { id: "ruim", prompt: "b", ...politica }]);
    assert.notEqual(r.codigo, 0, r.saida);
    assert.match(r.saida, /MCP|mcp_config|allow_mcp/);
    assert.equal(r.chamadas, "");
    assert.deepEqual(branches(a.dir), ["main"]);
  }
});


