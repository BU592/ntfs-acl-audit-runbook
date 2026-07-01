# GitHub Instructions

A first-time, no-command-line-required guide to putting this project on
GitHub and updating it later. Everything here uses the GitHub website —
you do not need to install Git or learn any commands.

## 1. Create a GitHub account (skip if you already have one)

1. Go to https://github.com and click **Sign up**.
2. Follow the prompts (email, username, password, verification).

## 2. Create the repository

1. Once logged in, click the **+** icon in the top-right corner, then
   **New repository**.
2. **Repository name**: `ntfs-acl-audit-runbook` (or whatever you'd like).
3. **Description** (optional): a short summary, e.g. "NTFS ACL audit and
   orphaned-SID cleanup toolkit."
4. **Public or Private**: choose **Private** if this shouldn't be visible
   to the public, **Public** if it's fine for anyone to see. You can
   change this later in repository settings.
5. **Do not** check "Add a README file," "Add .gitignore," or "Choose a
   license" — this project already includes those files, and adding them
   again here would create a conflict.
6. Click **Create repository**.

## 3. Upload the files

You'll land on a page for your new (empty) repository.

1. Click **uploading an existing file** (a link in the middle of the
   page). If you don't see that link, click **Add file** → **Upload
   files** near the top.
2. Open the `ntfs-acl-audit-runbook` folder on your computer (the one
   this was delivered as a .zip — unzip it first if needed).
3. Drag the **entire contents** of that folder (not the folder itself —
   its contents: `README.md`, `LICENSE`, `.gitignore`, `scripts/`,
   `config/`, `docs/`, `artifacts/`) into the upload area in your browser.
   GitHub supports dragging whole folders and will preserve the
   subfolder structure.
4. Wait for the upload progress to finish — for a project this size it
   should take a few seconds.

## 4. Commit the upload

Scrolling down on that same page, you'll see a **Commit changes** section:

1. Leave or edit the commit message (e.g. "Initial commit").
2. Leave **Commit directly to the main branch** selected.
3. Click **Commit changes**.

Your files are now published.

## 5. Verify the repository

1. Click the repository name (top-left) to return to the main view.
2. Confirm you see: `README.md`, `LICENSE`, `.gitignore`, and the
   `scripts`, `config`, `docs`, and `artifacts` folders.
3. Click into `scripts/` and confirm all five `.ps1` files are there:
   `00-init-folders.ps1`, `01-runbook-fixacl.ps1`,
   `02-audit-emitsummaries.ps1`, `03-shape.ps1`, `99-run-share.ps1`.
4. Click `README.md` — GitHub renders it automatically on the repository
   home page, so if it displays with headings and formatting, everything
   worked.

## 6. Making changes later

To edit a file directly on GitHub (no re-upload needed):

1. Navigate to the file (e.g. `docs/workflow.md`).
2. Click the pencil icon (**Edit this file**) in the top-right of the
   file view.
3. Make your changes.
4. Scroll down, add a short commit message describing the change, and
   click **Commit changes**.

To add or replace multiple files at once, repeat the **Add file → Upload
files** steps from Step 3 — uploading a file with the same name and path
as an existing one will overwrite it after you commit.

## 7. Troubleshooting

- **"This repository is not empty" / merge conflict on upload** —
  happens if you checked "Add a README" (or similar) when creating the
  repo. Fix: delete the conflicting file in the GitHub UI (open it, click
  the trash-can icon, commit), then re-upload.
- **Folder structure looks flattened** — this happens if you drag
  individual files instead of the folder contents with subfolders intact.
  Delete the misplaced files and re-drag, making sure your file manager
  window shows the `scripts/`, `config/`, `docs/`, `artifacts/`
  subfolders before you drag.
- **`README.md` isn't rendering with formatting** — double check the
  filename is exactly `README.md` (capitalization doesn't matter, but the
  `.md` extension does) and that it's in the repository root, not inside
  a subfolder.
- **Uploaded the wrong file / need to remove something** — open the file
  on GitHub, click the trash-can icon in the top-right, then commit the
  deletion.
- **Want to undo an upload entirely** — go to the repository's **Commits**
  history (small clock icon near the top of the file list, or
  `Insights` → `Commits`), find the commit, and use **Revert** if
  available, or manually delete/re-upload the correct files.

## 8. A note on the artifacts folder

`artifacts/` intentionally ships with only a placeholder file
(`.gitkeep`) — that's expected. It fills up locally when you run the
scripts, but generated audit data shouldn't live in version control (see
`.gitignore`). If you ever want to keep a specific report for the record,
upload just that CSV manually rather than the whole folder.
