#!/bin/bash
# Render the student-facing markdown into PDFs styled like the Marp decks.
#
#   markdown --(npx marked)--> HTML + share/handout.css --(chromium --print-to-pdf)--> PDF
#
# Runs on the AUTHORING box, not the lab host: it needs node and chromium, and the lab host
# deliberately has neither. Ship the results with instructor/runbook/scripts/deploy-share.sh.
#
#   ./build-handouts.sh              # everything
#   ./build-handouts.sh labs/02-shadow-ai/README.md
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
OUT="$HERE/build"
COURSE="Exploring AI Visibility"

CHROME="${CHROME:-$(command -v chromium || command -v chromium-browser || command -v google-chrome-stable || true)}"
[ -n "$CHROME" ] || { echo "no chromium found: set CHROME=/path/to/chrome" >&2; exit 1; }
command -v npx >/dev/null || { echo "npx required (markdown -> html)" >&2; exit 1; }

# What ships, and what it is called. Anything not listed here is not published, in particular
# nothing from instructor/, which is the answer key.
#   <source>|<output subdir>/<name>.pdf|<title>|<subtitle>
#
# WALKTHROUGH_MANIFEST is the instructor step-by-step, answers included. It is built into its own
# walkthroughs/ tree, styled differently, and share.sh will not release it with --all. It exists so
# an instructor can hand the full thing to an attendee who is genuinely stuck.
MANIFEST="
labs/01-fundamentals/README.md|labs/01-fundamentals|Lab 01: Under the hood of LLM tooling|Module M2 · mini-lab
labs/01b-demystifying-ai/README.md|labs/01b-demystifying-ai|Lab 01b: Demystifying how AI thinks|Module M2b
labs/00-environment-gravwell/README.md|labs/00-environment|Lab 00: Environment & Gravwell|Lab A
labs/02-shadow-ai/README.md|labs/02-shadow-ai|Lab 02: Shadow AI from network logs|Module M4
labs/03-endpoint-sysmon/README.md|labs/03-endpoint-sysmon|Lab 03: Endpoint detection with Sysmon|Module M5
labs/04-opencode-config/README.md|labs/04-opencode-config|Lab 04: The AI user & opencode config|Module M7
labs/05-llm-proxy/README.md|labs/05-llm-proxy|Lab 05: LLM proxies|Modules M8 & M9
labs/06-mcp-deep-dive/README.md|labs/06-mcp-deep-dive|Lab 06: MCP deep dive|Module M10
labs/07-mcp-tool-interaction/README.md|labs/07-mcp-tool-interaction|Lab 07: MCP tool interaction across servers|Modules M11 & M12
labs/_stretch/ai-assistant-audit/README.md|labs/p8-ai-assistant-audit|Audit an AI assistant from its own logs|Padding module P8
labs/_stretch/shadow-ai-sources/README.md|labs/p9-shadow-ai-sources|Shadow AI beyond the wire|Padding module P9
labs/_stretch/extend-the-proxy/README.md|labs/p2-extend-the-proxy|Vibe-code your own proxy|Padding module P2
labs/_stretch/second-client/README.md|labs/p4-second-client|A second client through the same proxy|Padding module P4
labs/_stretch/semantic-search/README.md|labs/p3-semantic-search|Semantic search over LLM logs|Padding module P3
materials/linux-cheatsheet.md|materials/linux-cheatsheet|Linux survival card|Hand out on day 1 to anyone new to the terminal
materials/terminal-cheatsheet.md|materials/terminal-cheatsheet|Terminal & Query Cheatsheet|Every command, written out
materials/questions-for-the-ciso.md|materials/questions-for-the-ciso|Questions for the CISO|Take-home one-pager
materials/ai-audit-checklist.md|materials/ai-audit-checklist|AI Audit Checklist|Take-home one-pager
materials/shadow-ai-detection-matrix.md|materials/shadow-ai-detection-matrix|Shadow AI Detection Matrix|Take-home one-pager
materials/self-study-guide.md|materials/self-study-guide|Working through this course on your own|Take-home guide
materials/attendee-prerequisites.md|materials/attendee-prerequisites|Before you arrive: what your laptop needs|Send with the abstract, weeks ahead
"

