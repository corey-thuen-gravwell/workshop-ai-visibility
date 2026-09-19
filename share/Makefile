# Build every student-facing PDF into share/build/.
#
# Runs on the AUTHORING box (needs node + chromium); the lab host has neither on purpose.
# Ship the result with instructor/runbook/scripts/deploy-share.sh.
#
#   make            handouts + slides
#   make handouts   just the lab/materials PDFs
#   make slides     just the decks
#   make clean
OUT = build

all: handouts slides

handouts:
	@./build-handouts.sh

slides:
	@$(MAKE) -C ../slides pdf
	@mkdir -p $(OUT)/slides
	@cp ../slides/build/*.pdf $(OUT)/slides/
	@echo "==> Slides -> $(OUT)/slides ($$(ls $(OUT)/slides/*.pdf | wc -l) decks)"

list: ; @find $(OUT) -name '*.pdf' | sed "s|$(OUT)/||" | sort
clean: ; rm -rf $(OUT)
.PHONY: all handouts slides list clean
