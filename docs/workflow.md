# Workflow

## One-time setup

```powershell
cd scripts
.\00-init-folders.ps1
```

This creates `artifacts/Combined`, `artifacts/Summaries`,
`artifacts/Analysis`, `artifacts/Logs`, `artifacts/Snapshots`, and — if it
doesn't already exist — copies `config/targets.txt.example` to
`config/targets.txt` for you to edit.

Edit `config/targets.txt` with the real share root(s) you want to audit,
one per line:

```
D:\ServerFolders\Maintenance
```

## Option A: Full pipeline (recommended)

```powershell
.\99-run-share.ps1 -ShareRoot 'D:\ServerFolders\Maintenance'
```

This runs, in order:

1. **PRE audit** — `02-audit-emitsummaries.ps1` against `-ShareRoot`
2. **PRE shape** — `03-shape.ps1`
3. Builds an offenders list (paths with orphaned SIDs) and writes it to
   `config/targets.txt`
4. **CLEAN** — `01-runbook-fixacl.ps1 -OnlyOrphanedSIDs` against that list
5. **POST audit** — `02-audit-emitsummaries.ps1` again
6. **POST shape** — `03-shape.ps1` again
7. Prints a delta: how many paths had orphans before vs. after, and how
   many were cleaned

Add `-IncludeFiles` to also audit individual files, not just folders (this
is significantly slower on large shares).

## Option B: Run stages independently

Useful if you want to review the PRE audit before deciding to clean, or
you want to re-run just one stage.

```powershell
# Audit only
.\02-audit-emitsummaries.ps1 -ScopeRoots 'D:\ServerFolders\Maintenance'

# Shape the most recent audit
.\03-shape.ps1

# Review artifacts\Analysis\Top25_Paths_ByRiskScore.csv, decide what to clean,
# then edit config\targets.txt to the paths you want to touch

# Run cleanup against config\targets.txt
.\01-runbook-fixacl.ps1 -OnlyOrphanedSIDs
```

## After a run

- Check `artifacts/Logs/` for Before/After CSVs per folder.
- Check `artifacts/Snapshots/` if you ever need to restore an ACL:

  ```powershell
  $acl = Import-Clixml -LiteralPath 'artifacts\Snapshots\ACL_Snapshot_<name>_<hash>_<timestamp>.xml'
  Set-Acl -LiteralPath 'D:\ServerFolders\Maintenance\SomeFolder' -AclObject $acl
  ```

- Review `artifacts/Analysis/Top25_Paths_ByRiskScore.csv` to see what
  still needs manual attention (broad grants and Deny ACEs are flagged but
  not auto-remediated).
