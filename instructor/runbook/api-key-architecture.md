# The API key: why students hold it directly

**Decision:** seats get the **real** Anthropic key in `~/.workshop_env` (0600).
There is no gateway in front of it.

## Why not proxy it

An earlier design ran a root-owned gateway on `127.0.0.1:9000` holding the real key, with seats
presenting a workshop token. It worked: and it was the wrong call. Three reasons, in order of how
much they matter:

1. **It stole the lesson.** Lab 05 Part 2b has students run the logging proxy with
   `--upstream-key`/`--client-key` and notice their workstation no longer holds a provider key.
   That's the key-boundary lesson, and it lands because *they build it*. A gateway doing the same
   thing invisibly from Lab 01 means they've been living in the architecture for a day without
   understanding it, and the reveal is spent.
2. **It was a single point of failure for the whole class.** Gateway down → 20 seats lose every AI
   lab at once. Direct-to-provider has no such coupling.
3. **It broke two labs.** The gateway bound loopback, which host processes reach fine (Lab 01's
   `curl`, opencode in Labs 04/06, Lab 05's Python proxy) but containers cannot, a container routes
   via its bridge address. litellm couldn't start and the LLM ingester returned
   `401 invalid x-api-key`. Verified from inside the ingester container:
   `wget http://172.18.0.1:9000/` → *Connection refused*.

## The threat model, stated plainly

Attendees are external conference-goers, so this isn't nothing, but the exposure is small and
bounded:

| | |
|---|---|
| Key lifetime | Short-lived, and **revoked when the class ends** |
| Spend | Spend-limited on the Anthropic side |
| Where it lives | Each seat's `~/.workshop_env`, mode 0600, on a disposable lab host |
| Worst case | An attendee uses it for something else before revocation, inside the spend cap |

That is cheaper to accept than to engineer around. Rotate on the day the class finishes.

## What this means operationally

- `makeuser.sh` writes `ANTHROPIC_API_KEY` into each seat's `~/.workshop_env` (0600, owned by the
  seat). Nothing else needs to know it.
- `/opt/workshop/.env` still holds the canonical copy for provisioning; keep it 0600.
- Lab 01 curls `https://api.anthropic.com/v1/messages` directly, no proxy, which is also the
  truest version of "it's just HTTP and JSON."
- Labs 04/05/06 point clients at the LLM ingester or the Python proxy, which **pass the key
  through**. That is the shipped config and it is deliberate.
- **To rotate:** change it in `/opt/workshop/.env`, re-run `makeuser.sh` (idempotent, it rewrites
  every seat's `~/.workshop_env`), and revoke the old key.

## The key boundary is still taught: as a lab

`scripts/start-gateway.sh` remains in the repo as a **reference implementation**, deliberately not
wired into provisioning. It's the production shape of what students build by hand in Lab 05:

```bash
./llm_audit_proxy.py --listen 0.0.0.0:${WORKSHOPUID}90 --upstream https://api.anthropic.com \
    --upstream-key "$ANTHROPIC_API_KEY" --client-key some-shared-token
```

Then remove the key from the client's config and give it the shared token instead. **The workstation
stops holding a provider key.** Revoking one developer becomes a line in a proxy config rather than
a fleet-wide rotation.

Use `start-gateway.sh` if you want to show the systemd-service version during the M9 architecture
discussion: it also self-verifies the 200-with-token / 401-without gate, which is a nice thing to
demonstrate live.

## The one gateway we *do* run: the Lab 01b relay

`scripts/start-llm-relay.sh` installs `workshop-llm-relay`: a root systemd unit running
`scripts/llm_relay.py` on **`127.0.0.1:9010`**, in front of the Gravwell research LLM that Lab 01b
(demystifying how AI thinks) uses. Seats get `GRAVWELL_LLM_URL=http://127.0.0.1:9010` and nothing
else; the relay adds the bearer token and forwards only `/api/generate`, `/api/embed`, `/api/tags`.
The token exists on the host in exactly two places: `/opt/workshop/gravwell-llm.env` (root, 0600) and
root's relay process. **For this lab, and this lab only.**

Why this doesn't contradict the three reasons above:

1. **No lesson to steal.** Lab 01b is about what the *model* is, not about key handling. Lab 05 still
   builds the key boundary by hand for the Anthropic key, which is the one students hold directly.
   If anything, having quietly used a relay in M2b makes the Lab 05 reveal land harder, the
   handout's last discussion point plants it.
2. **A tolerable single point of failure.** One 45-minute module depends on it, not the whole class,
   and it's a 90-line stdlib process with `Restart=always`.
3. **Nothing in a container needs it.** Every Lab 01b call is `curl` from the seat's shell on the
   host, so loopback is reachable. That's the exact property the Anthropic gateway lacked.

And why the *token* deserves it when the Anthropic key doesn't: it isn't a spend-capped throwaway
we revoke tomorrow. It's the credential to a Gravwell research box, rotated per workshop but not
per day, and a room of external attendees shouldn't walk out with it. Rotation:
edit `instructor/runbook/gravwell-llm.env` (git-ignored), then `start-llm-relay.sh restart`.
