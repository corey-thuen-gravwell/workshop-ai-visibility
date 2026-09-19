# Full workshop pass, part 1: Labs 01, 01b, 00, 02, 03. Run as a seat user with bash -l.
set -uo pipefail
cd ~ && . ~/.workshop_env
GW="https://localhost:${WORKSHOPUID}443"
ok(){ printf '  ✅ %s\n' "$*"; }; bad(){ printf '  ❌ %s\n' "$*"; }
chk(){ # label, actual, expected(substring)
  case "$2" in *"$3"*) ok "$1: $2";; *) bad "$1: got [$2] want [$3]";; esac; }
gwq(){ python3 - "$1" "$GWAUTH" "$GW" <<'PY'
import json,sys,subprocess,datetime
q,auth,gw=sys.argv[1:4]; now=datetime.datetime.now(datetime.timezone.utc)
body=json.dumps({"SearchString":q,"SearchStart":(now-datetime.timedelta(hours=48)).strftime("%Y-%m-%dT%H:%M:%SZ"),"SearchEnd":now.strftime("%Y-%m-%dT%H:%M:%SZ"),"Format":"csv"})
print(subprocess.run(["curl","-sk","-X","POST",gw+"/api/search/direct","-H",auth,"-H","content-type: application/json","-d",body],capture_output=True,text=True).stdout.strip())
PY
}
echo "################ LAB 01"
export LLM=https://api.anthropic.com/v1/messages TOKEN="$ANTHROPIC_API_KEY"
ask(){  curl -sS "$LLM" -H "x-api-key: $TOKEN" -H "anthropic-version: 2023-06-01" -H 'content-type: application/json' -d "$1"; }
askf(){ curl -sS "$LLM" -H "x-api-key: $TOKEN" -H "anthropic-version: 2023-06-01" -H 'content-type: application/json' -d @"$1"; }
t1=$(ask '{"model":"claude-haiku-4-5","max_tokens":64,"messages":[{"role":"user","content":"My favorite color is chartreuse. Reply with just: noted."}]}' | jq -r '.usage.input_tokens'); chk "task1 input_tokens" "$t1" "21"
t2=$(ask '{"model":"claude-haiku-4-5","max_tokens":64,"messages":[{"role":"user","content":"What is my favorite color?"}]}' | jq -r '.usage.input_tokens'); chk "task2 input_tokens" "$t2" "13"
t3=$(ask '{"model":"claude-haiku-4-5","max_tokens":64,"messages":[{"role":"user","content":"My favorite color is chartreuse. Reply with just: noted."},{"role":"assistant","content":"noted."},{"role":"user","content":"What is my favorite color?"}]}' | jq -r '[.usage.input_tokens, .content[0].text] | @tsv'); chk "task3 tokens+answer" "$t3" "35"; chk "task3 remembers" "$t3" "chartreuse"
# Task 4 the way the handout does it: the shipped conversation.json, the documented jq append, askf.
cd ~/jarvis/labs/01-fundamentals
chk "task4 conversation.json ships and parses" "$(jq -r '.messages | length' conversation.json 2>/dev/null)" "3"
jq '.messages += [{"role":"assistant","content":"Your favorite color is chartreuse."},
                  {"role":"user","content":"Name one flower that color. Two words max."}]' \
   conversation.json > /tmp/turn4.json
