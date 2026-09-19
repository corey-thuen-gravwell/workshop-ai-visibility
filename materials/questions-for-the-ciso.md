# Questions for the CISO
### A one-page take-home · *Exploring AI Visibility*

Ten questions about AI usage in your environment. They are ordered so that each one is harder to
answer than the last, and **none of them is about which model you use.**

Score yourself honestly: **Yes / No / I'd have to go find out.** The third answer is the most common
one, and it is the real finding.

---

### Discovery: do you know it's happening?

**1. How many distinct AI services did your network talk to last month?**
Not "which are approved." How many *were used*. If the answer comes from a vendor invoice rather
than your own logs, you're counting what you pay for, not what you run.

**2. Which of those did you learn about from a log, and which from a person telling you?**

**3. If an employee uses an AI tool over DNS-over-HTTPS, or a model hosted inside your own network,
which control notices?**
Domain blocklists are browser-facing. They do not contain `api.anthropic.com`, and they will never
contain `ollama.internal.yourcorp.com`.

### Content: do you know what was said?

**4. Can you produce the text of a single prompt an employee sent to an AI provider last week?**
Most organizations cannot produce one, ever, for any employee, at any time.

**5. If a developer pasted a customer record or a private key into an AI tool, what would tell you?**
Follow-up: would it tell you *at the time*, or only if you already suspected and went looking?

**6. Your AI vendor's audit log: is it a security log or a billing log?**
Read the field list. Count how many fields describe *what happened* versus *what it cost*.

### Agents: do you know what it did?

**7. For an AI coding agent running on a developer's laptop, can you list the tools it was offered
on its last run?**
Not the tools it used. The tools it *could* have used. That's the blast radius, and it changes
silently whenever someone adds an MCP server.

**8. If an agent ran a shell command that read a credential file, which log has it, and how long
does that log live?**
If the answer is "the tool's own history file on that laptop," ask who can delete it. (The user
can. So can the agent.)

**9. When an AI tool acts, whose credentials does it act with, and who approved that scope?**
An MCP server's real blast radius is the token you handed it, not the tool list it advertises.

### Accountability: could you reconstruct it?

**10. An incident review asks: "what did the AI do, when, at whose instruction, and what did it
send outside the company?" How much of that can you answer from logs you already keep?**

---

### If the answers were uncomfortable

That is the normal result, and the gap is structural, not a failure of diligence: the tools log for
their users, the vendors log for their invoices, and nobody logs for you.

**Three things that move the needle, cheapest first:**

1. **Discover before you control.** You cannot collect from tools you haven't found. Network logs
   you already have, DNS, TLS SNI, connection records, will give you the inventory, if you
   correlate them rather than trusting any single one.
2. **Put something in the path.** A proxy is the only place that sees prompts, tool calls and
   responses without asking a vendor for permission. It is also where a key boundary belongs, so
   developer workstations stop holding provider credentials.
3. **Log the offer, not just the action.** Record what an agent *could* do on each turn, not only
   what it did. That is the number that predicts your next incident.

<span style="font-size:0.85em">*Exploring AI Visibility: Shedding Light on Shadow AI, Attack Surface, Telemetry, and LLM Proxies*, Gravwell</span>
