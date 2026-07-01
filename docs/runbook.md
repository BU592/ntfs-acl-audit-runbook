# Runbook: How the Cleanup Engine Works

`scripts/01-runbook-fixacl.ps1` is the component that actually changes
permissions. This document explains its decision logic so you know exactly
what it will do before you run it.

## Default mode: orphaned SIDs only

Run with `-OnlyOrphanedSIDs` (this is what `99-run-share.ps1` uses). In
this mode, the script only ever touches ACEs whose identity fails to
translate from a SID to a name — i.e., genuinely orphaned entries. It will
not remove ACEs for accounts/groups it simply doesn't recognize as broad;
translation failure is the only trigger.

## Per-target sequence

For each folder in the target list:

1. **Snapshot** — the full current ACL is exported to XML before anything
   changes.
2. **Before CSV** — every current ACE is logged.
3. **Remove explicit orphan ACEs on the target** — any ACE that is
   *explicitly* set on this exact folder (not inherited) and matches an
   orphaned SID is removed directly.
4. **Fix inherited orphans at their source** — for orphaned SIDs that
   showed up as *inherited* on this folder, the script walks up the
   parent chain looking for the folder where that ACE is explicitly
   defined. When found:
   - The parent is snapshotted first.
   - The explicit ACE is removed at the parent.
   - This folder is marked so the same parent isn't reprocessed twice in
     one run.

   This matters because removing an *inherited* ACE at the child alone
   wouldn't stick — the next inheritance recompute would just reintroduce
   it from the parent. Fixing the source is what makes the change
   durable.
5. **Fallback: convert → purge → re-enable** — if no explicit source is
   found anywhere up the tree but the orphaned SID is still present after
   step 4 (this can happen depending on how inheritance was previously
   configured), the script:
   - Protects the ACL (copies all inherited ACEs to explicit ones on the
     object).
   - Removes the offending SID(s) from that now-explicit list.
   - Re-enables inheritance (unprotects), so the folder goes back to
     inheriting normally, just without the orphaned entries.
6. **Normalize inheritance** — the target's inheritance protection is
   reset to unprotected/inheriting.
7. **After CSV** — every ACE on the folder is logged again, post-cleanup.

## Parameters

| Parameter | Purpose |
|---|---|
| `-Targets` | Explicit array of folder paths, overrides `-TargetsFile` |
| `-TargetsFile` | Path to a target list file; defaults to `config/targets.txt` |
| `-OnlyOrphanedSIDs` | Restrict remediation to orphaned-SID ACEs (recommended) |
| `-FixInheritedOrphanSIDs` | Enable the parent-source-fix step (default: on) |
| `-KeepExplicitIdentities` | Identities to never remove even if not `-OnlyOrphanedSIDs` |
| `-SnapshotDir` / `-LogDir` | Override output locations (default: `artifacts/Snapshots`, `artifacts/Logs`) |
| `-OpenLogFolder` | Opens the log folder in Explorer when done |

`-PruneBroadWrite`, `-BroadPrincipals`, `-EditorsGroup`, `-ReadersGroup`,
and `-RequireReplacement` are accepted as parameters but are **not yet
wired to any remediation logic** — they're reserved for a future
broad-principal cleanup mode. Don't rely on them to change behavior today.

## Rollback

Every folder touched has a snapshot in `artifacts/Snapshots/`. To restore:

```powershell
$acl = Import-Clixml -LiteralPath 'artifacts\Snapshots\ACL_Snapshot_<name>_<hash>_<timestamp>.xml'
Set-Acl -LiteralPath '<original folder path>' -AclObject $acl
```

If a parent was also modified (step 4), restore it too from its
`ACL_SnapshotParent_*.xml` file, using the same approach.
