# Student repo seed

Content that becomes the separate **student repo** served at `/opt/gitsrv/jarvis.git`. Students
clone it to `~/jarvis`, receive later labs with `git pull` as instructors release them, and use
`git checkout stage-* -- labs/<dir>` to restore a lab's files to known-good.

## How it's built
`instructor/runbook/scripts/build-student-repo.sh` reads `checkpoints.yaml`:
1. For each stage, in `order`, it copies that stage's `paths` on top of the previous ones,
   applies the redaction list, commits and tags `stage-<name>`. Add-only is enforced.
2. The complete history goes to `/opt/gitsrv/jarvis-all.git` (root-only).
3. The served `/opt/gitsrv/jarvis.git` is fast-forwarded to the released stage,
   `release-stage.sh --next` during class. A rebuild keeps the previously released stage.

**Never hand-edit the served repos.** Rename, reorder, insert or re-scope a stage by editing
`checkpoints.yaml` and the source content, then regenerate.

## Expected behaviour
- A fresh clone holds Lab 01 only; `release-stage.sh` + `git pull` delivers the next lab with local
  edits in place; a mangled or deleted lab file is restored by its checkpoint command.
