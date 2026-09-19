# Walkthrough 01b: Demystifying how AI "thinks"

> ⛔ **INSTRUCTOR ONLY.** Contains every answer. Student handout:
> [`labs/01b-demystifying-ai/README.md`](../../labs/01b-demystifying-ai/README.md).

**Module:** M2b · **Budget:** 45 min (≈20 deck + ≈25 mini-lab) · **Checkpoint:** `stage-demystify`
(`git checkout stage-demystify -- labs/01b-demystifying-ai`)

> Every script prints the **request** it sends (the JSON body, on stderr) before the response, so
> the outputs quoted below are preceded by one or more `request  POST …/api/generate {…}` lines.
> That is on purpose: the knobs (`temperature`, `seed`, `logprobs`, `raw`) are the lesson.
**Flex:** ⏱ the lab compresses to a front-of-room demo (−20) · **Deck:** [`slides/01b-demystifying-ai.md`](../../slides/01b-demystifying-ai.md)

This is the "it's a token predictor" argument, made hands-on. M2 showed them that the *API* is
plain HTTP with no memory. M2b shows them that the *model* on the other end is a probability
table and a dice roll, and that both the table and the dice are things you can see and set from
the request. It exists because "how AI works" is the first of the four things this course must
teach, and because every later conversation about an agent "deciding" to do something goes better
once the room has watched a decision happen as a row of five percentages.

**Every output below was produced against the workshop endpoint** (`logbot` for
generation, `qwen3-embedding` for vectors), and the whole handout was then re-run **on the lab host
as seat `workshop28` through the installed relay** with identical results; `preflight.sh` 39 ok / 0 fail. Temperature-0 outputs are byte-stable and will
reproduce; everything sampled will differ, and the *shape* is what matters.

---

## Timing

| Min | Segment |
|---:|---|
| 0–8 | Deck: text predictor, tokens, embeddings, the Mark V Shaney → transformer lineage |
| 8–12 | Tasks 1–2: tokens and vectors (fast; they mostly read numbers) |
| 12–17 | Task 3: the determinism reveal. Do this one on the projector *with* them |
| 17–24 | Task 4: the probability table. Slowest and most important |
| 24–30 | Task 5: temperature. Let them run it repeatedly; it's fun |
| 30–34 | Task 6: their own sentence |
| 34–45 | Deck, slides 9–11: "it's a regular program"; anthropomorphism as marketing; discussion |

**If you're behind:** run Tasks 1–2 from the front (−5), and cut Task 6 (−4). Never cut Task 4 or 5,
they are the module. **If you're way behind:** the whole lab demos in 10 minutes from one
terminal; the deck's three "Demo!" slides were written for exactly that.

## Before class

- **One thing to stand up on the host: the relay.** `instructor/runbook/scripts/start-llm-relay.sh`
  installs a root systemd unit (`workshop-llm-relay`) that listens on **`127.0.0.1:9010`** and
  forwards `/api/generate`, `/api/embed` and `/api/tags` to the Gravwell research endpoint with the
  bearer token added. The token lives in `/opt/workshop/gravwell-llm.env` (root, 0600), copied from
  [`instructor/runbook/gravwell-llm.env`](../runbook/gravwell-llm.env). **Seats never receive it**:
  `makeuser.sh` gives them only `GRAVWELL_LLM_URL=http://127.0.0.1:9010`.
- **`preflight.sh` checks the relay**: unit active, bound to loopback only, token file root:600,
  `/api/tags` answers 200 with no client credential, `/api/version` gets 403, and no seat's
  `~/.workshop_env` contains the token. Run it. This is the one lab that depends on a box that
  isn't the lab host, and on a service that isn't docker.
- **`cat` anything you like on the projector.** The scripts carry no credential; neither does the
  seat's environment. The only place the token exists is a root-only file and root's process.
- **Rotate the token after the class**: edit `instructor/runbook/gravwell-llm.env`, commit, run
  `start-llm-relay.sh restart` on the host. The build script still refuses to publish a student repo
  containing the token string, belt and braces.
- **Relay down = lab dead.** `curl: (7) Failed to connect` from every seat means
  `systemctl restart workshop-llm-relay`; `journalctl -u workshop-llm-relay -n 30` says why. Its log
  is one line per request (method, path, status, sizes, ms), no prompt content, no token.
- `jq` and `python3` on the host (pre-flight checks both). `similar.bash` uses python3 for the
  cosine math; everything else is curl + jq.
- Twenty seats hitting one small model at once is fine, the generation calls are ~0.6 s each, but
  `TEMP=3` runs produce long output. `MAX=60` caps generation in `logprobs.bash` for that reason.

