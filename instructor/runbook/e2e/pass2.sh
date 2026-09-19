# Full workshop pass, part 2: Labs 04 and 05 (stack already up from part 1).
set -uo pipefail
cd ~ && . ~/.workshop_env
GW="https://localhost:${WORKSHOPUID}443"
ok(){ printf '  ✅ %s\n' "$*"; }; bad(){ printf '  ❌ %s\n' "$*"; }
chk(){ case "$2" in *"$3"*) ok "$1: $2";; *) bad "$1: got [$2] want [$3]";; esac; }
GRAVWELL_TOKEN="${GRAVWELL_TOKEN:-$(cat ~/.gravwell_token)}"; GWAUTH="Gravwell-Token: $GRAVWELL_TOKEN"
gwq(){ python3 - "$1" "$GWAUTH" "$GW" <<'PY'
import json,sys,subprocess,datetime
q,auth,gw=sys.argv[1:4]; now=datetime.datetime.now(datetime.timezone.utc)
body=json.dumps({"SearchString":q,"SearchStart":(now-datetime.timedelta(hours=2)).strftime("%Y-%m-%dT%H:%M:%SZ"),"SearchEnd":now.strftime("%Y-%m-%dT%H:%M:%SZ"),"Format":"csv"})
print(subprocess.run(["curl","-sk","-X","POST",gw+"/api/search/direct","-H",auth,"-H","content-type: application/json","-d",body],capture_output=True,text=True).stdout.strip())
PY
}
echo "################ part-1 re-checks"
cd ~/jarvis/labs/01b-demystifying-ai; chk "tokens.bash potato prompt_eval_count" "$(./tokens.bash 'I am a potato!' 2>/dev/null | grep -o '"prompt_eval_count": [0-9]*')" "5"
n=$(gwq 'tag=gravwell count | table count' | tail -1); [ "${n:-0}" -gt 0 ] && ok "tag=gravwell non-empty ($n)" || bad "tag=gravwell empty"
echo "################ LAB 04"
rm -rf ~/moneyprinter; cp -r ~/jarvis/labs/04-opencode-config/moneyprinter ~/moneyprinter && cd ~/moneyprinter
cat > opencode.json <<JSON
{ "\$schema": "https://opencode.ai/config.json",
  "provider": { "anthropic": { "options": { "baseURL": "http://localhost:${WORKSHOPUID}81/v1", "apiKey": "$ANTHROPIC_API_KEY" } } },
  "model": "anthropic/claude-sonnet-5", "small_model": "anthropic/claude-haiku-4-5" }
