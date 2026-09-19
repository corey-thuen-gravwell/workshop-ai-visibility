#!/usr/bin/env python3
"""
"Beyond the wire" shadow-AI scenario generator: four log sources the network lab cannot see.

Same company, same day, the SAME FOURTEEN HOSTS AND PEOPLE as generate_corelight_logs.py (the cast is
imported from it, so the two datasets stay consistent). Lab 02 hunts AI usage in Zeek/Corelight logs
and shows that every method is a partial view. This generator produces the sources that fill the
gaps: and one exposure that no network sensor could ever have seen.

Sources (one JSONL file each, one raw record per line, ingest each under its tag):

  osquery_results.jsonl   tag=osquery     endpoint inventory, osquery differential result log
                                          (processes, listening_ports, chrome_extensions,
                                          deb_packages/programs, python_packages, npm_packages)
  swg_access.jsonl        tag=swg         identity-aware secure web gateway with TLS inspection
                                          (user, full URL, method, sizes, UA, category, action)
  cloudtrail_events.jsonl tag=cloudtrail  AWS CloudTrail: Bedrock usage inside the company's own
                                          account (management + data events), IAM enablement chain
  gws_token_audit.jsonl   tag=gws         Google Workspace token audit, OAuth consent to third-party
                                          apps (authorize) and the API calls those apps then make
                                          server-to-server (activity)

Real formats are kept (osquery result log, CloudTrail record, Workspace Reports API activity) with
one concession for the classroom: Workspace's name/value `parameters[]` array is ALSO flattened to
top-level fields (app_name, scopes, ...) exactly as the Lab 02 Okta records flatten
application_hostname/client_ip. The SWG format is a generic Zscaler-NSS-style JSON feed.

--anchor sets when the 24h window ENDS (default: now), same convention as the Lab 02 generator, so
generate both with the same anchor and "last 24 hours" covers everything. --seed is deterministic.
--answer-key writes the instructor key. See README.md for the scenario table.
"""
import argparse, json, os, random, sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_corelight_logs import HOSTS, AI, BENIGN, INTERNAL_HTTP, UA_BROWSER, SAAS_AI  # noqa: E402

OFFICE_NAT = "203.0.113.10"          # what the internet (and AWS, and Google) sees the office as
AWS_ACCOUNT = "123456789012"
AWS_REGION = "us-east-1"

def iso(t): return t.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
def iso_s(t): return t.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
def cal(t): return t.astimezone(timezone.utc).strftime("%a %b %d %H:%M:%S %Y UTC").replace(" 0", "  ", 1) if t.day < 10 else t.astimezone(timezone.utc).strftime("%a %b %d %H:%M:%S %Y UTC")
def rid(n=16): return "".join(random.choice("0123456789abcdef") for _ in range(n))
def uuid4():
    h = rid(32); return f"{h[:8]}-{h[8:12]}-4{h[13:16]}-a{h[17:20]}-{h[20:32]}"

BY_NAME = {v[0]: k for k, v in HOSTS.items()}          # hostname -> ip
USER_OF = {v[0]: v[1] for v in HOSTS.values()}          # hostname -> user
DEPT = {"kwatts": "Marketing", "rdiaz": "Finance", "psingh": "HR", "svc-scan": "Security", "lchen": "Engineering",
        "mokafor": "Engineering", "abrennan": "Legal", "ubuntu": "Engineering", "jpark": "Engineering", "svc-ci": "Engineering",
        "tnguyen": "Facilities", "gmartin": "IT Ops", "dfoster": "Sales", "hvance": "Executive"}
LINUX_HOSTS = {"eng-lt-190", "ubuntu-sysmon", "dev-vm-51", "ci-runner-60", "ops-lt-48"}

