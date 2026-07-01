<#
.SYNOPSIS
  Cleans up orphaned-SID and (optionally) overly-broad ACEs on a list of
  target folders, with snapshots and before/after CSV logging for every
  change.

.DESCRIPTION
  For each target folder:
    1. Removes explicit orphaned-SID ACEs (or all non-kept explicit ACEs
       if -OnlyOrphanedSIDs is not set).
    2. For orphaned SIDs that are inherited, walks up the tree to find the
       explicit source ACE and removes it there instead (so the fix
       actually sticks instead of re-inheriting).
    3. If no explicit source is found up the tree but the SID is still
       present, falls back to a protect -> purge -> re-enable-inheritance
       sequence directly on the object.
  Every folder gets an ACL snapshot (Export-Clixml, restorable with
  Import-Clixml) plus Before/After CSVs of every ACE, written before any
  change is made.

.PARAMETER Targets
  Explicit list of folder paths to process. Overrides -TargetsFile.

.PARAMETER TargetsFile
  Path to a text file with one folder per line. Defaults to
  ..\config\targets.txt relative to this script.

.PARAMETER OnlyOrphanedSIDs
  Typical run mode: only touch orphaned-SID ACEs, leave everything else.

.PARAMETER PruneBroadWrite
  Reserved for broad-principal cleanup; not wired to remediation logic yet.

.EXAMPLE
  .\01-runbook-fixacl.ps1 -OnlyOrphanedSIDs
#>
[CmdletBinding()]
param(
  [string[]]$Targets,
  [string]$TargetsFile = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\targets.txt'),

  [switch]$OnlyOrphanedSIDs,            # typical run: ON
  [switch]$FixInheritedOrphanSIDs = $true,

  [switch]$PruneBroadWrite,
  [string[]]$BroadPrincipals = @('Everyone','Authenticated Users','Domain Users','BUILTIN\Users'),
  [string]$EditorsGroup,
  [string]$ReadersGroup,
  [switch]$RequireReplacement,

  [string]$SnapshotDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\Snapshots'),
  [string]$LogDir      = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\Logs'),
  [string[]]$KeepExplicitIdentities = @(),
  [switch]$OpenLogFolder
)

$ConfirmPreference = 'None'

function Ensure-Dir([string]$p){ if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }
function Get-PathHash([string]$s){ $sha=[System.Security.Cryptography.SHA256]::Create(); ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($s))|%{ $_.ToString('x2') }) -join '' }
function New-ArtifactName([string]$prefix,[string]$target,[string]$stamp,[string]$ext){
  $leaf = Split-Path -Path $target -Leaf
  $safe = ($leaf -replace '[:\\\/\*\?\"<>\|]','_').Trim()
  if ($safe.Length -gt 60) { $safe = $safe.Substring(0,60) }
  '{0}_{1}_{2}_{3}{4}' -f $prefix,$safe,(Get-PathHash $target).Substring(0,10),$stamp,$ext
}
function Resolve-Principal([string]$n){ try { ([System.Security.Principal.NTAccount]$n).Translate([System.Security.Principal.SecurityIdentifier]) } catch { $null } }

function Get-AclRows([string]$p){
  $acl=Get-Acl -LiteralPath $p -ErrorAction Stop
  foreach($ace in $acl.Access){
    [pscustomobject]@{
      Timestamp=(Get-Date).ToString('s'); Path=$p; Identity=$ace.IdentityReference.Value
      Rights=$ace.FileSystemRights.ToString(); AccessType=$ace.AccessControlType
      IsInherited=[bool]$ace.IsInherited; InheritanceFlags=$ace.InheritanceFlags
      PropagationFlags=$ace.PropagationFlags; IsOrphanSID=($ace.IdentityReference.Value -match '^S-\d-')
    }
  }
}

