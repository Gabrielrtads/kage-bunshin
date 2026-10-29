[CmdletBinding()]
param(
    [string]$ManifestPath,

    [string]$ManifestJson,

    [ValidateSet('agy', 'claude', 'codex')]
    [string]$Engine = 'agy',

    [object[]]$Tasks,

    [string]$WorkingDirectory = (Get-Location).Path,

    [ValidateRange(1, 86400)]
    [int]$TimeoutSeconds = 900,

    [ValidateRange(1, 32)]
    [int]$MaxConcurrency = 8,

    [switch]$UseWorktreeForEdits,

    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([int]($env:SWARM_DEPTH -as [int]) -ge 1) {
    throw "Recursao bloqueada: o processo atual ja esta em profundidade de swarm $($env:SWARM_DEPTH)."
}

function Get-ExecutableCommand {
    param([string]$Name)

    $command = Get-Command $Name -CommandType Application,ExternalScript -All -ErrorAction Stop | Select-Object -First 1
    if (-not $command.Source) {
        throw "CLI '$Name' nao possui um caminho executavel resolvido no PATH."
    }
    # ArgumentList protege argv nativo, mas nao a reinterpretacao feita pelo cmd.exe.
    if ([System.IO.Path]::GetExtension($command.Source) -in @('.cmd', '.bat')) {
        throw "CLI '$Name': shim cmd/bat recusado; instale o binario nativo ou um launcher .ps1 seguro."
    }
    return $command
}

function Get-TaskMcpPolicy {
    param([hashtable]$Task, [string]$Motor, [string]$TaskDirectory)

    $names = @()
    $field = if ($Task.ContainsKey('allow_mcp')) { 'allow_mcp' } else { 'mcp_servers' }
    if ($Task.ContainsKey($field)) {
        if ($Task[$field] -isnot [array]) { throw "$field deve ser uma lista de nomes MCP." }
        $names = @($Task[$field])
        foreach ($name in $names) {
            if ($name -isnot [string] -or $name -cnotmatch '\A[A-Za-z0-9_-]{1,80}\z') {
                throw "$field contem nome MCP invalido."
            }
        }
    }
    if ($Motor -eq 'agy') {
        throw 'MCP: agy nao oferece isolamento por sessao comprovado; use claude ou codex. Nada foi executado.'
    }
    $configJson = $null
    if ($Motor -eq 'claude' -and $names.Count -gt 0) {
        if (-not $Task.ContainsKey('mcp_config') -or -not $Task['mcp_config']) {
            throw 'MCP: lista Claude nao vazia exige mcp_config (JSON com mcpServers); nada foi executado.'
        }
        try {
            $sourcePath = [string]$Task['mcp_config']
            if (-not [System.IO.Path]::IsPathRooted($sourcePath)) { $sourcePath = Join-Path $TaskDirectory $sourcePath }
            $config = Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
            if ($config['mcpServers'] -isnot [System.Collections.IDictionary]) { throw 'Formato invalido' }
            $filtered = @{}
            foreach ($name in $names) {
                if (-not $config['mcpServers'].Contains($name) -or $config['mcpServers'][$name] -isnot [System.Collections.IDictionary]) {
                    throw 'Servidor ausente ou invalido'
                }
                $filtered[$name] = $config['mcpServers'][$name]
            }
            $configJson = @{ mcpServers = $filtered } | ConvertTo-Json -Compress -Depth 100
        } catch {
            # O arquivo pode conter credenciais: nao ecoar conteudo nem erro do parser.
            throw 'MCP: mcp_config invalido ou servidor solicitado sem definicao; nada foi executado.'
        }
    }
    return @{ Names = $names; ConfigJson = $configJson }
}

function Get-CodexMcpNames {
    $userProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    $configPath = Join-Path $userProfile '.codex\config.toml'
    if (-not (Test-Path -LiteralPath $configPath)) {
        return @()
    }

    $pattern = '^\s*\[mcp_servers\.(?:"(?<quoted>[^"]+)"|(?<bare>[^\].]+))\]\s*$'
    $names = foreach ($line in (Get-Content -LiteralPath $configPath)) {
        if ($line -match $pattern) {
            if ($Matches['quoted']) { $Matches['quoted'] } else { $Matches['bare'] }
        }
    }
    return @($names | Sort-Object -Unique)
}

function ConvertTo-WindowsProcessArgument {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + ($Value -replace '(\\*)(")', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

# 1. Resolver Lista de Tarefas (Manifesto, JSON ou Tasks array)
$parsedTasks = [System.Collections.Generic.List[hashtable]]::new()

if ($ManifestPath) {
    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        throw "Arquivo de manifesto nao encontrado: '$ManifestPath'"
    }
    $rawContent = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
    $jsonObj = $rawContent | ConvertFrom-Json
    if ($jsonObj -is [array]) {
        foreach ($item in $jsonObj) {
            $ht = @{}
            $item.psobject.properties | ForEach-Object { $ht[$_.Name] = $_.Value }
            $parsedTasks.Add($ht)
        }
    } else {
        $ht = @{}
        $jsonObj.psobject.properties | ForEach-Object { $ht[$_.Name] = $_.Value }
        $parsedTasks.Add($ht)
    }
} elseif ($ManifestJson) {
    $jsonObj = $ManifestJson | ConvertFrom-Json
    if ($jsonObj -is [array]) {
        foreach ($item in $jsonObj) {
            $ht = @{}
            $item.psobject.properties | ForEach-Object { $ht[$_.Name] = $_.Value }
            $parsedTasks.Add($ht)
        }
    } else {
        $ht = @{}
        $jsonObj.psobject.properties | ForEach-Object { $ht[$_.Name] = $_.Value }
        $parsedTasks.Add($ht)
    }
} elseif ($Tasks) {
    foreach ($item in $Tasks) {
        if ($item -is [hashtable]) {
            $parsedTasks.Add($item)
        } elseif ($item -is [pscustomobject]) {
            $ht = @{}
            $item.psobject.properties | ForEach-Object { $ht[$_.Name] = $_.Value }
            $parsedTasks.Add($ht)
        }
    }
} else {
    throw "E necessario fornecer -ManifestPath, -ManifestJson ou -Tasks."
}

if (@($parsedTasks).Count -eq 0) {
    throw "Nenhuma tarefa informada para execucao paralela."
}

$resolvedWorkdir = (Resolve-Path -LiteralPath $WorkingDirectory -ErrorAction Stop).Path

# Detectar se o diretorio de trabalho e um repositorio Git
$isGitRepo = $false
$gitRoot = $null
try {
    $proc = Start-Process -FilePath "git" -ArgumentList "rev-parse --show-toplevel" -WorkingDirectory $resolvedWorkdir -NoNewWindow -PassThru -RedirectStandardOutput (Join-Path $env:TEMP "git_root_$pid.txt") -RedirectStandardError ([System.IO.Path]::Combine($env:TEMP, "git_err_$pid.txt"))
    [void]$proc.WaitForExit(3000)
    if ($proc.ExitCode -eq 0) {
        $gitRoot = (Get-Content (Join-Path $env:TEMP "git_root_$pid.txt") -Raw -ErrorAction SilentlyContinue).Trim()
        if ($gitRoot -and (Test-Path -LiteralPath $gitRoot)) {
            $isGitRepo = $true
        }
    }
} catch {
    $isGitRepo = $false
} finally {
    Remove-Item (Join-Path $env:TEMP "git_root_$pid.txt") -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $env:TEMP "git_err_$pid.txt") -ErrorAction SilentlyContinue
}

# 2. Preparar Jobs e Worktrees
$idsDasTarefas = @(for ($i = 0; $i -lt $parsedTasks.Count; $i++) {
    if ($parsedTasks[$i].ContainsKey('id') -and $parsedTasks[$i]['id']) { [string]$parsedTasks[$i]['id'] } else { "task_$($i + 1)" }
})
$repetidos = @($idsDasTarefas | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
if ($repetidos.Count -gt 0) { throw "Ids de tarefa repetidos no manifesto: $($repetidos -join ', '). Cada tarefa precisa de um id unico." }
# Valida o manifesto inteiro antes de criar qualquer worktree: tarefa invalida nao deixa mesa orfa.
for ($i = 0; $i -lt $parsedTasks.Count; $i++) {
    $t = $parsedTasks[$i]; $id = $idsDasTarefas[$i]
    $motor = if ($t.ContainsKey('engine') -and $t['engine']) { [string]$t['engine'] } else { $Engine }
    $modo = if ($t.ContainsKey('mode') -and $t['mode']) { [string]$t['mode'] } else { 'plan' }
    $esforco = if ($t.ContainsKey('effort') -and $t['effort']) { [string]$t['effort'] } else { $null }
    if ($t.ContainsKey('model') -and ($t['model'] -isnot [string] -or $t['model'] -cnotmatch '\A[A-Za-z0-9._:-]{1,80}\z')) {
        throw "Tarefa '$id': model invalido (use 1..80 letras, numeros, . _ : -)."
    }
    $limite = if ($t.ContainsKey('timeout_seconds') -and $t['timeout_seconds']) { [int]$t['timeout_seconds'] } else { $TimeoutSeconds }
    if ($id -notmatch '^[A-Za-z0-9_-]{1,64}$') { throw "Tarefa com id invalido: '$id' (use letras, numeros, - e _)." }
    if ($motor -notin @('claude', 'codex', 'agy')) { throw "Tarefa '$id': motor invalido '$motor'." }
    if ($modo -notin @('plan', 'execute')) { throw "Tarefa '$id': modo invalido '$modo'." }
    if ($esforco -and $esforco -notin @('low', 'medium', 'high', 'xhigh', 'max')) { throw "Tarefa '$id': effort invalido '$esforco'." }
    if ($limite -lt 1 -or $limite -gt 7200) { throw "Tarefa '$id': timeout_seconds fora de 1..7200." }
    if (-not ($t.ContainsKey('prompt') -and $t['prompt'])) { throw "Tarefa '$id' nao possui 'prompt'." }
    $diretorio = if ($t.ContainsKey('working_directory') -and $t['working_directory']) {
        (Resolve-Path -LiteralPath $t['working_directory'] -ErrorAction Stop).Path
    } else { $resolvedWorkdir }
    $t['_mcpPolicy'] = Get-TaskMcpPolicy -Task $t -Motor $motor -TaskDirectory $diretorio
    $t['_cliCommand'] = Get-ExecutableCommand -Name $motor
}

# Diretorio privado para configs de MCP filtradas (podem conter credenciais dos
# servidores permitidos). Nunca vai em argv: a lista de processos e visivel a
# qualquer outro processo do mesmo usuario.
$mcpConfigDir = Join-Path $env:TEMP ("swarmv2-mcp-" + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $mcpConfigDir -Force)
try {
    icacls $mcpConfigDir /inheritance:r /grant:r "$($env:USERNAME):(OI)(CI)F" 2>&1 | Out-Null
} catch {}

$activeJobs = [System.Collections.Generic.List[PSCustomObject]]::new()
$taskIndex = 0

foreach ($task in $parsedTasks) {
    $taskIndex++
    $taskId = if ($task.ContainsKey('id') -and $task['id']) { [string]$task['id'] } else { "task_$taskIndex" }
    $taskEngine = if ($task.ContainsKey('engine') -and $task['engine']) { [string]$task['engine'] } else { $Engine }
    $taskMode = if ($task.ContainsKey('mode') -and $task['mode']) { [string]$task['mode'] } else { 'plan' }
    $taskPrompt = if ($task.ContainsKey('prompt') -and $task['prompt']) { [string]$task['prompt'] } else { throw "Tarefa '$taskId' nao possui 'prompt'." }
    $taskModel = if ($task.ContainsKey('model') -and $task['model']) { [string]$task['model'] } else { $null }
    $taskEffort = if ($task.ContainsKey('effort') -and $task['effort']) { [string]$task['effort'] } else { $null }
    $taskDir = if ($task.ContainsKey('working_directory') -and $task['working_directory']) {
        (Resolve-Path -LiteralPath $task['working_directory'] -ErrorAction Stop).Path
    } else {
        $resolvedWorkdir
    }
    $taskTimeout = if ($task.ContainsKey('timeout_seconds') -and $task['timeout_seconds']) { [int]$task['timeout_seconds'] } else { $TimeoutSeconds }
    $taskAllowMcp = @($task['_mcpPolicy'].Names)
    $taskNeedWorktree = if ($task.ContainsKey('worktree') -and $task['worktree']) { [bool]$task['worktree'] } else { $UseWorktreeForEdits.IsPresent }

    # O manifesto e entrada externa: so valores conhecidos chegam a git e aos CLIs.
    if ($taskId -notmatch '^[A-Za-z0-9_-]{1,64}$') { throw "Tarefa com id invalido: '$taskId' (use letras, numeros, - e _)." }
    if ($taskEngine -notin @('claude', 'codex', 'agy')) { throw "Tarefa '$taskId': motor invalido '$taskEngine'." }
    if ($taskMode -notin @('plan', 'execute')) { throw "Tarefa '$taskId': modo invalido '$taskMode'." }
    if ($taskEffort -and $taskEffort -notin @('low', 'medium', 'high', 'xhigh', 'max')) { throw "Tarefa '$taskId': effort invalido '$taskEffort'." }
    if ($taskTimeout -lt 1 -or $taskTimeout -gt 7200) { throw "Tarefa '$taskId': timeout_seconds fora de 1..7200." }

    # Isolamento de Worktree para tarefas de escrita concorrente
    $assignedDir = $taskDir
    $worktreePath = $null
    $worktreeBranch = $null

    if ($taskMode -eq 'execute' -and $taskNeedWorktree -and -not $isGitRepo) {
        throw "Tarefa '$taskId' pede worktree, mas a pasta nao e um repositorio Git; nada foi executado."
    }
    if ($taskMode -eq 'execute' -and $taskNeedWorktree) {
        $timestamp = '{0}-{1}' -f (Get-Date).ToString("yyyyMMdd_HHmmss"), ([guid]::NewGuid().ToString('N').Substring(0, 6))
        $worktreeBranch = "task/swarmv2-${taskId}-${timestamp}"
        $worktreesBase = Join-Path $gitRoot ".worktrees"
        if (-not (Test-Path -LiteralPath $worktreesBase)) {
            [void](New-Item -ItemType Directory -Path $worktreesBase -Force)
            # Garantir que .worktrees esta no .gitignore
            $gitignorePath = Join-Path $gitRoot ".gitignore"
            $hasIgnore = if (Test-Path -LiteralPath $gitignorePath) {
                (Get-Content -LiteralPath $gitignorePath -Raw) -match '^\.worktrees/?'
            } else { $false }
            if (-not $hasIgnore) {
                Add-Content -LiteralPath $gitignorePath -Value "`n.worktrees/`n" -Encoding UTF8
            }
        }
        $worktreePath = Join-Path $worktreesBase "${taskId}_${timestamp}"
        
        # Criar git worktree
        # Falha fechada: sem worktree isolada a tarefa de escrita nao roda na pasta compartilhada.
        $worktreeBase = git -C $gitRoot rev-parse --verify HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $worktreeBase) {
            $worktreeBase = $worktreeBase.Trim()
            git -C $gitRoot worktree add -b $worktreeBranch $worktreePath $worktreeBase 2>$null | Out-Null
        }
        if ($LASTEXITCODE -ne 0 -or -not $worktreeBase -or -not (Test-Path -LiteralPath $worktreePath)) {
            throw "Nao foi possivel criar a worktree isolada da tarefa '$taskId'; nada foi executado."
        }
        $assignedDir = $worktreePath
    }

    # Montar argumentos do motor
    $cliCommand = $task['_cliCommand']
    $arguments = [System.Collections.Generic.List[string]]::new()
    $promptViaStdin = $false

    switch ($taskEngine) {
        'claude' {
            [void]$arguments.Add('-p')
            # Prompt e dado, inclusive quando comeca por --mcp-config ou --help.
            $promptViaStdin = $true
            [void]$arguments.Add('--permission-prompts')
            [void]$arguments.Add('none')
            if ($taskMode -eq 'plan') {
                [void]$arguments.Add('--permission-mode')
                [void]$arguments.Add('plan')
                [void]$arguments.Add('--restricted')
            } else {
                # acceptEdits: edita so dentro da pasta; comando arriscado e negado (testado).
                [void]$arguments.Add('--permission-mode')
                [void]$arguments.Add('acceptEdits')
            }
            [void]$arguments.Add('--strict-mcp-config')
            if ($task['_mcpPolicy'].ConfigJson) {
                # Grava em arquivo (0600 equivalente via icacls) em vez de argv:
                # --mcp-config aceita arquivo JSON ou string, e o arquivo nao
                # aparece na lista de processos nem em logs de auditoria do SO.
                $mcpConfigFile = Join-Path $mcpConfigDir ("$taskId.json")
                Set-Content -LiteralPath $mcpConfigFile -Value $task['_mcpPolicy'].ConfigJson -NoNewline -Encoding UTF8
                [void]$arguments.Add('--mcp-config')
                [void]$arguments.Add($mcpConfigFile)
            }
            [void]$arguments.Add('--output-format')
            [void]$arguments.Add('json')
            if ($taskModel) {
                [void]$arguments.Add('--model')
                [void]$arguments.Add($taskModel)
            }
            if ($taskEffort) {
                [void]$arguments.Add('--effort')
                [void]$arguments.Add($taskEffort)
            }
        }

        'codex' {
            if ($taskMode -eq 'plan') {
                $taskPrompt = "[MODO LEITURA / PLANO - APENAS ANALISE, NAO EDITE ARQUIVOS]`n$taskPrompt"
                [void]$arguments.Add('-s')
                [void]$arguments.Add('read-only')
            } else {
                [void]$arguments.Add('-s')
                [void]$arguments.Add('workspace-write')
            }
            if ($taskModel) {
                [void]$arguments.Add('--model')
                [void]$arguments.Add($taskModel)
            }
            if ($taskEffort) {
                [void]$arguments.Add('--config')
                [void]$arguments.Add(('model_reasoning_effort="{0}"' -f $taskEffort))
            }

            $allowed = @($taskAllowMcp)
            if ($allowed.Length -gt 0) {
                foreach ($mcpName in (Get-CodexMcpNames)) {
                    if ($allowed -notcontains $mcpName) {
                        [void]$arguments.Add('--config')
                        [void]$arguments.Add(('mcp_servers.{0}.enabled=false' -f $mcpName))
                    }
                }
            }

            [void]$arguments.Add('exec')
            [void]$arguments.Add('--ephemeral')
            [void]$arguments.Add('--skip-git-repo-check')
            [void]$arguments.Add('--json')
            if ($allowed.Length -eq 0) { [void]$arguments.Add('--ignore-user-config') }
            [void]$arguments.Add('-')
            $promptViaStdin = $true
        }

        'agy' {
            [void]$arguments.Add('--print')
            [void]$arguments.Add($taskPrompt)
            [void]$arguments.Add('--mode')
            [void]$arguments.Add($(if ($taskMode -eq 'plan') { 'plan' } else { 'accept-edits' }))
            [void]$arguments.Add('--print-timeout')
            [void]$arguments.Add(('{0}s' -f $taskTimeout))
            # Nenhum modo usa --dangerously-skip-permissions. O --sandbox do agy so restringe o
            # terminal: no Windows ele ainda edita arquivos fora da pasta (testado).
            if ($taskMode -eq 'execute') {
                [void]$arguments.Add('--sandbox')
                Write-Warning "Tarefa '$taskId': agy em execute nao fica preso a pasta ao editar arquivos; prefira claude ou codex."
            }
            [void]$arguments.Add('--output-format')
            [void]$arguments.Add('json')
            if ($taskModel) {
                [void]$arguments.Add('--model')
                [void]$arguments.Add($taskModel)
            }
            if ($taskEffort -and $taskModel -notmatch '-(low|medium|high|max)$') {
                [void]$arguments.Add('--effort')
                [void]$arguments.Add($taskEffort)
            }
        }
    }

    # Configurar ProcessStartInfo
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $assignedDir
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    if ($cliCommand.Source -match '\.ps1$') {
        $pwsh = Get-ExecutableCommand -Name 'pwsh'
        $psi.FileName = $pwsh.Source
        $launcherArguments = @('-NoProfile', '-NonInteractive', '-File', $cliCommand.Source)
    } else {
        $psi.FileName = $cliCommand.Source
        $launcherArguments = @()
    }

    $allArguments = @($launcherArguments) + @($arguments | ForEach-Object { [string]$_ })
    $argumentListProperty = $psi.GetType().GetProperty('ArgumentList')
    if ($null -ne $argumentListProperty) {
        foreach ($arg in $allArguments) {
            [void]$psi.ArgumentList.Add($arg)
        }
    } else {
        $psi.Arguments = ($allArguments | ForEach-Object {
            ConvertTo-WindowsProcessArgument -Value $_
        }) -join ' '
    }

    # Guard anti-recursao
    $psi.Environment['SWARM_DEPTH'] = '1'

    $jobObj = [PSCustomObject]@{
        Id               = $taskId
        Engine           = $taskEngine
        Mode             = $taskMode
        Prompt           = $taskPrompt
        PromptViaStdin   = $promptViaStdin
        Model            = $taskModel
        Effort           = $taskEffort
        WorkingDirectory = $assignedDir
        WorktreePath     = $worktreePath
        WorktreeBranch   = $worktreeBranch
        WorktreeBase     = $(if ($worktreePath) { $worktreeBase } else { $null })
        TimeoutSeconds   = $taskTimeout
        ProcessStartInfo = $psi
        Process          = $null
        StdoutTask       = $null
        StderrTask       = $null
        StartTime        = $null
        EndTime          = $null
        DurationSeconds  = 0
        ExitCode         = -1
        Status           = 'pending'
        Stdout           = $null
        Stderr           = $null
        ParsedJson       = $null
    }

    $activeJobs.Add($jobObj)
}

# 3. Disparo Concorrente com Throttling e Fan-In com Watchdog
$startTimeTotal = [System.Diagnostics.Stopwatch]::StartNew()
$globalTimeoutWatch = [System.Diagnostics.Stopwatch]::StartNew()

function Start-JobProcess {
    param([object]$Job)

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $Job.ProcessStartInfo

    if (-not $proc.Start()) {
        $Job.Status = 'failed_to_start'
        $Job.Stderr = "Falha ao iniciar processo para $($Job.Engine)."
        return $false
    }

    if ($Job.PromptViaStdin) {
        $proc.StandardInput.Write($Job.Prompt)
    }

    # Fechamento IMEDIATO de Stdin: Contrato universal anti-deadlock
    $proc.StandardInput.Close()

    $Job.Process = $proc
    $Job.StartTime = [DateTime]::UtcNow
    $Job.Status = 'running'
    $Job.StdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $Job.StderrTask = $proc.StandardError.ReadToEndAsync()
    return $true
}

while ($true) {
    # 3.1 Checagem de Timeout Global
    $globalElapsed = $globalTimeoutWatch.Elapsed.TotalSeconds
    $globalTimeoutExceeded = ($globalElapsed -gt $TimeoutSeconds)

    # 3.2 Se timeout global excedido, cancela tarefas pendentes e aborta running
    if ($globalTimeoutExceeded) {
        foreach ($job in $activeJobs) {
            if ($job.Status -eq 'pending') {
                $job.Status = 'cancelled'
                $job.Stderr = "CANCELLED: Cancelada devido ao estouro do timeout global de ${TimeoutSeconds}s."
            } elseif ($job.Status -eq 'running') {
                try { $job.Process.Kill($true) } catch { try { $job.Process.Kill() } catch {} }
                $job.EndTime = [DateTime]::UtcNow
                $job.DurationSeconds = [math]::Round(($job.EndTime - $job.StartTime).TotalSeconds, 2)
                $job.ExitCode = 124
                $job.Status = 'timeout'
                $job.Stderr = "TIMEOUT: Tarefa '$($job.Id)' abortada por timeout global de ${TimeoutSeconds}s."
                $job.Process.Dispose()
            }
        }
        break
    }

    # 3.3 Spawn de tarefas pendentes respeitando $MaxConcurrency
    $runningCount = @($activeJobs | Where-Object { $_.Status -eq 'running' }).Count
    if ($runningCount -lt $MaxConcurrency) {
        $slotsAvailable = $MaxConcurrency - $runningCount
        $pendingJobs = @($activeJobs | Where-Object { $_.Status -eq 'pending' })
        for ($i = 0; $i -lt [math]::Min($slotsAvailable, $pendingJobs.Count); $i++) {
            [void](Start-JobProcess -Job $pendingJobs[$i])
        }
    }

    # 3.4 Monitorar jobs em execucao
    $stillRunning = 0
    foreach ($job in $activeJobs) {
        if ($job.Status -eq 'running') {
            if ($job.Process.HasExited) {
                $job.EndTime = [DateTime]::UtcNow
                $job.DurationSeconds = [math]::Round(($job.EndTime - $job.StartTime).TotalSeconds, 2)
                $job.ExitCode = $job.Process.ExitCode
                $job.Stdout = $job.StdoutTask.GetAwaiter().GetResult()
                $job.Stderr = $job.StderrTask.GetAwaiter().GetResult()

                # Tentar converter stdout para JSON estruturado
                if ($job.Stdout) {
                    try {
                        $job.ParsedJson = $job.Stdout | ConvertFrom-Json
                    } catch {
                        $job.ParsedJson = $null
                    }
                }

                $job.Status = if ($job.ExitCode -eq 0) { 'success' } else { 'failed' }
                $job.Process.Dispose()
            } else {
                # Checar timeout individual
                $elapsed = ([DateTime]::UtcNow - $job.StartTime).TotalSeconds
                if ($elapsed -gt $job.TimeoutSeconds) {
                    try { $job.Process.Kill($true) } catch { try { $job.Process.Kill() } catch {} }
                    $job.EndTime = [DateTime]::UtcNow
                    $job.DurationSeconds = [math]::Round($elapsed, 2)
                    $job.ExitCode = 124
                    $job.Status = 'timeout'
                    $job.Stderr = "TIMEOUT: Tarefa '$($job.Id)' excedeu $($job.TimeoutSeconds)s."
                    $job.Process.Dispose()
                } else {
                    $stillRunning++
                }
            }
        }
    }

    $hasPending = (@($activeJobs | Where-Object { $_.Status -eq 'pending' }).Count -gt 0)
    if ($stillRunning -eq 0 -and -not $hasPending) {
        break
    }

    Start-Sleep -Milliseconds 150
}

$startTimeTotal.Stop()
$totalDuration = [math]::Round($startTimeTotal.Elapsed.TotalSeconds, 2)

# 4. Mesa vazia nao pode sobrar. So desmonta com prova de que nao ha nada;
#    qualquer erro ou duvida preserva a worktree para revisao.
foreach ($job in $activeJobs) {
    if (-not $job.WorktreePath -or -not $job.WorktreeBase -or -not (Test-Path -LiteralPath $job.WorktreePath)) { continue }
    $alterados = @(git -C $job.WorktreePath status --porcelain --ignored 2>$null)
    $statusOk = ($LASTEXITCODE -eq 0)
    $novosCommits = git -C $gitRoot rev-list --count "$($job.WorktreeBase)..$($job.WorktreeBranch)" 2>$null
    $revOk = ($LASTEXITCODE -eq 0)
    if ($statusOk -and $revOk -and [int]$novosCommits -eq 0 -and $alterados.Count -eq 0) {
        git -C $gitRoot worktree remove $job.WorktreePath 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            git -C $gitRoot branch -d $job.WorktreeBranch 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $job.WorktreeBranch = $null
                $job.WorktreePath = $null
            }
        }
    }
}

