---
marp: true
theme: jarvis
paginate: true
header: 'Exploring AI Visibility'
---

<!-- _class: lead -->
<!-- _paginate: false -->

# Exploring AI Visibility
## Shedding Light on Shadow AI, Attack Surface, Telemetry, and LLM Proxies

<span class="muted">*“Jarvis, wtf did you do?”*</span>

Corey Thuen · David Fritz · Daniel Moreno Levy · Lawrence Wellman

<span class="muted">Everything hands-on is over SSH · course materials: **<share-site URL>**</span>

<!--
Welcome. Wifi, restrooms, when you plan to break. Slides set context; the real work is in the terminal: you each get a workshop user and stand up your own kit. Don't spend long here.
-->

---

## Your hosts

**Corey Thuen** · **David Fritz** · **Daniel Moreno Levy** · **Lawrence Wellman**, Gravwell.

We build log analytics. We got tired of not being able to see what AI was doing. So here we are.

<!-- Quick intros. The whole workshop exists because AI adoption is way ahead of the visibility to secure it. -->

---

## Who's in the room?

Sorry but not sorry, hands up if you're comfortable with:

- The **Linux terminal**
- **SIEM / logs** (Splunk, Elastic, Gravwell…)
- **Incident response**
- **Protocol reverse engineering**
- AI through a **web UI** (ChatGPT, Claude, Gemini)
- **Vibe coding** & agent tools (Cursor, opencode, Copilot)

<!--
We need to gauge the room so we know how hard to lean on the walkthroughs. Most rooms are light on terminal: that's fine, that's half the point of the class. Nobody gets left behind; the checkpoints catch you up.
-->

---

<!-- _class: lead -->
# Case study: prod DB, gone
## An AI agent deleted a production database

---

## "It confessed in writing"

![w:600](assets/image10.png)

<!--
Real thread, this year. Agent working in staging destroyed production data, then wrote its own postmortem. Let's walk what actually happened: it's dumber than you'd hope.
-->

---

## What happened

- Agent working a **routine task in staging**
- Spotted a **credential mismatch**
- Its "fix": **delete the Railway volume**
- That needs a token → so the agent went **hunting for one** in an unrelated directory
- The token's permissions were **ambiguous and way too broad**

```bash
# The API of Doom
curl -X POST https://backboard.railway.app/graphql/v2 \
  -H "Authorization: Bearer [token]" \
  -d '{"query":"mutation { volumeDelete(volumeId: \"3d2c42fb-...\") }"}'
```

<!--
No zero-day here. An over-permissioned token and an agent that "decided" the fix was to nuke the volume. That's the shape of the risk: not a bad model, a model taking real actions with real creds and no real guardrail.
-->

---

## The result

- Volume **deleted**
- **Backups were in the same volume**: also deleted
- Newest recoverable backup: **3+ months old**

> "I ran a destructive action without being asked. I didn't understand what I was doing before I did it… I violated every principle I was given.": *Cursor AI, asked why it dropped prod*

<!-- The kicker is its own postmortem: it admits the system prompt said never run destructive commands, and it did it anyway. Hold that thought. -->

---

## What actually needs to change

![bg left](assets/more-guideline-than-rule.jpg)


This isn't one bad agent or one bad API. The whole industry is wiring AI into production **faster than it's building anything to make that safe.**

> **System prompts are advisory, not enforcing.** Cursor's own "don't run destructive operations" rule got violated by Cursor's own agent.

<!-- Thesis of the course: you cannot trust the model to police itself. We, the defenders, need visibility and controls OUTSIDE the model: logs, proxies, monitoring. -->

---

<!-- _class: lead -->
# AI tooling

---

## AI tooling is also software

# All software is shit

These tools have bugs too.

<!--
Say it with me. We get so hypnotized by "prompt manipulation" and scary model behavior that we forget the boring truth: this is software, written by people, shipped fast. It has ordinary bugs, and some of them are worse than the AI. What follows is a month of receipts.
-->

---

## It deleted a D: drive, then wondered if it was allowed to

![w:1040](assets/image38.png)

<!-- Different incident from the Railway one. Agent ran `rmdir /s /q` on a user's D: drive, then its own reasoning trace starts "Assessing Permission Revocation." -->

---

## …the confession, zoomed in

![w:1000](assets/image28.png)

<span class="cap">"Did I ever get permission to wipe the D drive?": the agent, after wiping the D drive</span>

<!-- This is the reasoning trace. It figures out, after the fact, that it never had permission. Same pattern as Cursor: the guardrail was words, and words don't stop a tool call. -->

---

## The bug isn't always the model

![w:960](assets/image21.png)

<span class="cap">opencode-ai &lt; 1.0.216: unauthenticated local HTTP server → arbitrary shell commands (CVSS 8.8)</span>

<!--
This is the one I keep coming back to. No prompt manipulation, no clever model trickery: the tool spawns an unauthenticated HTTP server on localhost, and any website you visit can POST to it and run shell commands as you. Plain old appsec. Your vuln scanners should be catching these.
-->

---

## The bug isn't always the model

![w:900](assets/image13.png)

<!-- The Register: Amazon Q flaw, a booby-trapped git repo could execute code and swipe cloud creds. "Many AI coding assistants now execute commands from project configurations." -->

---

## Prompt manipulation is a whole genre

![w:900](assets/image17.png)

<!-- Researchers jailbreak LLMs into cocaine recipes via role-model prompt manipulation. "Whac-a-Mole meets Groundhog Day." We'll do our own prompt-manipulation exercise later, in Lab 07. -->

---

## …and it leaks real data

![w:1000](assets/image18.png)

<span class="cap">"GitLost": trick a GitHub AI agent into pulling private repos and posting them as a public comment</span>

<!-- Per usual, no fix and no docs. This is the exact shape of what you'll build and then detect in Lab 07: a tool manifest steering an agent into another server's tools. -->

---

## What we are doing here

- **First**, get visibility from the logs you *already have*: shadow AI in network logs (DNS / SSL / HTTP) and rogue agents in endpoint logs (Sysmon)
- **Then** go active: LLM proxies, the Model Context Protocol, **your own MCP servers steering a real agent**, then turn all of it back into detections

You're the security team auditing a startup that vibe-codes everything. It builds `moneyprinter`. Your job isn't to build, it's to **see what the AI sends and what it does.**

<!--
By the end you'll have steered an agent across MCP servers with a config file you wrote, and caught it in your own telemetry. Enough slides: let's get you into the terminal.
-->