WALKTHROUGH_MANIFEST="
instructor/walkthroughs/00-environment-gravwell.md|walkthroughs/00-environment|Lab 00: Environment & Gravwell|Complete walkthrough
instructor/walkthroughs/01-fundamentals.md|walkthroughs/01-fundamentals|Lab 01: Under the hood of LLM tooling|Complete walkthrough
instructor/walkthroughs/01b-demystifying-ai.md|walkthroughs/01b-demystifying-ai|Lab 01b: Demystifying how AI thinks|Complete walkthrough
instructor/walkthroughs/02-shadow-ai.md|walkthroughs/02-shadow-ai|Lab 02: Shadow AI from network logs|Complete walkthrough
instructor/walkthroughs/03-endpoint-sysmon.md|walkthroughs/03-endpoint-sysmon|Lab 03: Endpoint detection with Sysmon|Complete walkthrough
instructor/walkthroughs/04-opencode-config.md|walkthroughs/04-opencode-config|Lab 04: The AI user & opencode config|Complete walkthrough
instructor/walkthroughs/05-llm-proxy.md|walkthroughs/05-llm-proxy|Lab 05: LLM proxies|Complete walkthrough
instructor/walkthroughs/06-mcp-deep-dive.md|walkthroughs/06-mcp-deep-dive|Lab 06: MCP deep dive|Complete walkthrough
instructor/walkthroughs/07-mcp-tool-interaction.md|walkthroughs/07-mcp-tool-interaction|Lab 07: MCP tool interaction across servers|Complete walkthrough
instructor/walkthroughs/_stretch-ai-assistant-audit.md|walkthroughs/p8-ai-assistant-audit|Audit an AI assistant from its own logs|Complete walkthrough
instructor/walkthroughs/_stretch-extend-the-proxy.md|walkthroughs/p2-extend-the-proxy|Vibe-code your own proxy|Complete walkthrough
instructor/walkthroughs/_stretch-second-client.md|walkthroughs/p4-second-client|A second client through the same proxy|Complete walkthrough
instructor/walkthroughs/_stretch-semantic-search.md|walkthroughs/p3-semantic-search|Semantic search over LLM logs|Complete walkthrough
instructor/walkthroughs/_stretch-shadow-ai-sources.md|walkthroughs/p9-shadow-ai-sources|Shadow AI beyond the wire|Complete walkthrough
"

# Code blocks are printed with `white-space: pre` (no soft wrap, see handout.css), so a line
# wider than the page is silently clipped. Refuse to build rather than ship a truncated command.
# 100 leaves a margin under the measured 106 chars at 7.5pt DejaVu Sans Mono on A4.
MAX_CODE_WIDTH="${MAX_CODE_WIDTH:-100}"
lint_code_width() {
    local manifest="$1" src rest
    python3 - "$REPO" "$MAX_CODE_WIDTH" $(printf '%s\n' "$manifest" | cut -d'|' -f1 | grep -v '^$') <<'PY'
import sys
repo, maxw, *files = sys.argv[1:]; maxw = int(maxw); bad = 0
for f in files:
    fence = False
    for n, line in enumerate(open(f"{repo}/{f}", encoding="utf-8"), 1):
        if line.startswith("```"): fence = not fence; continue
        w = len(line.rstrip("\n"))
        if fence and w > maxw:
            print(f"  {f}:{n}: {w} chars (max {maxw}), a PDF viewer would wrap this mid-command"); bad += 1
sys.exit(1 if bad else 0)
PY
}

