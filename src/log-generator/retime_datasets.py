#!/usr/bin/env python3
"""
retime_datasets.py: shift the timestamps of a *real* captured dataset so it ends "now" (or at
--anchor), preserving every relative interval. Students ingest the output and search "last 24h"
instead of hunting a fixed date in 2026-01/04.

Handles the static real datasets in ../../datasets/:
  * Sysmon XML                     (shifts SystemTime="..." and Data Name="UtcTime">...)
  * Gravwell tagged-export JSONL   ({TS,Tag,SRC,Data(base64)}): shifts the envelope TS AND the
                                    inner timestamp, per known formats:
        - tag=gravwell  : RFC5424 syslog  <PRI>1 <TS> host app procid msgid [sd] msg
        - tag=corelight_*: Zeek JSON      "ts" (and "_write_ts")
        - anything else : envelope TS only (Data left byte-for-byte)

Newest record is placed at --anchor; everything else keeps its offset before it.

    ./retime_datasets.py --in ../../datasets/sysmon/sysmon-events-jan21-clean.xml \
                         --out ../../datasets/sysmon/generated/sysmon-now.xml
    ./retime_datasets.py --in ../../datasets/gravwell-ai-assistant/webserver-ai-logs-a.json \
                         --out ../../datasets/gravwell-ai-assistant/generated/logbot-a-now.json
    ./retime_datasets.py --in ../../datasets/gravwell-ai-assistant/webserver-ai-logs-b.json \
                         --out ../../datasets/gravwell-ai-assistant/generated/logbot-b-now.json --anchor now
"""
import argparse, base64, json, re, sys
from datetime import datetime, timedelta, timezone

def parse_iso(s):
    s = s.strip().replace("Z", "+00:00")
    # pad/truncate fractional seconds to 6 digits for %f
    m = re.match(r"(.*\.)(\d+)(.*)$", s)
    if m:
        frac = (m.group(2) + "000000")[:6]; s = m.group(1) + frac + m.group(3)
    return datetime.fromisoformat(s).astimezone(timezone.utc)

def anchor_time(a):
    return datetime.now(timezone.utc) if a == "now" else parse_iso(a)

# ---- Sysmon XML -----------------------------------------------------------------------------
def retime_sysmon(text, anchor):
    sys_times = [parse_iso(m) for m in re.findall(r'SystemTime="([^"]+)"', text)]
    if not sys_times: raise SystemExit("no SystemTime found, is this Sysmon XML?")
    delta = anchor - max(sys_times)
    def shift_sys(m):
        t = parse_iso(m.group(1)) + delta
        return 'SystemTime="%s000Z"' % t.strftime("%Y-%m-%dT%H:%M:%S.%f")
    def shift_utc(m):
        t = datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S.%f").replace(tzinfo=timezone.utc) + delta
        return 'Name="UtcTime">%s<' % t.strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
    text = re.sub(r'SystemTime="([^"]+)"', shift_sys, text)
    text = re.sub(r'Name="UtcTime">([^<]+)<', shift_utc, text)
    return text, delta, len(sys_times)

# ---- Gravwell tagged-export JSONL -----------------------------------------------------------
SYSLOG_RE = re.compile(r"^(<\d+>1 )(\S+)( .*)$", re.S)
def _shift_syslog(data_text, delta):
    m = SYSLOG_RE.match(data_text)
    if not m: return data_text
    t = parse_iso(m.group(2)) + delta
    return m.group(1) + t.strftime("%Y-%m-%dT%H:%M:%S.%fZ") + m.group(3)
def _shift_zeek(data_text, delta):
    try: obj = json.loads(data_text)
    except ValueError: return data_text
    for k in ("ts", "_write_ts"):
        if isinstance(obj.get(k), str):
            try: obj[k] = (parse_iso(obj[k]) + delta).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
            except ValueError: pass
    return json.dumps(obj, separators=(",", ":"))

def retime_tagged(lines, anchor):
    recs = [json.loads(l) for l in lines if l.strip()]
    if not recs: raise SystemExit("no records")
    ts = [parse_iso(r["TS"]) for r in recs]
    delta = anchor - max(ts)
    out = []
    for r in recs:
        r["TS"] = (parse_iso(r["TS"]) + delta).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        tag = r.get("Tag", "")
        try:
            data = base64.b64decode(r["Data"]).decode("utf-8", "replace")
            if tag == "gravwell":        data = _shift_syslog(data, delta)
            elif tag.startswith("corelight_"): data = _shift_zeek(data, delta)
            else:                        data = None   # leave Data untouched (opaque payloads)
            if data is not None:
                r["Data"] = base64.b64encode(data.encode()).decode()
        except Exception:
            pass
        out.append(json.dumps(r, separators=(",", ":")))
    return out, delta, len(out)

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--in", dest="inp", required=True)
    ap.add_argument("--out", dest="out", required=True)
    ap.add_argument("--anchor", default="now", help='ISO-8601 UTC to place the NEWEST event at (default: now)')
    a = ap.parse_args(); anchor = anchor_time(a.anchor)
    raw = open(a.inp, encoding="utf-8", errors="replace").read()
    import os; os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    if "<Event>" in raw[:4096] or a.inp.endswith(".xml"):
        text, delta, n = retime_sysmon(raw, anchor); open(a.out, "w").write(text)
    else:
        out, delta, n = retime_tagged(raw.splitlines(), anchor)
        open(a.out, "w").write("\n".join(out) + "\n")
    print(f"retimed {n} events by {delta} -> newest now at {anchor.isoformat()}  ({a.out})")

if __name__ == "__main__": main()