> **The endpoint is Ollama-shaped** (and the relay is transparent to that). `/api/generate` with `options.temperature` / `options.seed`,
> `logprobs` + `top_logprobs`, `think:false`, `raw:true`; `/api/embed`; `/api/tags`. If someone
> asks "is this the OpenAI API?": no, but the same knobs exist there under different names
> (`temperature`, `seed`, `logprobs`), and that's a good aside: **these are request parameters
> on every vendor's API.**

---

## Task 1: Tokens

`tokens.bash` deliberately parses **nothing**: per string it prints the curl
it runs and the full JSON response through `jq .`, so students see a raw model response once
before the later scripts start pulling single fields out. Point them at `prompt_eval_count`.

```
### I am a potato!
curl -sS http://127.0.0.1:9010/api/generate -H 'content-type: application/json' \
  -d '{"model":"logbot","prompt":"I am a potato!","raw":true,"stream":false,
       "options":{"num_predict":1}}'

{
  "model": "logbot",
  "created_at": "...",
  "response": "\n\n",
  "done": true,
  ...
  "prompt_eval_count": 5,
  "eval_count": 1
}
```

**Measured `prompt_eval_count`:**

| text | tokens |
|---|---|
| `I am a potato!` | 5 |
| `unbelievable` | 3 |
| `Hello world` | 2 |
| `cat` | 1 |
| `rm -rf /` | 4 |
| `supercalifragilisticexpialidocious` | 11 |

`I am a potato!` → 5 matches the deck slide exactly (`I` `am` `a` `pot` `ato!`). Point at
`unbelievable` = 3 and the M2 deck's table that said "1–2": *the tokenizer decides, not you.*

**Answer:** a token is whatever the tokenizer learned was a frequent chunk. Common words are one
token; rare words shatter into pieces; punctuation often glues onto its neighbour (`ato!`). Tell
them to hold onto `pot`+`ato`: they'll see the same thing happen *on output* in Task 5.

How it works: `raw:true` skips the chat template so `prompt_eval_count` is exactly the text's
token count; `num_predict:1` keeps the call cheap.

## Task 2: Embeddings

**Measured:** `qwen3-embedding` returns **4096** dimensions. First eight for "potato":
`[0.0116, 0.0175, 0.0087, -0.0068, 0.0203, …]`: meaningless individually, and that's the point.

`./similar.bash` (default set):

```
              king    queen   throne   potato    fries    Idaho firewall   syslog
     king    1.000    0.907    0.829    0.580    0.564    0.530    0.525    0.471
    queen    0.907    1.000    0.800    0.591    0.573    0.542    0.527    0.469
   throne    0.829    0.800    1.000    0.579    0.568    0.494    0.542    0.465
   potato    0.580    0.591    0.579    1.000    0.737    0.557    0.528    0.458
    fries    0.564    0.573    0.568    0.737    1.000    0.502    0.565    0.484
    Idaho    0.530    0.542    0.494    0.557    0.502    1.000    0.450    0.408
 firewall    0.525    0.527    0.542    0.528    0.565    0.450    1.000    0.639
   syslog    0.471    0.469    0.465    0.458    0.484    0.408    0.639    1.000

     king  is nearest to  queen  (0.907)
   throne  is nearest to  king   (0.829)
   potato  is nearest to  fries  (0.737)
    Idaho  is nearest to  potato (0.557)
 firewall  is nearest to  syslog (0.639)
```

