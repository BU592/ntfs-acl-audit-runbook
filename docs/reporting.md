# Reporting: Output Files Explained

All generated files live under `artifacts/`, which is gitignored (except
a `.gitkeep` placeholder) since it's regenerated output, not source.

## artifacts/Combined/

**`NTFS_Audit_ALL_<Computer>_<Timestamp>.csv`**
The raw master dataset — one row per ACE (Access Control Entry) on every
audited folder/file. Columns include Path, Identity, Rights, AccessType
(Allow/Deny), IsInherited, InheritanceBroken, BroadPrincipal, DenyACE, and
OrphanedSID. Use this for deep analysis or import into Excel/Power BI.

## artifacts/Summaries/

Three filtered views of the combined data, each timestamped:

- **`NTFS_Audit_RiskOnly_*.csv`** — rows where the principal is broad
  (Everyone, Authenticated Users, Domain Users, BUILTIN\Users) or the ACE
  is a Deny.
- **`NTFS_Audit_BrokenInheritance_*.csv`** — rows on folders where
  inheritance has been disabled/protected.
- **`NTFS_Audit_OrphanedSIDs_*.csv`** — rows where the identity failed to
  translate to a name (a genuinely orphaned SID, not just an unfamiliar
  one).

## artifacts/Analysis/

Produced by `03-shape.ps1` from the most recent combined CSV:

- **`NTFS_Audit_SummaryByPath.csv`** — one row per folder: ACE count,
  unique identities, counts of broad/deny/orphan/write ACEs, whether
  inheritance is broken, and a computed `RiskScore`
  (`Broad×1 + Deny×2 + Orphan×2 + Write×1`).
- **`NTFS_Audit_SummaryByIdentity.csv`** — one row per identity: how many
  paths it touches and with what kind of access. Useful for spotting
  accounts/groups with unexpectedly wide reach.
- **`NTFS_Audit_PathIdentityMatrix.csv`** — full Path × Identity matrix
  with per-cell counts. This is what the orchestrator reads to build the
  offenders list for cleanup.
- **`Top25_Paths_ByRiskScore.csv`** — the 25 highest-risk folders.
- **`Top25_Identities_ByUniquePaths.csv`** — the 25 accounts/groups with
  the widest reach.

(`TopN` defaults to 25; pass `-TopN` to `03-shape.ps1` to change it.)

## artifacts/Logs/

Written by `01-runbook-fixacl.ps1`, one pair per folder touched:

- **`Before_<name>_<hash>_<timestamp>.csv`** — every ACE on the folder
  before cleanup.
- **`After_<name>_<hash>_<timestamp>.csv`** — every ACE on the folder
  after cleanup.

These are your proof-of-change record for audits.

## artifacts/Snapshots/

- **`ACL_Snapshot_<name>_<hash>_<timestamp>.xml`** — full ACL of the
  target folder, captured before any change, via `Export-Clixml`.
- **`ACL_SnapshotParent_<name>_<hash>_<timestamp>.xml`** — same, for any
  parent folder the cleanup engine modified (when fixing an inherited
  orphan at its true source).

Restore any of these with:

```powershell
$acl = Import-Clixml -LiteralPath 'artifacts\Snapshots\<file>.xml'
Set-Acl -LiteralPath '<the original folder path>' -AclObject $acl
```
