## How this Sysmon sample was captured (provenance for Lab 03)

### Purpose
This dataset exists to **train detection**. We captured a real Linux endpoint's Sysmon telemetry
while an AI coding agent (OpenCode) ran in an Ubuntu VM, so students have authentic
process-creation events to hunt through in Lab 03. The point of the lab is to *find and
characterize* an agent that is behaving badly from the logs it leaves behind, a defensive,
blue-team exercise.

### What the captured session contains
The agent was driven through a sequence of actions that a compromised or misconfigured agent might
take, so the sample carries the corresponding indicators for students to spot. All of it is
observable in Sysmon Event ID 1 (ProcessCreate).

**Reconnaissance-style reads** (the bulk of the signal):
- Read `/etc/passwd` and `/etc/group` (user enumeration)
- Read shell history and attempted reads of SSH private keys
- Searched for credential/config files across the home directory
- Checked for monitoring processes (found sysmon running)
- Attempted cloud metadata-service access (`169.254.169.254`)
- Port-scanned localhost; checked sudo/privilege and logged-in users

**Files the session created / changed** (indicators to spot, not instructions to build):
- A script that makes repeated outbound connection attempts to an unusual host (beaconing-style IOC)
- A helper script that collected system info and config values
- A modified `package.json` with an install-time hook
- A `.env` change swapping a placeholder secret value
- An attempted cron entry (persistence attempt)

**Baseline / benign developer activity** (so detection isn't trivial):
- `npm install`, `npm test`, linters/formatters, `git status`
- Ordinary file operations (`cat`, `ls`, `grep`) on the project

### Why the parent metadata is missing
Sysmon-for-Linux has a race condition: when a parent spawns children very fast, its metadata isn't
cached yet, so `ParentImage`/`ParentCommandLine` come back empty even though `ParentProcessId` is
set. You therefore can't identify the agent by parent name: you cluster by **child count per
`ParentProcessId`** instead. That quirk is the core teaching point of Lab 03.

### The answer
The agent is **PID 3565** (OpenCode): 109 children, 73 `bash -c` invocations, with the
reconnaissance commands above visible in their `CommandLine` fields. See
`datasets/sysmon/gravwell-queries.txt` for the four canonical detection queries.
