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
trap 'rm -rf "$TMP_DIR"' EXIT

TASK_COUNT=$(jq '. | length' "$MANIFEST_FILE")
if [[ "$TASK_COUNT" -eq 0 ]]; then
  echo "Erro: Nenhuma tarefa encontrada no manifesto." >&2
  exit 1
fi

[[ "$TIMEOUT_SECS" =~ ^[0-9]+$ && "$TIMEOUT_SECS" -ge 1 && "$TIMEOUT_SECS" -le 7200 ]] || { echo "Erro: --timeout fora de 1..7200" >&2; exit 1; }

# Valida o manifesto inteiro antes de disparar qualquer tarefa: nada fica rodando pela metade.
declare -A IDS_VISTOS=()
for (( i=0; i<TASK_COUNT; i++ )); do
  V_ID=$(jq -r ".[$i].id // \"task_$i\"" "$MANIFEST_FILE")
  V_TIMEOUT=$(jq -r ".[$i].timeout_seconds // $TIMEOUT_SECS" "$MANIFEST_FILE")
  [[ "$V_ID" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || { echo "Tarefa com id inválido: '$V_ID'" >&2; exit 1; }
  [[ -z "${IDS_VISTOS[$V_ID]:-}" ]] || { echo "Id de tarefa repetido: '$V_ID'. Cada tarefa precisa de um id único." >&2; exit 1; }
  IDS_VISTOS[$V_ID]=1
  [[ "$V_TIMEOUT" =~ ^[0-9]+$ && "$V_TIMEOUT" -ge 1 && "$V_TIMEOUT" -le 7200 ]] || { echo "Tarefa '$V_ID': timeout_seconds fora de 1..7200" >&2; exit 1; }
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
  TASK_WORKDIR=$(jq -r ".[$i].working_directory // \"$PWD\"" "$MANIFEST_FILE")
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

  TASK_IDS+=("$TASK_ID")
  ENGINES+=("$TASK_ENGINE")
  MODES+=("$TASK_MODE")

  # Comando como lista: nenhum valor do manifesto é reinterpretado pelo shell.
  # Nenhum modo usa --dangerously-*: execute roda com proteção do próprio CLI.
  CMD=()
  case "$TASK_ENGINE" in
    claude)
      CMD=(claude -p "$TASK_PROMPT" --permission-prompts none --output-format json)
      if [[ "$TASK_MODE" == "plan" ]]; then
        CMD+=(--permission-mode plan --restricted --strict-mcp-config)
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
      CMD+=(exec --ephemeral --skip-git-repo-check --json)
      if [[ "$TASK_MODE" == "plan" ]]; then
        CMD+=(-s read-only)
      else
        CMD+=(-s workspace-write)
      fi
      CMD+=("$TASK_PROMPT")
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

  # Execução assíncrona com stdin fechado (< /dev/null) e SWARM_DEPTH=1
  (
    cd "$TASK_WORKDIR"
    export SWARM_DEPTH=1
    START_T=$(date +%s)

    # Timeout watchdog
    timeout "$TASK_TIMEOUT" "${CMD[@]}" < /dev/null > "$TASK_OUT" 2> "$TASK_ERR" && EXIT_CODE=0 || EXIT_CODE=$?
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
    
    [[ "$T_ST" == "success" ]] && ((SUCCESSES++)) || ((FAILURES++))
    
    OUT_CONTENT=$(jq -s -R '.' "$TMP_DIR/${T_ID}.out" 2>/dev/null || echo '""')
    ERR_CONTENT=$(jq -s -R '.' "$TMP_DIR/${T_ID}.err" 2>/dev/null || echo '""')
    
    TASKS_JSON=$(echo "$TASKS_JSON" | jq --arg id "$T_ID" --arg eng "${ENGINES[$i]}" --arg mode "${MODES[$i]}" \
      --arg st "$T_ST" --argjson code "$T_EXIT" --argjson dur "$T_DUR" --argjson out "$OUT_CONTENT" --argjson err "$ERR_CONTENT" \
      '. += [{id: $id, engine: $eng, mode: $mode, status: $st, exit_code: $code, duration_seconds: $dur, output: $out, error_output: $err}]')
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
