# Exploring AI Visibility: Shedding Light on Shadow AI, Attack Surface, Telemetry, and LLM Proxies

A hands-on course for security teams on auditing, detecting, and securing AI usage in an
enterprise: finding shadow AI in the logs you already have, seeing what coding agents actually
send to model providers, putting a logging proxy in the path, and turning what you learn into
detections. Gravwell is the log-analysis backend; the methods transfer to any SIEM.

The course runs two ways, from the same material:

- **Instructor-led.** An instructor provisions a lab host, students SSH into per-seat
  environments, and labs are released one at a time as the course reaches them.
- **Self-guided.** One person, one Linux box with docker, the walkthroughs in place of the
  instructor. Start with [`SETUP.md`](SETUP.md), then
  [`materials/self-study-guide.md`](materials/self-study-guide.md).

**Authors:** Corey Thuen · David Fritz · Daniel Moreno Levy · Lawrence Wellman (Gravwell)

## What you will learn

1. How LLM tooling works: a stateless HTTP API, context the caller supplies, tokens and cost, tool
   calling, and what a model is doing when it "decides" something.
2. How to find AI usage in existing telemetry: network logs (DNS, TLS, HTTP, SSO), endpoint
   process data (Sysmon), and the sources beyond the wire (inventory, proxies, cloud audit).
3. How to see the content: an agent's own local logs, a generic LLM gateway, and content-capturing
   proxies that record prompts, tool calls and usage.
4. How MCP servers steer an agent through tool descriptions, and how to detect that in the
   proxy's data.

## Layout

| Path | Contents |
|---|---|
| `SETUP.md` | Where to get an API key and a Gravwell license, and where each one goes |
| `AGENDA.md` | The module sequence with effort estimates, optional modules, compression plan, port map |
| `labs/NN-*/` | Student lab handouts, one directory per module |
| `labs/_stretch/` | Optional modules: extend the proxy, semantic search, audit an assistant's logs, shadow AI beyond the wire |
| `slides/` | Marp decks, one per module, plus the theme |
| `instructor/walkthroughs/` | Complete step-by-step per lab with every command, expected output and answer. Instructor-only in a class; the self-guided reader's instructor |
| `instructor/runbook/` | Provisioning a lab host, seat management, releasing labs, class-day sequence |
| `instructor/dry-run-protocol.md` | How to test the whole sequence with a co-instructor before teaching it |
| `materials/` | Take-home one-pagers, cheatsheets, attendee prerequisites, the self-study guide |
| `datasets/` | Log samples and lookup tables the analysis labs ingest; generated data is rebuilt by `src/log-generator/` |
| `src/logging-proxy/` | Vendor-agnostic Python LLM logging proxy, single stdlib file, take-home |
| `src/mcp-lab-server/` | Config-driven MCP server students run and connect to an agent |
| `src/log-generator/` | Deterministic scenario generators for the network, endpoint and beyond-the-wire labs |
| `student-repo/` | Manifest of the staged student repository an instructor serves to seats |
| `share/` | Builds the handouts and decks as HTML and PDF, and the site that serves them |
| `CONTRIBUTING.md` | Conventions for adding or changing course material |

## The scenario

You play a security team auditing AI activity. A startup "vibe-codes" a product (`moneyprinter`)
with AI agents; the security team must gain visibility into what those agents send to providers
and what actions they take. First from logs they already have, then with active interception,
ending with a lab where the tool manifests you write steer an agent across MCP servers, and with
turning the lessons into detections.

## Requirements

- **Self-guided:** a Linux machine or VM with docker, `jq`, `nc`, Python 3 and git; an Anthropic
  API key with a spend limit; a Gravwell Community Edition license; optionally Ollama for the
  demystification lab. `SETUP.md` covers all of it.
- **Instructor-led:** a lab host reachable by attendees on TCP 22, 443 and the per-seat HTTPS
  range; see `instructor/runbook/README.md`, and send `materials/attendee-prerequisites.md` to
  attendees weeks ahead so corporate network exceptions are in place.

Everything student-facing runs over SSH in a terminal. Per-seat docker stacks are keyed on
`WORKSHOPUID` (a two-digit seat id from which every port is derived), so one host serves a room
and one laptop serves one reader.

## Credentials

No credentials are committed to this repository. Copy `.env.example` to `.env` and fill it in;
put your Gravwell license at the repo root as `gravwell.license`. Both paths are git-ignored.
`SETUP.md` walks through obtaining each one.

## Reference

- Gravwell documentation: <https://docs.gravwell.io> (query language, modules, ingesters, kits)
- Gravwell REST API: <https://api.docs.gravwell.io>
- Gravwell kits, open source: <https://github.com/gravwell/kits>
