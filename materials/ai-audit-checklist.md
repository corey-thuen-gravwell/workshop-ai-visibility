# AI Audit Checklist
### A one-page take-home · *Exploring AI Visibility*

What to collect, in the order you can realistically get it. Each tier answers a question the tier
above it cannot.

---

## Tier 1: Discovery · *"who is using what?"*
**From logs you already have. Start here; it costs nothing new.**

- [ ] **DNS query logs**: resolve against an AI-domain list. *Finds:* browser-based AI use.
      *Misses:* DoH, self-hosted, provider API hosts (most blocklists are browser-facing).
- [ ] **TLS SNI / certificate logs**: server names on outbound sessions. *Misses:* QUIC/HTTP-3
      (no TLS record to read), and anything on a shared CDN address.
- [ ] **Connection records with byte counts**: the piece that separates *resolved* from *used*.
- [ ] **Plaintext HTTP host + URI**: the only thing that finds self-hosted models and internal MCP
      gateways, whose hostnames are on nobody's list.
- [ ] **SSO / IdP logs**: ties a host to a *person*. Only covers apps behind your IdP.

> **The one technique that matters:** correlate DNS answers to connection records **per host**.
> "This host resolved that AI domain **and** moved bytes to the address it got back." Any single
> signal produces false positives; the correlation doesn't.

## Tier 2: Endpoint · *"what did the agent do on the machine?"*

- [ ] **Process creation events** (Sysmon / EDR). Agents have a distinctive shape: hundreds of
      short-lived children from one parent.
- [ ] **Cluster by child count per parent PID**, not by parent process *name*, on Linux, Sysmon's
      parent metadata is often empty for exactly the fast-spawning workload you care about.
- [ ] **Command lines of those children.** This is where the real behaviour is visible.
- [ ] ⚠️ **Know what you can't get.** The agent's own history file holds the full transcript, and
      it lives on the machine you're investigating, ships nowhere, is a per-tool format, and the
      user (or the agent) can delete it. Collect it if you can; don't build on it.

## Tier 3: The path · *"what was actually said?"*
**The only tier that sees content. Nothing above it can.**

- [ ] **A logging proxy between clients and providers.** A generic API gateway is not this, it
      logs like a load balancer: that a request happened, and nothing about it.
- [ ] Capture, at minimum:
      - [ ] `user_message` / `system_message`: the prompt, and the standing instructions
      - [ ] `assistant_message`, the reply
      - [ ] `tool_call`, name **and arguments**
      - [ ] `tool_result`: what came back into the model's context
      - [ ] `usage`, prompt and completion tokens
      - [ ] **`tools_offered`**: every tool available on that turn. *The one most proxies skip, and
            the one that measures blast radius.*
- [ ] **A session identifier.** Have clients send one; inferring sessions by prefix-matching breaks
      on identical system prompts and long pauses.
- [ ] **Put the provider key in the proxy, not on workstations.** Clients present a token you issue.
      Revocation becomes one config change instead of a fleet-wide key rotation.

## Tier 4: Agent surface · *"what could it have done?"*

- [ ] **Inventory MCP servers** connected to each client. Tools are discovered at runtime, your
      inventory is only as fresh as the last `tools/list`.
- [ ] **Log tool discovery as an event**, so a newly-added capability is a detectable change rather
      than a silent one.
- [ ] **Record which tool descriptions are in play.** A tool description is a prompt fragment
      written by whoever wrote the server, and it lands in your model's context verbatim.
- [ ] **Scope the credential you hand each MCP server.** Blast radius is the token, not the tool
      list. This is the cheapest real control on this page.

---

## Detections worth building first

1. **Resolved-but-never-connected**: hosts that look like AI users and aren't. Tune this out early
   or your program loses credibility on false positives.
2. **The correlation positives**: host resolved an AI domain *and* moved bytes to that address.
3. **High-child-count parent processes**: agent shape on the endpoint, no signature needed.
4. **Volume and time outliers**, large uploads, off-hours bursts. Nobody types 48 MB.
5. **Tool-offer drift**: an agent's advertised tool list changed. Someone added an integration.

## Architecting for auditability

- **Assume the client won't tell you.** Design as if every tool is a black box that reports nothing.
- **Own the path.** Egress proxy per network, gateway per team, sidecar per CI runner, whichever
  fits, but own one.
- **Log the event model, not the vendor format.** `event_type`, `session_id`, `tool_name`,
  `tokens`: these outlive whichever provider and SIEM you use this year.
- **Discovery is a standing job, not a project.** New tools appear continuously and store their
  data wherever they like. The method transfers; a list of file paths does not.

<span style="font-size:0.85em">*Exploring AI Visibility: Shedding Light on Shadow AI, Attack Surface, Telemetry, and LLM Proxies*, Gravwell</span>
