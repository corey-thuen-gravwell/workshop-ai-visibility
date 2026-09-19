# Take-home materials

One-pagers handed to attendees **as materials**, alongside the slides, *not* shipped in the student
lab repo (`build-student-repo.sh` allowlists lab content only). One of them, the prerequisites, is
not take-home at all: it goes out **weeks before** the course, with the abstract.

| File | Used by | What it is |
|---|---|---|
| `questions-for-the-ciso.md` | **M6** (mid-course re-center) and take-home | Ten escalating questions an attendee takes back to their leadership. M6 is built around this |
| `ai-audit-checklist.md` | **M13** (wrap & next steps) and take-home | What to collect, in four tiers, plus the first detections to build and the architecture principles |
| `shadow-ai-detection-matrix.md` | **P9 debrief** (or M4 / M13) and take-home | Twenty shadow-AI indicators → technique → log source required → what each catches and is blind to → where the course proves it; six combining strategies; a four-tier collection plan |
| `linux-cheatsheet.md` | **At the start, to anyone who wants it** | The terminal itself, for people who have never used one: the prompt and what `~` means, moving around, reading files, `nano`'s three keys, pipes and redirection, why `./` is needed, the docker commands they will type, how to get out of a `>` prompt, and Tab completion. Every example is a real path or file from this course (`cd ~/moneyprinter`, `cp conversation.json turn4.json`, `. ~/.workshop_env`). It contains no lab answers, so unlike the terminal cheatsheet it can go out to everybody without a second thought |
| `terminal-cheatsheet.md` | **On request, during labs** | Every command and query in the course written out verbatim, in course order, plus a Gravwell query-language mini-reference and a symptom table. Give it to attendees who are struggling with the terminal rather than the concepts: it removes the typing, not the thinking, and reveals no lab answers. **Do not hand out by default**; the handouts are deliberately lighter than this. It carries no instructor-facing note of its own, so it is safe to hand over as-is |
| `attendee-prerequisites.md` | **Pre-event**, sent with the abstract | What an attendee's laptop needs to reach the lab host, and a paragraph they can forward to their security team to get the exception filed. Ports, the host's IP, and self-tests that prove each path works before they travel. It exists because attendees have arrived unable to open the slides, and an exception takes days |
| `self-study-guide.md` | **Take-home, and the published repo** | How to work through the whole course alone: what to install, how to license and stand up Gravwell on your own box, regenerating the data, a route through the modules with hour estimates, per-lab notes on what differs solo (Ollama for Lab 01b, and so on). Also the front door for anyone who finds this repo later |

## Producing them

All are Markdown so they stay editable. For handout, render to PDF however you render the decks,
e.g. `npx --yes @marp-team/marp-cli@latest --no-stdin --pdf materials/<file>.md`, or paste into the
Gravwell template if you want them visually matched to the slides.

Keep the take-home one-pagers to **one page each**. They are reference cards, not documents; the
moment they grow a second page they stop being used.

The two terminal references are the deliberate exception: `linux-cheatsheet.md` (4 pages) and
`terminal-cheatsheet.md` (much longer) are lookup tables, read a line at a time while somebody is
stuck, not documents anybody reads front to back. Length there costs nothing; a missing command
costs a lab.
