# Slides (Marp)

Decks are authored in **Marp** Markdown: version-controllable, diffable, and exportable to
**PDF / PPTX / HTML** so the venue still gets PowerPoint if needed. Re-authored from the original
68-slide `.pptx` content (not converted, conversion is lossy).

## One deck per module
Matches the AGENDA modules, so slides track the labs:

| Deck | Modules | Status |
|---|---|---|
| `00-intro.md` | M0 welcome/poll · M1 why AI auditing matters | 🟢 drafted |
| `01-fundamentals.md` | M2 under the hood (OpenAI API, tokens, tool calling) | 🟢 drafted |
| `01b-demystifying-ai.md` | M2b demystifying how AI "thinks" (tokens → vectors → prediction; seed, temperature, logprobs; anthropomorphism) | 🟢 drafted |
| `02-audit-gap.md` | M3 the audit gap | 🟢 drafted |
| `03-shadow-ai.md` | M4 shadow-AI from network logs | 🟢 drafted |
| `03b-shadow-ai-sources.md` | P9 shadow AI beyond the wire (padding; after M4) | 🟢 drafted |
| `03c-gravwell-tour.md` | M4b Gravwell tour: debrief of Lab 02, a high-level map of the platform's user-facing components (entries/tags/ingesters, Query Studio, library/templates/actionables/macros/ax, dashboards, resources/kits, scheduled searches/alerts/flows, playbooks/Data Explorer/Logbot+MCP), the live browser tour, Community Edition. Light by design; links the *Cadet Academy: Crafting a Query* video | 🟢 drafted |
| `04-sysmon.md` | M5 endpoint detection | 🟢 drafted |
| `05-opencode-proxy.md` | M7–M9 opencode + proxies | 🟢 drafted (bridge) |
| `05b-semantic-search.md` | P3 semantic search over LLM logs (padding; after M9 or M12). Embeddings recap, the two config halves, gotchas, a live-demo kick slide, and the measured results as backup slides | 🟢 drafted |
| `06-mcp.md` | M10 MCP deep dive | 🟢 drafted |
| `07-mcp-tool-interaction.md` | M11 MCP tool interaction across servers (Lab 07 Parts 1–2) | 🟢 drafted |
| `08-detections.md` | M12 detections from the ingester's data (Lab 07 Part 3) | 🟢 drafted (bridge), repointed at `tag=llm` |

## Build
No local install needed (uses `npx`):
```bash
make pdf      # build every deck to build/*.pdf
make pptx     # build every deck to build/*.pptx (for the venue)
make watch DECK=00-intro.md   # live preview while editing
make theme    # regenerate themes/jarvis.css after editing themes/gravwell/
```

## Theme: Gravwell 2026 look
`themes/jarvis.css` is **generated**: edit `themes/gravwell/jarvis.template.css` and run `make theme`
(`themes/gravwell/build-theme.py` inlines the background art as data URIs so pdf/pptx/html all render
identically). Ported from `Gravwell-Presentation-Template-2026.pptx`: the template's own master art
(logo baked in), gold titles `#FED36B`, white Arial body, blue rule `#708EC8`, orange corner brackets
`#ED561B`; Avenir → Montserrat (Google Fonts; needs network at build time, falls back to system sans).

Slide classes:

| class | look | use for |
|---|---|---|
| *(none)* | header band + arcs art, top-aligned content | normal slides |
| `lead` | purple→orange art, big uppercase gold title, centered | deck title, section breaks, lab intros |
| `statement` | diagonal purple→orange art, one big line | a single point / quote |

Swap art: drop new 16:9 JPGs over `themes/gravwell/bg-{title,content,statement}.jpg` and `make theme`.

## Conventions
- Front-matter sets `theme: jarvis` (see `themes/jarvis.css`), `paginate: true`.
- Slides separated by `---`. Presenter notes go in `<!-- HTML comments -->` (Marp presenter view).
- Use `<!-- _class: lead -->` for section-title slides.
- Reference checkpoint names exactly as in `../student-repo/checkpoints.yaml`.
- `build/` is git-ignored; commit only the source `.md` + theme.
