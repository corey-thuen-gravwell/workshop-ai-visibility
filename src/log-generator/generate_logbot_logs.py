#!/usr/bin/env python3
"""
generate_logbot_logs.py: synthesize a Gravwell AI-assistant ("Logbot") audit trail.

Logbot is Gravwell's built-in, MCP-enabled AI assistant. Its webserver logs every LLM round-trip's
token usage and every MCP tool call it makes: a real example of a vendor logging its OWN AI. This
generator reproduces that wire format (RFC5424 syslog, tag=gravwell, from `webserver .../ai.go`),
anchored to "now", with a planted scenario so the lab has a right answer. Schema matches the real
capture in ../../datasets/gravwell-ai-assistant/.

Teaching points it sets up:
  * You CAN audit an AI assistant from app logs: who used it, which MCP tools it called, token spend.
  * You CANNOT see prompt/response CONTENT here: tool names and counts only. (Motivates the proxy.)
  * UEBA for AI: one user's session is a token/tool outlier and touches data-access tools in a burst.

Output: raw RFC5424 syslog lines (ingest as tag=logbot via the seat listener) + instructor key.
(--wrapped also emits Gravwell tagged-export {TS,Tag,SRC,Data} for UI import / parity with the real dump.)
    ./generate_logbot_logs.py --out ../../datasets/gravwell-ai-assistant/generated/logbot.json \
        --answer-key ../../datasets/gravwell-ai-assistant/generated/answer-key.json --seed 1
    then per seat:  nc -q1 localhost ${WORKSHOPUID}08 < logbot.log
"""
import argparse, base64, json, random
from datetime import datetime, timedelta, timezone

CONTAINERS = ["73fedbd319bf", "fadd3e492b1d"]        # the two webserver instances in the real data
# MCP tools Logbot exposes (from the real capture), split by what they touch
TOOLS_READ_META = ["list_tags", "list_queries", "list_knowledge_bases", "list_resources",
                   "list_extractors", "time_of_day", "whoami", "system_stats", "ping_indexers",
                   "storage_overview", "ingester_stats", "parse_query", "load_skill"]
TOOLS_DATA      = ["knowledge_base_search", "knowledge_base_get_data", "knowledge_base_list_keys",
                   "sample_tag_entries"]                                   # touch actual stored data
TOOLS_WRITE     = ["create_extractor", "update_extractor", "save_query", "update_query",
                   "create_scheduled_search"]                             # change config
AITAG_LINE = {"token": "ai.go:378", "mcp": "ai.go:394", "mcp_fail": "ai.go:398",
              "llm_fail": "ai.go:352", "read_fail": "ai.go:370", "health": "ai.go:158"}

def iso(t): return t.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")

