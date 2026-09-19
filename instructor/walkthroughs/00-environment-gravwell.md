# Walkthrough 00: Environment onboarding & stand up Gravwell

> ⛔ **INSTRUCTOR ONLY.** Do not distribute. Student handout:
> [`labs/00-environment-gravwell/README.md`](../../labs/00-environment-gravwell/README.md).

**Module:** Lab A · **Budget:** 60 min · **Checkpoint:** `stage-gravwell` · **Flex:** 🔒 never cut

This is the module that decides whether the rest of the class works. Every later lab assumes a
running, licensed, reachable Gravwell. Budget the full hour and do **not** let it run long by
debugging one seat in front of the room, see *Triage* below.

---

## Timing

| Min | Segment | Notes |
|---:|---|---|
| 0–10 | SSH in, verify the seat | The slowest part. Windows attendees + PuTTY are the long pole |
| 10–15 | `docker run hello-world` | Proves the docker group applied |
| 15–25 | `docker compose up -d`, watch it come up | Image is pre-pulled; should be fast |
| 25–40 | Browse the UI, log in | Cert warnings and typo'd ports live here |
| 40–50 | First `tag=` search in Query Studio | Teach the query bar, not the data |
| 50–55 | `make-token.sh`, the API token | One command; the talk track matters more than the time |
| 55–60 | Buffer / catch up stragglers | **Always** gets used |

## Before the room arrives

Run the pre-flight and require a clean exit:

```bash
sudo SEATS=20 START_ID=10 /path/to/instructor/runbook/scripts/preflight.sh; echo "exit=$?"
```

Non-zero exit means a ❌ somewhere. The ones that will *actually* ruin the class:

- `gravwell license missing`, nothing starts. Login **and** ingest both return
  `{"Error":"missing license"}` and the indexer never opens its pipe.
- `cert expires in N days` / `no cert at /opt/workshop/certs`: students get browser errors they
  cannot click through on some managed laptops.
- `N seats missing` / `N seats not in docker group`, re-run `makeuser.sh`.
- `ANTHROPIC_API_KEY missing/malformed`: doesn't bite until M7, but fix it now.

`❌ /opt/gitsrv/jarvis.git missing` means you have not run **`build-student-repo.sh`** yet. Run it
*before* `makeuser.sh`, or seats get no `~/jarvis` and every `cd ~/jarvis/...` path in every
handout fails. Re-run it the morning of class so Lab 02/03 data lands inside the "last 48 hours" the handouts ask for.

Also confirm the images are present so 20 seats don't pull simultaneously over venue wifi:

```bash
docker image inspect gravwell/gravwell:latest gravwell/llm_ingester:5.10.1 \
    hello-world:latest >/dev/null && echo pulled
```

> Note: `preflight.sh` checks for `gravwell/llm_ingester:**latest**` but the compose pins
> `:5.10.1`. Pre-flight will warn even when the correct image is present. Harmless, but don't let
> it send you chasing a non-problem.

---

