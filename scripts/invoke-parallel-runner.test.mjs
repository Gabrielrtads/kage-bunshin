// Testa o invoke-parallel-runner.ps1 com CLIs falsos que só registram os argumentos.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const SCRIPT = path.join(path.dirname(fileURLToPath(import.meta.url)), "invoke-parallel-runner.ps1");
const onde = (exe) => path.dirname(execFileSync("where.exe", [exe], { encoding: "utf8" }).split(/\r?\n/)[0]);
const PATH_BASE = [onde("git"), onde("pwsh"), path.join(process.env.SystemRoot, "System32")];

function ambiente() {
  const raiz = fs.mkdtempSync(path.join(os.tmpdir(), "swarmv2-"));
  const falsos = path.join(raiz, "bin");
  fs.mkdirSync(falsos);
  for (const nome of ["claude", "codex", "agy"]) {
    fs.writeFileSync(path.join(falsos, `${nome}.cmd`), [
      "@echo off",
      `>>"%FAKE_LOG%" echo ${nome} %*`,
      'if defined FAKE_TOUCH echo x> "%CD%\\criado-pelo-agente.txt"',
      "echo {}",
      "exit /b 0",
      "",
    ].join("\r\n"));
  }
  const log = path.join(raiz, "chamadas.log");
  const dir = path.join(raiz, "repo");
  execFileSync("git", ["init", "-q", "-b", "main", dir]);
  execFileSync("git", ["-C", dir, "config", "user.email", "t@t"]);
  execFileSync("git", ["-C", dir, "config", "user.name", "t"]);
  fs.writeFileSync(path.join(dir, ".gitignore"), ".worktrees/\n");
  execFileSync("git", ["-C", dir, "add", "."]);
  execFileSync("git", ["-C", dir, "commit", "-qm", "base"]);
  const rodar = (tarefas, { tocar = false, extra = [] } = {}) => {
    const env = { ...process.env, PATH: [falsos, ...PATH_BASE].join(";"), FAKE_LOG: log };
    if (tocar) env.FAKE_TOUCH = "1"; else delete env.FAKE_TOUCH;
    const r = spawnSync("pwsh", ["-NoProfile", "-NonInteractive", "-File", SCRIPT, "-ManifestJson", JSON.stringify(tarefas), "-WorkingDirectory", dir, "-Json", ...extra], { env, encoding: "utf8" });
    const chamadas = fs.existsSync(log) ? fs.readFileSync(log, "utf8") : "";
    fs.rmSync(log, { force: true });
    return { codigo: r.status, saida: r.stdout + r.stderr, chamadas };
  };
  return { dir, rodar };
}

const branches = (dir) => execFileSync("git", ["-C", dir, "branch", "--format=%(refname:short)"], { encoding: "utf8" }).trim().split(/\r?\n/);

test("execute dos três motores sem desvio de segurança", () => {
  const a = ambiente();
  const r = a.rodar([
    { id: "c1", engine: "claude", mode: "execute", prompt: "teste" },
    { id: "c2", engine: "codex", mode: "execute", prompt: "teste" },
    { id: "c3", engine: "agy", mode: "execute", prompt: "teste" },
  ]);
  assert.equal(r.codigo, 0, r.saida);
  assert.match(r.chamadas, /claude .*--permission-mode acceptEdits/);
  assert.match(r.chamadas, /codex .*-s workspace-write/);
  assert.match(r.chamadas, /agy .*--mode accept-edits .*--sandbox/);
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
  assert.match(r.chamadas, /claude .*--strict-mcp-config/);
  assert.match(r.chamadas, /codex .*--ignore-user-config/);
});


