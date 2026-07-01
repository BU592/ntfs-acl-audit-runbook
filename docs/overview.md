# Overview

This toolkit audits NTFS folder permissions (Access Control Lists, or ACLs)
across a share, identifies risk, and cleans up orphaned security
identifiers (SIDs) — accounts or groups that no longer resolve to a real
identity, usually left behind after a user/group deletion or a domain
migration.

## Why it exists

Over time, shared folders accumulate:

- **Orphaned SIDs** — ACEs referencing deleted accounts/groups, showing up
  as raw `S-1-5-...` strings instead of names.
- **Broad grants** — permissions given to `Everyone`, `Authenticated
  Users`, `Domain Users`, or `BUILTIN\Users`, often wider than intended.
- **Broken inheritance** — folders where permission inheritance has been
  disabled, creating one-off exceptions that are easy to lose track of.

Manually finding and fixing these across thousands of folders isn't
practical. This toolkit automates the inventory, scores the risk, and
performs the cleanup safely — with a snapshot and a before/after record for
every folder it touches.

## What it does not do

- It does not modify permissions other than removing orphaned-SID ACEs by
  default (`-OnlyOrphanedSIDs`). Broad-principal pruning parameters exist
  in the cleanup script but are not wired to remediation logic — treat
  them as a placeholder for future work, not an active feature.
- It does not manage AD/domain objects — it only reads and writes NTFS
  ACLs on the file system.

## Who this is for

Windows/systems administrators who need a repeatable, auditable process
for NTFS permission cleanup — with enough of a paper trail (snapshots,
before/after CSVs, PRE/POST deltas) to satisfy an internal audit or
security review.