**Answers:** `Idaho` → **potato** (the deck's joke, confirmed by a 4096-dimensional vector);
`throne` → **king**. Everything security-flavoured clusters together, everything royal clusters
together, and the cross-cluster numbers sit around 0.45–0.55, that's the "floor".

*Beat:* the comparison step is `sum(a*b)/(|a||b|)` in eleven lines of Python, no model involved.
"Similar" is geometry. This is also the seed for the P3 padding module (semantic search over LLM
logs) and the RAG conversation: a vector database is a pile of these plus nearest-neighbour search.

> Single words are a slightly unfair test of a sentence-embedding model (the baseline similarity
> between unrelated words is ~0.5). If someone's own word set gives mushy numbers, have them try
> short sentences: *"The king sat on the throne"* vs *"The queen sat on the throne"* scored 0.821
> with unrelated sentences down at 0.08–0.27.

## Task 3: Determinism

The default prompt is *"In one sentence, give me your honest opinion of pineapple on pizza."*,
because it is divisive enough that the model has opinions and colourful enough that the differences
between runs are obvious. Any strongly flavoured local thing works; swap it for something the room
knows if you have a better one. The exact sentences depend on the model behind the relay; the
*pattern* below does not.

**`./random.bash` (temperature 0), three runs:** the same sentence, character for character, every
time. `SEED=7` at temperature 0: **also identical**, at temperature 0 there is no dice roll to seed.

**`TEMP=1 ./random.bash`, two runs (no seed sent):** two different sentences, usually the same
opinion in different words.

**`TEMP=1 SEED=42 ./random.bash`, two runs:** identical again, and different from the temperature-0
sentence. A different seed (`SEED=7`) gives a different, equally stable sentence.

**Answer:** the randomness is a random *number* the sampler consumes. Leave it out and the server
draws one for you, which is what every chat client does, that's the "illusion of
non-determinism" on slide 6. Supply it and the program is exactly as deterministic as any other
program. `cat random.bash` shows the seed going into `options.seed`, in the request, from the client.

*Beats:* "So when a vendor says the model is non-deterministic, who chose that?" And: every one of
those sentences says the same thing in different words. The *table* behind them (Task 4) didn't
move; the dice did.

## Task 4: The probability table

**Measured, `./logprobs.bash` (temperature 0):**

```
response:    great leader who inspires his team to achieve their best.

picked            candidates (probability)
"great"           "great" 41.9%   "support" 19.2%   "very" 4.3%   "hard" 2.8%   "fant" 1.8%
" leader"         " leader" 91.9%   " mentor" 4.9%   " manager" 1%   " support" 0.6%
" who"            " who" 77.8%   "." 10.6%   "<|im_end|>" 10.4%   " and" 0.9%   " to" 0.1%
" inspires"       " inspires" 68.7%   " always" 17.7%   " values" 4.6%   " supports" 2.3%
" his"            " his" 40%   " confidence" 30.9%   " the" 13%   " me" 6.4%   " everyone" 5%
" team"           " team" 100%   " entire" 0%   " colleagues" 0%   " employees" 0%   "团队" 0%
…
```

**Answers:** first row, runner-up **"support" at 19.2%** against "great" at 41.9%. So "great"
wasn't a judgement about Alex; it was the biggest slice of a pie that was 58% *not* "great".
(The percentages here were measured with an earlier wording of the prompt; expect the shape, not
the exact values.)

Things to point at on the projector:
- `<|im_end|>` at 10.4% on row three: the model nearly stopped after "great leader". "Stop" is
  just another token in the table.
- `"团队"` (Chinese for "team") at 0% in row six: the vocabulary is the whole world's text.
- `" his"` at 40% vs `" confidence"` at 30.9%: a coin-flip that sends the sentence two different
  places. **Each row is conditioned on the pick before it.** That's why "it's autocomplete" is
  exactly right and also why the output still reads like a sentence.

**`./logprobs_code.bash`:**

```
response:    void main(void){ printf("Hello, World!\n"); }

"void"            "void" 68.4%   "```" 16.3%   "The" 3.9%   "Here" 2.2%   "#include" 1.8%
" main"           " main" 99.7%   " printf" 0.1%   …
"(void"           "(void" 99.3%   "(){" 0.5%   …
" printf"         " printf" 78.4%   "\n" 16%   …
"Hello"           "Hello" 99.1%   "hello" 0.6%   …
" World"          " World" 97.5%   " world" 2.4%   …
"!\\"             "!\\" 98.5%   …
```

**Answer:** code is more "certain" because the training data is nearly unanimous, there are a
million `printf("Hello, World!\n")`s and one grammar. Prose about a person named Alex has no
such consensus. Same program, different training distribution; slide 2's pirate joke in numbers.

*Beat:* this is why coding agents feel competent on boilerplate and go sideways on your weird
internal API: the table is sharp where the internet agrees and flat where it doesn't.

## Task 5: Temperature

**Measured, `./logprobs_high_temp.bash` (TEMP=1.5), two runs:**

```
response:    fantastic leader who truly supports our professional growth.
"fant"            "great" 41.9%   "support" 19.2%   "very" 4.3%   "hard" 2.8%   "fant" 1.8%
"astic"           "astic" 100%   …
" truly"          " always" 45.6%   " inspires" 38.5%   " truly" 5.2%   …
" supports"       " values" 60.6%   " supports" 20.1%   …
```
```
response:    hard-working and supportive leader who always encourages professional growth.
"hard"            "great" 41.9%   "support" 19.2%   "very" 4.3%   "hard" 2.8%   "fant" 1.8%
"-working"        "working" 96.5%   "-working" 2.6%   …
```

**Answers:**
1. **The candidate list did not change: the pick did.** Row one is `41.9 / 19.2 / 4.3 / 2.8 / 1.8`
   in every run at every temperature. The model computed the same table; the sampler rolled
   differently. Temperature flattens the distribution the dice are thrown against; it does not
   touch what the model "knows". (The endpoint reports the raw distribution, which is what makes
   this visible.)
2. Rows where the pick isn't in the top five happen on most TEMP=1.5 runs past the first few
   tokens: the second run of the *first* validation produced `" motivated"` against a top-5 of
   `insightful / inspiring / dedicated / visionary / encouraging`. That's the potato from slide 8.
3. **`TEMP=3`** picked `"gener"` (not in the top five) for token one and produced 190+ tokens of
   increasingly unhinged prose: *"…without losing comper professionalism by using sarcsm
   appropriately…"*: including two mid-word derailments (`" com"`+`"per"` where `"posure"` was
   99.8%; `" sarc"`+`"sm"` where `"asm"` was 99.3%). It also sailed straight past a 99.6%
   `<|im_end|>`. At high temperature the sampler ignores near-certainties, and the text stops
   being language. `MAX=60` caps that run so the projector survives it.

*Beat:* "creative" in vendor UI is a slider on this number. Nothing more mystical.

Note the `fant`→`astic` and `hard`→`-working` rows: **sub-word tokens on output**, the Task 1
lesson coming back unprompted. Point it out if they don't.

## Task 6: Their sentence

No fixed answer. Make sure they keep the *"without annotation, just complete the sentence"* prefix:
`"Complete the sentence: The most common cause of a breach is"` produced a bold **human error**
followed by a `### Explanation:` section citing the Verizon DBIR, a chat-tuned model reverting to
type, and a nice aside in itself (the prompt is the only steering wheel), but not the table you want. Walk the room and ask two or three people to read their first row aloud. The
question to land: *whose opinion is in that table?* Answer: nobody's, it's the frequency of what
followed those words in the training text, and that is exactly as trustworthy as the average of
the internet on that topic.

---

## The close (slides 9–11)

Land three things, in this order:

1. **It's a regular computer program.** Same input, same output when you ask for it. Everything
   "random" is a number you can set. Everything "decided" is a row you can print.
2. **Anthropomorphism is the product.** "Thinks", "decides", "hallucinates", "wants", human
   words for a probability table, because human words are what sells. Sunflowers "want" sunlight.
3. **Why a SOC cares.** Every breach story that says "the AI decided to…" means *a sampler drew a
   token and a program executed it*. You can't audit a mind. You can absolutely log a request
   with `temperature`, `seed`, a prompt, and the tool call that came back. That is the rest of
   this course.

## Failure table

| Symptom | Cause | Fix |
|---|---|---|
| `curl: (7) Failed to connect to 127.0.0.1 port 9010` | Relay not running | Root: `systemctl restart workshop-llm-relay`, then `journalctl -u workshop-llm-relay -n 30` |
| `curl: (22) … 403` on every script | Upstream rejected the token, rotated but relay not restarted | Root: `start-llm-relay.sh restart` (re-copies the token from the repo file) |
| `curl: (22) … 403` with `path not allowed by the workshop relay` | Student hit a path outside the allowlist | Intended. `/api/generate`, `/api/embed`, `/api/tags` only |
| `curl: (22) … 502` `upstream unreachable` | Research endpoint down / no egress from the host | `curl -sI "$LLM_UPSTREAM_URL"` from root (URL from `gravwell-llm.env`); it's not a seat problem |
| `curl: (22) … 404` then `model 'x' not found` | `MODEL=` typo | `logbot` / `qwen3-embedding` (`curl -s $GRAVWELL_LLM_URL/api/tags` lists them) |
| `TEMP=1` runs come back identical | They passed `SEED=` too | Unset SEED; that's the lesson |
| `SEED=7` didn't change anything | Temperature is 0 | Correct, argmax has no dice. Make them say why |
| `logprobs.bash` output wraps badly | Narrow terminal | Widen, or `TOP=3` |
| Long stall on `TEMP=3` | It's generating 60 tokens of noise | Wait, or `MAX=30` |
| `--fail-with-body` unknown option | curl < 7.76 | Not on a current Debian/Ubuntu host; if self-hosting on an older one, replace with `-f` |

## Where students get stuck

- Reading `" leader"` with the leading space and asking why. The space is part of the token:
  most word tokens carry their preceding space. Good moment, don't skip it.
- Thinking the `%` column is the model's "confidence" in a *fact*. It isn't; it's the share of
  training text that continued this way. `great 41.9%` is not 41.9% sure Alex is great.
- Expecting `TEMP=1` to make the *table* change. Ask them to compare row one across runs.
- Trying `TEMP=0 SEED=…` and concluding the seed is broken.