# ------------------------------------------------------------------------------------------
class World:
    def __init__(self, end):
        self.end = end; self.start = end - timedelta(hours=24)
        self.osq, self.swg, self.ct, self.gws = [], [], [], []
        self.key = {"hosts": {}, "findings": []}
    def at(self, hour, minute=None, spread_min=0):
        base = self.start.replace(minute=0, second=0, microsecond=0) + timedelta(hours=1)
        t = base.replace(hour=hour % 24, minute=minute if minute is not None else random.randint(0, 59), second=random.randint(0, 59))
        if t < self.start: t += timedelta(days=1)
        if t > self.end: t -= timedelta(days=1)
        if spread_min: t += timedelta(minutes=random.uniform(0, spread_min))
        return max(self.start, min(self.end, t))
    def note(self, host, source, finding, **k):
        h = self.key["hosts"].setdefault(host, {"hostname": HOSTS[host][0], "user": HOSTS[host][1], "sources": {}})
        h["sources"].setdefault(source, []).append({"finding": finding, **k})

    # ================================================================== osquery (tag=osquery)
    def clamp(self, t): return max(self.start, min(self.end, t))   # every record stays inside the 24h window
    def osq_row(self, t, host, query, columns, action="added"):
        t = self.clamp(t)
        self.osq.append({"name": f"pack_ai-inventory_{query}", "hostIdentifier": host, "calendarTime": cal(t), "unixTime": int(t.timestamp()),
            "epoch": 0, "counter": random.randint(0, 40), "numerics": False, "action": action,
            "decorations": {"host_uuid": uuid4().upper(), "username": USER_OF[host], "os": "linux" if host in LINUX_HOSTS else "windows"},
            "columns": columns})
    def osq_baseline(self, host):
        """Every managed host reports its ordinary software: the noise the AI list has to be pulled out of."""
        t = self.at(random.randint(7, 9), spread_min=30); linux = host in LINUX_HOSTS
        procs = ["chrome", "slack", "zoom", "code", "explorer.exe", "outlook.exe"] if not linux else ["bash", "sshd", "systemd", "code", "chrome", "python3"]
        for p in procs:
            self.osq_row(t, host, "processes", {"pid": str(random.randint(400, 30000)), "name": p, "path": (f"/usr/bin/{p}" if linux else f"C:\\Program Files\\{p}"), "cmdline": p, "uid": "1000"})
        for port, name in ((22, "sshd"), (5353, "avahi-daemon")) if linux else ((135, "svchost.exe"), (445, "System")):
            self.osq_row(t, host, "listening_ports", {"pid": str(random.randint(400, 3000)), "port": str(port), "protocol": "6", "address": "0.0.0.0", "name": name, "path": ""})
        for ext, ident, perms in (("1Password – Password Manager", "aeblfdkhhhdcdjpifhhbdiojplfjncoa", "tabs, storage"), ("uBlock Origin", "cjpalhdlnbpafiamejdnhcphjbkeiagm", "tabs, webRequest, <all_urls>")):
            self.osq_row(t, host, "chrome_extensions", {"name": ext, "identifier": ident, "version": "3.1.0", "permissions": perms, "author": "", "profile": "Default"})
        pkgs = "deb_packages" if linux else "programs"
        for name, ver in (("git", "2.47.1"), ("curl", "8.5.0"), ("openssh-client", "9.9")) if linux else (("Google Chrome", "131.0.6778.86"), ("Microsoft Teams", "24295.605"), ("Zoom Workplace", "6.2.11")):
            self.osq_row(t, host, pkgs, {"name": name, "version": ver})
        for name, ver in (("requests", "2.32.3"), ("pip", "24.3"), ("numpy", "2.1.3")):
            self.osq_row(t, host, "python_packages", {"name": name, "version": ver, "directory": "/usr/lib/python3/dist-packages" if linux else "C:\\Python312\\Lib\\site-packages"})

    def s_osquery(self):
        for host in HOSTS.values(): self.osq_baseline(host[0])
        # --- ops-lt-48 / gmartin: LM Studio, local inference only. ZERO network signal in Lab 02.
        t = self.at(8, 40)
        self.osq_row(t, "ops-lt-48", "deb_packages", {"name": "lm-studio", "version": "0.3.9"})
        self.osq_row(t, "ops-lt-48", "processes", {"pid": "4127", "name": "lms", "path": "/home/gmartin/.lmstudio/bin/lms", "cmdline": "lms server start --port 1234", "uid": "1000"})
        self.osq_row(t, "ops-lt-48", "listening_ports", {"pid": "4127", "port": "1234", "protocol": "6", "address": "127.0.0.1", "name": "lms", "path": "/home/gmartin/.lmstudio/bin/lms"})
        self.osq_row(t, "ops-lt-48", "python_packages", {"name": "llama_cpp_python", "version": "0.3.2", "directory": "/home/gmartin/.local/lib/python3.12/site-packages"})
        self.note(BY_NAME["ops-lt-48"], "osquery", "LM Studio installed and serving on 127.0.0.1:1234, a local model. Benign in EVERY Lab 02 method: it never touches the network.")
        # --- dev-vm-51 / jpark: ollama bound to 0.0.0.0 (exposed to the LAN), confirms Lab 02 Method 3
        t = self.at(8, 55)
        self.osq_row(t, "dev-vm-51", "deb_packages", {"name": "ollama", "version": "0.5.7"})
        self.osq_row(t, "dev-vm-51", "processes", {"pid": "1188", "name": "ollama", "path": "/usr/local/bin/ollama", "cmdline": "/usr/local/bin/ollama serve", "uid": "998"})
        self.osq_row(t, "dev-vm-51", "listening_ports", {"pid": "1188", "port": "11434", "protocol": "6", "address": "0.0.0.0", "name": "ollama", "path": "/usr/local/bin/ollama"})
        self.osq_row(t, "dev-vm-51", "processes", {"pid": "2231", "name": "node", "path": "/usr/bin/node", "cmdline": "node /opt/mcp-gateway/server.js --port 8080", "uid": "1000"})
        self.osq_row(t, "dev-vm-51", "listening_ports", {"pid": "2231", "port": "8080", "protocol": "6", "address": "0.0.0.0", "name": "node", "path": "/usr/bin/node"})
        self.osq_row(t, "dev-vm-51", "python_packages", {"name": "ollama", "version": "0.4.5", "directory": "/home/jpark/.local/lib/python3.12/site-packages"})
        self.osq_row(t, "dev-vm-51", "python_packages", {"name": "langchain", "version": "0.3.14", "directory": "/home/jpark/.local/lib/python3.12/site-packages"})
        self.note(BY_NAME["dev-vm-51"], "osquery", "ollama serving on 0.0.0.0:11434 (LAN-exposed) + a node MCP gateway on :8080; langchain/ollama SDKs. Confirms Lab 02 Method 3 and adds the exposure.")
        # --- eng-lt-190 / lchen: opencode + anthropic SDK, AND cloudflared (DoH), explains the Lab 02 DNS blind spot
        t = self.at(9, 5)
        self.osq_row(t, "eng-lt-190", "npm_packages", {"name": "opencode-ai", "version": "1.18.25", "directory": "/usr/local/lib/node_modules"})
        self.osq_row(t, "eng-lt-190", "python_packages", {"name": "anthropic", "version": "0.42.0", "directory": "/home/lchen/.local/lib/python3.12/site-packages"})
        self.osq_row(t, "eng-lt-190", "python_packages", {"name": "httpx", "version": "0.28.1", "directory": "/home/lchen/.local/lib/python3.12/site-packages"})
        self.osq_row(t, "eng-lt-190", "deb_packages", {"name": "cloudflared", "version": "2025.1.0"})
        self.osq_row(t, "eng-lt-190", "processes", {"pid": "902", "name": "cloudflared", "path": "/usr/bin/cloudflared", "cmdline": "cloudflared proxy-dns --port 53 --upstream https://cloudflare-dns.com/dns-query", "uid": "0"})
        self.osq_row(t, "eng-lt-190", "listening_ports", {"pid": "902", "port": "53", "protocol": "17", "address": "127.0.0.1", "name": "cloudflared", "path": "/usr/bin/cloudflared"})
        self.note(BY_NAME["eng-lt-190"], "osquery", "opencode + anthropic SDK installed; cloudflared proxy-dns running on 127.0.0.1:53, the DoH client that made this host invisible to Lab 02 Method 1.")
        # --- hr-lt-140 / psingh: an AI sidebar extension with <all_urls>, the source of the DNS-only 'link preview' lookups
        t = self.at(8, 20)
        self.osq_row(t, "hr-lt-140", "chrome_extensions", {"name": "AI Sidebar - ChatGPT Claude & Gemini", "identifier": "camppjleccjaphfdbohjdohecfnoikec", "version": "5.4.1",
                     "permissions": "tabs, storage, contextMenus, <all_urls>", "author": "", "profile": "Default"})
        self.note(BY_NAME["hr-lt-140"], "osquery", "AI sidebar Chrome extension with <all_urls>: reads every page the user opens and pre-resolves the AI backends. Explains the DNS-only noise in Lab 02, and is itself a data-handling finding.")
        # --- mkt-lt-221 / kwatts: ChatGPT desktop app + Grammarly extension (browser usage confirmed in Lab 02)
        t = self.at(8, 10)
        self.osq_row(t, "mkt-lt-221", "programs", {"name": "ChatGPT", "version": "1.2024.346"})
        self.osq_row(t, "mkt-lt-221", "processes", {"pid": "7712", "name": "ChatGPT.exe", "path": "C:\\Users\\kwatts\\AppData\\Local\\Programs\\ChatGPT\\ChatGPT.exe", "cmdline": "ChatGPT.exe", "uid": "1001"})
        self.osq_row(t, "mkt-lt-221", "chrome_extensions", {"name": "Grammarly: AI Writing and Grammar Checker App", "identifier": "kbfnbcaeplbcioakkpcpgfkobkghlhen", "version": "14.1180", "permissions": "tabs, storage, <all_urls>", "author": "", "profile": "Default"})
        self.note(BY_NAME["mkt-lt-221"], "osquery", "ChatGPT desktop app + Grammarly extension. Consistent with the confirmed browser usage in Lab 02.")
        # --- ubuntu-sysmon: opencode (the Lab 03 agent)
        t = self.at(10, 50)
        self.osq_row(t, "ubuntu-sysmon", "npm_packages", {"name": "opencode-ai", "version": "1.18.25", "directory": "/usr/local/lib/node_modules"})
        self.osq_row(t, "ubuntu-sysmon", "processes", {"pid": "3565", "name": "opencode", "path": "/usr/local/bin/opencode", "cmdline": "opencode run", "uid": "1000"})
        self.note(BY_NAME["10.13.42.42"] if "10.13.42.42" in BY_NAME else "10.13.42.42", "osquery", "opencode installed and running (PID 3565, the Lab 03 agent).")
        # --- fin-lt-112 / rdiaz: Copilot app (sanctioned)
        self.osq_row(self.at(8, 30), "fin-lt-112", "programs", {"name": "Microsoft 365 Copilot", "version": "1.24.1"})
        self.note(BY_NAME["fin-lt-112"], "osquery", "Microsoft 365 Copilot app, sanctioned.")

    # ================================================================== SWG (tag=swg)
    def swg_row(self, t, user, host, path, method="GET", reqsize=None, respsize=None, ua=UA_BROWSER, cat="Business", app="", appclass="General Browsing",
                action="Allowed", inspected=True, status=200, filename=None, filetype=None, dlp=None, dst=None):
        t = self.clamp(t)
        src = BY_NAME[[h for h, u in USER_OF.items() if u == user][0]]
        rec = {"time": iso(t), "user": f"{user}@acme.corp", "department": DEPT[user], "src_ip": src, "dst_ip": dst or (AI.get(host, {}).get("v4") or BENIGN.get(host) or SAAS_AI.get(host) or ["104.18.32.47"])[0],
               "host": host, "url": f"https://{host}{path}" if inspected else f"https://{host}/", "method": method if inspected else "CONNECT", "status": status,
               "reqsize": reqsize if reqsize is not None else random.randint(300, 2500), "respsize": respsize if respsize is not None else random.randint(1_000, 400_000),
               "useragent": ua, "urlcategory": cat, "appname": app or host, "appclass": appclass, "action": action, "ssl_inspected": inspected,
               "policy": "Default-Allow" if action == "Allowed" else "AI-Upload-Block", "location": "HQ", "device": [h for h, u in USER_OF.items() if u == user][0]}
        if filename: rec["filename"] = filename; rec["filetype"] = filetype or filename.rsplit(".", 1)[-1]
        if dlp: rec["dlp_dictionaries"] = dlp
        self.swg.append(rec)

    def s_swg(self):
        AI_CAT, AI_CLASS = "AI & ML Applications", "AI & ML"
        # --- kwatts: ChatGPT in the browser all day (mirrors Lab 02), plus ONE blocked spreadsheet upload
        for hour in (9, 10, 13, 15, 16):
            t = self.at(hour, spread_min=40)
            for i in range(random.randint(4, 9)):
                self.swg_row(t + timedelta(seconds=random.uniform(2, 240) * (i + 1)), "kwatts", "chatgpt.com", random.choice(["/", "/c/" + uuid4(), "/backend-api/conversation", "/backend-api/conversation"]),
                             method="POST" if random.random() < 0.5 else "GET", cat=AI_CAT, app="ChatGPT", appclass=AI_CLASS, reqsize=random.randint(900, 14_000))
        t_up = self.at(15, 22)
        self.swg_row(t_up, "kwatts", "chatgpt.com", "/backend-api/files", method="POST", reqsize=2_418_336, respsize=512, cat=AI_CAT, app="ChatGPT", appclass=AI_CLASS,
                     action="Blocked", status=403, filename="Q3-pipeline-forecast.xlsx", filetype="xlsx", dlp=["Financial Statements"])
        self.swg_row(t_up + timedelta(seconds=41), "kwatts", "chatgpt.com", "/backend-api/files", method="POST", reqsize=2_418_402, respsize=512, cat=AI_CAT, app="ChatGPT", appclass=AI_CLASS,
                     action="Blocked", status=403, filename="Q3-pipeline-forecast.xlsx", filetype="xlsx", dlp=["Financial Statements"])
        self.note(BY_NAME["mkt-lt-221"], "swg", "Attributed to kwatts. Two BLOCKED POSTs to chatgpt.com/backend-api/files: Q3-pipeline-forecast.xlsx (2.4 MB), DLP 'Financial Statements'. The control worked; the attempt is the finding.", when=iso(t_up))
        # --- rdiaz: Copilot (sanctioned)
        for hour in range(8, 18):
            t = self.at(hour, spread_min=50)
            for i in range(random.randint(2, 5)):
                self.swg_row(t + timedelta(seconds=random.uniform(2, 200) * (i + 1)), "rdiaz", "copilot.microsoft.com", random.choice(["/", "/c/", "/turing/conversation/create"]),
                             method=random.choice(["GET", "POST"]), cat=AI_CAT, app="Microsoft Copilot", appclass=AI_CLASS)
        self.note(BY_NAME["fin-lt-112"], "swg", "rdiaz → Microsoft Copilot all day, allowed (sanctioned).")
        # --- lchen: SDK traffic to api.anthropic.com, non-browser user agent (the DoH host in Lab 02; the proxy identifies the user regardless)
        for hour in (8, 9, 10, 11, 14, 15):
            t = self.at(hour, spread_min=59)
            for _ in range(random.randint(3, 8)):
                self.swg_row(t + timedelta(seconds=random.uniform(5, 900)), "lchen", "api.anthropic.com", "/v1/messages", method="POST", reqsize=random.randint(6_000, 120_000), respsize=random.randint(4_000, 60_000),
                             ua=random.choice(["anthropic-sdk-python/0.42.0", "opencode/1.18.25", "python-httpx/0.28.1"]), cat=AI_CAT, app="Anthropic API", appclass=AI_CLASS)
        self.note(BY_NAME["eng-lt-190"], "swg", "lchen → api.anthropic.com/v1/messages with SDK/agent user agents (anthropic-sdk-python, opencode). Not a person in a browser, an agent. The proxy attributes it even though DoH hid it from DNS.")
        # --- abrennan: the recipes site (decoy confirmed: category Food, no AI)
        for hour in (12, 12, 17):
            t = self.at(hour, spread_min=50)
            self.swg_row(t, "abrennan", "www.cloudflare-fronted-recipes.example", "/recipes/" + random.choice(["sourdough", "ramen", "focaccia"]), cat="Food & Dining", app="", appclass="General Browsing", respsize=random.randint(50_000, 400_000))
        self.note(BY_NAME["legal-lt-77"], "swg", "abrennan → a recipes site, category Food & Dining. The shared-CDN decoy stays cleared.")
        # --- dfoster: Notion (sanctioned SaaS, category Productivity), TLS-inspected paths show the AI feature, and the CONVERSATION SHAPE: request size climbs turn over turn
        for hour in (10, 14):
            t = self.at(hour, spread_min=30)
            for i in range(random.randint(3, 6)):   # ordinary Notion use
                self.swg_row(t + timedelta(seconds=i * random.uniform(20, 90)), "dfoster", "www.notion.so", random.choice(["/api/v3/loadPageChunk", "/api/v3/syncRecordValues", "/api/v3/getSpaces"]), method="POST",
                             reqsize=random.randint(400, 3_000), cat="Productivity", app="Notion", appclass="Collaboration")
            size = random.randint(1_800, 2_600); off = 6.0
            for turn in range(random.randint(6, 9)):  # the AI conversation: each turn re-sends the whole transcript (Lab 01!) so reqsize climbs monotonically
                size += random.randint(900, 3_200); off += random.uniform(0.6, 1.6)
                self.swg_row(t + timedelta(minutes=off), "dfoster", "www.notion.so", "/api/v3/runInferenceTranscript", method="POST", reqsize=size, respsize=random.randint(2_000, 12_000),
                             cat="Productivity", app="Notion", appclass="Collaboration")
        t_doc = self.at(14, 48)
        self.swg_row(t_doc, "dfoster", "www.notion.so", "/api/v3/runInferenceTranscript", method="POST", reqsize=1_912_540, respsize=9_100, cat="Productivity", app="Notion", appclass="Collaboration",
                     filename="ACME-Q3-customer-pipeline.csv", filetype="csv", dlp=["Customer Records"])
        self.note(BY_NAME["sales-lt-66"], "swg", "dfoster → www.notion.so/api/v3/runInferenceTranscript: POST sizes climb turn over turn (an LLM conversation), then a 1.9 MB customer CSV goes through ALLOWED, category 'Productivity', sanctioned app, the AI-upload block never fired. No domain list can catch an AI feature inside a sanctioned SaaS.", when=iso(t_doc))
        # --- benign browsing for everyone on the laptop subnet (servers 10.13.42.x bypass the proxy, a documented gap)
        sites = [("github.com", "Technology"), ("slack.com", "Collaboration"), ("wikipedia.org", "Reference"), ("www.nytimes.com", "News"), ("outlook.office365.com", "Webmail"), ("teams.microsoft.com", "Collaboration")]
        for hn, user in USER_OF.items():
            if not BY_NAME[hn].startswith("10.13.20.") or user == "svc-scan": continue
            for _ in range(random.randint(10, 25)):
                host, cat = random.choice(sites)
                self.swg_row(self.at(random.randint(8, 17), spread_min=59), user, host, random.choice(["/", "/inbox", "/feed", "/wiki/Main_Page"]), cat=cat, app=host.split(".")[-2].title(), appclass="General Browsing")
        self.key["findings"].append({"source": "swg", "blind_spots": ["10.13.42.60 ci-runner: the 48 MB api.openai.com upload is ABSENT, servers bypass the proxy",
                                                                       "10.13.20.203 mokafor: QUIC/UDP 443 is not proxied, the HTTP/3 ChatGPT user is ABSENT here too; only Lab 02's conn log saw it",
                                                                       "10.13.20.140 psingh: ordinary browsing only, no AI rows, DNS-only in Lab 02, and (see gws) the real exposure never touched this laptop at all"]})

    # ================================================================== CloudTrail (tag=cloudtrail)
    def ct_row(self, t, identity, source, name, ip, ua, params=None, resp=None, error=None, category="Management", ro=True, region=AWS_REGION):
        t = self.clamp(t)
        rec = {"eventVersion": "1.10", "userIdentity": identity, "eventTime": iso_s(t), "eventSource": source, "eventName": name, "awsRegion": region,
               "sourceIPAddress": ip, "userAgent": ua, "requestParameters": params, "responseElements": resp, "requestID": uuid4(), "eventID": uuid4(),
               "readOnly": ro, "eventType": "AwsApiCall", "managementEvent": category == "Management", "recipientAccountId": AWS_ACCOUNT, "eventCategory": category}
        if error: rec["errorCode"], rec["errorMessage"] = error
        if category == "Data": rec["resources"] = [{"type": "AWS::Bedrock::FoundationModel", "ARN": f"arn:aws:bedrock:{AWS_REGION}::foundation-model/{params.get('modelId', '')}"}]
        self.ct.append(rec)
    def sso_identity(self, user, role="DeveloperAccess"):
        return {"type": "AssumedRole", "principalId": f"AROA{rid(17).upper()}:{user}@acme.corp", "arn": f"arn:aws:sts::{AWS_ACCOUNT}:assumed-role/AWSReservedSSO_{role}_9f1c2a7b3d4e5f60/{user}@acme.corp",
                "accountId": AWS_ACCOUNT, "accessKeyId": "ASIA" + rid(16).upper(),
                "sessionContext": {"sessionIssuer": {"type": "Role", "arn": f"arn:aws:iam::{AWS_ACCOUNT}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_{role}_9f1c2a7b3d4e5f60", "userName": f"AWSReservedSSO_{role}_9f1c2a7b3d4e5f60"}, "attributes": {"mfaAuthenticated": "true"}}}
    def ec2_identity(self, role, instance):
        return {"type": "AssumedRole", "principalId": f"AROA{rid(17).upper()}:{instance}", "arn": f"arn:aws:sts::{AWS_ACCOUNT}:assumed-role/{role}/{instance}", "accountId": AWS_ACCOUNT,
                "accessKeyId": "ASIA" + rid(16).upper(), "sessionContext": {"sessionIssuer": {"type": "Role", "arn": f"arn:aws:iam::{AWS_ACCOUNT}:role/{role}", "userName": role}, "ec2RoleDelivery": "2.0"}}

    def s_cloudtrail(self):
        console_ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36"
        # --- noise: ordinary account activity from a few identities
        for _ in range(140):
            who = random.choice(["jpark", "gmartin", "svc-ci", "lchen", "hvance"])
            ident = self.sso_identity(who, "AdministratorAccess" if who == "gmartin" else "DeveloperAccess" if who != "hvance" else "ReadOnlyAccess")
            src, name, ro = random.choice([("ec2.amazonaws.com", "DescribeInstances", True), ("sts.amazonaws.com", "GetCallerIdentity", True), ("s3.amazonaws.com", "ListBuckets", True),
                                           ("logs.amazonaws.com", "DescribeLogGroups", True), ("iam.amazonaws.com", "ListRoles", True), ("cloudwatch.amazonaws.com", "GetMetricData", True), ("ecr.amazonaws.com", "GetAuthorizationToken", True)])
            self.ct_row(self.at(random.randint(7, 19), spread_min=59), ident, src, name, OFFICE_NAT, random.choice([console_ua, "aws-cli/2.22.7 md/awscrt#0.23.4 ua/2.0 os/linux", "terraform-provider-aws/5.82.0"]), ro=ro)
        for _ in range(60):
            ident = self.ec2_identity("app-prod-ec2-role", "i-0f3a9c2e7b1d4e5f6")
            self.ct_row(self.at(random.randint(0, 23), spread_min=59), ident, random.choice(["sts.amazonaws.com", "logs.amazonaws.com", "secretsmanager.amazonaws.com"]),
                        random.choice(["GetCallerIdentity", "PutLogEvents", "GetSecretValue"]), "10.42.1.87", "aws-sdk-go-v2/1.32.6 os/linux lang/go#1.23.4 md/GOOS#linux", ro=True)
        # --- the enablement chain: jpark (the ollama developer) enables Claude on Bedrock from the console, then attaches Bedrock access to the PROD instance role
        t0 = self.at(13, 47)
        jp = self.sso_identity("jpark")
        self.ct_row(t0, jp, "signin.amazonaws.com", "ConsoleLogin", OFFICE_NAT, console_ua, resp={"ConsoleLogin": "Success"}, ro=False)
        self.ct_row(t0 + timedelta(minutes=2), jp, "bedrock.amazonaws.com", "ListFoundationModels", OFFICE_NAT, console_ua, ro=True)
        self.ct_row(t0 + timedelta(minutes=4), jp, "bedrock.amazonaws.com", "PutUseCaseForModelAccess", OFFICE_NAT, console_ua, params={"formData": "HIDDEN_DUE_TO_SECURITY_REASONS"}, ro=False)
        self.ct_row(t0 + timedelta(minutes=4, seconds=20), jp, "bedrock.amazonaws.com", "CreateFoundationModelAgreement", OFFICE_NAT, console_ua,
                    params={"modelId": "anthropic.claude-3-7-sonnet-20250219-v1:0", "offerToken": "HIDDEN"}, ro=False)
        self.ct_row(t0 + timedelta(minutes=4, seconds=25), jp, "bedrock.amazonaws.com", "PutFoundationModelEntitlement", OFFICE_NAT, console_ua, params={"modelId": "anthropic.claude-3-7-sonnet-20250219-v1:0"}, ro=False)
        self.ct_row(t0 + timedelta(minutes=9), jp, "iam.amazonaws.com", "AttachRolePolicy", OFFICE_NAT, console_ua,
                    params={"roleName": "app-prod-ec2-role", "policyArn": "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"}, ro=False)
        self.key["findings"].append({"source": "cloudtrail", "finding": "Enablement chain by jpark@acme.corp (SSO DeveloperAccess, console, from the office NAT): ConsoleLogin → ListFoundationModels → CreateFoundationModelAgreement/PutFoundationModelEntitlement (anthropic.claude-3-7-sonnet) → iam:AttachRolePolicy AmazonBedrockFullAccess onto app-prod-ec2-role. Nine minutes.", "when": iso_s(t0)})
        # --- the prod workload starts invoking the model 11 minutes after the policy landed: data events, from inside the VPC
        prod = self.ec2_identity("app-prod-ec2-role", "i-0f3a9c2e7b1d4e5f6")
        t1 = t0 + timedelta(minutes=20); n = 0
        for m in range(0, 170, 1):
            if random.random() < 0.28:
                tt = t1 + timedelta(minutes=m, seconds=random.uniform(0, 59))
                self.ct_row(tt, prod, "bedrock.amazonaws.com", random.choice(["InvokeModel", "InvokeModel", "InvokeModelWithResponseStream"]), "10.42.1.87",
                            "aws-sdk-go-v2/1.32.6 os/linux lang/go#1.23.4 md/GOOS#linux api/bedrockruntime#1.24.0", params={"modelId": "anthropic.claude-3-7-sonnet-20250219-v1:0"},
                            category="Data", ro=False); n += 1
        self.key["findings"].append({"source": "cloudtrail", "finding": f"{n} InvokeModel / InvokeModelWithResponseStream data events by app-prod-ec2-role (i-0f3a9c2e7b1d4e5f6) from 10.42.1.87 starting {iso_s(t1)}, a PRODUCTION workload sending data to a model, wired in by a developer the same afternoon. Invisible to every on-prem sensor. NOTE: these are DATA events, only logged if Bedrock data-event logging is enabled.", "count": n})
        # --- intent: gmartin (the LM Studio user) tries Bedrock from the CLI and is denied
        gm = self.sso_identity("gmartin", "AdministratorAccess")
        t2 = self.at(10, 14)
        for i in range(3):
            self.ct_row(t2 + timedelta(seconds=i * 40), gm, "bedrock.amazonaws.com", "InvokeModel", OFFICE_NAT, "aws-cli/2.22.7 md/awscrt#0.23.4 ua/2.0 os/linux",
                        params={"modelId": "meta.llama3-1-70b-instruct-v1:0"}, category="Data", ro=False,
                        error=("AccessDeniedException", "You don't have access to the model with the specified model ID."))
        self.key["findings"].append({"source": "cloudtrail", "finding": "gmartin@acme.corp: 3× InvokeModel AccessDeniedException on meta.llama3-1-70b from the CLI, intent, not usage. Same person running LM Studio locally (osquery).", "when": iso_s(t2)})

    # ================================================================== Google Workspace token audit (tag=gws)
    def gws_row(self, t, actor, ip, name, app_name, client_id, params, flat):
        t = self.clamp(t)
        rec = {"kind": "admin#reports#activity", "id": {"time": iso(t), "uniqueQualifier": str(random.randint(10**17, 10**18 - 1)), "applicationName": "token", "customerId": "C03az79cb"},
               "etag": '"' + rid(24) + '"', "actor": {"email": f"{actor}@acme.corp", "profileId": str(random.randint(10**20, 10**21 - 1))}, "ipAddress": ip,
               "events": [{"type": "auth", "name": name, "parameters": [{"name": "client_id", "value": client_id}, {"name": "app_name", "value": app_name}, {"name": "client_type", "value": "WEB"}] + params}],
               # flattened for the classroom (the same concession Lab 02's Okta records make):
               "event_name": name, "actor_email": f"{actor}@acme.corp", "app_name": app_name, "client_id": client_id, **flat}
        self.gws.append(rec)
    def authorize(self, t, actor, ip, app, cid, scopes):
        self.gws_row(t, actor, ip, "authorize", app, cid, [{"name": "scope", "multiValue": scopes}], {"scopes": " ".join(scopes), "scope_count": len(scopes)})
    def activity(self, t, actor, app, cid, api, method, nbytes):
        self.gws_row(t, actor, "SERVER_TO_SERVER", "activity", app, cid, [{"name": "api_name", "value": api}, {"name": "method_name", "value": method}, {"name": "num_response_bytes", "intValue": str(nbytes)}, {"name": "product_bucket", "value": api.upper()}],
                     {"api_name": api, "method_name": method, "num_response_bytes": nbytes})

    def s_gws(self):
        DRIVE_RO, DRIVE_FILE, GMAIL_RO, CAL_RO, EMAIL, PROFILE = ("https://www.googleapis.com/auth/drive.readonly", "https://www.googleapis.com/auth/drive.file", "https://www.googleapis.com/auth/gmail.readonly",
                                                                  "https://www.googleapis.com/auth/calendar.readonly", "https://www.googleapis.com/auth/userinfo.email", "https://www.googleapis.com/auth/userinfo.profile")
        SANCTIONED = [("Slack", "1035840394411-hc7fh6rsjb9lb2o1i4l9oj1rv6fgbnvu.apps.googleusercontent.com", [EMAIL, PROFILE, CAL_RO]),
                      ("Zoom", "849883241272-3m6h6ftp07bcjrnob5f3tt2c5ueh6svl.apps.googleusercontent.com", [EMAIL, CAL_RO]),
                      ("Figma", "396742129471-lvj0m0uibno7v6u8kjhqqg2jqvh3p8er.apps.googleusercontent.com", [EMAIL, PROFILE]),
                      ("Atlassian", "292311234567-atl9v6u8kjhqqg2jqvh3p8er0m0uibno.apps.googleusercontent.com", [EMAIL, PROFILE, DRIVE_FILE]),
                      ("Miro", "618922334455-miro0m0uibno7v6u8kjhqqg2jqvh3p8e.apps.googleusercontent.com", [EMAIL, PROFILE])]
        # --- noise: routine sanctioned consents + their ordinary activity
        for _ in range(40):
            actor = random.choice(list(DEPT)); app, cid, scopes = random.choice(SANCTIONED)
            ip = OFFICE_NAT if random.random() < 0.8 else "198.51.100." + str(random.randint(2, 200))
            t = self.at(random.randint(7, 19), spread_min=59)
            if random.random() < 0.35: self.authorize(t, actor, ip, app, cid, scopes)
            for _ in range(random.randint(1, 4)):
                self.activity(t + timedelta(minutes=random.uniform(1, 200)), actor, app, cid, "calendar" if CAL_RO in scopes else "oauth2", "calendar.events.list" if CAL_RO in scopes else "oauth2.userinfo.get", random.randint(400, 30_000))
        # --- THE exposure: psingh (HR; DNS-only in Lab 02) consents to a ChatGPT connector with Drive + Gmail read scopes, from a PHONE on a carrier IP,
        #     and the vendor then pulls her Drive server-to-server. Not one byte crosses the corporate network.
        CHATGPT = ("ChatGPT", "77377267392-d8rc2nqjb1o0hs1ebd9pn5mzd9x2qhhr.apps.googleusercontent.com")
        t_c = self.at(13, 41)
        self.authorize(t_c, "psingh", "172.58.44.219", CHATGPT[0], CHATGPT[1], [DRIVE_RO, GMAIL_RO, EMAIL, PROFILE])
        total = 0; calls = 0
        for m in range(0, 70):
            for _ in range(random.randint(2, 7)):
                nb = random.choice([random.randint(2_000, 90_000), random.randint(200_000, 1_400_000), random.randint(1_500_000, 6_000_000)])
                self.activity(t_c + timedelta(minutes=m, seconds=random.uniform(0, 59)), "psingh", CHATGPT[0], CHATGPT[1], "drive", random.choice(["drive.files.list", "drive.files.get", "drive.files.export", "drive.files.get"]), nb)
                total += nb; calls += 1
        for _ in range(35):
            nb = random.randint(3_000, 400_000)
            self.activity(t_c + timedelta(minutes=random.uniform(2, 70)), "psingh", CHATGPT[0], CHATGPT[1], "gmail", random.choice(["gmail.users.messages.list", "gmail.users.messages.get"]), nb); total += nb; calls += 1
        self.key["findings"].append({"source": "gws", "finding": f"psingh@acme.corp (HR) authorized 'ChatGPT' with drive.readonly + gmail.readonly at {iso(t_c)} from a mobile-carrier IP (172.58.44.219). The app then made {calls} Drive/Gmail API calls totalling {total/1e6:.0f} MB in ~70 minutes, SERVER_TO_SERVER. Zero network or proxy evidence, Lab 02 CLEARED this host as DNS-only.", "bytes": total, "calls": calls})
        # --- dfoster consents to an AI meeting notetaker with calendar + drive.file (moderate; the point is the pattern, not the volume)
        NOTES = ("Fireflies.ai Notetaker", "1002830912345-ffnotes0m0uibno7v6u8kjhqqg2jqvh3.apps.googleusercontent.com")
        t_n = self.at(9, 12)
        self.authorize(t_n, "dfoster", OFFICE_NAT, NOTES[0], NOTES[1], [CAL_RO, DRIVE_FILE, EMAIL, PROFILE])
        for _ in range(14):
            self.activity(t_n + timedelta(minutes=random.uniform(1, 400)), "dfoster", NOTES[0], NOTES[1], "calendar", "calendar.events.list", random.randint(5_000, 60_000))
        for _ in range(3):
            self.activity(t_n + timedelta(minutes=random.uniform(60, 400)), "dfoster", NOTES[0], NOTES[1], "drive", "drive.files.create", random.randint(800, 2_000))
        self.key["findings"].append({"source": "gws", "finding": "dfoster authorized an AI meeting notetaker (calendar.readonly + drive.file). Every meeting it joins is transcribed by a third party. Not sanctioned.", "when": iso(t_n)})
        # --- a revoke, so students see the other verb exists
        self.gws_row(self.at(16, 5), "hvance", OFFICE_NAT, "revoke", "Miro", SANCTIONED[4][1], [], {})

    def build(self):
        self.s_osquery(); self.s_swg(); self.s_cloudtrail(); self.s_gws()
        self.osq.sort(key=lambda r: r["unixTime"]); self.swg.sort(key=lambda r: r["time"]); self.ct.sort(key=lambda r: r["eventTime"]); self.gws.sort(key=lambda r: r["id"]["time"])
        self.key["summary"] = {"counts": {"osquery": len(self.osq), "swg": len(self.swg), "cloudtrail": len(self.ct), "gws": len(self.gws)},
                               "window": {"start": iso(self.start), "end": iso(self.end)},
                               "what_each_source_adds": {
                                   "osquery": "AI software present regardless of network use: LM Studio on ops-lt-48 (zero network signal), ollama exposed on dev-vm-51, cloudflared (DoH) on eng-lt-190, an <all_urls> AI extension on hr-lt-140",
                                   "swg": "user attribution; the BLOCKED xlsx upload (kwatts); SDK user agents (lchen); the ALLOWED customer CSV into Notion AI (dfoster) found by request-size growth; and two blind spots (servers bypass, QUIC)",
                                   "cloudtrail": "AI inside the cloud account: jpark's nine-minute enablement chain, prod role invoking Claude, gmartin's AccessDenied attempts",
                                   "gws": "psingh's OAuth consent + ~server-to-server Drive/Gmail pull to an AI vendor, the largest exposure of the day, invisible to every network source; dfoster's notetaker"}}
        return self

