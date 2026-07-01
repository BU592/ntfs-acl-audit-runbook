<#
.SYNOPSIS
  Initializes the working folder structure for the NTFS ACL audit toolkit.

.DESCRIPTION
  Run this once after cloning the repository (safe to re-run any time).
  Creates the artifacts subfolders next to the scripts, and seeds
  config\targets.txt from the example file if it doesn't exist yet.

.EXAMPLE
  .\00-init-folders.ps1
#>
[CmdletBinding()]
param()

$RepoRoot      = Split-Path -Parent $PSScriptRoot
$ArtifactsRoot = Join-Path $RepoRoot 'artifacts'
$ConfigDir     = Join-Path $RepoRoot 'config'

$dirs = @(
  (Join-Path $ArtifactsRoot 'Combined'),   # audit combined CSVs (timestamped)
  (Join-Path $ArtifactsRoot 'Summaries'),  # risk-only / broken-inheritance / orphaned-SIDs
  (Join-Path $ArtifactsRoot 'Analysis'),   # shaped outputs (Step 03)
  (Join-Path $ArtifactsRoot 'Logs'),       # BEFORE/AFTER runbook CSVs
  (Join-Path $ArtifactsRoot 'Snapshots')   # ACL_Snapshot_*.xml and ACL_SnapshotParent_*.xml
)
$dirs | ForEach-Object { New-Item -ItemType Directory -Path $_ -Force | Out-Null }

$targetsFile    = Join-Path $ConfigDir 'targets.txt'
$targetsExample = Join-Path $ConfigDir 'targets.txt.example'
if (-not (Test-Path -LiteralPath $targetsFile)) {
  Copy-Item -LiteralPath $targetsExample -Destination $targetsFile
  Write-Host "Created config\targets.txt from the example. Edit it with your real share path(s) before running the runbook directly." -ForegroundColor Yellow
}

Write-Host "Folder structure ready under: $ArtifactsRoot" -ForegroundColor Cyan