render() {
    local src="$1" dest="$2" title="$3" sub="$4" kind="${5:-handout}"
    local abs="$REPO/$src" html out
    [ -f "$abs" ] || { echo "  MISSING $src" >&2; return 1; }
    out="$OUT/$dest.pdf"; mkdir -p "$(dirname "$out")"
    html="$(mktemp --suffix=.html)"
    web="$OUT/$dest.html"        # the same document for the browser, with Copy buttons on code

    # Drop the leading "# Title" line (the title block replaces it). The old "**Module ...** Status:"
    # line no longer exists in handouts; the regexes
    # stay so a stray one can never reach a student.
    # and the status line is authoring metadata students don't need.
    python3 - "$abs" "$HERE/handout.css" "$title" "$sub" "$COURSE" "$kind" "$web" > "$html" <<'PY'
import html as H, subprocess, sys, re
src, css_path, title, sub, course, kind, web_out = sys.argv[1:8]
md = open(src, encoding="utf-8").read()
md = re.sub(r'\A#\s+.*?\n', '', md)                       # leading H1
md = re.sub(r'\A\*\*Module[^\n]*\n', '', md)              # authoring status line
md = re.sub(r'^\*\*Modules?[^\n]*Status:[^\n]*\n', '', md, flags=re.M)
body = subprocess.run(["npx","--yes","marked","--gfm"], input=md, text=True,
                      capture_output=True, check=True).stdout
css = open(css_path, encoding="utf-8").read()
cls = "titleblock walkthrough" if kind == "walkthrough" else "titleblock"
banner = ""
if kind == "walkthrough":
    banner = ("<div class='answerbanner'><strong>This is the complete walkthrough.</strong> "
              "Every command, every expected result, and the answer to every task. It is written "
              "for whoever is teaching, so it also contains notes about how the lab is meant to "
              "land. If you are working through the lab yourself, the handout is the one you want "
              "&mdash; this is the safety net.</div>")
doc = f"""<div class="{cls}"><p class="course">{H.escape(course)}</p>
<h1>{H.escape(title)}</h1><p class="sub">{H.escape(sub)}</p></div>
{banner}
{body}
<div class="footer"><span>{H.escape(course)}</span><span>{H.escape(title)}</span></div>"""
head = f'<!doctype html><html lang="en"><head><meta charset="utf-8"><title>{H.escape(title)}</title>'
# 1) print source: no scripts, no viewport, chromium prints exactly this
print(f"{head}<style>{css}</style></head><body>{doc}</body></html>")
# 2) web twin: same document + a Copy button on every code block. Copying from the PDF is what
#    breaks pasted commands (viewers insert a newline at every visual line), so the browser copy
#    of the exact source text is the path students should use during the labs.
COPY_JS = r"""
document.querySelectorAll('pre').forEach(function (pre) {
  var wrap = document.createElement('div'); wrap.className = 'codeblock';
  pre.parentNode.insertBefore(wrap, pre); wrap.appendChild(pre);
  var b = document.createElement('button'); b.type = 'button'; b.className = 'copy';
  b.textContent = 'Copy'; b.title = 'Copy this block exactly as written';
  b.addEventListener('click', function () {
    var text = pre.innerText.replace(/\s+$/, '') + '\n';
    var done = function (ok) {
      b.textContent = ok ? 'Copied' : 'Select + Ctrl-C'; b.classList.toggle('ok', ok);
      setTimeout(function () { b.textContent = 'Copy'; b.classList.remove('ok'); }, 1600);
    };
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(function () { done(true); }, function () { done(false); });
    } else {
      var ta = document.createElement('textarea'); ta.value = text; ta.style.position = 'fixed';
      ta.style.opacity = '0'; document.body.appendChild(ta); ta.select();
      var ok = false; try { ok = document.execCommand('copy'); } catch (e) {}
      document.body.removeChild(ta); done(ok);
    }
  });
  wrap.appendChild(b);
});
"""
webbar = ('<div class="webbar">Use the <strong>Copy</strong> button on each code block, it copies the '
          'command exactly as written, ready to paste into your terminal or the Gravwell query bar.</div>')
open(web_out, "w", encoding="utf-8").write(
    f'{head}<meta name="viewport" content="width=device-width, initial-scale=1">'
    f'<meta name="robots" content="noindex, nofollow"><style>{css}</style></head>'
    f'<body class="web">{webbar}{doc}<script>{COPY_JS}</script></body></html>')
PY

    "$CHROME" --headless --disable-gpu --no-sandbox --no-pdf-header-footer \
        --print-to-pdf="$out" "file://$html" >/dev/null 2>&1
    rm -f "$html"
    [ -s "$out" ] && [ -s "$web" ] || { echo "  FAILED $src" >&2; return 1; }
    printf '  %-46s %s  + .html\n' "$dest.pdf" "$(du -h "$out" | cut -f1)"
}

mkdir -p "$OUT"
ok=0; bad=0
build_manifest() {
    local kind="$1" manifest="$2"
    while IFS='|' read -r src dest title sub; do
        [ -z "${src:-}" ] && continue
        if [ $# -gt 2 ]; then :; fi
        if [ "${#ONLY[@]}" -gt 0 ]; then
            case " ${ONLY[*]} " in *" $src "*) ;; *) continue;; esac
        fi
        if render "$src" "$dest" "$title" "$sub" "$kind"; then ok=$((ok+1)); else bad=$((bad+1)); fi
    done <<< "$manifest"
}

ONLY=("$@")
echo "==> Checking code-block width (<= $MAX_CODE_WIDTH chars; wider lines wrap on copy-paste from the PDF)"
lint_code_width "$MANIFEST$WALKTHROUGH_MANIFEST" || { echo "    fix the lines above (break shell with ' \\', JSON after a comma, queries before '|')" >&2; exit 1; }
echo "==> Handouts -> $OUT"
build_manifest handout "$MANIFEST"
echo "==> Walkthroughs (answers included; share.sh will not release these with --all)"
build_manifest walkthrough "$WALKTHROUGH_MANIFEST"
echo "    $ok rendered, $bad failed"
[ "$bad" -eq 0 ]
