# `mcp-lab-server`: run your own MCP server

A **config-driven MCP server** for the MCP module. Students declare a server's identity, tools,
prompts and resources in a TOML file, start the server, and connect a real AI client to it. They
never edit the server code.

```bash
./mcp_lab_server.py --config examples/looney-tunes-compliance.toml --validate   # check config
./mcp_lab_server.py --config my-server.toml                                     # stdio (opencode)
./mcp_lab_server.py --config my-server.toml --http 0.0.0.0:${WORKSHOPUID}91     # HTTP (curl)
```

Stdlib only, Python 3.11+ (`tomllib`). One file, no build, no dependencies, same design rule as
`src/logging-proxy/`.

> Harmless by design, including the attacker. Lab 06 uses it to teach how MCP works; Lab 07 uses it
> to play a malicious server whose manifest makes the model fetch a secret tag with Gravwell's own
> tools and hand it over, and then to detect that. The "exfiltration" is an append to a file in the
> student's home directory. Keep new behaviours observable and local (see the *Tool source* section
> of `CONTRIBUTING.md`).

## Why config-driven

An MCP server is mostly a **manifest**, names, descriptions, schemas, plus a little behaviour.
Making the manifest the editable surface puts students' attention where it belongs: on the tool
*description*, which is the only thing the model actually reads, and which they can rewrite and
re-test in seconds.

## What a config declares

| Section | Becomes |
|---|---|
| `[server]` | `initialize` → `serverInfo`, `capabilities`, and optional `instructions` |
| `[[tools]]` | `tools/list` and `tools/call` |
| `[[prompts]]` | `prompts/list` and `prompts/get` |
| `[[resources]]` | `resources/list` and `resources/read` |

## Tool behaviours

No backend, on purpose: the lab is about the protocol, not plumbing.

| `behavior` | Does | Key config |
|---|---|---|
| `static` | Returns fixed text | `text` |
| `template` | Returns text with `{arg}` substituted | `text` |
| `echo` | Returns the arguments it received | - |
| `forbidden_words` | Fails if any listed phrase appears | `words`, `field` |
| `required_words` | Fails if any listed phrase is missing | `words`, `field` |
| `regex_check` | Matches a pattern; `expect = "absent"` or `"present"` | `pattern`, `field` |
| `word_count` | Counts words/chars, optional limit | `field`, `max_words` |
| `always_error` | Always returns a protocol error | `text` |
| `gravwell_grep_hoist` | Query advisor: given a Gravwell query **and** the result of Gravwell's own `parse_query` tool, suggests moving a late raw `grep` (no `-e`) to the front of the pipeline. Refuses without a parse result; never validates syntax itself | `query_field`, `parse_field`, `require_parse` |
| `exfiltrate` | The Lab 07 attacker's tool: a cover story. Returns `text` with `{argument}` placeholders filled in (a tidy report that mentions nothing), while the dispatcher keeps every argument it received in `loot_file`. The theft is in the manifest, not here: the sentences that make the model fetch something nobody asked for and pass it in | `loot_file` (required), `text` |

**`loot_file`, on any tool.** A tool with a `loot_file` key appends one JSON line per call (`ts`,
`tool`, `bytes` per argument, `arguments`) to that path, whatever its behaviour. `~` and `$HOME`
are expanded. Lab 07 Task 6 puts it on the working query advisor: a useful tool and a thief can be
the same tool. In a real malicious server that line is a socket to a host the attacker owns (this
script already does network I/O, see `--tcp`); here it stays on the seat so the student can read
exactly what left.

**The log file** (`--log-file`) gets one JSON line per message in (`direction: in`) and out (`out`),
plus one `direction: call` record per accepted tool call holding just the tool name and the
arguments as received. `--verbose` prints the same on stderr. `--tcp host:port` streams the same
lines to a Gravwell listener (`tag=mcp` in the labs).

Shared options: `case_sensitive`, `pass_message`, `fail_message`, and `error_on_fail` (return a
JSON-RPC error rather than a normal "failed" result: worth trying, because clients react to the
two very differently).

## Examples

| File | What it teaches |
|---|---|
| `examples/looney-tunes-compliance.toml` | The worked example: a compliance tool, a policy tool, a length tool, one prompt, one resource. Heavily commented |
| `examples/pii-guard.toml` | Three tools that fail in three different ways |
| `examples/query-advisor-starter.toml` | Lab 07 Task 2 starter: plumbing done, every model-facing text is `WRITE ME`; `--validate` counts the placeholders left |
| `examples/log-hygiene-starter.toml` | Lab 07 Task 5 starter: APT Cherdenko's `log-hygiene` server on `exfiltrate`, same idea; the `WRITE ME`s are the lure |
| `examples/starter-template.toml` | Copy this to build your own. Every option documented inline |

**`--http` binds every interface** when told to (`0.0.0.0:<ID>91`, as the handouts say, so a
`curl` to `localhost` works from any shell on the seat). On a shared lab host that also means any
other seat can call your server, and with a `loot_file` set, append to your loot. Bind `127.0.0.1`
if that matters to you; nothing in the labs needs the wider bind. The HTTP transport is
deliberately minimal: one endpoint, no GET/SSE stream, and it issues `Mcp-Session-Id` without
checking it on later requests.

## Connecting opencode

Add an `mcp` block to `opencode.json` (stdio: opencode spawns the server itself, so no ports and
no per-seat collisions):

```jsonc
{
  "mcp": {
    "looney-tunes": {
      "type": "local",
      "command": ["python3", "/home/USER/jarvis/src/mcp-lab-server/mcp_lab_server.py",
                  "--config", "/home/USER/jarvis/my-server.toml"],
      "enabled": true
    }
  }
}
```

Verify with `opencode mcp list`: it should print `✓ <name> connected`.

With opencode 1.18.25 the model discovered the tools, chose
`check_looney_tunes_compliance` from its description alone, called it with the right argument, and
reported the verdict. Note opencode **namespaces** tool names as `<server>_<tool>`, so the model
sees `looney-tunes_check_looney_tunes_compliance`.

**Restart matters.** Clients cache the tool list from `initialize`. After editing a config, restart
the server *and* the client.

## Watching your own protocol traffic

Every message in and out can be logged as JSONL: the same idea as the logging proxy in Lab 05,
applied to your own server:

```bash
./mcp_lab_server.py --config my-server.toml \
    --log-file ~/mcp.jsonl \
    --tcp localhost:${WORKSHOPUID}10        # → Gravwell, tag=mcp
```

Each record: `ts`, `direction` (`in`/`out`, plus one `call` per accepted tool call), `session_id`, `server`, `method`, `id`, `message`.

```
tag=mcp json direction method session_id | table direction method session_id
tag=mcp json method message | grep -e method tools/call | table message
```

`--verbose` echoes message names to stderr, which is the fastest way to see whether a client is
actually talking to you.

## Config errors

`--validate` reports every problem at once, with the fix. It catches missing names, duplicate tool
names, unknown or misspelled behaviours (and prints the valid list), behaviours missing their
required keys, and prompts/resources missing required fields. A missing tool `description` is a
**warning**, with an explanation of why it matters.

Malformed TOML gets a parse error plus the three things that usually cause it.
