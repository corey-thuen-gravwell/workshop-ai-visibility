#!/usr/bin/env python3
"""Which share-site document belongs to which student-repo stage.

Joins the two manifests: student-repo/checkpoints.yaml (stage -> paths it adds) and the MANIFEST
in share/build-handouts.sh (source markdown -> published name). Prints one line per handout:

    <stage>\t<share name>        e.g.  stage-shadowai\tlabs/02-shadow-ai

release-stage.sh uses it to publish a lab's web page when it releases the stage; share.sh uses it
to warn when a handout goes live before the files it refers to.
"""
import re, sys, os
here = os.path.dirname(os.path.abspath(__file__))
repo = os.path.abspath(os.path.join(here, "..", "..", ".."))

stages = []
txt = open(os.path.join(repo, "student-repo", "checkpoints.yaml"), encoding="utf-8").read()
for m in re.finditer(r'^\s*-\s*tag:\s*(\S+)\s*$(.*?)(?=^\s*-\s*tag:|\Z)', txt, re.M | re.S):
    tag, body = m.group(1), re.sub(r'#.*', '', m.group(2))
    order = re.search(r'^\s*order:\s*(\d+)', body, re.M)
    pm = re.search(r'^\s*paths:\s*(.*?)(?=^\s*\w+:|\Z)', body, re.M | re.S)
    paths = []
    if pm:
        blob = pm.group(1).strip()
        paths = ([p.strip() for p in blob.strip('[]').split(',') if p.strip()] if blob.startswith('[')
                 else [l.strip()[1:].strip() for l in blob.splitlines() if l.strip().startswith('-')])
    stages.append((int(order.group(1)) if order else 9999, tag, paths))
stages.sort()

sh = open(os.path.join(repo, "share", "build-handouts.sh"), encoding="utf-8").read()
man = re.search(r'^MANIFEST="\n(.*?)^"', sh, re.M | re.S).group(1)
docs = [line.split("|")[:2] for line in man.strip().splitlines() if "|" in line]

for src, dest in docs:
    for _, tag, paths in stages:
        if any(src == p or src.startswith(p.rstrip("/") + "/") for p in paths):
            print(f"{tag}\t{dest}")
            break
