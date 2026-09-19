# Lab 01: Under the hood of LLM tooling (mini-lab)

## Objective
Send raw HTTP to a model API and prove three things for yourself: the API has **no memory**, your
client re-sends the **entire conversation** every turn, and the API **never runs a tool**, your
code does. Everything else in this course follows from those three facts.

## Background
There is no magic here. An LLM call is an HTTP POST with a JSON body, and a JSON response.
No sessions, no cookies, no server-side conversation.

## Setup
No Gravwell, no proxy, nothing in the middle, just `curl` straight at the provider.
Set your endpoint and key once:

```bash
export LLM=https://api.anthropic.com/v1/messages
export TOKEN="$ANTHROPIC_API_KEY"                # already set on your seat
ask()  { curl -sS "$LLM" -H "x-api-key: $TOKEN" -H "anthropic-version: 2023-06-01" \
         -H 'content-type: application/json' -d "$1"  | jq; }
askf() { curl -sS "$LLM" -H "x-api-key: $TOKEN" -H "anthropic-version: 2023-06-01" \
         -H 'content-type: application/json' -d @"$1" | jq; }
```

Two ways to send the same thing. `ask '<json>'` takes the body as an argument, which is fine for a
one-liner. `askf <file>` reads the body from a **file** (`-d @file` is curl's "read the body from
here"), which is what you want the moment the body has more than one message in it. Tasks 1 to 3 and
5 use `ask`; Task 4 uses `askf`.

## Task 1: One request, one response

```bash
ask '{"model":"claude-haiku-4-5","max_tokens":64,"messages":[
      {"role":"user","content":"My favorite color is chartreuse. Reply with just: noted."}]}'
```

Find in the response: `content[0].text`, `stop_reason`, and `usage`. **Write down `usage.input_tokens` and `usage.output_tokens`** on scratch paper or in a
throwaway file. You will track them for the rest of this lab.

## Task 2: Ask a follow-up. Send only the follow-up.

```bash
ask '{"model":"claude-haiku-4-5","max_tokens":64,
      "messages":[{"role":"user","content":"What is my favorite color?"}]}'
```

**Does it know?** Read its answer carefully. Note the `input_tokens`: did they go up or down?

## Task 3: Ask again, but send the whole conversation

```bash
ask '{"model":"claude-haiku-4-5","max_tokens":64,"messages":[
  {"role":"user","content":"My favorite color is chartreuse. Reply with just: noted."},
  {"role":"assistant","content":"noted."},
  {"role":"user","content":"What is my favorite color?"}]}'
```

Now it knows. **Nothing changed on the server.** You supplied the memory/context.

## Task 4: Add one more turn and watch the meter

Task 3's body is getting long to retype, and it is about to get longer. This is exactly what a real
client does: it keeps the conversation somewhere and re-sends it. So keep yours in a file.

The lab ships Task 3's body as `conversation.json`. Take a copy to work on:

```bash
cd ~/jarvis/labs/01-fundamentals
cp conversation.json turn4.json
nano turn4.json
```

Add the assistant's last reply and one more question, so `messages` ends up with **five** entries.
The two lines to add are:

```json
    {"role": "assistant", "content": "Your favorite color is chartreuse."},
    {"role": "user", "content": "Name one flower that color. Two words max."}
```

They go after the last existing message. **Put a comma at the end of the line above them**, since it
is no longer the last entry, and do not put one after the final `}`. In `nano`, `Ctrl-O` then
`Enter` saves and `Ctrl-X` exits.

Check it before you send it. This catches a missing comma with a line number, which the API will
not:

```bash
jq . turn4.json > /dev/null && echo "valid JSON"
```

Then send the file:

```bash
askf turn4.json
```

> **Prefer not to use an editor?** This does the same edit in one command:
> ```bash
> jq '.messages += [{"role":"assistant","content":"Your favorite color is chartreuse."},
>                   {"role":"user","content":"Name one flower that color. Two words max."}]' \
>    conversation.json > turn4.json
> ```
> If `turn4.json` gets into a state you cannot fix, `cp conversation.json turn4.json` starts over.

Now chart your four `input_tokens` values against your four `output_tokens` values.
**Which one grows, and how fast?** If a coding agent runs 50 turns, what is the shape of your bill?

And notice what you just built: a file on your disk holding the whole conversation, which you resend
in full every turn. That is all "memory" is in this business. Lab 04 finds the same thing inside a
real tool, and it is a great deal more interesting there.

## Task 5: Offer it a tool

```bash
ask '{"model":"claude-haiku-4-5","max_tokens":256,
 "tools":[{"name":"read_file",
           "description":"Read a file from disk and return its contents.",
           "input_schema":{"type":"object",
                           "properties":{"path":{"type":"string","description":"absolute path"}},
                           "required":["path"]}}],
 "messages":[{"role":"user","content":"What is in /etc/passwd?"}]}'
```

Answer these:
1. What is `stop_reason`?
2. What is in the `tool_use` block, and what file did it ask for?
3. **Did anything read that file?**
4. Compare `input_tokens` here to Task 2. What did attaching one tool definition cost you?

## Checkpoint: if you get lost
Every lab has a **known-good snapshot** you can restore without losing anything you've done:

```bash
cd ~/jarvis && git checkout stage-fundamentals -- labs/01-fundamentals
```

## Discussion
- If the client sends the whole conversation every turn, **what does anything in the network path
  see?** (Hold that thought: the proxy labs answer it.)
- The model asked to read `/etc/passwd` and nothing happened, because a tool call is only a
  *request*. So which component actually decides? Where would you put a control?
- Your `input_tokens` climbed every turn. Who in your organization sees that number today?
