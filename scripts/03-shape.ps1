<#
.SYNOPSIS
  Builds analytical rollups (risk scoring, per-identity, path x identity
  matrix, Top-N lists) from the most recent combined audit CSV.

.PARAMETER CombinedDir
  Folder containing NTFS_Audit_ALL_*.csv files. Defaults to ..\artifacts\Combined.

.PARAMETER OutDir
  Where to write the analysis CSVs. Defaults to ..\artifacts\Analysis.

.PARAMETER TopN
  How many rows to include in the Top-N leaderboard files. Default 25.

.EXAMPLE
  .\03-shape.ps1
#>
[CmdletBinding()]
param(
  [string]$RepoRoot    = (Split-Path -Parent $PSScriptRoot),
  [string]$CombinedDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\Combined'),
  [string]$OutDir      = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\Analysis'),
  [int]$TopN = 25
)

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$combined = Get-ChildItem -Path $CombinedDir -Filter 'NTFS_Audit_ALL_*.csv' -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1 -ExpandProperty FullName
if (-not $combined) { throw "No combined CSV found in $CombinedDir" }

function Test-True([string]$s){ if ($null -eq $s) { return $false }; $b=$null; [bool]::TryParse($s.Trim(),[ref]$b)|Out-Null; $b }
$WriteRegex = [regex]::new('(Write|Modify|FullControl|CreateFiles|CreateDirectories|AppendData|WriteData|Delete|DeleteSubdirectoriesAndFiles|WriteAttributes|WriteExtendedAttributes|ChangePermissions|TakeOwnership)','IgnoreCase')
function Test-Write([string]$r){ if([string]::IsNullOrWhiteSpace($r)){return $false}; $WriteRegex.IsMatch($r) }

$pathAgg=@{}; $identAgg=@{}; $matrix=@{}

Import-Csv -LiteralPath $combined | ForEach-Object {
  $p=$_.Path; $id=$_.Identity; $r=$_.Rights
  $broad=Test-True $_.BroadPrincipal; $deny=Test-True $_.DenyACE; $orph=Test-True $_.OrphanedSID
  $broken=Test-True $_.InheritanceBroken; $inh=Test-True $_.IsInherited; $wr=Test-Write $r

  if(-not $pathAgg.ContainsKey($p)){ $pathAgg[$p]=[ordered]@{Path=$p;AceCount=0;Broad=0;Deny=0;Orph=0;Write=0;Explicit=0;Broken=$false;Ids=New-Object 'System.Collections.Generic.HashSet[string]'} }
  $x=$pathAgg[$p]; $x.AceCount++; if($broad){$x.Broad++}; if($deny){$x.Deny++}; if($orph){$x.Orph++}; if($wr){$x.Write++}; if(-not $inh){$x.Explicit++}; if($broken){$x.Broken=$true}; $null=$x.Ids.Add($id)

  if(-not $identAgg.ContainsKey($id)){ $identAgg[$id]=[ordered]@{Identity=$id;AceCount=0;Broad=0;Deny=0;Orph=0;Write=0;Paths=New-Object 'System.Collections.Generic.HashSet[string]'} }
  $y=$identAgg[$id]; $y.AceCount++; if($broad){$y.Broad++}; if($deny){$y.Deny++}; if($orph){$y.Orph++}; if($wr){$y.Write++}; $null=$y.Paths.Add($p)

  $k="$p|$id"; if(-not $matrix.ContainsKey($k)){ $matrix[$k]=[ordered]@{Path=$p;Identity=$id;AceCount=0;Broad=0;Deny=0;Orph=0;Write=0;Explicit=0;AnyBroken=$false} }
  $m=$matrix[$k]; $m.AceCount++; if($broad){$m.Broad++}; if($deny){$m.Deny++}; if($orph){$m.Orph++}; if($wr){$m.Write++}; if(-not $inh){$m.Explicit++}; if($broken){$m.AnyBroken=$true}
}

foreach($path in $pathAgg.Keys){
  try{ $acl=Get-Acl -LiteralPath $path -ErrorAction Stop; $pathAgg[$path].Broken=[bool]$acl.AreAccessRulesProtected } catch {}
}

$byPath =
  $pathAgg.GetEnumerator() |
  ForEach-Object {
    $x=$_.Value
    $risk=($x.Broad*1)+($x.Deny*2)+($x.Orph*2)+($x.Write*1)
    [pscustomobject]@{
      Path=$x.Path; AceCount=$x.AceCount; UniqueIdentities=$x.Ids.Count; BroadACEs=$x.Broad; DenyACEs=$x.Deny; OrphanedSIDACEs=$x.Orph
      WriteACEs=$x.Write; ExplicitACEs=$x.Explicit; InheritanceBroken=$x.Broken; RiskScore=$risk
    }
  } | Sort-Object -Property RiskScore, AceCount -Descending

$byId =
  $identAgg.GetEnumerator() |
  ForEach-Object {
    $y=$_.Value
    [pscustomobject]@{
      Identity=$y.Identity; AceCount=$y.AceCount; UniquePaths=$y.Paths.Count; BroadACEs=$y.Broad; DenyACEs=$y.Deny; OrphanedSIDACEs=$y.Orph; WriteACEs=$y.Write
    }
  } | Sort-Object -Property UniquePaths, AceCount -Descending

$matrixRows =
  $matrix.GetEnumerator() |
  ForEach-Object {
    $m=$_.Value
    [pscustomobject]@{
      Path=$m.Path; Identity=$m.Identity; AceCount=$m.AceCount; BroadACEs=$m.Broad; DenyACEs=$m.Deny; OrphanedSIDACEs=$m.Orph; WriteACEs=$m.Write; ExplicitACEs=$m.Explicit; AnyBrokenInheritance=$m.AnyBroken
    }
  }

$byPath     | Export-Csv (Join-Path $OutDir 'NTFS_Audit_SummaryByPath.csv') -NoTypeInformation
$byId       | Export-Csv (Join-Path $OutDir 'NTFS_Audit_SummaryByIdentity.csv') -NoTypeInformation
$matrixRows | Export-Csv (Join-Path $OutDir 'NTFS_Audit_PathIdentityMatrix.csv') -NoTypeInformation
$byPath | Select-Object -First $TopN | Export-Csv (Join-Path $OutDir ("Top{0}_Paths_ByRiskScore.csv" -f $TopN)) -NoTypeInformation
$byId   | Select-Object -First $TopN | Export-Csv (Join-Path $OutDir ("Top{0}_Identities_ByUniquePaths.csv" -f $TopN)) -NoTypeInformation

Write-Host "Shaping complete -> $OutDir" -ForegroundColor Cyan
