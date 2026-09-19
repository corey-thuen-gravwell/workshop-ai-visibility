---
marp: true
theme: jarvis
paginate: true
header: 'Exploring AI Visibility · Detection & response'
---

<!-- _class: lead -->
# Now catch it
## Turn the behavior into a detection

<!--
You've run the lab. Everything crossed a wire you own. Now go find it, and write the rule that finds it next time.
-->

---

## Correlate the three layers

The story only makes sense when you line them up:

- **Prompt**: what was asked (the LLM ingester, `tag=llm`)
- **Tool call**: what the model chose to do (`tag=llm`, and the server's own log, `tag=mcp`)
- **Action**: what actually ran on the host (Sysmon)

> One host queried an AI domain, its agent called a weird tool, and a process read `/etc/passwd`. Separately: noise. Together: an incident.

<!-- This is the whole thesis realized. No single log tells the story; correlation does. Same skill as the DNS↔SSL correlation, scaled up. -->

---

## What to alert on

- **Unknown / unexpected tools** appearing in `tag=llm`: a tool name you have never seen, or one server's tool called right after another's
- **Excessive tool use** or a silent agent loop
- **Wildcard / recon** file access (`cat /etc/passwd`, SSH keys)
- **Large or odd uploads**: data leaving that shouldn't
- **High bash-spawn** parents (the Sysmon rule from Lab 03)

<!-- Concrete primitives. Most map to a Gravwell search you can schedule + alert on. Start noisy, tune down. -->

---

## Build the alert (lab)

Turn the behavior into a detection:

- An agent calling a tool from a **server the user never asked about**, in `tag=llm` (Lab 07 Part 3)
- Correlate it with the prompt and the tool result that led to it
- Fire a webhook / SIEM notification when the pattern matches

> The lab traffic is your test case: if your rule catches it, it works.

<!-- Lab 07 Part 3: write the detection against the tag=llm traffic the room just produced in Parts 1 and 2. You know the answer, so it's ideal test data. Keep it framed as detection, not attack construction. -->

---

## UEBA for AI

Baseline normal, alert on the deviation:

- This user's usual token volume, tool set, upload size
- A token that suddenly does 10×: stolen key or rogue agent?
- An agent that starts touching files it never touched before

<!-- Same UEBA you already do for humans, pointed at AI identities and agents. The agent has a "normal" too. -->

---

## What you must log

- **Prompts + context** (proxy), the ask
- **Tools called, arguments, results** (the ingester); **tools offered** (the Python proxy adds this)
- **Responses** (proxy)
- **Host process creation** (Sysmon), the action
- **Network** (Zeek / Corelight), the shadow-AI backstop

> If you can't see it, you can't audit it. Architect for auditability **before** the incident.

<!-- The take-home checklist. None of it comes from the vendor. All of it you can stand up yourself, you just did. -->

---

## Where this is heading

- Model-level introspection (Starseer et al.): auditing from *inside* the model
- OpenTelemetry GenAI semconv: structured telemetry, if providers adopt it
- Everything is still moving faster than the safety around it

<!-- The frontier. We built the defensible version today; the research is chasing deeper visibility. -->

---

<!-- _class: lead -->
# Jarvis, wtf did you do?
## Now you can actually answer that.

<span class="muted">Take-home: all lab code · proxy configs · the AI-domain lookup + searches · Sysmon queries · your MCP server configs · the CISO questions</span>

<!-- Close it out. They came in unable to see what their AI was doing. They leave with the telemetry, the searches, and the hands-on scars. Q&A. -->
