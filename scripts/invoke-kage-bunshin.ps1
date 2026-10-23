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

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$targetScript = Join-Path $scriptDir 'invoke-parallel-runner.ps1'

& $targetScript @PSBoundParameters
