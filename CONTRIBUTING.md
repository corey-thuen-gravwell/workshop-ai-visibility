# Authoring conventions

Read this before adding or editing course material: it keeps slides, walkthroughs, labs, and the
student checkpoint repo in sync.

The course runs two ways, and material has to work in both: **an instructor teaching a room**, and
**one person working through it alone**. No artifact may depend on somebody being in the room to
explain it, and nothing may assume a schedule, a session count, or a day boundary. Where the two
genuinely differ, say so in the text rather than writing for one of them.

## The three views of every module

Each teaching module produces up to three artifacts that must stay consistent:

1. **Slides** (`slides/`): what's projected. Concepts, diagrams, the "why."
2. **Instructor walkthrough** (`instructor/walkthroughs/NN-name.md`): the *complete* step-by-step
   with every command, expected output, common failure, and the answer to every lab task. Held
   back from a room, because it is the answer key. Someone reading this course alone is the
   exception, and the one they lean on instead of an instructor. Write it for both readers.
3. **Student lab handout** (`labs/NN-name/README.md`), lighter: goals, context, the tasks, and
   pointers to the checkpoint. Enough to do the work, not a copy-paste script. That friction is
   what makes the terminal practice stick.

If a module has no hands-on component, it has slides only (mark it so in `AGENDA.md`).

## Lab handout structure

Each `labs/NN-name/README.md` follows:

- **Objective**: one or two sentences.
- **Background**: the minimum concept needed.
- **Setup**: checkpoint to start from, prerequisites.
- **Tasks**: numbered, outcome-oriented ("find the PID that spawned the most bash children"),
  not keystroke-by-keystroke.
- **Checkpoint**: `git checkout stage-<name> -- labs/<dir>` to *restore* that lab's files in place.
- **Discussion**: what it proves, how it maps to real environments.

Nothing distributed to students carries a status line, a "validated" tag, a date, or a note about
who decided what. Keep that in commit messages and in the walkthroughs' failure tables.

## Writing style

No em dashes (this means you, AI). Use commas, semicolons, colons, parentheses, or a new sentence. Handouts, slides,
walkthroughs, code comments, script output, all of it.

## Gravwell references

Anything that touches Gravwell, a query, a module option, an ingester setting, an API call, gets
checked against the published source before it goes into a handout. All three are open, no login:

| Site | What it is | Use it for |
|---|---|---|
| <https://docs.gravwell.io> | Product documentation for the pinned version (`gravwell/gravwell:5.10.1`) | Query language and modules (`json`, `grep`, `regex`, `eval`, `stats`, `lookup`, `table`, `chart`, `semantic`, …), ingesters (`simple_relay`, `file_follow`, `llm_ingester`, preprocessors), resources, kits, flows, alerts, scheduled searches, tokens, CBAC, the MCP server, docker deployment, `gravwell.conf` |
| <https://api.docs.gravwell.io> | The REST API reference (Swagger UI; OpenAPI document at `/gravwell.json`) | Anything scripted against an instance: `/api/search/direct`, `/api/tags`, `/api/resources`, `/api/kits`, scheduled searches, alerts, users. The MCP server (`/api/mcp`) and API tokens are documented on the product site |
| <https://github.com/gravwell/kits> | Source of every published kit | Example searches, dashboards and templates. Prefer a kit's own query as the model for a lab query, and say which kit it came from |

Prefer purpose-built extractors where they exist (`winlog` for Windows-schema events, `ax` once a
kit is installed) and show the general one (`xml`, `json`) once so students know it is there.

**Authenticating a script against a seat's Gravwell: use the API token, never a login.** Lab 00
mints one per seat (`labs/00-environment-gravwell/make-token.sh` → `~/.gravwell_token`, exported as
`$GRAVWELL_TOKEN` by `~/.workshop_env`). Anything new that talks to Gravwell sends
`-H "Gravwell-Token: $GRAVWELL_TOKEN"`, not a `POST /api/login` JWT: a login is tied to the admin
password, and a student is free to change it. Behaviours verified against a live 5.10.1 that the
docs don't spell out are recorded in `instructor/runbook/gravwell-provisioning.md`.

