---
marp: true
theme: jarvis
paginate: true
header: 'Exploring AI Visibility · Demystifying how AI thinks'
---

<!-- _class: lead -->
# &#*$ your stupid token predictor
## Or, LLMs are magic and AGI is here today

<!--
Runs after M2: they've seen the API is stateless HTTP; now open the box on the other end. Lab: labs/01b-demystifying-ai, seven scripts against the Gravwell-hosted model. The three "Demo!" slides map to random.bash, logprobs.bash, logprobs_high_temp.bash.
-->

---

## What's in an LLM

- Just a **text predictor**
- "Samples" probable next tokens
- "Picks" a next token via a **(tunable!)** probability function
- "Probable" is based on **training**

If all your training data is pirate speak…

> *Ayy matey the response will be naught but "arrr" and "avast," ye scurvy transformer! Every token a doubloon plundered from the same salty sea, and nary a landlubber's word to be found in yer vocabulary. Yarrr.*

<!-- Four claims. The lab proves each one on their own terminal. The pirate joke comes back in Task 4: code prompts are "certain" because the training data is unanimous. -->

---

## What's in a token?

Text is **tokenized**:

```
"I am a potato!"   →   I  |  am  |  a  |  pot  |  ato!
```

Not a word. Not a character. Whatever the tokenizer learned was a frequent chunk.

Tokens become **embeddings** →

<!-- Lab Task 1: ./tokens.bash, "I am a potato!" really is 5 tokens on the workshop model. "unbelievable" is 3; "supercalifragilisticexpialidocious" is 11. -->

---

## What's an embedding?

- Just a **big vector**: `"potato"` → `[0.0116, 0.0175, 0.0087, -0.0068, …]` × 4096
- Vectors that are **close** to each other (high-school geometry!) are "similar"
- Vector distance ≈ **semantic similarity**

| | |
|---|---|
| **king** is similar to | queen (0.907) |
| **potato** is similar to | Idaho (0.557), and fries (0.737) |
| **firewall** is similar to | syslog (0.639) |

<!-- Numbers measured with ./similar.bash (Task 2). The comparison is cosine similarity in eleven lines of Python, no model involved in the "similar" step. This is also the whole idea behind a vector database, RAG, and the P3 semantic-search padding module. -->

---

## Predicting text

Combine:
- **Semantic embeddings**
- **Training** on human-generated text
- **Novel prediction algorithms**
  - used to be Markov chains (Mark V Shaney)
  - then neural nets (Hey Siri!)
  - now transformers ("AI")

…and you get a text predictor.

```
"My liege is a"   →   ℙ(X ∈ [ king, queen, usurper, … ])
```

<!-- Mark V Shaney: the 1980s Usenet bot that posted Markov-chain gibberish and got taken seriously. The lineage matters: every step is "better distribution over the next token", not a change of kind. -->

---

## But isn't it non-deterministic? Stochastic?

# No.

- For a given input, you **always get the same output**
- Your input is submitted to the program **with a random number**
- "Seed" the input to give the **illusion** of non-determinism

**Demo!** `./random.bash` · `TEMP=1 ./random.bash` · `TEMP=1 SEED=42 ./random.bash`

<!-- Task 3. The prompt asks for an honest opinion of pineapple on pizza. Temperature 0: the same sentence, identical three times. TEMP=1, no seed: different every run. TEMP=1 SEED=42: the same sentence twice. The randomness is a number, and the client supplies it. -->

---

## Isn't it "thinking" about how to respond?

# No.

- For a given input, the program **samples** the probable next token
- `"My liege is a…"` → distribution includes `[king, queen, usurper]`
- **Pick one.**
- *How* the program picks is important, **and controllable**

**Demo!** `./logprobs.bash` · `./logprobs_code.bash`

<!-- Task 4. Row one: great 41.9% / support 19.2% / very 4.3% / hard 2.8% / fant 1.8%. "great" wasn't a judgement, it was the biggest slice of a pie that was 58% not-great. Code prompt: main 99.7%, Hello 99.1%, unanimous training data gives a sharp table. -->

---

## But doesn't it always take the most predictable token?

# No.

- For a given sample, **temperature** changes *how we pick*
- `"My liege is a…"` → `[king, queen, usurper, potato]`
- *Potato* isn't a likely next token…
- …but a **high temperature** gives potato a better chance of being chosen
- In LLM-speak we say the model is being more **"creative"**

**Demo!** `./logprobs_high_temp.bash` (×3) · `TEMP=3 ./logprobs_high_temp.bash`

<!-- Task 5. The candidate list NEVER changes between runs, only the pick. At 1.5 it chose "fant" (1.8%) then "astic"; at 3 it picked a token outside the top five, ignored a 99.6% stop token, and wrote 190 tokens of noise. "Creative" is a slider on this number. -->

---

<!-- _class: statement -->
# Wait: it's just a regular computer program?!

<!-- Yes. And it's wild that we've chosen to ignore this. Same input + same seed = same output. Everything "random" is a number you can set. Everything "decided" is a row you can print. -->

---

## The real magic of LLMs

# Marketing!

More specifically: **anthropomorphism** as a marketing tool.

- Usually: using "human" words to describe non-human things
- Also human traits, human mental states, …
- Sunflowers "behave" like they "want" sunlight: *want* is the human trait we apply
- LLMs are no exception: it "thinks", it "decides", it "hallucinates"

**AGI TODAY!**

<!-- Every word in quotes on this slide names a probability table and a dice roll. The lab just printed both. -->

---

## The real magic of LLMs

Anthropomorphizing LLMs is a **cognitive shortcut**, and it carries every downstream effect of giving human traits to a non-human thing:

- **Trust**
- **Valuing its opinion**
- **Falling in love**
- …
- Most importantly: it convinces **VC money** to fly out of bank accounts and into datacenters

<!--
Bridge to the rest of the course: "the AI decided to delete the database" = a sampler drew a token and a program executed it. You can't audit a mind. You can log a request: temperature, seed, prompt, and the tool call that came back. That's M3 onward.
-->

---

<!-- _class: lead -->
# Lab 01b
## Tokens, embeddings, seeds, and the table behind every "decision"

<span class="muted">`git checkout stage-demystify -- labs/01b-demystifying-ai`</span>

<!-- To the terminal. Seven scripts against a model we host: they never hold a credential, the relay on 127.0.0.1:9010 does. The three Demo! slides above are Tasks 3-5; Task 6 is theirs to poke at. -->
