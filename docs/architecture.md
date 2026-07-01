# Architecture

## Script pipeline

```
00-init-folders.ps1          (run once)
        │
        ▼
99-run-share.ps1  ──calls──▶ 02-audit-emitsummaries.ps1   (PRE audit)
        │            ──calls──▶ 03-shape.ps1               (PRE shape)
        │            ──calls──▶ 01-runbook-fixacl.ps1       (CLEAN)
        │            ──calls──▶ 02-audit-emitsummaries.ps1  (POST audit)
        │            ──calls──▶ 03-shape.ps1               (POST shape)
        ▼
   Delta report (orphans before vs. after)
```

Each script is also runnable independently — `99-run-share.ps1` is a thin
orchestrator, not the only entry point.

## Path resolution

Every script resolves its own paths relative to its own location
(`$PSScriptRoot`), one level up to the repository root, then into
`config/` or `artifacts/`. There are no hardcoded absolute paths or
machine-specific folders anywhere in the scripts — clone the repo anywhere
and it works.

```
repo-root/
├── config/targets.txt     <- $PSScriptRoot\..\config\targets.txt
├── artifacts/...          <- $PSScriptRoot\..\artifacts\...
└── scripts/*.ps1          <- $PSScriptRoot
```

## Data flow

1. **`02-audit-emitsummaries.ps1`** walks the target share, reads the ACL
   of every folder (and file, if `-IncludeFiles`), and writes one row per
   ACE to a timestamped combined CSV. It also splits that data into
   risk-only, broken-inheritance, and orphaned-SID summary CSVs.
2. **`03-shape.ps1`** reads the most recent combined CSV and rolls it up
   into per-path and per-identity aggregates, a Path x Identity matrix,
   and Top-N leaderboards by risk score / reach.
3. **`01-runbook-fixacl.ps1`** reads a target list (explicit paths or
   `config/targets.txt`), and for each target:
   - Snapshots the current ACL.
   - Removes explicit orphaned-SID ACEs on the target itself.
   - For SIDs that are *inherited* (not explicit), walks up the parent
     chain to find where the ACE is actually defined and removes it
     there — snapshotting the parent first.
   - If no explicit source is found anywhere up the tree but the SID
     persists (this can happen with certain inheritance states),
     falls back to a protect → purge → re-enable-inheritance sequence
     directly on the object.
   - Logs a before/after CSV of every ACE on the folder.
4. **`99-run-share.ps1`** strings steps 1–3 together twice (PRE and POST)
   around the cleanup step, and prints how many previously-offending
   paths are now clean.

## Design choices worth knowing

- **Snapshot-first**: nothing is changed without an `Export-Clixml`
  snapshot written first, so any single-folder change is technically
  reversible.
- **Conservative default**: `-OnlyOrphanedSIDs` is the intended normal
  mode — it only removes ACEs that fail SID-to-name translation, not
  ACEs for arbitrary broad principals.
- **Parent-aware**: the cleanup engine specifically avoids just stripping
  an inherited ACE at the child (which would be undone by the next
  inheritance recompute) — it fixes the actual source.
