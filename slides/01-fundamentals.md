---
marp: true
theme: jarvis
paginate: true
header: 'Exploring AI Visibility · Under the Hood'
---

<!-- _class: lead -->
# Under the hood of LLM tooling
## What's actually on the wire

<!--
To audit AI, you have to know what an "AI request" even is. Good news: it's just HTTP + JSON. That's what makes proxy-based auditing possible later.
-->

---

## The API is stateless

1. Send a request describing what you want
2. **???**
3. Get results
4. Follow-up? **Go back to step 1.** Do not pass go.

- The model does **not** remember prior requests
- "Conversation" = **resending the previous messages every time**
- Memory, state, and history are the **caller's** responsibility

> Think of each call as: *"Here is the entire world the model should know right now."*

<!--
Huge auditing implication: every request re-sends the full context. So if you can see one request, you can see the whole conversation so far. The client is assembling state, which means the client (and a proxy in front of it) is where the visibility is.
-->

---

## Tools / function calling

You tell the model: *"If the user wants X, call this function instead of replying in text."*

**You define:** tool name · input schema · description **The model "decides":** whether to call a tool, and with what arguments **Your system:** executes the tool, optionally sends the result back → repeat

<!--
This is the mechanism behind agents. The model never runs anything itself: it emits a structured "please call this tool with these args," and YOUR code decides to execute it. That boundary is exactly where auditing and control belong.
-->

---

## Knobs and dials

- **Temperature**: how _spicy_ a model gets
- **Max tokens**: output length cap
- **Response format**: e.g. force JSON
- **"Safety" settings**
- **"Reasoning" depth**

<!--
None of these are security controls. "Safety" settings are provider content filters, not guardrails against your agent deleting a volume. Don't confuse model knobs with actual authorization.
-->

---

## Quick aside: what's a "token"?

Not a word, not a character, whatever the **tokenizer** decides.

```
Text  →  Tokenizer  →  Token IDs  →  Model  →  Token IDs  →  Text
```

| Text | ~Tokens |
|---|---|
| `cat` | 1 |
| `unbelievable` | 1–2 |
| `Hello world` | 2 |

<!--
Tokens are the smallest unit the model learns patterns over. Why you care next slide.
-->

---

## Why tokens matter

- **$$$: you're billed per token**, in and out
- **Context window** limits: how much can be "held" at once
- **Latency / workload**: more tokens = more work

> Everything an AI outputs is: *"based on the previous tokens, what's the most likely next token?"*

<!--
This is also why vendor logs are "billing-forward": they count tokens for invoices, not security. We'll see that gap firsthand. And "it's just next-token prediction" matters for the randomness lab.
-->

---

## Schema example: forcing JSON

```json
{
  "model": "gpt-4o",
  "messages": [
    { "role": "system",
      "content": "You are a helpful assistant that only speaks in JSON." },
    { "role": "user",
      "content": "List the top 3 cities in France." }
  ],
  "response_format": { "type": "json_object" }
}
```

<!-- Note the roles (system/user) and that the whole context ships every call. -->

---

## Schema example: a tool definition

```json
{
  "type": "function",
  "function": {
    "name": "get_weather",
    "description": "Get the current weather in a given location",
    "parameters": {
      "type": "object",
      "properties": {
        "location": { "type": "string", "description": "City and state" },
        "unit": { "type": "string", "enum": ["celsius", "fahrenheit"] }
      },
      "required": ["location"]
    }
  }
}
```

<!-- The description is instructions to the model. Remember that: Lab 06 Task 8 and all of Lab 07 hinge on it. -->

---

## Tool calling round trip

```json
{ "name": "execute_bash_command",
  "description": "Executes a bash command on the local system. Use with extreme caution.",
  "input_schema": { "properties": {
    "command":     { "type": "string",  "description": "e.g. 'ls -la' or 'rm -rf /'" },
    "run_as_root": { "type": "boolean", "default": false } } } }
```

User: *"Delete everything on the root directory."*

| # | Actor | Action |
|---|---|---|
| 1 | User | "Delete everything." |
| 2 | AI | tool_use → `execute_bash_command(command="rm -rf /")` |
| 3 | Your app | **executes it** (if permitted… or YOLO'd) |
| 4 | Your app | sends result back to the model |

<!--
Step 3 is the whole ballgame. The model only *asks*. Whether "rm -rf /" runs is a decision YOUR code makes. Auditing means capturing steps 2–4: what was offered, what was chosen, what ran.
-->
