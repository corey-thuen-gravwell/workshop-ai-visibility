# Share: student-facing documents and the site that serves them

Slides, lab handouts and take-home one-pagers published over HTTPS, so instructors hand out
**URLs** instead of email attachments or paper.

**Every document is built twice.** `NAME.html` is the rendered page students work from during a
lab: same look, a **Copy** button on every code block that copies the command exactly as written.
`NAME.pdf` is the take-home. The split exists because copying out of a PDF inserts a newline at
every visual line: a multi-line `curl` or a JSON body pasted from a PDF fails, and no amount of
layout fixes that reliably. Release the `.html` when a lab starts; release the PDFs at the end.

## The two directories

```
/opt/workshop/share/
├── staged/   everything built and shipped, NOT served, unreachable from the web
└── live/     what students can download: this is the web root
```

Material is released **as the course reaches it**. Nothing is live until an instructor puts it
there, and `staged/` is not mounted into the server, so an unreleased handout returns 404 rather
than being merely unlisted.

### Walkthroughs are a fourth category, held back on purpose

`walkthroughs/` carries the complete instructor step-by-step, every command, every expected
result, the answer to every task. It exists so an instructor can hand the whole thing to someone
who is genuinely stuck rather than watch them drown.

Because of that, **`share publish --all` deliberately skips it.** "Release everything" is something
you do at the end of a day, and it should never quietly hand over the answer keys. Releasing a
walkthrough takes an explicit `--walkthroughs`, or naming the file. `share status` prints a warning
while any walkthrough is live.

They also *look* different: brown-and-orange title block instead of gold, and a banner on page one
saying what they are, so nobody confuses one with the lab handout they were supposed to work
through.

## Building (authoring box)

Needs `node`/`npx` and `chromium`. The lab host has neither, deliberately: it is a lab host, not
a build box.

```bash
make -C share all          # every handout as .pdf + .html, plus the decks, into share/build/
make -C share handouts     # just the labs + materials
make -C share slides       # just the decks
```

Handouts render `markdown → npx marked → handout.css → chromium --print-to-pdf`. Decks use the
existing Marp build unchanged.

**`handout.css` is the deck theme adapted for reading**: same Montserrat display face, same
gold/blue/orange accents, same orange list markers and blue-ruled code blocks, but a light body,
because a 200-line handout on dark purple is miserable to read and worse to print. The dark title
block keeps it recognisably part of the same family.

To add a document, add one line to the `MANIFEST` in `build-handouts.sh`. Anything not in that
manifest is not published: in particular nothing from `instructor/`, which is the answer key.

## Shipping and releasing

```bash
./instructor/runbook/scripts/deploy-share.sh        # authoring box -> host staged/
```

Then on the host, as the class progresses:

```bash
share status                  # what is live, what is still staged
share publish 02-shadow-ai    # release one document, .html and .pdf (substring; ambiguity is reported)
share publish 02-shadow-ai html   # just the web page: do this as the lab starts
share publish --labs          # or --slides, --materials; add "html" or "pdf" to pick a format
share publish --all           # everything EXCEPT walkthroughs
share publish --all pdf       # end of day: the take-home PDFs
share publish --walkthroughs  # the answers: deliberate, never swept in by --all
share unpublish 02-shadow-ai
share url                     # the URL and username to read out
```

## The server

`server/docker-compose.yml` runs stock `nginx:alpine` with everything supplied as bind mounts, so
it is portable: point `SHARE_ROOT` and `WORKSHOP_CERT_DIR` elsewhere and it runs anywhere docker
does. Started by `instructor/runbook/scripts/start-share-server.sh`, which also writes `.htpasswd`.

- **HTTPS on 443** with the same Let's Encrypt cert the Gravwell UI uses, so no browser warning
  and no port number to read aloud. Port 80 redirects.
- **Basic auth**, because this is on the public internet and the point is keeping crawlers and
  drive-by bots off the material. It is not a secrecy measure: treat the password as public the
  moment you say it in a room.
- **nginx `autoindex`** rather than a generated index page: a file is listed the instant it is
  copied into `live/`, there is nothing to regenerate, and there is no page probing the filesystem.
- `robots.txt` disallows everything, and `X-Robots-Tag: noindex` is set on every response.

Credentials live in `/opt/workshop/.env` as `SHARE_USER` / `SHARE_PASSWORD`.