# Walk ancestors robustly via DirectoryInfo.Parent
function Find-ExplicitAceUpTree([string]$start, [string]$sidValue){
  try { $dir = Get-Item -LiteralPath $start -ErrorAction Stop } catch { return $null }
  while ($dir) {
    try {
      $acl = Get-Acl -LiteralPath $dir.FullName -ErrorAction Stop
      $hits = $acl.Access | Where-Object { -not $_.IsInherited -and $_.IdentityReference.Value -eq $sidValue }
      if ($hits) { return [pscustomobject]@{ Path=$dir.FullName; Acl=$acl; Hits=$hits } }
    } catch {}
    $dir = $dir.Parent
  }
  $null
}

function Remove-ExactAces([System.Security.AccessControl.FileSystemSecurity]$acl,[System.Collections.IEnumerable]$aces){
  $removed = 0
  foreach($ace in $aces){
    try{
      $sid  = [System.Security.Principal.SecurityIdentifier]$ace.IdentityReference.Value
      $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
               $sid,$ace.FileSystemRights,$ace.InheritanceFlags,$ace.PropagationFlags,$ace.AccessControlType)
      if ($acl.RemoveAccessRuleSpecific($rule)) { $removed++ }
    }catch{}
  }
  ,@($acl,$removed)
}

# NOTE: this function is called from the normal pipeline (not inside a
# background job / Invoke-Command / ForEach-Object -Parallel), so it must
# use the plain $SnapshotDir variable rather than $using:SnapshotDir.
# The original draft used $using:SnapshotDir here, which only works inside
# a separate runspace and would throw at runtime in a normal function call.
function ConvertPurgeReEnable([string]$path,[string[]]$sidValues){
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $snap  = Join-Path $SnapshotDir (New-ArtifactName 'ACL_Snapshot' $path $stamp '.xml')
  (Get-Acl -LiteralPath $path) | Export-Clixml -LiteralPath $snap

  $acl = Get-Acl -LiteralPath $path
  $acl.SetAccessRuleProtection($true,$true)  # protect; copy inherited to explicit
  Set-Acl -LiteralPath $path -AclObject $acl

  $acl2 = Get-Acl -LiteralPath $path
  foreach($sid in ($sidValues | Select-Object -Unique)){
    $hits = $acl2.Access | Where-Object { $_.IdentityReference.Value -eq $sid }
    $tuple = Remove-ExactAces -acl $acl2 -aces $hits
    $acl2 = $tuple[0]
  }
  Set-Acl -LiteralPath $path -AclObject $acl2

  $acl3 = Get-Acl -LiteralPath $path
  $acl3.SetAccessRuleProtection($false,$true) # unprotect; continue inheriting
  Set-Acl -LiteralPath $path -AclObject $acl3

  Write-Host "[FallbackFixedAtObject] $path" -ForegroundColor Yellow
}

# --- Main ---
if (-not $Targets -or $Targets.Count -eq 0) {
  if (-not (Test-Path -LiteralPath $TargetsFile)) { throw "Targets file not found: $TargetsFile" }
  $Targets = Get-Content -LiteralPath $TargetsFile | Where-Object { $_ -and -not $_.StartsWith('#') } | ForEach-Object { $_.Trim() }
}

Ensure-Dir $SnapshotDir; Ensure-Dir $LogDir

$handledParent = @{}   # SID||ParentPath
$idx=0; $total=$Targets.Count