Remove-Item -LiteralPath $mcpConfigDir -Recurse -Force -ErrorAction SilentlyContinue

# 5. Consolidacao e Apresentacao dos Resultados (Fan-In)
$successCount = @($activeJobs | Where-Object { $_.Status -eq 'success' }).Count
$failedCount = @($activeJobs | Where-Object { $_.Status -eq 'failed' }).Count
$timeoutCount = @($activeJobs | Where-Object { $_.Status -eq 'timeout' }).Count

$report = [ordered]@{
    summary = [ordered]@{
        total_tasks      = @($activeJobs).Count
        success          = $successCount
        failed           = $failedCount
        timeout          = $timeoutCount
        duration_seconds = $totalDuration
    }
    tasks = @($activeJobs | ForEach-Object {
        [ordered]@{
            id               = $_.Id
            engine           = $_.Engine
            mode             = $_.Mode
            status           = $_.Status
            exit_code        = $_.ExitCode
            duration_seconds = $_.DurationSeconds
            worktree_branch  = $_.WorktreeBranch
            worktree_path    = $_.WorktreePath
            output           = if ($_.ParsedJson) { $_.ParsedJson } else { $_.Stdout }
            error_output     = $_.Stderr
        }
    })
}

if ($Json) {
    $report | ConvertTo-Json -Depth 15
} else {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  SWARMv2: RELATORIO DE EXECUCAO PARALELA (FAN-IN CONSOLIDADO)  " -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ("Total Tarefas: {0} | Sucesso: {1} | Falhas: {2} | Timeouts: {3} | Tempo Total: {4}s" -f `
        $report.summary.total_tasks, $report.summary.success, $report.summary.failed, $report.summary.timeout, $report.summary.duration_seconds) -ForegroundColor Yellow
    Write-Host "----------------------------------------------------------------"
    foreach ($t in $report.tasks) {
        $color = switch ($t.status) {
            'success' { 'Green' }
            'timeout' { 'Red' }
            default   { 'Yellow' }
        }
        Write-Host ("[{0}] ID: {1} | Motor: {2} ({3}) | Duracao: {4}s | Status: {5}" -f `
            $t.status.ToUpper(), $t.id, $t.engine, $t.mode, $t.duration_seconds, $t.status) -ForegroundColor $color
        if ($t.worktree_branch) {
            Write-Host ("    -> Git Worktree Branch: {0} ({1})" -f $t.worktree_branch, $t.worktree_path) -ForegroundColor DarkCyan
        }
        if ($t.error_output -and $t.status -ne 'success') {
            Write-Host ("    -> Erro: {0}" -f $t.error_output.Trim()) -ForegroundColor Red
        }
    }
    Write-Host "================================================================" -ForegroundColor Cyan
}

# Retorna exit code de acordo com o resultado geral
if ($failedCount -gt 0 -or $timeoutCount -gt 0) {
    exit 1
} else {
    exit 0
}