chk "task4 five messages after the append" "$(jq -r '.messages | length' /tmp/turn4.json)" "5"
t4=$(askf /tmp/turn4.json | jq -r '.usage.input_tokens'); chk "task4 input_tokens" "$t4" "59"
rm -f /tmp/turn4.json; cd ~
t5=$(ask '{"model":"claude-haiku-4-5","max_tokens":256,"tools":[{"name":"read_file","description":"Read a file from disk and return its contents.","input_schema":{"type":"object","properties":{"path":{"type":"string","description":"absolute path"}},"required":["path"]}}],"messages":[{"role":"user","content":"What is in /etc/passwd?"}]}' | jq -r '[.stop_reason, .usage.input_tokens, ([.content[]|select(.type=="tool_use")|.input.path]|join(","))] | @tsv'); chk "task5 tool_use" "$t5" "tool_use"; chk "task5 575 tokens" "$t5" "575"; chk "task5 asked for /etc/passwd" "$t5" "/etc/passwd"
echo "################ LAB 01b"
cd ~/jarvis/labs/01b-demystifying-ai
chk "tokens.bash potato" "$(./tokens.bash 'I am a potato!' 2>/dev/null | grep -o '"prompt_eval_count": *[0-9]*' | head -1)" "5"
chk "embed dims" "$(./embed.bash potato 2>/dev/null | jq '.embeddings[0]|length')" "4096"
chk "similar king->queen" "$(./similar.bash king queen potato 2>/dev/null | grep '^ *king' | tail -1)" "queen"
a=$(./random.bash 2>/dev/null); b=$(./random.bash 2>/dev/null); [ "$a" = "$b" ] && ok "random TEMP=0 deterministic" || bad "random TEMP=0 differs"
a=$(TEMP=1 SEED=42 ./random.bash 2>/dev/null); b=$(TEMP=1 SEED=42 ./random.bash 2>/dev/null); [ "$a" = "$b" ] && ok "random SEED=42 deterministic" || bad "random SEED=42 differs"
chk "logprobs first pick" "$(MAX=2 ./logprobs.bash 2>/dev/null | grep -A1 '^picked' | tail -1)" "great"
chk "logprobs_code" "$(MAX=2 ./logprobs_code.bash 2>/dev/null | grep -A1 '^picked' | tail -1)" "void"
echo "################ LAB 00"
docker run --rm hello-world 2>&1 | grep -q "Hello from Docker" && ok "hello-world" || bad "hello-world"
cd ~/jarvis/labs/00-environment-gravwell && docker compose up -d >/dev/null 2>&1
for i in $(seq 1 40); do curl -sk -o /dev/null -w "%{http_code}" -X POST $GW/api/login -H "content-type: application/json" -d '{"User":"admin","Pass":"changeme"}' | grep -q 200 && break; sleep 3; done; ok "gravwell login after ~$((i*3))s"
# Everything below authenticates with the seat's API token, the way the labs now do.
~/jarvis/labs/00-environment-gravwell/make-token.sh >/dev/null && ok "gravwell API token minted" || bad "make-token.sh failed"
GRAVWELL_TOKEN=$(cat ~/.gravwell_token); export GRAVWELL_TOKEN; GWAUTH="Gravwell-Token: $GRAVWELL_TOKEN"
chk "compose ps Up x2" "$(docker compose ps --format '{{.Status}}' | grep -c Up)" "2"; sleep 8
[ "$(gwq 'tag=gravwell limit 20 | table TIMESTAMP DATA' | tail -n +2 | wc -l)" -ge 1 ] && ok "tag=gravwell has rows" || bad "tag=gravwell empty"
chk "/api/mcp initialize" "$(curl -sk -o /dev/null -w '%{http_code}' -X POST $GW/api/mcp -H "$GWAUTH" -H 'content-type: application/json' -H 'accept: application/json, text/event-stream' -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"e2e","version":"1.0"},"capabilities":{}}}')" "200"
[ "$(docker exec ${WORKSHOPUID}llm grep -ci "gone hot" /opt/gravwell/log/llm_ingester.log)" -ge 1 ] && ok "ingester hot ($(docker exec ${WORKSHOPUID}llm grep -ci "starting listener" /opt/gravwell/log/llm_ingester.log) listeners)" || bad "ingester not hot"
echo "################ LAB 02"
cd ~/jarvis/datasets/corelight/generated; for f in dns:01 ssl:02 conn:03 http:04; do nc -q1 localhost ${WORKSHOPUID}${f#*:} < corelight_${f%%:*}.jsonl; done; nc -q1 localhost ${WORKSHOPUID}06 < okta_access.jsonl
cd ~/jarvis; ./labs/02-shadow-ai/upload-resource.sh AI_DOMAINS datasets/resources/ai_domains.txt >/dev/null && ./labs/02-shadow-ai/upload-resource.sh AI_DOMAINS_PLUS_API datasets/resources/ai_domains_plus_api.txt >/dev/null && ok "resources uploaded"; sleep 12
chk "detour raw conn rows" "$(gwq 'tag=corelight_conn count | table count' | tail -1)" "431"
chk "method1 loudest" "$(gwq 'tag=corelight_dns json "id.orig_h" as src_ip query | lookup -s -r AI_DOMAINS query Domain | stats unique_count(query) as domains by src_ip | sort by domains desc | table src_ip domains' | sed -n 2p)" "10.13.20.155,6"
chk "method2 hosts" "$(gwq 'tag=corelight_ssl json "id.orig_h" as src_ip server_name | lookup -s -r AI_DOMAINS_PLUS_API server_name Domain | count by src_ip | table src_ip count' | tail -n +2 | cut -d, -f1 | sort | tr '\n' ' ')" "10.13.20.112 10.13.20.190 10.13.20.221 10.13.42.42 10.13.42.60"
chk "method3 dev-vm-51" "$(gwq 'tag=corelight_http json "id.orig_h" as src_ip host | count by src_ip host | sort by count desc | table src_ip host count' | sed -n 2p)" "10.13.42.51,mcp-gateway.acme.corp,20"
chk "method4 okta" "$(gwq 'tag=okta json application_hostname actor.alternateId as user | lookup -s -r AI_DOMAINS_PLUS_API application_hostname Domain | table user application_hostname' | tail -n +2 | tr '\n' ' ')" "kwatts@acme.corp,chatgpt.com"
two=$(gwq '@ai_resolved { tag=corelight_dns json "id.orig_h" as src_ip query answers | lookup -s -r AI_DOMAINS_PLUS_API query Domain | regex -e answers "(?P<ip>\d+\.\d+\.\d+\.\d+)" | table src_ip ip query }; tag=corelight_conn json "id.orig_h" as src_ip "id.resp_h" as dst_ip orig_bytes resp_bytes service | lookup -s -r @ai_resolved [src_ip dst_ip] [src_ip ip] (query) | stats count sum(orig_bytes) as up sum(resp_bytes) as down by src_ip query service | table src_ip query service count up down' | tail -n +2 | cut -d, -f1 | sort | tr '\n' ' ')
chk "compound two-step = 5 hosts" "$two" "10.13.20.112 10.13.20.203 10.13.20.221 10.13.42.42 10.13.42.60"
chk "task4 DoH host DNS" "$(gwq 'tag=corelight_dns json "id.orig_h" as src_ip query | eval src_ip == "10.13.20.190" | count by query | table query count' | grep -c cloudflare-dns)" "1"
chk "task7 biggest upload" "$(gwq 'tag=corelight_conn json "id.orig_h" as src_ip orig_bytes | stats max(orig_bytes) as up by src_ip | sort by up desc | table src_ip up' | sed -n 2p)" "10.13.42.60,48000000"
w=$(gwq 'tag=corelight_conn json "id.orig_h" as src_ip "id.resp_h" as dst_ip | eval src_ip == "10.13.42.42" | eval dst_ip == "160.79.104.10" | stats min(TIMESTAMP) as first max(TIMESTAMP) as last count | table first last count' | tail -1); chk "task8 burst 79 conns" "$w" ",79"; echo "     network window: $w"
echo "################ LAB 03"
nc -q1 localhost ${WORKSHOPUID}07 < ~/jarvis/datasets/sysmon/generated/sysmon-retimed.xml; sleep 10
chk "tag=sysmon count" "$(gwq 'tag=sysmon count | table count' | tail -1)" "3598"
x=$(gwq 'tag=sysmon xml Event.System.EventID as EventID Event.EventData.Data[Name]=="ParentProcessId" as ParentPID | eval EventID == "1" | count by ParentPID | sort by count desc | table ParentPID count' | sed -n 2,3p | tr '\n' ' ')
w1=$(gwq 'tag=sysmon winlog EventID == 1 ParentProcessId | count by ParentProcessId | sort by count desc | table ParentProcessId count' | sed -n 2,3p | tr '\n' ' ')
[ "$x" = "$w1" ] && ok "xml == winlog: $w1" || bad "xml [$x] != winlog [$w1]"
chk "task2 race condition" "$(gwq 'tag=sysmon winlog EventID == 1 ParentProcessId == 3565 ParentImage | count by ParentImage | table ParentImage count' | tail -1)" "-,109"
chk "task3 bash 73" "$(gwq 'tag=sysmon winlog EventID == 1 ParentProcessId == 3565 Image | count by Image | sort by count desc | table Image count' | sed -n 2p)" "/usr/bin/bash,73"
chk "task4 passwd read" "$(gwq 'tag=sysmon winlog EventID == 1 ParentProcessId == 3565 Image ~ bash CommandLine ~ passwd | count | table count' | tail -1)" "1"
chk "task5 rule one row" "$(gwq 'tag=sysmon winlog EventID == 1 Image ~ bash ParentProcessId | count by ParentProcessId | eval count > 10 | table ParentProcessId count' | tail -n +2 | tr '\n' ' ')" "3565,73"
sw=$(gwq 'tag=sysmon winlog EventID == 1 ParentProcessId == 3565 | stats min(TIMESTAMP) as first max(TIMESTAMP) as last count | table first last count' | tail -1); chk "task6 sysmon window 109" "$sw" ",109"; echo "     sysmon window:  $sw"
echo "-- Sysmon kit (API stand-in for the UI clicks)"; H="$GWAUTH"
for i in 1 2 3; do RUUID=$(curl -sk -m 60 $GW/api/kits/remote/list -H "$H" | jq -r '.[] | select(.ID=="io.gravwell.windows.sysmon") | .UUID' 2>/dev/null); [ -n "$RUUID" ] && break; sleep 5; done; curl -sk -X POST $GW/api/kits -H "$H" -F "remote=$RUUID" -o /tmp/sk28.json; UUID=$(jq -r .UUID /tmp/sk28.json)
curl -sk -X PUT "$GW/api/kits/$UUID" -H "$H" -H content-type:application/json -d '{"OverwriteExisting":true,"Global":true}' -o /dev/null
for i in $(seq 1 30); do st=$(curl -sk $GW/api/kits -H "$H" | jq -r ".[] | select(.UUID==\"$UUID\") | .Installed"); [ "$st" = true ] && break; sleep 4; done; chk "kit installed" "$st" "true"
Q=$(python3 -c "import json;print([e['Query'] for e in json.load(open('/dev/stdin')) if e.get('Name')=='Sysmon: Top 100 Parent Processes'][0])" < <(curl -sk $GW/api/library -H "$H"))
chk "kit query empty before macro fix" "$(gwq "$Q" | tail -n +2 | wc -l)" "0"
MID=$(curl -sk $GW/api/macros -H "$H" | jq -r '.[] | select(.Name=="PROVIDER") | .ID'); M=$(curl -sk $GW/api/macros -H "$H" | jq -c '.[] | select(.Name=="PROVIDER") | .Expansion = "Provider==\"Linux-Sysmon\""'); curl -sk -X PUT "$GW/api/macros/$MID" -H "$H" -H content-type:application/json -d "$M" -o /dev/null
chk "kit query after macro fix" "$(gwq "$Q" | sed -n 2p)" "-,553"
echo "-- checkpoint"; cd ~/jarvis && echo garbage > labs/03-endpoint-sysmon/README.md && git checkout stage-sysmon -- labs/03-endpoint-sysmon && chk "checkpoint restore clean" "[$(git status --short)]" "[]"
echo "(stack left up for part 2)"
