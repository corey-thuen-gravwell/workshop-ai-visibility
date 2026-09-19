#!/usr/bin/env python3
"""
Scenario-driven Corelight/Zeek log generator for the Shadow-AI lab (M4 / Lab 02).

Schema is aligned to the real Corelight sample in datasets/corelight/real-sample-corelight-ai-events.json
(ISO-8601 `ts`/`_write_ts`, `_system_name`/`_node`, paired A+AAAA queries, real CDN answer IPs,
`ssl_history`, `curve`, ...). Every SSL/HTTP connection also gets its `conn` record (same `uid`),
because that is how Zeek works and it is what makes "did bytes actually move?" answerable.

The whole point of the lab is CORRELATION. A DNS query for an AI domain proves only that a name
was resolved. The scenarios below are built so that each hunt method (DNS / SSL SNI / HTTP host)
finds a different subset, and only correlating DNS answers <-> conn/ssl `id.resp_h` per source host
(with bytes > 0) separates real usage from noise. See README.md for the scenario table and the
answer key that `--answer-key` writes.

Output (--outdir): corelight_dns.jsonl, corelight_ssl.jsonl, corelight_conn.jsonl,
corelight_http.jsonl, okta_access.jsonl (Method 4, tag=okta): one raw JSON record per line,
ingest each under its tag. --wrapped writes the Gravwell tagged-export format for parity with the
legacy sample. --anchor sets when the 24h window ENDS (default: now) so "last 24 hours" works.
--sysmon-in/--sysmon-out re-times the real Sysmon XML so the rogue agent's process burst lines up
with the same host's network burst (cross-source correlation with Lab 03).
"""
import argparse, base64, hashlib, json, os, random, re, uuid
from datetime import datetime, timedelta, timezone

# ------------------------------------------------------------------------------------------
# World
# ------------------------------------------------------------------------------------------
SENSOR = {"_system_name": "raspberrypi", "_node": "worker-01"}
SENSOR_IP = "10.13.66.200"
DNS_SERVER = "8.8.8.8"
INTERNAL_DNS = "10.13.0.53"

# Real-world answer IPs (Cloudflare fronts chatgpt.com; note the SHARED-CDN scenario relies on it)
AI = {
    "chatgpt.com":            {"v4": ["104.18.32.47", "172.64.155.209"], "v6": ["2a06:98c1:310b::ac40:9bd1", "2a06:98c1:3100::6812:202f"]},
    "ab.chatgpt.com":         {"v4": ["104.18.32.47", "172.64.155.209"], "v6": ["2a06:98c1:310b::ac40:9bd1", "2a06:98c1:3100::6812:202f"]},
    "ws.chatgpt.com":         {"v4": ["172.64.148.235", "104.18.39.21"],  "v6": ["2a06:98c1:3108::ac40:94eb", "2a06:98c1:3107::6812:2715"]},
    "api.openai.com":         {"v4": ["162.159.140.245", "172.66.0.243"], "v6": ["2606:4700:7::a29f:8cf5"]},
    "claude.ai":              {"v4": ["160.79.104.10"],                    "v6": ["2607:6bc0::10"]},
    "api.anthropic.com":      {"v4": ["160.79.104.10"],                    "v6": ["2607:6bc0::10"]},
    "gemini.google.com":      {"v4": ["142.250.72.14"],                    "v6": ["2607:f8b0:400a:80b::200e"]},
    "generativelanguage.googleapis.com": {"v4": ["142.250.217.74"],        "v6": ["2607:f8b0:400a:801::200a"]},
    "copilot.microsoft.com":  {"v4": ["20.112.52.29"],                     "v6": []},
    "api.githubcopilot.com":  {"v4": ["140.82.112.22"],                    "v6": []},
    "huggingface.co":         {"v4": ["3.163.189.37", "3.163.189.74"],     "v6": []},
    "perplexity.ai":          {"v4": ["104.18.26.120", "104.18.27.120"],   "v6": []},
    "api.deepseek.com":       {"v4": ["104.18.20.207", "104.18.21.207"],   "v6": []},
    "character.ai":           {"v4": ["172.64.144.129"],                   "v6": []},
}
BENIGN = {
    "github.com":       ["140.82.113.3"],
    "slack.com":        ["3.89.11.20", "52.203.68.43"],
    "wikipedia.org":    ["208.80.154.224"],
    "cdn.jsdelivr.net": ["151.101.1.229"],
    "ubuntu.com":       ["185.125.190.21"],
    "outlook.office365.com": ["52.96.165.2"],
    "teams.microsoft.com":   ["52.113.194.132"],
    "registry.npmjs.org":    ["104.16.27.34"],
    "www.nytimes.com":       ["151.101.1.164"],
    "fonts.gstatic.com":     ["142.250.72.3"],
    # a non-AI site behind the SAME Cloudflare IP chatgpt.com uses (shared-CDN scenario)
    "www.cloudflare-fronted-recipes.example": ["104.18.32.47"],
}
DOH = {"cloudflare-dns.com": ["104.16.248.249", "104.16.249.249"]}
# AI *inside* a sanctioned SaaS. Not on any AI-domain list (you can't block Notion), so every Lab 02
# method reads this host as benign, on purpose. The "beyond the wire" lab's TLS-inspecting web gateway
# sees the inference path and the request-size growth. Kept out of BENIGN so the random stream of the
# existing scenarios is untouched (outputs stay byte-identical for a given --seed/--anchor).
SAAS_AI = {"www.notion.so": ["104.18.24.128", "104.18.25.128"]}
INTERNAL_HTTP = {
    "ollama.dev.acme.corp":  {"ip": "10.13.7.20", "port": 11434, "uris": ["/api/generate", "/api/chat", "/api/tags", "/v1/chat/completions"]},
    "mcp-gateway.acme.corp": {"ip": "10.13.7.21", "port": 8080,  "uris": ["/mcp", "/mcp", "/mcp"]},
}
UA_BROWSER = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36"
UA_TOOLS = ["python-requests/2.32.0", "OpenAI/Python 1.40.0", "node-fetch/1.0", "curl/8.5.0", "Go-http-client/2.0", "opencode/1.18"]

