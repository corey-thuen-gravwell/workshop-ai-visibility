# Automated end-to-end pass (instructor-side)

Three scripts that walk every lab as a seat user and print ✅/❌ per check against the known
answers. They are the automated counterpart of the human dry run in `../../dry-run-protocol.md`:
they prove the host, data, scripts and queries work; they say nothing about whether the handouts
read well.

| Script | Covers | Spends API money |
|---|---|---|
| `pass1.sh` | Labs 01, 01b, 00, 02, 03 (incl. the Sysmon kit and its macro fix) | a few cents (Lab 01 curls) |
| `pass2.sh` | Labs 04 and 05 (real opencode sessions, litellm, ingester, Python proxy, gateway stretch) | ~$0.50 |
| `pass3.sh` | Lab 06 parts 1 and 2 (incl. Task 8), Lab 07 (the chain, the flag, the thief, the hidden version, the control, the `tag=llm` detections), P9, P8, P2 premises, P4; tears the seat's stacks down | ~$0.80 |

Run them **in order, as one seat, from a clone of the complete history** (the served repo may
stop at Lab 01), **against a stack that holds no lab data yet**: every count is for one ingestion
of the fixtures, and `pass1.sh` refuses to continue if `tag=corelight_conn` already has rows
(`docker compose down -v` in `labs/00-environment-gravwell` first). They are not a "did I get it
right" check to run after doing the labs by hand. UI-only steps (kit install, macro edit) use the
REST API as a stand-in. Each script exits non-zero if any check failed and prints the count last.

```bash
# on the host, as root; pick a seat nobody is using
SEAT=11
git clone -q /opt/gitsrv/jarvis-all.git /tmp/j && git -C /tmp/j remote set-url origin /opt/gitsrv/jarvis.git
# pass3 reads the Lab 07 reference TOMLs from materials/terminal-cheatsheet.md, which is not in the
# student repo: put a seat-readable copy at /tmp/terminal-cheatsheet.md before running pass3.
cp /opt/workshop/src/materials/terminal-cheatsheet.md /tmp/terminal-cheatsheet.md && chmod 644 /tmp/terminal-cheatsheet.md
rm -rf /home/workshop$SEAT/jarvis && mv /tmp/j /home/workshop$SEAT/jarvis && chown -R workshop$SEAT: /home/workshop$SEAT/jarvis
# The scripts have to be somewhere the seat can READ: /opt/workshop is 0750 root, on purpose.
mkdir -p /tmp/e2e && cp /opt/workshop/src/instructor/runbook/e2e/pass*.sh /tmp/e2e/
chmod 755 /tmp/e2e /tmp/e2e/*.sh
for p in pass1 pass2 pass3; do sudo -u workshop$SEAT bash -l /tmp/e2e/$p.sh; done
START_ID=$SEAT SEATS=1 /opt/workshop/src/instructor/runbook/scripts/reset-seats.sh     # back to pristine
```

Each pass is worth backgrounding so an SSH drop cannot kill it:

```bash
nohup setsid sudo -u workshop$SEAT bash -l /tmp/e2e/pass2.sh > /var/log/e2e-pass2.log 2>&1 < /dev/null &
```

About 25 minutes end to end.

The passes also run on a solo box (one user, `~/.workshop_env` from `SETUP.md`, the authoring
repo as `~/jarvis`); the whole sequence was run that way on a fresh 4 GB Debian 13 VM and on
Ubuntu 24.04 under WSL2. Expect up to four Lab 01b checks in `pass1.sh` to differ there: the
expected token count, 4096 dimensions and the two first-pick words are the class's hosted model's,
and a local `llama3.2` plus `qwen3-embedding:0.6b` give 6, 1024 and its own picks (the WSL run
matched the words and differed only on the first two). The `stage-sysmon` checkpoint falls back to
`HEAD` on a clone without the classroom tags. Everything else is model-independent.
`pass3.sh` also creates, waits for and deletes a scheduled search, which proves the search agent
can reach the HTTPS webserver; that check adds up to two minutes.

The Sysmon kit step retries the kit-server listing (the first request after boot has returned empty
once).