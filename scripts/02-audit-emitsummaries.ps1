<#
.SYNOPSIS
  Collects raw NTFS ACL data for one or more roots and emits a combined
  CSV plus risk/broken-inheritance/orphaned-SID summary CSVs.

.PARAMETER ScopeRoots
  One or more folder roots to audit (recurses into subfolders).

.PARAMETER IncludeFiles
  Also audit individual files, not just folders.

.PARAMETER ArtifactsRoot
  Where to write output. Defaults to ..\artifacts relative to this script.

.EXAMPLE
  .\02-audit-emitsummaries.ps1 -ScopeRoots 'D:\ServerFolders\Maintenance'
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string[]]$ScopeRoots,
  [switch]$IncludeFiles,
  [string]$ArtifactsRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts')
)

$combinedDir = Join-Path $ArtifactsRoot 'Combined'
$summDir     = Join-Path $ArtifactsRoot 'Summaries'
New-Item -ItemType Directory -Path $combinedDir,$summDir -Force | Out-Null

$stamp       = Get-Date -Format 'yyyyMMdd_HHmmss'
$combinedCsv = Join-Path $combinedDir ("NTFS_Audit_ALL_{0}_{1}.csv" -f $env:COMPUTERNAME,$stamp)
$header      = 'Server,ShareRoot,Path,Scope,Owner,Identity,Rights,AccessType,IsInherited,InheritanceFlags,PropagationFlags,InheritanceBroken,BroadPrincipal,DenyACE,OrphanedSID'
$header | Out-File -FilePath $combinedCsv -Encoding UTF8

function Test-Broad([string]$id){
  @('Everyone','Authenticated Users','Domain Users','BUILTIN\Users') -icontains $id
}

function Get-Targets([string]$root,[switch]$files){
  $list = New-Object System.Collections.Generic.List[System.IO.FileSystemInfo]
  try { $list.Add((Get-Item -LiteralPath $root -ErrorAction Stop)) | Out-Null } catch { return $list }
  try {
    Get-ChildItem -LiteralPath $root -Directory -Recurse -Force -ErrorAction SilentlyContinue |
      Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } |
      ForEach-Object { $list.Add($_) | Out-Null }
  } catch {}
  if ($files) {
    try {
      Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } |
        ForEach-Object { $list.Add($_) | Out-Null }
    } catch {}
  }
  ,$list
}

foreach ($root in $ScopeRoots) {
  Write-Host "Auditing: $root" -ForegroundColor Yellow
  $targets = Get-Targets -root $root -files:$IncludeFiles

  foreach ($it in $targets) {
    try { $acl = Get-Acl -LiteralPath $it.FullName -ErrorAction Stop } catch { continue }
    $inheritBroken = $acl.AreAccessRulesProtected
    $scope         = if ($it.PSIsContainer) {'Folder'} else {'File'}

    foreach ($ace in $acl.Access) {
      $id      = $ace.IdentityReference.Value
      $isBroad = Test-Broad $id
      $isDeny  = ($ace.AccessControlType -eq 'Deny')

      # Orphaned = only if identity cannot translate to NTAccount
      $isOrph = $false
      try {
        if ($id -match '^S-\d-') {
          ([System.Security.Principal.SecurityIdentifier]$id).Translate([System.Security.Principal.NTAccount]) | Out-Null
        } else {
          [System.Security.Principal.NTAccount]$id | Out-Null
        }
      } catch {
        $isOrph = $true
      }

      $line = '{0},{1},{2},{3},{4},{5},"{6}",{7},{8},{9},{10},{11},{12},{13},{14}' -f `
        $env:COMPUTERNAME,($root -replace ',',';'),($it.FullName -replace ',',';'),$scope,($acl.Owner -replace ',',';'),($id -replace ',',';'),
        ($ace.FileSystemRights -replace '"',''''),$ace.AccessControlType,$ace.IsInherited,$ace.InheritanceFlags,$ace.PropagationFlags,
        $inheritBroken,$isBroad,$isDeny,$isOrph

      $line | Out-File -FilePath $combinedCsv -Append -Encoding UTF8
    }
  }
}

# Summaries
$riskCsv   = Join-Path $summDir ("NTFS_Audit_RiskOnly_{0}_{1}.csv" -f $env:COMPUTERNAME,$stamp)
$brokenCsv = Join-Path $summDir ("NTFS_Audit_BrokenInheritance_{0}_{1}.csv" -f $env:COMPUTERNAME,$stamp)
$orphCsv   = Join-Path $summDir ("NTFS_Audit_OrphanedSIDs_{0}_{1}.csv" -f $env:COMPUTERNAME,$stamp)

$header | Out-File $riskCsv   -Encoding UTF8
$header | Out-File $brokenCsv -Encoding UTF8
$header | Out-File $orphCsv   -Encoding UTF8

Import-Csv $combinedCsv | ForEach-Object {
  if (($_.BroadPrincipal -match '^(?i)true$') -or ($_.DenyACE -match '^(?i)true$')) { $_ | Export-Csv $riskCsv   -NoTypeInformation -Append }
  if ($_.InheritanceBroken -match '^(?i)true$')                                    { $_ | Export-Csv $brokenCsv -NoTypeInformation -Append }
  if ($_.OrphanedSID      -match '^(?i)true$')                                     { $_ | Export-Csv $orphCsv   -NoTypeInformation -Append }
}

Write-Host "Combined  : $combinedCsv" -ForegroundColor Cyan
Write-Host "Summaries : $summDir"     -ForegroundColor Cyan
