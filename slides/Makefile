# Build Marp decks. Requires no local install: uses npx (needs Chromium for pdf/pptx/png).
# Usage: make pdf | make pptx | make html   (builds every NN-*.md deck in this dir into build/)
#        make theme                          (regenerate themes/jarvis.css from themes/gravwell/)
#        make watch DECK=00-intro.md         (live preview)
MARP  = npx --yes @marp-team/marp-cli@latest --no-stdin --allow-local-files
THEME = themes/jarvis.css
DECKS = $(wildcard [0-9]*.md)
OUTDIR = build

pdf:  $(THEME); @mkdir -p $(OUTDIR); for d in $(DECKS); do $(MARP) --theme $(THEME) --pdf $$d -o $(OUTDIR)/$${d%.md}.pdf; done
pptx: $(THEME); @mkdir -p $(OUTDIR); for d in $(DECKS); do $(MARP) --theme $(THEME) --pptx $$d -o $(OUTDIR)/$${d%.md}.pptx; done
html: $(THEME); @mkdir -p $(OUTDIR); for d in $(DECKS); do $(MARP) --theme $(THEME) --html $$d -o $(OUTDIR)/$${d%.md}.html; done
watch: $(THEME); $(MARP) --theme $(THEME) -p -w $(DECK)
theme $(THEME): themes/gravwell/jarvis.template.css themes/gravwell/*.jpg
	python3 themes/gravwell/build-theme.py
clean: ; rm -rf $(OUTDIR)
.PHONY: pdf pptx html watch theme clean
