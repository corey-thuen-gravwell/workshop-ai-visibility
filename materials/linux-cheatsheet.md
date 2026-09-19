# Linux survival card

Everything in this course is typed into a terminal. If that is new, this is the whole of what you
need, with the course's own files as the examples. Nothing here is a lab answer: it is the typing,
not the thinking.

## Reading the prompt

```
workshop14@jarvis:~$
```

You are the user `workshop14`, on the machine `jarvis`, and you are currently in `~`. **`~` means
your home directory**, `/home/workshop14`. Everything you own lives under it. The `$` is where what
you type begins; never type the `$` itself.

## Where am I, and how do I move

| Command | What it does |
|---|---|
| `pwd` | print working directory: where you are right now |
| `cd ~/moneyprinter` | go to the `moneyprinter` directory **inside your home directory** |
| `cd ~/jarvis/labs/02-shadow-ai` | the same idea, three levels down |
| `cd ..` | up one level |
| `cd -` | back to wherever you just were. Useful when a lab bounces you between two directories |
| `cd` | home, from anywhere |

Paths that start with `~` or `/` work from anywhere. A path that starts with a name (`cd litellm`)
is **relative**: it only works if that thing is in the directory you are standing in. "No such file
or directory" usually means you are not where you think.

**Press Tab.** Type `cd ~/jarvis/labs/02-sh` and hit Tab; the shell finishes the name. Tab twice
lists the choices. This is the single biggest typing saver on this card.

## Looking at what is there

```bash
ls                      # names only
ls -l                   # one per line, with size and date
ls -la                  # ...including dotfiles, whose names start with a . and are normally hidden
ls ~/jarvis/labs        # list somewhere else without going there
```

`~/.workshop_env` and `~/.gravwell_token` are dotfiles: `ls` alone will not show them.

## Reading files without changing them

```bash
cat notes.md                    # dump the whole file
less proxy.jsonl                # page through it: space for next page, q to quit
head -20 ~/proxy.jsonl          # first 20 lines
tail -20 ~/proxy.jsonl          # last 20 lines
tail -f ~/proxy.jsonl           # keep watching as new lines arrive. Ctrl-C to stop
wc -l ~/proxy.jsonl             # how many lines
```

`less` is the safe way to open something large. If you find yourself stuck in it, the way out is
`q`.

## Editing a file

```bash
nano turn4.json
```

`nano` is the friendly editor. The keys you need are printed along the bottom, where `^` means
Ctrl:

- **Ctrl-O** then **Enter** saves.
- **Ctrl-X** exits.
- **Ctrl-K** cuts the current line, **Ctrl-U** pastes it back.

Arrow keys move; there are no modes to worry about.

## Copying, moving, deleting

```bash
cp conversation.json turn4.json     # copy. The original is untouched, which is why labs do this
mv old.json new.json                # rename or move
mkdir ~/scratch                     # make a directory
rm turn4.json                       # delete. There is no undo and no recycle bin
```

When a lab says "work on a copy", it is protecting you: if the copy gets into a state you cannot
fix, `cp conversation.json turn4.json` starts over.

## Searching inside files

```bash
grep chartreuse ~/lab01.out              # lines containing chartreuse
grep -i chartreuse ~/lab01.out           # ...ignoring upper/lower case
grep -c tools_offered ~/proxy.jsonl      # count matching lines instead of printing them
grep -r WORKSHOPUID ~/jarvis/labs        # search every file under a directory
```

## Joining commands together

```bash
cat ~/proxy.jsonl | wc -l           # send the output of one command into the next
jq . turn4.json > /dev/null         # send output to the bin: you only wanted to know if it parsed
opencode stats > ~/stats.txt        # write output to a file, replacing what was there
echo "one more line" >> AGENTS.md   # append to a file instead of replacing it
```

`|` is a pipe, `>` writes, `>>` adds. The course uses all three constantly.

## Environment variables

```bash
echo $WORKSHOPUID                   # your seat number, e.g. 14
echo $GRAVWELL_TOKEN                # your Gravwell API token, after Lab 00
. ~/.workshop_env                   # re-read the file that sets them
```

A variable is set **for one terminal**. Two things follow, and both bite people in this course: a
terminal you opened before something was set does not have it (fix it with `. ~/.workshop_env`),
and the ports you type are built out of your seat number, so `${WORKSHOPUID}443` on seat 14 is
`14443`. Type `${WORKSHOPUID}443` literally and the shell does the arithmetic for you.

## Running things

```bash
./make-token.sh                     # run a script in the directory you are standing in
~/jarvis/labs/02-shadow-ai/upload-resource.sh AI_DOMAINS datasets/resources/ai_domains.txt
```

The `./` is not decoration: without it the shell only looks in its list of system commands, and
answers `command not found` even though the file is right there.

## The docker commands you will type

Always from the directory holding the `docker-compose.yml`, which is why the labs say `cd` first.

```bash
cd ~/jarvis/labs/00-environment-gravwell
docker compose up -d                # start, in the background
docker compose ps                   # is it running?
docker logs 14gravwell              # what did that container print
docker compose down                 # stop it, keep the data
```

## Getting out of trouble

| What you see | What it means | What to do |
|---|---|---|
| `>` on a line by itself | You opened a quote or a bracket and never closed it, so the shell is still waiting | **Ctrl-C**, then retype the command |
| Nothing happens, no prompt | The command is still running, or it is waiting for input | **Ctrl-C** cancels. For something you meant to run, let it finish |
| `command not found` | Typo, or a script that needs `./` in front | Check the spelling, add `./` |
| `Permission denied` | Not yours to touch, or the file is not marked executable | `chmod +x thefile.sh`, or you are somewhere you should not be |
| `No such file or directory` | You are not in the directory you think you are | `pwd`, then `ls` |
| Stuck in a full-screen program | Probably `less` or `nano` | `q` for `less`, **Ctrl-X** for `nano` |

**Ctrl-C** stops the thing that is running. **Ctrl-D** ends your session, the same as typing
`exit`. Neither will break anything a checkpoint cannot restore.

## Typing less

- **Up arrow** walks back through what you have already run. Edit the line and press Enter.
- **Ctrl-R** then a few letters searches your history. Enter runs it.
- **Tab** completes file and directory names.

## Copy and paste

In most terminals **Ctrl-V does not paste**. Use **Ctrl-Shift-V**, or right-click, or Cmd-V on a
Mac. Work from the `.html` version of a handout rather than the PDF when you can: it has a copy
button on every command block, and copying out of a PDF inserts line breaks that silently break
what you paste.

## A second terminal

Some labs need two at once, one running a proxy and one driving it. Open a second window or tab and
SSH in again exactly as you did the first time. Both are the same machine and the same files; only
the environment variables are per-terminal.