# The cast. IPs 10.13.42.42 and 10.13.20.221 are the two hosts that appear in the REAL sample.
HOSTS = {
    # ip: (hostname, user, role, subnet role)
    "10.13.20.221": ("mkt-lt-221",  "kwatts",    "marketing laptop, heavy ChatGPT web user (confirmed usage)"),
    "10.13.20.112": ("fin-lt-112",  "rdiaz",     "finance laptop, Copilot all day (sanctioned SaaS, benign-ish)"),
    "10.13.20.140": ("hr-lt-140",   "psingh",    "HR laptop, link previews resolve AI names, never connects (DNS-only)"),
    "10.13.20.155": ("sec-scan-155","svc-scan",  "vuln scanner, resolves everything, connects to nothing (DNS-only noise)"),
    "10.13.20.190": ("eng-lt-190",  "lchen",     "engineer, uses DoH; Anthropic API traffic with NO DNS log (conn-without-DNS)"),
    "10.13.20.203": ("eng-lt-203",  "mokafor",   "engineer, QUIC/UDP to chatgpt: DNS + conn, but no ssl record"),
    "10.13.20.77":  ("legal-lt-77", "abrennan",  "legal laptop, hits a recipes site on the same Cloudflare IP as chatgpt (shared-CDN decoy)"),
    "10.13.42.42":  ("ubuntu-sysmon","ubuntu",   "dev VM running the rogue opencode agent (bursty api.anthropic.com + repeated failed outbound conns)"),
    "10.13.42.51":  ("dev-vm-51",   "jpark",     "dev VM, self-hosted ollama + MCP gateway over plaintext HTTP (Method 3)"),
    "10.13.42.60":  ("ci-runner-60","svc-ci",    "CI runner, 03:00 api.openai.com with a 48 MB upload (off-hours volume outlier)"),
    "10.13.20.33":  ("recep-33",    "tnguyen",   "reception, benign"),
    "10.13.20.48":  ("ops-lt-48",   "gmartin",   "ops, benign"),
    "10.13.20.66":  ("sales-lt-66", "dfoster",   "sales, benign to every Lab 02 method; uses Notion AI (sanctioned SaaS), revealed only by the TLS-inspecting proxy in the beyond-the-wire lab"),
    "10.13.20.98":  ("exec-lt-98",  "hvance",    "exec, benign"),
}
SUSPECT_HOST = "185.220.101.47"   # unusual external host the agent repeatedly failed to reach (IOC; see Sysmon data)

# ------------------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------------------
def iso(t): return t.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
def uid(): return "C" + "".join(random.choice("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789") for _ in range(17))
def sport(): return random.randint(32768, 60999)
def jitter(t, lo, hi): return t + timedelta(milliseconds=random.uniform(lo, hi))

