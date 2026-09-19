#!/usr/bin/env python3
"""Generate ../jarvis.css from jarvis.template.css by inlining the background images as data URIs.
Marp resolves url() in theme CSS unreliably across pdf/pptx/html export; data URIs always work.
Run after editing the template or swapping a background:  python3 build-theme.py"""
import base64, pathlib, re
here = pathlib.Path(__file__).parent
tpl = (here / "jarvis.template.css").read_text()
def inline(m):
    p = here / m.group(1); mime = "image/jpeg" if p.suffix == ".jpg" else "image/png"
    return f'url("data:{mime};base64,{base64.b64encode(p.read_bytes()).decode()}")'
css = re.sub(r'url\("@asset/([^"]+)"\)', inline, tpl)
(here.parent / "jarvis.css").write_text(css)
print(f"wrote {here.parent/'jarvis.css'} ({len(css)//1024} KB)")