JSON
chk "planted bug present" "$(grep -c 'quantity > BULK_THRESHOLD' pricing.py)" "1"
t0=$(date +%s); timeout 600 opencode run "Run the tests, find the failing one, explain the bug, and fix it." < /dev/null > ~/lab04.out 2>&1; echo "     agent took $(( $(date +%s) - t0 ))s"
chk "bug fixed to >=" "$(grep -c 'quantity >= BULK_THRESHOLD' pricing.py)" "1"
chk "log has no prompt text" "$(grep -c 'find the failing one' ~/.local/share/opencode/log/*.log | tail -1 | cut -d: -f2)" "0"
SID=$(opencode session list -n 5 2>/dev/null | grep -oE "ses_[A-Za-z0-9]+" | head -1); opencode export "$SID" > session.json 2>/dev/null
chk "export valid JSON" "$(jq -e . session.json >/dev/null 2>&1 && echo yes || echo no)" "yes"
chk "export has prompt" "$(grep -c 'find the failing one' session.json)" "1"
b=$(jq '[.. | objects | select(.tool? == "bash")] | length' session.json); [ "$b" -gt 0 ] && ok "export has $b bash calls with output" || bad "no bash calls in export"
c=$(jq '[.. | objects | .cost? // empty] | add' session.json); ok "session cost \$$c"
chk "ingester saw Lab 04 (tag=llm)" "$(gwq 'tag=llm intrinsic event_type | grep -e event_type response.tool_call | count | table count' | tail -1 | awk '$1>0{print "yes"}')" "yes"
echo "################ LAB 05 part 1: litellm"
cd ~/jarvis/labs/05-llm-proxy/litellm && docker compose up -d >/dev/null 2>&1
for i in $(seq 1 30); do curl -s -o /dev/null -w "%{http_code}" http://localhost:${WORKSHOPUID}00/health/liveliness | grep -q 200 && break; sleep 3; done; ok "litellm up after ~$((i*3))s"
cd ~/jarvis/labs/05-llm-proxy && ./testai.sh > ~/testai.out 2>&1; chk "testai advertises models" "$(grep -c '^claude' ~/testai.out)" "3"; chk "testai got Boise" "$(grep -ci boise ~/testai.out)" "1"; sleep 8
n=$(gwq 'tag=syslog grep HTTP | count | table count' | tail -1); [ "${n:-0}" -gt 0 ] && ok "tag=syslog HTTP rows: $n" || bad "tag=syslog empty"
chk "gateway log content-blind (Boise rows)" "$(gwq 'tag=syslog grep Boise | count | table count' | tail -n +2 | wc -l)" "0"
echo "################ LAB 05 part 2a: ingester"
cat > ~/moneyprinter/opencode.json <<JSON
{ "\$schema": "https://opencode.ai/config.json",
  "provider": { "anthropic": { "options": { "baseURL": "http://localhost:${WORKSHOPUID}81/v1", "apiKey": "$ANTHROPIC_API_KEY" } } },
  "model": "anthropic/claude-haiku-4-5", "small_model": "anthropic/claude-haiku-4-5" }
JSON
cd ~/moneyprinter
timeout 300 opencode run "Which model are you running? One sentence." < /dev/null 2>&1 | tail -1 | cut -c1-100 | sed 's/^/     /'
timeout 300 opencode run "List the files in this directory and read pricing.py. One sentence summary." < /dev/null > /dev/null 2>&1; sleep 6
chk "tag=llm which-model prompt captured" "$(gwq 'tag=llm intrinsic event_type role | grep "Which model are you running" | count | table count' | tail -1 | awk '$1>0{print "yes"}')" "yes"
chk "tag=llm tool calls with args" "$(gwq 'tag=llm intrinsic event_type tool_name | grep -e event_type response.tool_call | count by tool_name | table tool_name count' | grep -c 'read,')" "1"
s=$(gwq 'tag=llm intrinsic session_id | count by session_id | table session_id count' | tail -n +2 | wc -l); ok "tag=llm sessions: $s"
echo "################ LAB 05 part 2c: the system prompt (traffic still on the ingester)"
chk "system_message recorded" "$(gwq 'tag=llm intrinsic event_type | grep -e event_type request.system_message | count | table count' | tail -1 | awk '$1>=1{print "yes"}')" "yes"
chk "task 2 measure: system prompt is the biggest" "$(gwq 'tag=llm intrinsic event_type | eval chars = len(DATA); | stats sum(chars) as chars by event_type | sort by chars desc | table event_type chars' | sed -n 2p | cut -d, -f1)" "request.system_message"
chk "task 4 cwd regex" "$(gwq 'tag=llm intrinsic event_type | grep -e event_type request.system_message | regex -e DATA "Working directory: (?P<cwd>[^\n]+)" | table cwd' | sed -n 2p)" "/home/$USER/moneyprinter"
chk "task 5 hash/count query runs" "$(gwq 'tag=llm intrinsic event_type | grep -e event_type request.system_message | eval fp = hash_sha256(DATA); chars = len(DATA); | stats count by fp chars | table fp chars count' | tail -n +2 | wc -l | awk '$1>=1{print "rows"}')" "rows"
cd ~/moneyprinter; echo "MARKER-$USER: always address the user as Captain." >> AGENTS.md
timeout 300 opencode run "What is the bulk threshold in pricing.py? One sentence." < /dev/null > ~/lab05-2c.out 2>&1; sleep 8
chk "task 6 marker landed in system_message" "$(gwq "tag=llm intrinsic event_type | grep -e DATA \"MARKER-$USER\" | count by event_type | table event_type count" | sed -n 2p | cut -d, -f1)" "request.system_message"
[ "$(grep -c -i captain ~/lab05-2c.out)" -ge 1 ] && ok "task 6 agent obeyed (Captain)" || echo "  ℹ️  task 6: marker was in the prompt but the model did not say Captain this run (the lab asks whether it obeyed; usually, not always)"
chk "harness replay query runs" "$(gwq 'tag=llm intrinsic event_type session_id | sort by TIMESTAMP asc | table TIMESTAMP event_type DATA' | tail -n +2 | wc -l | awk '$1>5{print "rows"}')" "rows"
# Task (c) is a hunt, not an invariant: whether it finds anything depends on whether the agent
# decided to read a file holding a key (its own opencode.json is one). The handout covers both
# outcomes, so the check is that the query RUNS, and it reports which way the run came out.
sec=$(gwq 'tag=llm intrinsic event_type | regex -e DATA "(?P<secretish>sk-[A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]+PRIVATE KEY-----)" | count | table count' | tail -1)
case "$sec" in
    count) ok "secret-shape hunt ran, no matches this run (the handout's usual case)" ;;
    ''|*[!0-9]*) bad "secret-shape query did not run: [$sec]" ;;
    *) ok "secret-shape hunt ran, $sec match(es): the agent read a file holding a key, which is handout task (c)" ;;