class Logbot:
    def __init__(self, end, seed):
        random.seed(seed); self.end = end; self.start = end - timedelta(hours=24)
        self.rows = []; self.key = {"users": {}, "window": {"start": iso(self.start), "end": iso(end)}}
    def at(self, hour, minute=None, spread=0):
        """A time at hour:minute mapped INTO the rolling 24h window (matches the corelight generator)."""
        base = self.start.replace(minute=0, second=0, microsecond=0) + timedelta(hours=1)
        t = base.replace(hour=hour % 24, minute=minute if minute is not None else random.randint(0, 59), second=random.randint(0, 59))
        if t < self.start: t += timedelta(days=1)
        if t > self.end: t -= timedelta(days=1)
        if spread: t += timedelta(minutes=random.uniform(0, spread))
        return max(self.start, min(self.end, t))
    def _emit(self, t, container, pri, line, msg, **sd):
        procid = "%08x" % random.randint(0x40000000, 0x4fffffff)
        sdtext = " ".join('%s="%s"' % (k, str(v).replace('"', '\\"')) for k, v in sd.items())
        data = '<%d>1 %s %s webserver %s webserver/%s [gw@1 %s] %s' % (pri, iso(t), container, procid, line, sdtext, msg)
        self.rows.append({"TS": iso(t), "SRC": "172.17.0.%d" % (2 + CONTAINERS.index(container)), "raw": data})
    # one assistant "turn": the model calls k MCP tools, then a token-usage record
    def turn(self, t, user, container, tools, prompt_tokens, completion_tokens, fail=False):
        for i, tool in enumerate(tools):
            tt = t + timedelta(seconds=i * random.uniform(0.3, 2.5))
            if fail and i == len(tools) - 1:
                self._emit(tt, container, 12, AITAG_LINE["mcp_fail"], "MCP tool call failed", tool=tool,
                           error='calling \\"tools/call\\": invalid params: validating \\"arguments\\": missing properties: [\\"database\\"]',
                           uid=self.key["users"][user]["uid"], user=user)
            else:
                self._emit(tt, container, 14, AITAG_LINE["mcp"], "MCP tool call", tool=tool,
                           uid=self.key["users"][user]["uid"], user=user)
        tk = t + timedelta(seconds=len(tools) * 2 + random.uniform(0.5, 3))
        self._emit(tk, container, 14, AITAG_LINE["token"], "logbot token usage",
                   **{"prompt-tokens": prompt_tokens, "completion-tokens": completion_tokens,
                      "total-tokens": prompt_tokens + completion_tokens,
                      "uid": self.key["users"][user]["uid"], "user": user})
    def session(self, user, hour, turns, tools_per_turn, tokpool, container=None, data_heavy=False, fails=0):
        container = container or random.choice(CONTAINERS)
        t = self.at(hour, spread=1)
        for n in range(turns):
            pick = (TOOLS_DATA if data_heavy else TOOLS_READ_META)
            tools = random.sample(pick + (TOOLS_READ_META if data_heavy else []), k=min(tools_per_turn, len(pick)))
            pt = random.randint(*tokpool); ct = random.randint(20, 400)
            self.turn(t, user, container, tools, pt, ct, fail=(n < fails))
            t += timedelta(seconds=random.uniform(20, 240))
    def build(self):
        # user roster (uid, role); "changeme..." is the real joke account left in the data
        roster = {"admin": (1, "platform admin, baseline heavy user"),
                  "evan": (7, "analyst, normal usage"),
                  "priya": (4, "analyst, normal usage"),
                  "svc-reporting": (9, "service account, scheduled digests")}
        for u, (uid, role) in roster.items(): self.key["users"][u] = {"uid": uid, "role": role, "scenario": "benign"}
        # --- benign baseline: normal assistant use across the day
        for hour in (9, 10, 11, 13, 14, 15, 16):
            self.session("admin", hour, turns=random.randint(2, 5), tools_per_turn=random.randint(1, 3), tokpool=(5000, 18000))
        for hour in (9, 12, 15):
            self.session("evan", hour, turns=random.randint(1, 3), tools_per_turn=random.randint(1, 2), tokpool=(5000, 14000))
            self.session("priya", hour + 1, turns=random.randint(1, 3), tools_per_turn=random.randint(1, 2), tokpool=(6000, 15000))
        # service account: small, regular, only meta tools
        for hour in range(0, 24, 6):
            self.session("svc-reporting", hour, turns=1, tools_per_turn=2, tokpool=(4000, 6000), container=CONTAINERS[1])
        # a few health-check failures (LLM backend flap): noise + a real ops signal
        for hour in (2, 2, 3, 18):
            self._emit(self.at(hour, spread=1), random.choice(CONTAINERS), 14, AITAG_LINE["health"],
                       "ai health check request failed",
                       error='Get \\"http://zek:8081/v1/health\\": dial tcp 10.0.8.20:8081: connect: connection refused')
        # --- THE SCENARIO: 'evan' account, off-hours, runs a burst that hammers data-access tools
        # with climbing token counts: the UEBA outlier the lab is meant to find.
        self.key["users"]["evan"]["scenario"] = "outlier: 03:1x burst, data-access tools, token spend >> baseline"
        t = self.at(3, 12, spread=0)
        pt = 20000
        for n in range(14):
            tools = random.sample(TOOLS_DATA, k=random.randint(2, 4)) + ["sample_tag_entries"]
            self.turn(t, "evan", CONTAINERS[0], tools, pt, random.randint(200, 900), fail=(n in (4, 9)))
            pt = min(pt + random.randint(1000, 2500), 39000)          # context growing as it pulls data
            t += timedelta(seconds=random.uniform(8, 40))
        self.key["scenario_window"] = {"user": "evan", "start": iso(self.at(3, 12, spread=0)), "approx_end": iso(t)}
        self.rows.sort(key=lambda r: r["TS"])
        self.key["counts"] = {"total": len(self.rows)}
        return self

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True, help="raw RFC5424 syslog lines (ingest as tag=logbot)")
    ap.add_argument("--wrapped", help="also write Gravwell tagged-export JSON (UI import / parity)")
    ap.add_argument("--answer-key")
    ap.add_argument("--anchor", default="now"); ap.add_argument("--seed", type=int, default=1)
    a = ap.parse_args()
    end = datetime.now(timezone.utc) if a.anchor == "now" else datetime.fromisoformat(a.anchor.replace("Z", "+00:00"))
    import os; os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    w = Logbot(end, a.seed).build()
    # Primary: RAW RFC5424 syslog lines -> students `nc` into the logbot listener (tag=logbot).
    with open(a.out, "w") as f:
        for r in w.rows: f.write(r["raw"] + "\n")
    # Optional: Gravwell tagged-export (parity with the real dump; UI import / decode-first path).
    if a.wrapped:
        os.makedirs(os.path.dirname(a.wrapped) or ".", exist_ok=True)
        with open(a.wrapped, "w") as f:
            for r in w.rows:
                f.write(json.dumps({"TS": r["TS"], "Tag": "gravwell", "SRC": r["SRC"],
                                    "Data": base64.b64encode(r["raw"].encode()).decode(), "Enumerated": None}, separators=(",", ":")) + "\n")
    if a.answer_key:
        os.makedirs(os.path.dirname(a.answer_key) or ".", exist_ok=True)
        with open(a.answer_key, "w") as f: json.dump(w.key, f, indent=2)
    print(f"wrote {len(w.rows)} logbot syslog lines -> {a.out}  (window {w.key['window']['start']} .. {w.key['window']['end']})")

if __name__ == "__main__": main()
