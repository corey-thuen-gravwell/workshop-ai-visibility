# Lab 01b: Demystifying how AI "thinks" (mini-lab)

## Objective
Take the magic out of the box. In seven short scripts you will watch a language model turn text
into tokens, tokens into vectors, and vectors into a **probability table**, then watch it "pick"
from that table, prove the picking is deterministic when you tell it to be, and turn the knob that
makes it "creative". None of this is a metaphor. It is what the program does.

## Background
An LLM is a text predictor. Given the text so far, it produces a list of every possible next token
with a probability, and a **sampler** picks one. Then it does it again. There is no plan, no
intent, no "thinking": a distribution and a pick, repeated. Three things you can control from the
outside decide what you get:

- **The seed**: the random number the sampler uses. Same input + same seed = same output.
- **The temperature**: how far the sampler is willing to stray from the most likely token.
  `0` means "always the top one".
- **The prompt**: everything else. The distribution is a function of the input and nothing else.

Every knob is visible in the request, because it's HTTP and JSON, same as Lab 01.

## Setup
No Gravwell. The scripts talk to a model **Gravwell hosts for this class**, through a small relay
on this machine at `http://127.0.0.1:9010` that adds the credential on the way out. You never see a
token and never need one:

```bash
cd ~/jarvis/labs/01b-demystifying-ai
echo $GRAVWELL_LLM_URL        # http://127.0.0.1:9010, if empty:  . ~/.workshop_env
curl -s $GRAVWELL_LLM_URL/api/tags | jq '.models[].name'     # the models behind the relay
ls                    # seven scripts. Read them: cat any one. Nothing in them is hidden.
```

Every script is ten to twenty lines of `curl` + `jq`. **`cat` each one before you run it.** Each
one prints the **request it is about to send**, the exact JSON that goes to the model, before the
response, so you can see every knob (model, prompt, `temperature`, `seed`, `logprobs`) on the wire.
(That goes to stderr, so piping a script into `jq` still works.)

## Tasks

### Task 1: What's in a token?
```bash
./tokens.bash
```
Four strings. For each one you see the exact `curl` that was sent and the model's **entire
response, unedited JSON**. Read one response top to bottom: this is what every AI call looks
like on the wire. Find `prompt_eval_count`: that is how many tokens the tokenizer made of your
text. (`response` is the single token we asked it to generate; `eval_count` counts those.)

Now feed it your own:
```bash
./tokens.bash "I am a potato!" "supercalifragilisticexpialidocious" "rm -rf /"
```
Is a token a word? A character? What is it? *(The later scripts pull one field out of a response
like this for you: now you know what they are hiding.)*

### Task 2: What's an embedding?
```bash
./embed.bash "potato" | jq '.embeddings[0] | length'
./embed.bash "potato" | jq '.embeddings[0][:8]'
```
That's "potato": a list of numbers. How many? Now compare a few:
```bash
./similar.bash
```
Read the matrix and the "nearest to" lines. **Which word is nearest to `Idaho`?** To `throne`? Try
your own set, `./similar.bash cat dog kitten firewall`, and predict the pairs before you look.

### Task 3: Isn't it non-deterministic?
The script asks the model for its honest opinion of pineapple on pizza. **Run it three times** and compare
the sentences:
```bash
./random.bash
```
Same sentence every time? Now let it sample. **Run this twice:**
```bash
TEMP=1 ./random.bash
```
Different. Now sample **with a fixed random number**, again **twice**:
```bash
TEMP=1 SEED=42 ./random.bash
```
Same again. `cat random.bash`. Where does the "randomness" come from, and who supplies it?

### Task 4: Isn't it thinking about what to say?
```bash
./logprobs.bash
```
Left column: the token it produced. Right: the five candidates it was choosing between, with
probabilities. Read the first row out loud. **What was the runner-up, and what were its odds?**
Then:
```bash
./logprobs_code.bash
```
Same picker, different training data. Compare the probabilities in the two tables. Why is code
so much more "certain" than prose?

### Task 5: Doesn't it always take the most likely token?
```bash
./logprobs_high_temp.bash
```
**Run it repeatedly** until the first token is **not** the top candidate. Then answer:
1. Did the candidate list (right column) change between runs? Did the pick (left column)?
2. Find a row where the picked token isn't in the top five at all.
3. Now `TEMP=3 ./logprobs_high_temp.bash`. Describe what happens to the sentence.

### Task 6: Your turn
Pick a sentence-opener from your own world: *"The most common cause of a breach is"*, *"Our
CISO's first priority should be"*, and run it through
`./logprobs.bash "Complete the sentence without annotation, just complete the sentence: …"`.
(Leave out the "without annotation" and watch it write you an essay with headings instead.)
Whose opinion is in that table?

## Checkpoint
The scripts are the only files in this lab. If you've edited one into a corner, restore just this
lab's files, nothing else is touched:
```bash
cd ~/jarvis && git checkout stage-demystify -- labs/01b-demystifying-ai
```

## Discussion
- The table on your screen in Task 4 is the whole "decision". There is no second process that
  weighs it, no intent behind it. What does that do to a sentence like *"the AI decided to delete
  the database"*? (Hold that until Lab 04 and Lab 07.)
- Temperature and seed are **request parameters**: set by the client, visible on the wire. If you
  were logging AI traffic, would you want them? What would a temperature of `2` in production tell
  you about the tool that sent it?
- Everything you did here was against a model your own organization hosts. Same API shape as the
  vendor's. Which one would you rather have to audit, and why?
- You never held a credential for that model. Something on `127.0.0.1:9010` did, and it decided
  which paths you could reach. Remember that shape: you'll build it yourself in Lab 05.