esac
echo "################ LAB 05 part 2b: python proxy"
cd ~/jarvis/src/logging-proxy; setsid ./llm_audit_proxy.py --listen 0.0.0.0:${WORKSHOPUID}90 --upstream https://api.anthropic.com --log-file ~/proxy.jsonl --tcp localhost:${WORKSHOPUID}05 > ~/proxy.out 2>&1 < /dev/null & sleep 2
sed -i "s|localhost:${WORKSHOPUID}81/v1|localhost:${WORKSHOPUID}90/v1|" ~/moneyprinter/opencode.json
cd ~/moneyprinter; timeout 300 opencode run "Read pricing.py and tell me the bulk threshold. One sentence." < /dev/null 2>&1 | tail -1 | cut -c1-100 | sed 's/^/     /'; sleep 6
chk "proxy.jsonl tools_offered = 10" "$(jq -c 'select(.event_type=="request.tools_offered") | (.tool_names|length)' ~/proxy.jsonl | head -1)" "10"
chk "tag=proxy tools_offered in Gravwell" "$(gwq 'tag=proxy json event_type | grep -e event_type request.tools_offered | count | table count' | tail -1 | awk '$1>0{print "yes"}')" "yes"
echo "-- stretch: gateway mode"; setsid ~/jarvis/src/logging-proxy/llm_audit_proxy.py --listen 127.0.0.1:${WORKSHOPUID}92 --upstream https://api.anthropic.com --upstream-key "$ANTHROPIC_API_KEY" --client-key hunter2 --log-file ~/proxy-gw.jsonl > ~/proxy-gw.out 2>&1 < /dev/null & sleep 3
chk "client key accepted" "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:${WORKSHOPUID}92/v1/messages -H 'x-api-key: hunter2' -H 'anthropic-version: 2023-06-01' -H 'content-type: application/json' -d '{"model":"claude-haiku-4-5","max_tokens":8,"messages":[{"role":"user","content":"hi"}]}')" "200"
chk "wrong key refused" "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:${WORKSHOPUID}92/v1/messages -H 'x-api-key: wrong' -H 'anthropic-version: 2023-06-01' -H 'content-type: application/json' -d '{"model":"claude-haiku-4-5","max_tokens":8,"messages":[{"role":"user","content":"hi"}]}')" "401"
chk "real key never logged" "$(cat ~/proxy.jsonl ~/proxy-gw.jsonl | grep -c "${ANTHROPIC_API_KEY:0:20}")" "0"
echo "(stack + proxies left up for part 3)"