## Checkpoints (student repo)

- Checkpoints are **git tags** on the student repo, named `stage-<shortname>`. The manifest
  `student-repo/checkpoints.yaml` is the single source of truth for their names, order, and
  contents.
- The student repo is a **linear, add-only history**: one commit per stage, each adding the
  `paths` the manifest lists for it, each tagged. A stage **never modifies or deletes** a file an
  earlier stage introduced (the build script refuses): that is what makes `git pull` safe on a
  seat with uncommitted edits.
- Students clone a **served copy that stops at the last released stage** and pick up later labs
  with `git pull` after an instructor runs `release-stage.sh`. Nothing is visible before it is
  taught, same as the share site. The tag is also the lab's recovery point:
  `git checkout stage-x -- labs/<dir>` restores that lab's files in place without moving HEAD.
- The student repo is **generated** by replaying the manifest; never hand-edit the served repo.
  To rename, reorder, insert or update a stage, edit the manifest and the source content, then
  regenerate. A file a lab needs must be in that lab's `paths`, or students will not have it.
- `order` values leave gaps (10, 20, 30…) so a new checkpoint slots between two others.
- Slides and handouts reference checkpoint names as they appear in the manifest, so a rename
  propagates from one place.

## Secrets: hard rules

- **Never commit credentials.** Secrets come from `.env` (git-ignored) or are supplied at
  provisioning. `.env.example` documents every variable. The Gravwell license
  (`gravwell.license`) and the Lab 01b model token (`instructor/runbook/gravwell-llm.env`) are
  git-ignored too; both have `.example` files or are described in `SETUP.md`.
- Sample/lab data is synthetic or de-identified; commit it deliberately (see `datasets/README.md`).
- If you find a real secret in source material, quote its location, don't reproduce it, and flag
  it for rotation.
- The Lab 01b token is handled differently from the Anthropic key on purpose: seats hold the
  Anthropic key directly and a root-only relay holds the model token. The reasoning is in
  `instructor/runbook/api-key-architecture.md`; do not merge the two approaches.

## Tool source

- The vendor-agnostic logging proxy (`src/logging-proxy/llm_audit_proxy.py`) is a single stdlib
  Python file: no build, no deps, runs anywhere. Keep it that way: it is take-home material for
  non-Gravwell shops and students are meant to read and extend it.
- The Gravwell-native path is the official `gravwell/llm_ingester` image, wired as a sidecar in
  the Lab 00 compose. Its listener config is `labs/00-environment-gravwell/config/llm_ingester.conf`.
- The MCP labs use the benign, config-driven server in `src/mcp-lab-server/`. Keep examples
  observable (a tool that reads, counts, reformats); the material teaches how tool manifests steer
  a model and how to see that in telemetry, with "what would the attacker version look like" left
  as discussion.
- Everything student-facing runs over SSH and in the terminal.
- Per-attendee ports derive from `WORKSHOPUID` (10–49). Don't hardcode ports; template on the id.
  The port map lives in `AGENDA.md`.
- Gravwell tags in use: `corelight_dns` / `corelight_ssl` / `corelight_conn` / `corelight_http`,
  `sysmon`, `okta`, `logbot`, `syslog` (litellm container logs, raw text), `llm` (Gravwell LLM
  ingester), `proxy` (vendor-agnostic Python proxy), `mcp` (the student's own MCP lab server), and
  for the beyond-the-wire lab `osquery`, `swg`, `cloudtrail`, `gws`. Reuse these names.
- LLM event schema: both LLM log sources emit the same `event_type` vocabulary
  (`request.user_message`, `request.system_message`, `request.tool_result`,
  `response.assistant_message`, `response.tool_call`, `response.usage`, …). The ingester exposes
  fields as intrinsic enumerated values (`tag=llm intrinsic event_type …`); the Python proxy emits
  JSON (`tag=proxy json event_type …`). Write searches so the same field names work on both.
- Seat count is a parameter (`SEATS`, default 2; ids from `START_ID` within 10–49). Never hardcode it.
