#!/usr/bin/env bash
# ==============================================================================
# Swarmv2 - Orquestrador de Fan-Out Paralelo (Linux / VPS Bash)
# Executa múltiplas tarefas concorrentes para o mesmo agente (agy, claude, codex)
# ==============================================================================

set -euo pipefail

MANIFEST_FILE=""
ENGINE_DEFAULT="agy"
TIMEOUT_SECS=900
USE_WORKTREE=0
OUTPUT_JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--manifest)
      MANIFEST_FILE="$2"
      shift 2
      ;;
    -e|--engine)
      ENGINE_DEFAULT="$2"
      shift 2
      ;;
    -t|--timeout)
      TIMEOUT_SECS="$2"
      shift 2
      ;;
    -w|--worktree)
      USE_WORKTREE=1
      shift
      ;;
    --json)
      OUTPUT_JSON=1
      shift
      ;;
    *)
      echo "Argumento desconhecido: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$MANIFEST_FILE" || ! -f "$MANIFEST_FILE" ]]; then
  echo "Erro: Manifesto JSON obrigatório. Uso: $0 -m <manifest.json> [--engine agy] [--timeout 900] [--worktree] [--json]" >&2
  exit 1
fi

TMP_DIR=$(mktemp -d /tmp/swarmv2_XXXXXX)
declare -a WORKTREE_PATHS=() WORKTREE_BRANCHES=() WORKTREE_ROOTS=() WORKTREE_BASES=() WORKTREE_GITDIRS=()
JOBS_STARTED=0
JOBS_FINISHED=0