foreach($TargetPath in $Targets){
  $idx++
  $pct = if ($total){ ($idx/$total*100) } else { 100 }
  Write-Progress -Activity "ACL cleanup" -Status "[${idx}/${total}] $TargetPath" -PercentComplete $pct

  if (-not (Test-Path -LiteralPath $TargetPath)) { Write-Warning "Skip (not found): $TargetPath"; continue }
  if ((Test-Path -LiteralPath $TargetPath -PathType Leaf) -or ($TargetPath -match '\.ps1$')) { Write-Warning "Skip (not a folder): $TargetPath"; continue }

  $stamp     = Get-Date -Format 'yyyyMMdd_HHmmss'
  $snapFile  = Join-Path $SnapshotDir (New-ArtifactName 'ACL_Snapshot' $TargetPath $stamp '.xml')
  $beforeCsv = Join-Path $LogDir      (New-ArtifactName 'Before'       $TargetPath $stamp '.csv')
  $afterCsv  = Join-Path $LogDir      (New-ArtifactName 'After'        $TargetPath $stamp '.csv')

  try{
    (Get-Acl -LiteralPath $TargetPath) | Export-Clixml -LiteralPath $snapFile
    Get-AclRows -p $TargetPath | Export-Csv -LiteralPath $beforeCsv -NoTypeInformation

    # 1) Remove explicit orphan ACEs on the target
    $acl=Get-Acl -LiteralPath $TargetPath
    $explicit=$acl.Access | Where-Object { -not $_.IsInherited }
    $toRemove = if ($OnlyOrphanedSIDs) {
      $explicit | Where-Object { $_.IdentityReference.Value -match '^S-\d-' }
    } else {
      $explicit | Where-Object { $KeepExplicitIdentities -notcontains $_.IdentityReference.Value }
    }
    if ($toRemove) {
      $tuple = Remove-ExactAces -acl $acl -aces $toRemove
      $acl   = $tuple[0]
      Set-Acl -LiteralPath $TargetPath -AclObject $acl
    }

    # 2) Fix inherited orphans by removing explicit sources at nearest parent(s)
    if ($FixInheritedOrphanSIDs) {
      $aclNow = Get-Acl -LiteralPath $TargetPath
      $inheritedSids = $aclNow.Access | Where-Object { $_.IsInherited -and $_.IdentityReference.Value -match '^S-\d-' } |
        Select-Object -ExpandProperty IdentityReference -Unique | ForEach-Object { $_.Value }

      $parentHits = 0
      foreach($sidValue in ($inheritedSids | Select-Object -Unique)){
        $src = Find-ExplicitAceUpTree -start $TargetPath -sidValue $sidValue
        if ($src) {
          $key = "$sidValue||$($src.Path)"
          if (-not $handledParent.ContainsKey($key)){
            $snapParent = Join-Path $SnapshotDir (New-ArtifactName 'ACL_SnapshotParent' $src.Path $stamp '.xml')
            (Get-Acl -LiteralPath $src.Path) | Export-Clixml -LiteralPath $snapParent

            $tuple = Remove-ExactAces -acl $src.Acl -aces $src.Hits
            $pAcl  = $tuple[0]
            Set-Acl -LiteralPath $src.Path -AclObject $pAcl
            $handledParent[$key] = $true
            $parentHits++
            Write-Host ("[ParentFixed] {0} -> {1}" -f $sidValue,$src.Path) -ForegroundColor Yellow
          }
        }
      }

      # 3) Fallback: if no parent source found but SID persists, convert->purge->re-enable at object
      if ($parentHits -eq 0) {
        $aclCheck = Get-Acl -LiteralPath $TargetPath
        $stillSids = $aclCheck.Access | Where-Object { $_.IdentityReference.Value -match '^S-\d-' } |
          Select-Object -ExpandProperty IdentityReference -Unique | ForEach-Object { $_.Value }
        if ($stillSids) { ConvertPurgeReEnable -path $TargetPath -sidValues $stillSids }
      }
    }

    # Normalize inheritance at target
    $acl2=Get-Acl -LiteralPath $TargetPath
    $acl2.SetAccessRuleProtection($false,$true)
    Set-Acl -LiteralPath $TargetPath -AclObject $acl2

    Get-AclRows -p $TargetPath | Export-Csv -LiteralPath $afterCsv -NoTypeInformation
    Write-Host "[OK] $TargetPath" -ForegroundColor Green
  }
  catch{
    Write-Host "[FAIL] $TargetPath :: $($_.Exception.Message)" -ForegroundColor Red
  }
}

Write-Host "`nArtifacts:" -ForegroundColor Cyan
Write-Host "`tLogs      : $LogDir"
Write-Host "`tSnapshots : $SnapshotDir"
if ($OpenLogFolder) { Start-Process explorer.exe $LogDir }
