# A second client through the same proxy
**Padding module P4.** Insert after M9. ~30 min.

## Objective
Run **Claude Code** through the same LLM ingester you pointed opencode at, doing the same task, and
compare what the two clients leave in `tag=llm`. Everything you build downstream, detections,
inventories, cost reports: depends on assumptions about that traffic. This is where you find out
which of them survive a change of client.

## Setup

Your Lab 00 stack is up. `claude` is installed on the host.

```bash
mkdir -p ~/p4 && cd ~/p4
cat > notes.md <<'MD'
# Pricing notes
The bulk discount threshold is 100 units.
MD
```

Point Claude Code at your ingester, it reads two environment variables and needs no config file:

```bash
export ANTHROPIC_BASE_URL="http://localhost:${WORKSHOPUID}81"
claude -p "Read notes.md and state the threshold." --allowedTools Read
```

Then run the *same task* through opencode, pointed at the same listener as in Lab 05.

## Task 1: Whose session id is it?

The ingester is configured with `Session-ID-Header = "x-claude-code-session-id"`. Check whether each
client actually supplies one:

```bash
docker exec ${WORKSHOPUID}llm grep -c "session id header configured but absent" \
    /opt/gravwell/log/llm_ingester.log
```

Read the count, run one client, read it again. Then the other.

1. **Which client sends the header, and which doesn't?**
2. For the one that doesn't, where does its `session_id` come from? *(Hint: the ingester's
   `Session-Match-Window` and `Session-TTL` settings in `llm_ingester.conf`.)*
3. Two people run identical prompts with an identical system prompt, thirty seconds apart. What
   happens to a session id that was **inferred** rather than supplied?

## Task 2: Count the sessions

```
tag=llm intrinsic session_id | count by session_id | sort by count desc | table session_id count
```

One of these clients produces **more sessions than you performed tasks**. Find it, look at the small
one, and work out what it is. *(Hint: what else does a coding agent need a model for, besides your
actual request?)*

## Task 3: The detection-breaker

```
tag=llm intrinsic event_type tool_name | grep -e event_type response.tool_call
| count by tool_name | table tool_name count
```

Look carefully at the tool names from the two clients.

**Now imagine you had written a detection keyed on a tool name.** What happens to it the day
somebody in your org switches editors?

## Task 4: Same task, same model, same answer. Same cost?

```
tag=llm intrinsic event_type session_id prompt_tokens completion_tokens
| grep -e event_type response.usage
| stats sum(prompt_tokens) as inTok sum(completion_tokens) as outTok by session_id
| sort by inTok desc | table session_id inTok outTok
```

Compare input tokens between the two clients for the *same* one-sentence task.

1. How big is the difference?
2. Neither of you wrote that context, so what is it, and who chose it?
3. If you were charging teams back for AI spend, would you bill the person or the tool?

## Discussion
- Which of your Lab 05 searches still work unchanged against Claude Code's traffic? Which quietly
  return less than you think?
- The client decides the session id, the tool names, the system prompt and most of the token bill.
  **How much of your AI telemetry is actually a property of the client rather than the user?**
- What would you have to standardise across an organisation for cross-client detections to hold?