# ------------------------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--outdir", default="out")
    ap.add_argument("--anchor", default="now", help="ISO-8601 UTC time the 24h window ENDS at (default: now). Use the same anchor as the Lab 02 generator.")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--answer-key", help="write the instructor answer key JSON here")
    a = ap.parse_args(); random.seed(a.seed)
    end = datetime.now(timezone.utc) if a.anchor == "now" else datetime.fromisoformat(a.anchor.replace("Z", "+00:00"))
    w = World(end).build()
    os.makedirs(a.outdir, exist_ok=True)
    for name, rows in (("osquery_results", w.osq), ("swg_access", w.swg), ("cloudtrail_events", w.ct), ("gws_token_audit", w.gws)):
        with open(os.path.join(a.outdir, name + ".jsonl"), "w") as f:
            for r in rows: f.write(json.dumps(r, separators=(",", ":")) + "\n")
    if a.answer_key:
        os.makedirs(os.path.dirname(a.answer_key) or ".", exist_ok=True)
        with open(a.answer_key, "w") as f: json.dump(w.key, f, indent=2)
    c = w.key["summary"]["counts"]
    print(f"wrote {a.outdir}/: osquery={c['osquery']} swg={c['swg']} cloudtrail={c['cloudtrail']} gws={c['gws']}  window {w.key['summary']['window']['start']} -> {w.key['summary']['window']['end']}")
    if a.answer_key: print(f"answer key: {a.answer_key}")

if __name__ == "__main__":
    main()