> **Offer `materials/linux-cheatsheet.md` now, to the whole room.** It is the terminal itself
> (`~`, `cd`, Tab completion, `nano`'s three keys, how to escape a `>` prompt), with every example
> taken from this course. It holds no lab answers, so unlike the terminal cheatsheet there is no
> reason to hold it back: publish it with `share publish materials/linux-cheatsheet` and read the
> URL out. The people who need it are rarely the people who will ask for it.

## Step 1: SSH in (10 min)

Write these on the whiteboard before you start talking:

```
ssh workshop<ID>@<lab-host>
password: workshop<ID>password
```

Hand out seat IDs on index cards or a slide. IDs start at **10** and run to `10 + SEATS - 1`,
so a class of 20 is **10–29**. (The scripts' own default is 2 seats, 10–11: that is for
development and self-guided readers, so pass `SEATS=` the roster size when you provision.)

**What to say:** "Your ID is the number on your card. It shows up in every port you'll type today.
If a command in the handout says `${WORKSHOPUID}443` and your ID is 14, that's port 14443."

**Expected:** a normal bash prompt as `workshop<ID>`.

**Failure modes:**

| Symptom | Cause | Fix |
|---|---|---|
| `Permission denied (publickey,password)` | Typo'd username or password | Password is `<username>password` unless `WORKSHOP_USER_PASSWORD` was set in `.env`. Check which |
| Windows attendee has no SSH client | - | Windows 10+ has `ssh` in PowerShell. Fall back to PuTTY; have someone float |
| Connection refused / times out | Venue firewall blocks 22 outbound | **Check this at the venue the day before.** No workaround from inside the room |

## Step 2: Verify the seat (5 min)

```bash
echo $WORKSHOPUID
docker run --rm hello-world
```

**Expected:** the seat number, then hello-world's "installation appears to be working correctly".

**Failure modes:**

| Symptom | Cause | Fix |
|---|---|---|
| `echo $WORKSHOPUID` prints nothing | Not an interactive/login shell (rare when they just SSH'd in) | `. ~/.workshop_env` |
| `permission denied while trying to connect to the Docker daemon socket` | The `docker` group membership applies at **next login** | `exit` and SSH back in. `newgrp docker` also works but confuses people |

> This is the single most common Lab 00 failure. If a seat was created *after* someone already
> logged in, they will hit it. Say up front: "if docker says permission denied, log out and back
> in: that's the fix, it's not you."

## Step 3: Bring up the stack (10 min)

```bash
cd ~/jarvis/labs/00-environment-gravwell
docker compose up -d
docker compose ps
```

**Expected:** two containers, `<ID>gravwell` and `<ID>llm`, both `Up`. The compose project is
named after `WORKSHOPUID`, which is how `rmuser.sh` finds and tears down a seat.

Watch it settle:

```bash
docker compose logs -f gravwell | head -60
```

**Failure modes:**

| Symptom | Cause | Fix |
|---|---|---|
| `Failed authentication, bad secret` from simple_relay | Only one of `GRAVWELL_INGEST_AUTH` / `GRAVWELL_INGEST_SECRET` set | Both must be set to the same value. The compose does this from `.env`; if someone edited it, restore |
| simple_relay logs pipe-connect retries at startup | Indexer isn't up yet | **Benign.** Say so out loud or twenty hands go up |
| `<ID>llm` restarting in a loop, `device or resource busy` | The ingester rewrites its config on boot (stamps `Ingester-UUID` via temp-file + rename) and can't do that on a `:ro` bind mount | The compose already mounts to `/config/` and `cp`s it in. If someone "simplified" the mount, revert. **The manager backs off for 10 minutes after 3 failures**: you cannot just retry your way out; fix the mount, then `docker compose up -d --force-recreate llm-ingester` |
| `missing license` in the logs | License not mounted | It's mounted read-only from the repo root. Check the file exists and is non-empty |
| `port is already allocated` | Another seat's stack, or a stale container | `docker ps -a`, find the holder. Two students on one seat ID is the usual cause |

## Step 4: Reach the UI and log in (15 min)

```
https://<lab-host>:<ID>443
```

**Expected:** a browser-trusted Let's Encrypt cert (`CN=<lab-host>`) and the Gravwell login page. Credentials `admin` / `changeme`.

No forced password change on first login. A seat that changes the password only has to remember
the new one for the UI: since Step 5b every script authenticates with an API token instead, so a
changed password does not break the labs.

**Failure modes:**

| Symptom | Cause | Fix |
|---|---|---|
| Cert warning | Seat is running the self-signed fallback (`WORKSHOP_CERT_DIR` unset → `./config/`) | Check `~/.workshop_env` has `WORKSHOP_CERT_DIR=/opt/workshop/certs`, then recreate the container |
| Connection refused | Wrong port: they used their seat number, not `<ID>443` | The port is the ID *followed by* 443 |
| Page loads over HTTP, not HTTPS | `https.conf` drop-in not mounted | The image defaults to HTTP on :80 and **ignores** `GRAVWELL_WEB_PORT`; the drop-in is what moves it |
| Loads but login returns an error | License | See above |

**Teaching beat while they wait:** this is one Gravwell per person, in docker, on one box. Nobody
sees anyone else's data, and if you wreck yours we throw it away and make a new one. That's the
point of the whole disposable-lab design: say it now so people experiment freely later.

## Step 5: First search (10 min)

Open **Query Studio**. The goal here is the query bar and the time picker, not the data, the
timeline is essentially empty until Lab 02.

```
tag=gravwell limit 20
```

**Expected:** Gravwell's own internal logs. This gives them something non-empty to look at.

`tag=gravwell` is where Gravwell logs about itself (webserver, indexer, searchagent), so a one-hour
window has entries from the moment the stack booted.

Useful framing: their timeline is *not* empty, but everything in it is **the SIEM talking about
itself**. No security data until Lab 02. That's a truer picture of a new deployment than an empty
screen, and it gives them something to click.

Teach three things and stop:

1. **The time picker.** Every "no results" complaint from here on is a time-range
   problem. Show them where it is. Say it twice.
2. **`tag=` comes first.** It's the index selector, not a filter.
3. **The pipeline.** `|` chains modules left to right. They'll see `json`, `lookup`, `stats`,
   `table` in Lab 02.

## Step 5b: Mint the API token (5 min)

```bash
cd ~/jarvis/labs/00-environment-gravwell && ./make-token.sh
. ~/.workshop_env
echo "${GRAVWELL_TOKEN:0:6}..."
```

**Expected:** `Token created and verified: /home/workshop<ID>/.gravwell_token`, `49 capabilities`,
then six characters of the token. Re-running it says `You already have a working token`: it is
idempotent, so a student who runs it twice has not broken anything.

This is the credential every later script and `curl` uses. It exists because of a real failure in
a live class: scripts logged in as `admin`/`changeme`, and a seat that changed its password
got confusing auth errors in labs that had nothing to do with passwords.

Three points to make, briefly, because they pay off in Lab 06:

1. **The header is `Gravwell-Token:`**, not `Authorization: Bearer`. A token sent as a bearer
   credential returns 401.
2. **It is scoped.** The script grants every capability the instance offers except token
   management, so the credential cannot mint another credential. `curl $GW/api/tokens` with it
   returns 403, which students do in Lab 06 Task 5.
3. **Capabilities only subtract.** A token is an overlay on the user's own permissions, so it can
   never grant more than the account has.

**Failure modes:**

| Symptom | Cause | Fix |
|---|---|---|
| `Could not log in` | Gravwell is still starting, or they changed the admin password | `docker compose ps`, then re-run; if the password changed, `GW_PASS='new one' ./make-token.sh` |
| `$GRAVWELL_TOKEN` is empty | The shell predates the token file | `. ~/.workshop_env` in that shell. A new terminal gets it automatically |
| Later script says "No Gravwell API token" | They skipped this step | Run it; nothing else is lost |

> A seat that wipes its Gravwell volumes (`docker compose down -v`) gets a new instance, and the
> old token dies with it. Re-running `make-token.sh` notices the dead token and mints a fresh one.

## Step 6: Confirm ingest listeners are bound (5 min, optional)

Worth doing if you're ahead of schedule: it turns Lab 02's "nothing showed up" into a
five-second check instead of a ten-minute debug:

```bash
ss -ltn | grep -E ":(${WORKSHOPUID}0[1-8])\b"
```

**Expected:** eight listeners, `<ID>01`–`<ID>08`.

---

## Answers to the student tasks

1. SSH in: no answer, it either works or you triage it.
2. `echo $WORKSHOPUID` → their seat number. `hello-world` → the standard success message.
3. `docker compose up -d` → `<ID>gravwell` and `<ID>llm` both `Up`.
4. UI on `https://<lab-host>:<ID>443`, login `admin`/`changeme`, `tag=gravwell limit 20`
   in Query Studio. Timeline is otherwise empty: data arrives in Lab 02.
5. `./make-token.sh` writes `~/.gravwell_token` (0600) and `. ~/.workshop_env` exports it as
   `$GRAVWELL_TOKEN`. The verification `curl` against `/api/resources` returns `0`: a fresh
   instance has no resources yet, and `0` still proves the token authenticates.

## Triage policy

With 20 seats you will have 2–4 stuck people. **Do not debug from the front of the room.**

- Instructors float; one stays on the projector and keeps moving.
- The two fixes that cover most cases: **log out and back in** (docker group), and
  **`. ~/.workshop_env`** (missing `WORKSHOPUID`).
- Nuclear option for one seat, from root on the host:
  ```bash
  cd /home/workshop<ID>/jarvis/labs/00-environment-gravwell
  sudo -u workshop<ID> WORKSHOPUID=<ID> docker compose down -v
  sudo -u workshop<ID> WORKSHOPUID=<ID> docker compose up -d
  ```
  `down -v` drops the named volumes and re-initializes from the image: about a minute, and it
  clears essentially every "I broke it" state. Nothing is lost this early.
- Last resort: pair them with a neighbour. Nobody sits out Lab 02 because of Lab 00.

## What this module is really for

Two things, and it's worth being explicit with your co-instructors about both:

1. **Gentle Linux ramp.** Most of the room is weak on the terminal. Lab 00 is where they get used
   to typing paths and reading error messages, on a task where failure is cheap.
2. **Everything downstream assumes it worked.** A seat that limps out of Lab 00 will fail Lab 02
   and stay failed. Spend the buffer here, not later.
