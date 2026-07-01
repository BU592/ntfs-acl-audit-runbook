<#
.SYNOPSIS
  End-to-end PRE -> CLEAN -> POST pipeline for a single share root.

.DESCRIPTION
  1. PRE:   audits the share (02-audit-emitsummaries.ps1) and shapes it
            (03-shape.ps1), then writes every path with orphaned-SID ACEs
            into config\targets.txt.
  2. CLEAN: runs 01-runbook-fixacl.ps1 -OnlyOrphanedSIDs against that
            targets file.
  3. POST:  re-audits and re-shapes, then prints a before/after delta of
            how many paths still have orphaned SIDs.

.PARAMETER ShareRoot
  The share/folder root to audit and clean, e.g. D:\ServerFolders\Maintenance

.PARAMETER IncludeFiles
  Also audit individual files, not just folders.

.EXAMPLE
  .\99-run-share.ps1 -ShareRoot 'D:\ServerFolders\Maintenance'
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$ShareRoot,
  [switch]$IncludeFiles
)

$RepoRoot = Split-Path -Parent $PSScriptRoot
$scr      = Join-Path $RepoRoot 'scripts'
$cfg      = Join-Path $RepoRoot 'config'
$inp      = Join-Path $cfg 'targets.txt'
$art      = Join-Path $RepoRoot 'artifacts'
$analysis = Join-Path $art  'Analysis'
$combined = Join-Path $art  'Combined'

# Guard: ensure required scripts exist
$required = @('02-audit-emitsummaries.ps1','03-shape.ps1','01-runbook-fixacl.ps1')
foreach ($f in $required) {
  $p = Join-Path $scr $f
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "Missing required script: $p" }
}

# === PRE: Audit & Shape ===
Write-Host "ShareRoot: $ShareRoot" -ForegroundColor Yellow
Write-Host "=== PRE: Audit & Shape ===" -ForegroundColor Yellow
& (Join-Path $scr '02-audit-emitsummaries.ps1') -ScopeRoots $ShareRoot -IncludeFiles:$IncludeFiles
& (Join-Path $scr '03-shape.ps1')

# Build offenders list from PRE matrix into targets.txt
$matrixCsv = Join-Path $analysis 'NTFS_Audit_PathIdentityMatrix.csv'
if (-not (Test-Path -LiteralPath $matrixCsv)) { throw "Matrix not found: $matrixCsv" }
$offenders = Import-Csv -LiteralPath $matrixCsv |
  Where-Object { $_.Path -like "$ShareRoot*" -and [int]$_.OrphanedSIDACEs -gt 0 } |
  Select-Object -ExpandProperty Path -Unique
$offenders | Set-Content -LiteralPath $inp -Encoding UTF8

Write-Host "`nOrphaned SID entries (PRE):" -ForegroundColor Cyan
Import-Csv -LiteralPath $matrixCsv |
  Where-Object { $_.Path -like "$ShareRoot*" -and [int]$_.OrphanedSIDACEs -gt 0 } |
  Select-Object Path,Identity,OrphanedSIDACEs,ExplicitACEs |
  Sort-Object Path | Format-Table -Auto

# === CLEAN ===
Write-Host "`n=== CLEAN: Orphaned SID removal (explicit + parent-source + fallback) ===" -ForegroundColor Yellow
& (Join-Path $scr '01-runbook-fixacl.ps1') -OnlyOrphanedSIDs

# === POST: Audit & Shape ===
Write-Host "`n=== POST: Audit & Shape ===" -ForegroundColor Yellow
& (Join-Path $scr '02-audit-emitsummaries.ps1') -ScopeRoots $ShareRoot -IncludeFiles:$IncludeFiles
& (Join-Path $scr '03-shape.ps1')

# Delta summary
$matrix2  = Import-Csv (Join-Path $analysis 'NTFS_Audit_PathIdentityMatrix.csv')
$orphPre  = $offenders
$orphPost = $matrix2 | Where-Object { $_.Path -like "$ShareRoot*" -and [int]$_.OrphanedSIDACEs -gt 0 } | Select-Object -ExpandProperty Path -Unique

Write-Host "`nDelta (Orphaned SIDs):" -ForegroundColor Cyan
[pscustomobject]@{
  PathsWithOrphans_PRE  = ($orphPre  | Measure-Object | Select-Object -ExpandProperty Count)
  PathsWithOrphans_POST = ($orphPost | Measure-Object | Select-Object -ExpandProperty Count)
  Cleaned               = @($orphPre | Where-Object { $_ -notin $orphPost }).Count
} | Format-Table -Auto

Write-Host "`nArtifacts:" -ForegroundColor Cyan
Write-Host "`tCombined   : $combined"
Write-Host "`tSummaries  : $($art)\Summaries"
Write-Host "`tAnalysis   : $analysis"
Write-Host "`tLogs       : $($art)\Logs"
Write-Host "`tSnapshots  : $($art)\Snapshots"