cleanup_worktrees() {
  local i wt root branch base gitdir pointer dirty head
  for (( i=0; i<${#WORKTREE_PATHS[@]}; i++ )); do
    wt=${WORKTREE_PATHS[$i]}
    [[ -n "$wt" && -d "$wt" ]] || continue
    root=${WORKTREE_ROOTS[$i]}; branch=${WORKTREE_BRANCHES[$i]}; base=${WORKTREE_BASES[$i]}
    gitdir=${WORKTREE_GITDIRS[$i]}
    # O agente tem acesso de escrita na worktree: nunca confie no ponteiro
    # $wt/.git para resolver o repositorio (poderia ser trocado por um symlink
    # ou apontar pra um gitdir malicioso com hooks). Confirme que o ponteiro
    # ainda bate com o gitdir capturado na criacao antes de rodar qualquer
    # comando git, e resolva por --git-dir/--work-tree explicitos, nunca -C.
    [[ -n "$gitdir" && -f "$wt/.git" && ! -L "$wt/.git" ]] || continue
    pointer=$(cat "$wt/.git" 2>/dev/null) || continue
    [[ "$pointer" == "gitdir: $gitdir" ]] || continue
    # Remove somente com prova de zero trabalho; qualquer duvida preserva a mesa.
    dirty=$(git --git-dir="$gitdir" --work-tree="$wt" -c core.fsmonitor=false -c core.hooksPath=/dev/null status --porcelain --ignored 2>/dev/null) || continue
    head=$(git --git-dir="$gitdir" --work-tree="$wt" -c core.hooksPath=/dev/null rev-parse HEAD 2>/dev/null) || continue
    [[ -z "$dirty" && "$head" == "$base" ]] || continue
    [[ "$(git -C "$root" rev-parse "$branch" 2>/dev/null)" == "$base" ]] || continue
    if git -C "$root" worktree remove "$wt" 2>/dev/null && git -C "$root" branch -d "$branch" >/dev/null 2>&1; then
      WORKTREE_PATHS[$i]=""; WORKTREE_BRANCHES[$i]=""
    fi
  done
}

cleanup() {
  if [[ "$JOBS_STARTED" -eq 0 || "$JOBS_FINISHED" -eq 1 ]]; then cleanup_worktrees; fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

TASK_COUNT=$(jq '. | length' "$MANIFEST_FILE")
if [[ "$TASK_COUNT" -eq 0 ]]; then
  echo "Erro: Nenhuma tarefa encontrada no manifesto." >&2
  exit 1
fi

[[ "$TIMEOUT_SECS" =~ ^[0-9]+$ && "$TIMEOUT_SECS" -ge 1 && "$TIMEOUT_SECS" -le 7200 ]] || { echo "Erro: --timeout fora de 1..7200" >&2; exit 1; }

# Valida o manifesto inteiro antes de disparar qualquer tarefa: nada fica rodando pela metade.
declare -A IDS_VISTOS=()
declare -a MCP_CONFIGS=() TASK_WORKDIRS=() NEED_WORKTREES=()
for (( i=0; i<TASK_COUNT; i++ )); do
  V_ID=$(jq -r ".[$i].id // \"task_$i\"" "$MANIFEST_FILE")
  V_TIMEOUT=$(jq -r ".[$i].timeout_seconds // $TIMEOUT_SECS" "$MANIFEST_FILE")
  [[ "$V_ID" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || { echo "Tarefa com id inválido: '$V_ID'" >&2; exit 1; }
  [[ -z "${IDS_VISTOS[$V_ID]:-}" ]] || { echo "Id de tarefa repetido: '$V_ID'. Cada tarefa precisa de um id único." >&2; exit 1; }
  IDS_VISTOS[$V_ID]=1
  [[ "$V_TIMEOUT" =~ ^[0-9]+$ && "$V_TIMEOUT" -ge 1 && "$V_TIMEOUT" -le 7200 ]] || { echo "Tarefa '$V_ID': timeout_seconds fora de 1..7200" >&2; exit 1; }
  V_ENGINE=$(jq -r --arg default "$ENGINE_DEFAULT" ".[$i].engine // \$default" "$MANIFEST_FILE")
  V_MODE=$(jq -r ".[$i].mode // \"plan\"" "$MANIFEST_FILE")
  [[ "$V_ENGINE" =~ ^(claude|codex|agy)$ ]] || { echo "Tarefa '$V_ID': motor invalido" >&2; exit 1; }
  [[ "$V_MODE" =~ ^(plan|execute)$ ]] || { echo "Tarefa '$V_ID': modo invalido" >&2; exit 1; }
  V_MODEL=$(jq -r ".[$i].model // empty" "$MANIFEST_FILE")
  V_EFFORT=$(jq -r ".[$i].effort // empty" "$MANIFEST_FILE")
  [[ -z "$V_MODEL" || "$V_MODEL" =~ ^[A-Za-z0-9._:-]{1,80}$ ]] || { echo "Tarefa '$V_ID': model invalido" >&2; exit 1; }
  [[ -z "$V_EFFORT" || "$V_EFFORT" =~ ^(low|medium|high|xhigh|max)$ ]] || { echo "Tarefa '$V_ID': effort invalido" >&2; exit 1; }
  V_WORKDIR=$(jq -r --arg default "$PWD" ".[$i].working_directory // \$default" "$MANIFEST_FILE")
  V_WORKDIR=$(cd "$V_WORKDIR" && pwd -P) || { echo "Tarefa '$V_ID': diretorio invalido" >&2; exit 1; }
  TASK_WORKDIRS+=("$V_WORKDIR")
  V_WORKTREE=$(jq -r ".[$i].worktree // false" "$MANIFEST_FILE")
  [[ "$V_WORKTREE" == true || "$V_WORKTREE" == false ]] || { echo "Tarefa '$V_ID': worktree deve ser booleano" >&2; exit 1; }
  if [[ "$V_WORKTREE" == true || ( "$USE_WORKTREE" -eq 1 && "$V_MODE" == execute ) ]]; then
    NEED_WORKTREES+=(1)
  else
    NEED_WORKTREES+=(0)
  fi

  # Presenca do campo define precedencia: allow_mcp:[] significa nenhum MCP.
  V_MCP=$(jq -ce ".[$i] | if has(\"allow_mcp\") then .allow_mcp elif has(\"mcp_servers\") then .mcp_servers else [] end |
    if type == \"array\" and all(.[]; if type == \"string\" then test(\"^[A-Za-z0-9_-]{1,80}$\") else false end) then . else error(\"lista invalida\") end" "$MANIFEST_FILE" 2>/dev/null) || {
    echo "Tarefa '$V_ID': allow_mcp/mcp_servers deve ser uma lista de nomes MCP validos" >&2; exit 1;
  }
  V_MCP_COUNT=$(jq 'length' <<< "$V_MCP")
  V_CONFIG=""
  if [[ "$V_ENGINE" == agy ]]; then
    echo "MCP: agy nao oferece isolamento por sessao comprovado; use claude ou codex. Nada foi executado." >&2; exit 1
  elif [[ "$V_ENGINE" == codex && "$V_MCP_COUNT" -gt 0 ]]; then
    echo "MCP: lista Codex nao vazia ainda nao tem isolamento comprovado no Bash; nada foi executado." >&2; exit 1
  elif [[ "$V_ENGINE" == claude && "$V_MCP_COUNT" -gt 0 ]]; then
    V_CONFIG_PATH=$(jq -r ".[$i].mcp_config // empty" "$MANIFEST_FILE")
    [[ -n "$V_CONFIG_PATH" ]] || { echo "MCP: lista Claude nao vazia exige mcp_config" >&2; exit 1; }
    [[ "$V_CONFIG_PATH" == /* ]] || V_CONFIG_PATH="$V_WORKDIR/$V_CONFIG_PATH"
    V_CONFIG=$(jq -ce --argjson names "$V_MCP" '
      .mcpServers as $servers |
      if ($servers | type) != "object" then error("config invalido") else
        {mcpServers: (reduce $names[] as $name ({};
          if ($servers | has($name)) and ($servers[$name] | type) == "object"
          then .[$name] = $servers[$name] else error("servidor ausente") end))}
      end' "$V_CONFIG_PATH" 2>/dev/null) || {
      echo "MCP: mcp_config invalido ou servidor solicitado sem definicao" >&2; exit 1;
    }
  fi
  V_CONFIG_FILE=""
  if [[ -n "$V_CONFIG" ]]; then
    # O JSON filtrado pode conter credenciais dos servidores MCP permitidos;
    # nunca vai em argv (visivel na lista de processos). Grava num arquivo
    # 0600 dentro do TMP_DIR privado, removido no cleanup junto com o resto.
    V_CONFIG_FILE="$TMP_DIR/mcp_${V_ID}.json"
    ( umask 077; printf '%s' "$V_CONFIG" > "$V_CONFIG_FILE" )
  fi
  MCP_CONFIGS+=("$V_CONFIG_FILE")
done

# Preparar todas as mesas antes de iniciar clones. Falha nunca usa a pasta compartilhada.
for (( i=0; i<TASK_COUNT; i++ )); do
  WORKTREE_PATHS+=(""); WORKTREE_BRANCHES+=(""); WORKTREE_ROOTS+=(""); WORKTREE_BASES+=(""); WORKTREE_GITDIRS+=("")
  [[ "${NEED_WORKTREES[$i]}" -eq 1 ]] || continue
  V_ID=$(jq -r ".[$i].id // \"task_$i\"" "$MANIFEST_FILE")
  V_ROOT=$(git -C "${TASK_WORKDIRS[$i]}" rev-parse --show-toplevel 2>/dev/null) || {
    echo "Tarefa '$V_ID' pede worktree, mas a pasta nao e um repositorio Git" >&2; exit 1;
  }
  V_BASE=$(git -C "$V_ROOT" rev-parse --verify HEAD 2>/dev/null) || {
    echo "Tarefa '$V_ID': nao foi possivel obter a base da worktree" >&2; exit 1;
  }
  V_STAMP="$(date +%Y%m%d_%H%M%S)-$$-$i"
  V_BRANCH="task/swarmv2-${V_ID}-${V_STAMP}"
  V_PATH="$V_ROOT/.worktrees/${V_ID}_${V_STAMP}"
  mkdir -p "$V_ROOT/.worktrees" || { echo "Tarefa '$V_ID': falha ao criar pasta de worktree" >&2; exit 1; }
  git -C "$V_ROOT" worktree add -b "$V_BRANCH" "$V_PATH" "$V_BASE" >/dev/null 2>&1 || {
    echo "Tarefa '$V_ID': nao foi possivel criar a worktree isolada; nada foi executado" >&2; exit 1;
  }
  # Captura o gitdir real agora, antes que o agente tenha qualquer chance de
  # escrever na worktree: e a unica leitura do ponteiro .git em que confiamos.
  V_GITDIR=$(git -C "$V_PATH" rev-parse --absolute-git-dir 2>/dev/null) || {
    echo "Tarefa '$V_ID': nao foi possivel confirmar o gitdir da worktree; nada foi executado" >&2; exit 1;
  }
  WORKTREE_PATHS[$i]="$V_PATH"; WORKTREE_BRANCHES[$i]="$V_BRANCH"
  WORKTREE_ROOTS[$i]="$V_ROOT"; WORKTREE_BASES[$i]="$V_BASE"; WORKTREE_GITDIRS[$i]="$V_GITDIR"
  TASK_WORKDIRS[$i]="$V_PATH"
done

declare -a PIDS=()
declare -a TASK_IDS=()
declare -a MODES=()
declare -a ENGINES=()

START_TIME_TOTAL=$(date +%s)

for (( i=0; i<TASK_COUNT; i++ )); do
  TASK_ID=$(jq -r ".[$i].id // \"task_$i\"" "$MANIFEST_FILE")
  TASK_ENGINE=$(jq -r ".[$i].engine // \"$ENGINE_DEFAULT\"" "$MANIFEST_FILE")
  TASK_MODE=$(jq -r ".[$i].mode // \"plan\"" "$MANIFEST_FILE")
  TASK_PROMPT=$(jq -r ".[$i].prompt" "$MANIFEST_FILE")
  TASK_MODEL=$(jq -r ".[$i].model // empty" "$MANIFEST_FILE")
  TASK_EFFORT=$(jq -r ".[$i].effort // empty" "$MANIFEST_FILE")
  TASK_WORKDIR=${TASK_WORKDIRS[$i]}
  TASK_TIMEOUT=$(jq -r ".[$i].timeout_seconds // $TIMEOUT_SECS" "$MANIFEST_FILE")

  # O manifesto é entrada externa: só valores conhecidos viram nome de arquivo ou argumento.
  [[ "$TASK_ID" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || { echo "Tarefa com id inválido: '$TASK_ID'" >&2; exit 1; }
  [[ "$TASK_ENGINE" =~ ^(claude|codex|agy)$ ]] || { echo "Tarefa '$TASK_ID': motor inválido '$TASK_ENGINE'" >&2; exit 1; }
  [[ "$TASK_MODE" =~ ^(plan|execute)$ ]] || { echo "Tarefa '$TASK_ID': modo inválido '$TASK_MODE'" >&2; exit 1; }
  [[ -z "$TASK_EFFORT" || "$TASK_EFFORT" =~ ^(low|medium|high|xhigh|max)$ ]] || { echo "Tarefa '$TASK_ID': effort inválido '$TASK_EFFORT'" >&2; exit 1; }
  [[ "$TASK_TIMEOUT" =~ ^[0-9]+$ && "$TASK_TIMEOUT" -ge 1 && "$TASK_TIMEOUT" -le 7200 ]] || { echo "Tarefa '$TASK_ID': timeout_seconds inválido '$TASK_TIMEOUT'" >&2; exit 1; }
  [[ -z "$TASK_MODEL" || "$TASK_MODEL" =~ ^[A-Za-z0-9._:-]{1,80}$ ]] || { echo "Tarefa '$TASK_ID': model inválido" >&2; exit 1; }

  TASK_OUT="$TMP_DIR/${TASK_ID}.out"
  TASK_ERR="$TMP_DIR/${TASK_ID}.err"
  TASK_STATUS_FILE="$TMP_DIR/${TASK_ID}.status"
  TASK_IN="$TMP_DIR/${TASK_ID}.in"
  # Stdin impede que um prompt iniciado por -- seja interpretado como opcao do CLI.
  printf '%s' "$TASK_PROMPT" > "$TASK_IN"

  TASK_IDS+=("$TASK_ID")
  ENGINES+=("$TASK_ENGINE")
  MODES+=("$TASK_MODE")

  # Comando como lista: nenhum valor do manifesto é reinterpretado pelo shell.
  # Nenhum modo usa --dangerously-*: execute roda com proteção do próprio CLI.
  CMD=()
  case "$TASK_ENGINE" in
    claude)
      CMD=(claude -p --permission-prompts none --output-format json --strict-mcp-config)
      [[ -z "${MCP_CONFIGS[$i]}" ]] || CMD+=(--mcp-config "${MCP_CONFIGS[$i]}")
      if [[ "$TASK_MODE" == "plan" ]]; then
        CMD+=(--permission-mode plan --restricted)
      else
        CMD+=(--permission-mode acceptEdits)
      fi
      [[ -n "$TASK_MODEL" ]] && CMD+=(--model "$TASK_MODEL")
      [[ -n "$TASK_EFFORT" ]] && CMD+=(--effort "$TASK_EFFORT")
      ;;
    codex)
      CMD=(codex)
      [[ -n "$TASK_MODEL" ]] && CMD+=(--model "$TASK_MODEL")
      [[ -n "$TASK_EFFORT" ]] && CMD+=(--config "model_reasoning_effort=\"$TASK_EFFORT\"")
      CMD+=(exec --ephemeral --skip-git-repo-check --json --ignore-user-config)
      if [[ "$TASK_MODE" == "plan" ]]; then
        CMD+=(-s read-only)
      else
        CMD+=(-s workspace-write)
      fi
      CMD+=(-)
      ;;
    agy)
      CMD=(agy --print "$TASK_PROMPT" --output-format json --print-timeout "${TASK_TIMEOUT}s")
      if [[ "$TASK_MODE" == "plan" ]]; then
        CMD+=(--mode plan)
      else
        CMD+=(--mode accept-edits --sandbox)
      fi
      [[ -n "$TASK_MODEL" ]] && CMD+=(--model "$TASK_MODEL")
      [[ -n "$TASK_EFFORT" ]] && CMD+=(--effort "$TASK_EFFORT")
      ;;
  esac

  # Execucao assincrona: stdin finito (arquivo de prompt) e SWARM_DEPTH=1.
  JOBS_STARTED=1
  (
    cd "$TASK_WORKDIR"
    export SWARM_DEPTH=1
    START_T=$(date +%s)

    # Timeout watchdog
    timeout "$TASK_TIMEOUT" "${CMD[@]}" < "$TASK_IN" > "$TASK_OUT" 2> "$TASK_ERR" && EXIT_CODE=0 || EXIT_CODE=$?
    END_T=$(date +%s)
    DUR=$(( END_T - START_T ))
    
    echo "$EXIT_CODE:$DUR" > "$TASK_STATUS_FILE"
  ) &
  PIDS+=($!)
done

# Aguardar todos os processos (Fan-In)
for pid in "${PIDS[@]}"; do
  wait "$pid" 2>/dev/null || true
done
JOBS_FINISHED=1
cleanup_worktrees

END_TIME_TOTAL=$(date +%s)
TOTAL_DURATION=$(( END_TIME_TOTAL - START_TIME_TOTAL ))

# Agregar resultados
FAILURES=0
SUCCESSES=0

if [[ "$OUTPUT_JSON" -eq 1 ]]; then
  TASKS_JSON="[]"
  for (( i=0; i<TASK_COUNT; i++ )); do
    T_ID="${TASK_IDS[$i]}"
    STATUS_DATA=$(cat "$TMP_DIR/${T_ID}.status" 2>/dev/null || echo "1:0")
    T_EXIT=$(echo "$STATUS_DATA" | cut -d: -f1)
    T_DUR=$(echo "$STATUS_DATA" | cut -d: -f2)
    T_ST=$( [[ "$T_EXIT" -eq 0 ]] && echo "success" || echo "failed" )
    [[ "$T_EXIT" -eq 124 ]] && T_ST="timeout"
    
    # Pos-incremento retorna 1 no primeiro sucesso sob set -e.
    if [[ "$T_ST" == "success" ]]; then SUCCESSES=$((SUCCESSES + 1)); else FAILURES=$((FAILURES + 1)); fi
    
    OUT_CONTENT=$(jq -s -R '.' "$TMP_DIR/${T_ID}.out" 2>/dev/null || echo '""')
    ERR_CONTENT=$(jq -s -R '.' "$TMP_DIR/${T_ID}.err" 2>/dev/null || echo '""')
    
    TASKS_JSON=$(echo "$TASKS_JSON" | jq --arg id "$T_ID" --arg eng "${ENGINES[$i]}" --arg mode "${MODES[$i]}" \
      --arg st "$T_ST" --argjson code "$T_EXIT" --argjson dur "$T_DUR" --argjson out "$OUT_CONTENT" --argjson err "$ERR_CONTENT" \
      --arg wt "${WORKTREE_PATHS[$i]}" --arg branch "${WORKTREE_BRANCHES[$i]}" \
      '. += [{id: $id, engine: $eng, mode: $mode, status: $st, exit_code: $code, duration_seconds: $dur, worktree_path: $wt, worktree_branch: $branch, output: $out, error_output: $err}]')
  done

  jq -n --argjson tot "$TASK_COUNT" --argjson succ "$SUCCESSES" --argjson fail "$FAILURES" --argjson dur "$TOTAL_DURATION" --argjson tasks "$TASKS_JSON" \
    '{summary: {total_tasks: $tot, success: $succ, failed: $fail, duration_seconds: $dur}, tasks: $tasks}'
else
  echo ""
  echo "================================================================"
  echo "  SWARMv2: RELATÓRIO DE EXECUÇÃO PARALELA (FAN-IN CONSOLIDADO)  "
  echo "================================================================"
  echo "Total Tarefas: $TASK_COUNT | Tempo Total: ${TOTAL_DURATION}s"
  echo "----------------------------------------------------------------"
  for (( i=0; i<TASK_COUNT; i++ )); do
    T_ID="${TASK_IDS[$i]}"
    STATUS_DATA=$(cat "$TMP_DIR/${T_ID}.status" 2>/dev/null || echo "1:0")
    T_EXIT=$(echo "$STATUS_DATA" | cut -d: -f1)
    T_DUR=$(echo "$STATUS_DATA" | cut -d: -f2)
    T_ST="failed"
    [[ "$T_EXIT" -eq 0 ]] && T_ST="success"
    [[ "$T_EXIT" -eq 124 ]] && T_ST="timeout"
    
    echo "[$T_ST] ID: $T_ID | Motor: ${ENGINES[$i]} (${MODES[$i]}) | Duração: ${T_DUR}s"
  done
  echo "================================================================"
fi

[[ "$FAILURES" -eq 0 ]] && exit 0 || exit 1
