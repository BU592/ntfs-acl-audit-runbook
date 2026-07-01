# NTFS ACL Audit & Cleanup Runbook

A PowerShell toolkit for auditing NTFS folder permissions (ACLs) at scale,
scoring risk, and cleaning up orphaned SIDs with full before/after
snapshots — so every change is provable and reversible.

## Features

- **Full ACL inventory** — every ACE on every folder (optionally file) under
  a share root, written to a single combined CSV.
- **Risk summaries** — automatic flagging of broad principals (Everyone,
  Authenticated Users, etc.), Deny ACEs, broken inheritance, and orphaned
  SIDs.
- **Analysis layer** — per-path and per-identity risk scoring, a full
  Path x Identity matrix, and Top-N leaderboards for prioritizing cleanup.
- **Safe cleanup engine** — removes orphaned-SID entries at the correct
  level (explicit on the target, or at the true inherited source up the
  tree), with an XML snapshot and CSV before/after log for every folder it
  touches.
- **One-command pipeline** — a PRE → CLEAN → POST orchestrator that audits,
  cleans, re-audits, and reports exactly what changed.

## Quick Start

```powershell
# 1. Clone this repo, then from the repo root:
cd scripts
.\00-init-folders.ps1

# 2. Edit config\targets.txt with your real share path(s)
#    (00-init-folders.ps1 creates it from config\targets.txt.example)

# 3. Run the full PRE -> CLEAN -> POST pipeline against a share:
.\99-run-share.ps1 -ShareRoot 'D:\Path\To\Your\Share'
```

That single command audits the share, identifies folders with orphaned
SIDs, cleans them, re-audits, and prints a before/after delta.

You can also run any stage on its own — see [docs/workflow.md](docs/workflow.md).

## Structure

```
project-root/
├── README.md
├── LICENSE
├── .gitignore
├── scripts/
│   ├── 00-init-folders.ps1        # one-time setup: folders + targets.txt
│   ├── 01-runbook-fixacl.ps1      # cleanup engine (explicit/parent/fallback)
│   ├── 02-audit-emitsummaries.ps1 # raw ACL collection + risk summaries
│   ├── 03-shape.ps1               # analysis layer (scoring, Top-N)
│   └── 99-run-share.ps1           # orchestrator: PRE -> CLEAN -> POST
├── config/
│   └── targets.txt.example        # copy to targets.txt and edit
├── docs/
│   ├── overview.md
│   ├── workflow.md
│   ├── reporting.md
│   ├── runbook.md
│   ├── architecture.md
│   └── github-instructions.md
└── artifacts/                     # generated output (gitignored)
```

## Outputs

All generated output lands under `artifacts/`, created automatically:

- `Combined/` — raw master ACL dataset (one row per ACE)
- `Summaries/` — risk-only, broken-inheritance, and orphaned-SID subsets
- `Analysis/` — risk scoring, identity rollups, Path x Identity matrix, Top-N lists
- `Logs/` — before/after CSVs from every cleanup run
- `Snapshots/` — XML ACL snapshots, restorable with `Import-Clixml`

See [docs/reporting.md](docs/reporting.md) for a full description of every file.

## Requirements

- Windows with PowerShell 5.1+ (or PowerShell 7+)
- Permissions to read/write NTFS ACLs on the target share(s)

## Documentation

- [docs/overview.md](docs/overview.md) — what this toolkit does and why
- [docs/architecture.md](docs/architecture.md) — how the scripts fit together
- [docs/workflow.md](docs/workflow.md) — running each stage, in order
- [docs/reporting.md](docs/reporting.md) — every output file explained
- [docs/runbook.md](docs/runbook.md) — how the cleanup engine decides what to fix
- [docs/github-instructions.md](docs/github-instructions.md) — first-time guide to publishing/updating this repo on GitHub

## License

MIT — see [LICENSE](LICENSE).