class World:
    def __init__(self, end):
        self.end = end; self.start = end - timedelta(hours=24)
        self.dns, self.ssl, self.conn, self.http, self.okta = [], [], [], [], []
        self.key = {"hosts": {}, "events": []}
    def at(self, hour, minute=None, spread_min=0):
        """A time on the window's calendar day at hour:minute (window ends at anchor)."""
        base = self.start.replace(minute=0, second=0, microsecond=0) + timedelta(hours=1)
        t = base.replace(hour=hour % 24, minute=minute if minute is not None else random.randint(0, 59), second=random.randint(0, 59))
        if t < self.start: t += timedelta(days=1)
        if t > self.end: t -= timedelta(days=1)
        if spread_min: t += timedelta(minutes=random.uniform(0, spread_min))
        return max(self.start, min(self.end, t))
    def note(self, host, scenario, **k):
        h = self.key["hosts"].setdefault(host, {"hostname": HOSTS[host][0], "user": HOSTS[host][1], "role": HOSTS[host][2], "scenarios": []})
        h["scenarios"].append({"scenario": scenario, **k})
    # ---- record builders (Zeek JSON, Corelight flavour) ------------------------------------
    def rec(self, path, t, **fields):
        r = {"_path": path, **SENSOR, "_write_ts": iso(jitter(t, 30, 90)), "ts": iso(t)}
        r.update(fields); return r
    def q(self, t, src, name, qtype="A", answers=None, server=DNS_SERVER, rcode=0):
        answers = answers if answers is not None else []
        self.dns.append(self.rec("dns", t, uid=uid(), **{"id.orig_h": src, "id.orig_p": sport(), "id.resp_h": server, "id.resp_p": 53},
            proto="udp", trans_id=random.randint(1, 65535), rtt=round(random.uniform(0.02, 0.09), 6), query=name, qclass=1, qclass_name="C_INTERNET",
            qtype=1 if qtype == "A" else 28, qtype_name=qtype, rcode=rcode, rcode_name="NOERROR" if rcode == 0 else "NXDOMAIN",
            AA=False, TC=False, RD=True, RA=True, Z=0, answers=answers, TTLs=[300.0] * len(answers), rejected=False))
    def resolve(self, t, src, name, server=DNS_SERVER):
        """Paired A + AAAA like a real resolver client. Returns the v4 answers (clients connect to v4[0])."""
        rec = AI.get(name); v4 = list(rec["v4"] if rec else BENIGN.get(name) or DOH.get(name) or SAAS_AI.get(name) or [])
        v6 = list(rec["v6"] if rec else []); random.shuffle(v4); random.shuffle(v6)   # resolvers rotate answer order
        self.q(t, src, name, "A", v4, server); self.q(jitter(t, 0, 3), src, name, "AAAA", v6, server)
        return v4
    def tls(self, t, src, dst, sni, orig_b, resp_b, dur=None, hist="CsiI", version="TLSv13", cipher="TLS_AES_128_GCM_SHA256", proto="tcp", service="ssl", quic=False):
        u = uid(); sp = sport(); dur = dur if dur is not None else round(random.uniform(0.3, 40.0), 6)
        c = self.rec("conn", t, uid=u, **{"id.orig_h": src, "id.orig_p": sp, "id.resp_h": dst, "id.resp_p": 443}, proto=proto,
            service="quic" if quic else service, duration=dur, orig_bytes=orig_b, resp_bytes=resp_b, conn_state="SF", local_orig=True, local_resp=False,
            missed_bytes=0, history="ShADadFf" if proto == "tcp" else "Dd", orig_pkts=max(2, orig_b // 1200), orig_ip_bytes=orig_b + max(2, orig_b // 1200) * 52,
            resp_pkts=max(2, resp_b // 1400), resp_ip_bytes=resp_b + max(2, resp_b // 1400) * 52)
        self.conn.append(c)
        if not quic:
            self.ssl.append(self.rec("ssl", jitter(t, 40, 120), uid=u, **{"id.orig_h": src, "id.orig_p": sp, "id.resp_h": dst, "id.resp_p": 443},
                version=version, cipher=cipher, curve=random.choice(["x25519", "unknown-4588"]), server_name=sni, resumed=random.random() < 0.3,
                established=True, ssl_history=hist))
        return u
    def failed_conn(self, t, src, dst, port, state="S0"):
        self.conn.append(self.rec("conn", t, uid=uid(), **{"id.orig_h": src, "id.orig_p": sport(), "id.resp_h": dst, "id.resp_p": port}, proto="tcp",
            duration=round(random.uniform(3.0, 3.2), 6), orig_bytes=0, resp_bytes=0, conn_state=state, local_orig=True, local_resp=False, missed_bytes=0,
            history="S" if state == "S0" else "Sr", orig_pkts=3, orig_ip_bytes=180, resp_pkts=0 if state == "S0" else 1, resp_ip_bytes=0 if state == "S0" else 40))
    def web(self, t, src, host, uri, method="GET", ua=UA_BROWSER, status=200, req_len=0, resp_len=None, dst=None, port=80, mime="application/json"):
        u = uid(); sp = sport(); dst = dst or INTERNAL_HTTP.get(host, {}).get("ip") or BENIGN.get(host, ["172.64.155.209"])[0]
        port = INTERNAL_HTTP.get(host, {}).get("port", port); resp_len = resp_len if resp_len is not None else random.randint(200, 9000)
        self.conn.append(self.rec("conn", t, uid=u, **{"id.orig_h": src, "id.orig_p": sp, "id.resp_h": dst, "id.resp_p": port}, proto="tcp", service="http",
            duration=round(random.uniform(0.05, 12.0), 6), orig_bytes=req_len + 300, resp_bytes=resp_len + 200, conn_state="SF", local_orig=True,
            local_resp=dst.startswith("10."), missed_bytes=0, history="ShADadFf", orig_pkts=3, orig_ip_bytes=req_len + 456, resp_pkts=3, resp_ip_bytes=resp_len + 356))
        self.http.append(self.rec("http", jitter(t, 20, 80), uid=u, **{"id.orig_h": src, "id.orig_p": sp, "id.resp_h": dst, "id.resp_p": port}, trans_depth=1,
            method=method, host=host, uri=uri, version="1.1", user_agent=ua, request_body_len=req_len, response_body_len=resp_len, status_code=status,
            status_msg={200: "OK", 301: "Moved Permanently", 404: "Not Found"}.get(status, "OK"), tags=[], resp_fuids=["F" + uid()[1:]], resp_mime_types=[mime]))
    def sso(self, t, user, src, app_host, outcome="SUCCESS"):
        self.okta.append({"published": iso(t), "eventType": "user.authentication.sso", "displayMessage": "User single sign on to app",
            "outcome": {"result": outcome}, "actor": {"alternateId": f"{user}@acme.corp", "displayName": user, "type": "User"},
            "client": {"ipAddress": src, "userAgent": {"rawUserAgent": UA_BROWSER, "browser": "CHROME", "os": "Windows 10"}, "zone": "OFFICE"},
            "target": [{"type": "AppInstance", "displayName": app_host.split(".")[0].title(), "alternateId": app_host}],
            "application_hostname": app_host, "client_ip": src, "url": f"https://{app_host}/"})

    # ---- scenarios -------------------------------------------------------------------------
    def browse_session(self, t, src, name, pages=6, sso_user=None):
        """A human in a browser: resolve, then several TLS conns to the resolved IP, real bytes."""
        v4 = self.resolve(t, src, name)
        if sso_user: self.sso(jitter(t, 500, 2000), sso_user, src, name)
        for i in range(pages):
            tt = t + timedelta(seconds=random.uniform(2, 240) * (i + 1))
            self.tls(tt, src, v4[0], name, random.randint(2_000, 60_000), random.randint(20_000, 900_000))
        return v4

    def s_confirmed_browser(self, w):
        src = "10.13.20.221"
        for hour in (9, 10, 13, 15, 16):
            t = self.at(hour, spread_min=40)
            self.browse_session(t, src, "chatgpt.com", pages=random.randint(4, 9), sso_user="kwatts" if hour == 9 else None)
            self.resolve(jitter(t, 800, 1500), src, "ab.chatgpt.com")
            v4 = self.resolve(jitter(t, 1500, 2500), src, "ws.chatgpt.com")
            self.tls(jitter(t, 2600, 4000), src, v4[0], "ws.chatgpt.com", random.randint(8_000, 90_000), random.randint(40_000, 400_000), dur=random.uniform(300, 1800))
        # one plaintext http that 301s to https (real sample had exactly this)
        self.web(self.at(13, 5), src, "chatgpt.com", "/", ua="Wget/1.25.0", status=301, resp_len=167, mime="text/html")
        self.note(src, "confirmed-usage", detail="DNS + SSL/conn (bytes>0) to the resolved IPs, five sessions in business hours, SSO login to ChatGPT at 09:xx; also one plaintext GET chatgpt.com -> 301", methods=["dns", "ssl", "http", "sso", "correlation"])

    def s_sanctioned_copilot(self, w):
        src = "10.13.20.112"
        for hour in range(8, 18):
            t = self.at(hour, spread_min=50)
            self.browse_session(t, src, "copilot.microsoft.com", pages=random.randint(2, 5), sso_user="rdiaz" if hour == 8 else None)
        self.note(src, "confirmed-usage-sanctioned", detail="Copilot all day, SSO'd. Confirmed usage: but is it *shadow*? Policy question, not a detection question.", methods=["dns", "ssl", "sso", "correlation"])

    def s_dns_only_previews(self, w):
        src = "10.13.20.140"
        for name in ["claude.ai", "gemini.google.com", "perplexity.ai", "character.ai"]:
            self.resolve(self.at(random.randint(9, 16), spread_min=59), src, name)
        # normal benign browsing so the host isn't otherwise silent
        for name in ["outlook.office365.com", "teams.microsoft.com", "www.nytimes.com"]:
            v4 = self.resolve(self.at(random.randint(8, 17), spread_min=59), src, name)
            self.tls(self.at(random.randint(8, 17), spread_min=59), src, v4[0], name, random.randint(1000, 8000), random.randint(5000, 80000))
        self.note(src, "dns-only", detail="Resolves four AI domains (email/chat link previews) but NEVER connects to any of them. DNS-only = not usage.", methods=["dns"])

    def s_scanner(self, w):
        src = "10.13.20.155"
        t = self.at(2, 0)
        for i, name in enumerate(list(AI) + list(BENIGN)[:6]):
            self.resolve(t + timedelta(seconds=i * random.uniform(0.2, 1.5)), src, name, server=INTERNAL_DNS)
        self.note(src, "dns-only-scanner", detail="Vuln scanner resolves every AI domain in ~20s at 02:00 against the internal resolver; zero connections. Biggest DNS 'hit', zero usage.", methods=["dns"])

    def s_doh_no_dns(self, w):
        src = "10.13.20.190"
        # the only DNS this host does: bootstrap the DoH resolver
        v4 = self.resolve(self.at(8, 31), src, "cloudflare-dns.com")
        for hour in (8, 9, 10, 11, 14, 15):
            t = self.at(hour, spread_min=59)
            self.tls(t, src, v4[0], "cloudflare-dns.com", random.randint(400, 3000), random.randint(800, 6000), dur=random.uniform(30, 600))
            # API traffic straight to Anthropic, no DNS record for it anywhere
            for _ in range(random.randint(3, 8)):
                self.tls(t + timedelta(seconds=random.uniform(5, 900)), src, AI["api.anthropic.com"]["v4"][0], "api.anthropic.com",
                         random.randint(6_000, 120_000), random.randint(4_000, 60_000), cipher="TLS_AES_256_GCM_SHA384")
        self.note(src, "conn-without-dns", detail="Uses DNS-over-HTTPS (only DNS you see is cloudflare-dns.com). Method 1 is blind; Method 2 (SNI=api.anthropic.com) catches it. DoH itself is a finding.", methods=["ssl"])

    def s_quic(self, w):
        src = "10.13.20.203"
        for hour in (10, 14):
            t = self.at(hour, spread_min=45)
            v4 = self.resolve(t, src, "chatgpt.com")
            for i in range(random.randint(4, 8)):
                self.tls(t + timedelta(seconds=random.uniform(2, 500)), src, v4[0], None, random.randint(3_000, 50_000), random.randint(30_000, 700_000), proto="udp", quic=True)
        self.note(src, "quic-no-ssl", detail="Browser used HTTP/3: DNS shows chatgpt.com, conn shows UDP/443 service=quic to the resolved IP with real bytes, but there is NO ssl record (no TLS handshake Zeek can parse). Method 2 misses it; DNS<->conn correlation finds it.", methods=["dns", "correlation"])

    def s_shared_cdn(self, w):
        src = "10.13.20.77"
        for hour in (12, 12, 17):
            t = self.at(hour, spread_min=50)
            v4 = self.resolve(t, src, "www.cloudflare-fronted-recipes.example")
            self.tls(jitter(t, 200, 900), src, v4[0], "www.cloudflare-fronted-recipes.example", random.randint(1_000, 5_000), random.randint(50_000, 400_000))
        self.note(src, "shared-cdn-decoy", detail="Connects to 104.18.32.47, the same Cloudflare IP chatgpt.com resolves to, but SNI is a recipes site and this host never resolved chatgpt.com. Correlating by IP alone is a false positive; require the DNS answer from the SAME host, or the SNI.", methods=[])

    def s_rogue_agent(self, w):
        """Mirrors the real Sysmon capture: PID 3565 (opencode) spawned 110 children in ~7 minutes on
        ubuntu-sysmon. --sysmon-out re-times that XML onto this window so the two sources line up."""
        src = "10.13.42.42"; start = self.at(11, 7)
        self.key["rogue_window"] = {"host": src, "start": iso(start), "end": iso(start + timedelta(minutes=8))}
        self.resolve(jitter(start, 500, 3000), src, "api.anthropic.com")
        n = 0
        for m in range(0, 8):
            for _ in range(random.randint(8, 14)):  # agent loop: a model round-trip per tool call, big prompts (context) out
                t = start + timedelta(minutes=m, seconds=random.uniform(2, 59))
                self.tls(t, src, AI["api.anthropic.com"]["v4"][0], "api.anthropic.com", random.randint(30_000, 400_000), random.randint(2_000, 30_000),
                         dur=random.uniform(1, 20), cipher="TLS_AES_256_GCM_SHA384"); n += 1
        # things the agent's commands touched (see CommandLine fields in the Sysmon data)
        t_recon = start + timedelta(minutes=3, seconds=20)
        self.failed_conn(t_recon, src, "169.254.169.254", 80, state="S0")                         # AWS metadata probe (curl -m 2)
        self.failed_conn(t_recon + timedelta(seconds=3), src, "169.254.169.254", 80, state="S0")   # Azure metadata probe
        t_beacon = start + timedelta(minutes=5, seconds=40)
        for i in range(4):
            self.failed_conn(t_beacon + timedelta(seconds=i * 30), src, SUSPECT_HOST, 4444, state="S0" if i < 3 else "REJ")  # repeated failed outbound conns to an unusual host:port (beaconing-style IOC)
        # earlier the same morning: the legit npm install the same VM did (baseline)
        t_npm = start - timedelta(minutes=35)
        self.resolve(t_npm, src, "registry.npmjs.org")
        self.tls(t_npm + timedelta(seconds=2), src, BENIGN["registry.npmjs.org"][0], "registry.npmjs.org", 4000, 2_400_000)
        self.note(src, "rogue-agent-burst", detail=f"{n} TLS connections to api.anthropic.com in 8 minutes (~11/min), orig_bytes >> resp_bytes (context going out), plus 2 failed conns to 169.254.169.254 (cloud metadata probe) and 4 failed conns to {SUSPECT_HOST}:4444 (repeated outbound attempts to an unusual host:port). Same host & window as Sysmon PID 3565.", methods=["dns", "ssl", "correlation", "sysmon"], api_connections=n)

    def s_plaintext_internal(self, w):
        src = "10.13.42.51"
        for hour in (9, 11, 14, 16):
            t = self.at(hour, spread_min=50)
            self.resolve(t, src, "ollama.dev.acme.corp", server=INTERNAL_DNS)
            for _ in range(random.randint(3, 7)):
                self.web(t + timedelta(seconds=random.uniform(1, 600)), src, "ollama.dev.acme.corp", random.choice(INTERNAL_HTTP["ollama.dev.acme.corp"]["uris"]),
                         method="POST", ua=random.choice(UA_TOOLS), req_len=random.randint(800, 40_000), resp_len=random.randint(2_000, 90_000))
            self.resolve(jitter(t, 100, 400), src, "mcp-gateway.acme.corp", server=INTERNAL_DNS)
            for _ in range(random.randint(2, 6)):
                self.web(t + timedelta(seconds=random.uniform(1, 600)), src, "mcp-gateway.acme.corp", "/mcp", method="POST", ua="opencode/1.18",
                         req_len=random.randint(200, 3_000), resp_len=random.randint(300, 20_000))
        self.note(src, "ai-over-http", detail="Self-hosted model (ollama :11434) and an MCP gateway (:8080/mcp), all plaintext HTTP inside the network. Not on any public AI-domain list: Method 3 (HTTP host/uri) is the only hunt that sees it, and only if you look for model/MCP paths.", methods=["http"])

    def s_offhours_volume(self, w):
        src = "10.13.42.60"
        t = self.at(3, 12)
        v4 = self.resolve(t, src, "api.openai.com")
        self.tls(t + timedelta(seconds=4), src, v4[0], "api.openai.com", 48_000_000, 120_000, dur=610.0, cipher="TLS_AES_256_GCM_SHA384")
        for i in range(6):
            self.tls(t + timedelta(minutes=11 + i), src, v4[0], "api.openai.com", random.randint(5_000, 40_000), random.randint(2_000, 9_000))
        # normal daytime CI noise
        for hour in (9, 12, 15):
            tt = self.at(hour, spread_min=59); v = self.resolve(tt, src, "github.com"); self.tls(tt + timedelta(seconds=2), src, v[0], "github.com", 20_000, 5_000_000)
        self.note(src, "offhours-volume-outlier", detail="03:12, one 48 MB upload to api.openai.com from a CI runner, then a burst of calls. Confirmed usage AND a volume/time outlier: what got uploaded?", methods=["dns", "ssl", "correlation", "volume"])

    def s_benign(self, w):
        for src in ("10.13.20.33", "10.13.20.48", "10.13.20.66", "10.13.20.98"):
            for _ in range(random.randint(14, 30)):
                name = random.choice([n for n in BENIGN if "example" not in n])
                t = self.at(random.randint(8, 17), spread_min=59); v4 = self.resolve(t, src, name)
                self.tls(jitter(t, 100, 900), src, v4[0], name, random.randint(500, 20_000), random.randint(2_000, 300_000))
            self.note(src, "benign", detail="No AI domains resolved or contacted.", methods=[])
        # background: everyone hits the office 365 endpoints
        for src in HOSTS:
            if src.startswith("10.13.42."): continue
            for _ in range(random.randint(3, 8)):
                t = self.at(random.randint(7, 18), spread_min=59); v4 = self.resolve(t, src, "outlook.office365.com")
                self.tls(jitter(t, 100, 900), src, v4[0], "outlook.office365.com", random.randint(500, 9_000), random.randint(2_000, 90_000))

    def s_embedded_saas_ai(self, w):
        """Appended LAST (after s_benign) so every earlier record is byte-identical to the earlier output."""
        src = "10.13.20.66"
        for hour in (10, 14):
            t = self.at(hour, spread_min=30)
            v4 = self.resolve(t, src, "www.notion.so")
            for i in range(random.randint(8, 14)):   # ordinary Notion use + the AI feature, all one SNI, all one IP
                self.tls(t + timedelta(seconds=random.uniform(2, 900)), src, v4[0], "www.notion.so", random.randint(1_000, 12_000), random.randint(2_000, 60_000))
        self.note(src, "ai-inside-sanctioned-saas", detail="Notion (sanctioned SaaS): its AI feature is used from this host, including a 1.9 MB customer CSV. www.notion.so is on NO AI-domain list and never will be, so Methods 1-4 and the two-step all read this host as benign. Only a TLS-inspecting proxy sees the /api/v3/runInferenceTranscript path (the beyond-the-wire lab).", methods=[])

    def build(self):
        for s in (self.s_confirmed_browser, self.s_sanctioned_copilot, self.s_dns_only_previews, self.s_scanner, self.s_doh_no_dns, self.s_quic,
                  self.s_shared_cdn, self.s_rogue_agent, self.s_plaintext_internal, self.s_offhours_volume, self.s_benign, self.s_embedded_saas_ai):
            s(self)
        for lst in (self.dns, self.ssl, self.conn, self.http, self.okta):
            lst.sort(key=lambda r: r.get("ts") or r.get("published"))
        # answer key summary
        ai_names = set(AI)
        self.key["summary"] = {
            "true_ai_usage_hosts": ["10.13.20.221", "10.13.20.112", "10.13.20.190", "10.13.20.203", "10.13.42.42", "10.13.42.51", "10.13.42.60"],
            "dns_only_hosts": ["10.13.20.140", "10.13.20.155"],
            "decoy_hosts": ["10.13.20.77"],
            "invisible_to_every_method": {"10.13.20.66": "AI feature inside sanctioned SaaS (Notion), see the beyond-the-wire lab (tag=swg)"},
            "found_only_by": {"dns": ["10.13.20.140", "10.13.20.155 (both false positives)"], "ssl_sni_not_dns": ["10.13.20.190"],
                              "dns_and_conn_not_ssl": ["10.13.20.203"], "http_only": ["10.13.42.51"]},
            "counts": {"dns": len(self.dns), "ssl": len(self.ssl), "conn": len(self.conn), "http": len(self.http), "okta": len(self.okta)},
            "window": {"start": iso(self.start), "end": iso(self.end)},
        }
        return self

# ------------------------------------------------------------------------------------------
# Sysmon re-timing (cross-source correlation with the real Lab 03 data)
# ------------------------------------------------------------------------------------------
def retime_sysmon(src_path, dst_path, rogue_start_iso):
    """Shift every timestamp in the real Sysmon XML so PID 3565's first child lands at rogue_start."""
    xml = open(src_path, encoding="utf-8", errors="replace").read()
    events = re.findall(r"<Event>.*?</Event>", xml)
    first = None
    for e in events:
        if 'ParentProcessId">3565<' in e and "<EventID>1</EventID>" in e:
            first = datetime.strptime(re.search(r'SystemTime="([^"]+)"', e).group(1)[:26], "%Y-%m-%dT%H:%M:%S.%f").replace(tzinfo=timezone.utc); break
    if first is None: raise SystemExit("PID 3565 not found in the Sysmon XML")
    target = datetime.strptime(rogue_start_iso[:26], "%Y-%m-%dT%H:%M:%S.%f").replace(tzinfo=timezone.utc)
    delta = target - first
    def shift_sys(m):
        t = datetime.strptime(m.group(1)[:26], "%Y-%m-%dT%H:%M:%S.%f").replace(tzinfo=timezone.utc) + delta
        return f'SystemTime="{t.strftime("%Y-%m-%dT%H:%M:%S.%f")}000Z"'
    def shift_utc(m):
        t = datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S.%f").replace(tzinfo=timezone.utc) + delta
        return f'Name="UtcTime">{t.strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]}<'
    out = re.sub(r'SystemTime="([^"]+)"', shift_sys, xml)
    out = re.sub(r'Name="UtcTime">([^<]+)<', shift_utc, out)
    os.makedirs(os.path.dirname(dst_path) or ".", exist_ok=True)
    with open(dst_path, "w") as f: f.write(out)
    return len(events), delta

# ------------------------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--outdir", default="out", help="write per-tag JSONL files here")
    ap.add_argument("--anchor", default="now", help="ISO-8601 UTC time the 24h window ENDS at (default: now)")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--wrapped", help="also write a single Gravwell tagged-export file here")
    ap.add_argument("--answer-key", help="write the instructor answer key JSON here")
    ap.add_argument("--sysmon-in", help="real Sysmon XML to re-time onto the rogue-agent window")
    ap.add_argument("--sysmon-out", help="where to write the re-timed Sysmon XML")
    a = ap.parse_args(); random.seed(a.seed)
    end = datetime.now(timezone.utc) if a.anchor == "now" else datetime.fromisoformat(a.anchor.replace("Z", "+00:00"))
    w = World(end).build()
    os.makedirs(a.outdir, exist_ok=True)
    for name, rows in (("corelight_dns", w.dns), ("corelight_ssl", w.ssl), ("corelight_conn", w.conn), ("corelight_http", w.http), ("okta_access", w.okta)):
        with open(os.path.join(a.outdir, name + ".jsonl"), "w") as f:
            for r in rows: f.write(json.dumps(r, separators=(",", ":")) + "\n")
    if a.wrapped:
        os.makedirs(os.path.dirname(a.wrapped) or ".", exist_ok=True)
        with open(a.wrapped, "w") as f:
            for tag, rows in (("corelight_dns", w.dns), ("corelight_ssl", w.ssl), ("corelight_conn", w.conn), ("corelight_http", w.http), ("okta", w.okta)):
                for r in rows:
                    f.write(json.dumps({"TS": r.get("ts") or r.get("published"), "Tag": tag, "SRC": SENSOR_IP,
                                        "Data": base64.b64encode(json.dumps(r, separators=(",", ":")).encode()).decode(), "Enumerated": None}) + "\n")
    if a.sysmon_in and a.sysmon_out:
        n, delta = retime_sysmon(a.sysmon_in, a.sysmon_out, w.key["rogue_window"]["start"])
        w.key["sysmon"] = {"events": n, "shifted_by_seconds": int(delta.total_seconds()), "rogue_pid": 3565, "host": "ubuntu-sysmon (10.13.42.42)"}
    if a.answer_key:
        os.makedirs(os.path.dirname(a.answer_key) or ".", exist_ok=True)
        with open(a.answer_key, "w") as f: json.dump(w.key, f, indent=2)
    c = w.key["summary"]["counts"]
    print(f"wrote {a.outdir}/: dns={c['dns']} ssl={c['ssl']} conn={c['conn']} http={c['http']} okta={c['okta']}  window {w.key['summary']['window']['start']} -> {w.key['summary']['window']['end']}")
    if a.answer_key: print(f"answer key: {a.answer_key}")

if __name__ == "__main__":
    main()
