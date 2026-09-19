---
marp: true
theme: jarvis
paginate: true
header: 'Exploring AI Visibility · Endpoint detection'
---

<!-- _class: lead -->
# Rogue agents on the endpoint
## Finding AI agents in Sysmon

<!--
Network logs catch the traffic. But an agent's real damage is on the host, the commands it runs. Sysmon (process creation) is where that lives.
-->

---

## Why agents look different

An AI coding agent doesn't run one command. It runs **a LOT**. `cat`, `ls`, `grep`, `bash`, over and over, all spawned from one parent.

- Normal dev: a human types a command every few seconds
- Agent: a firehose of child processes from a single PID

That pattern (one parent, tons of short-lived children) is the signature.

<!-- This is the behavioral tell. You're not fingerprinting the model, you're spotting a process that spawns like a machine because it is one. -->

---

## The Sysmon-for-Linux gotcha

There's a **race condition**: when a parent spawns children *fast*, Sysmon hasn't cached the parent's metadata yet, so `ParentImage` and `ParentCommandLine` come back **empty**.

```xml
<Data Name="Image">/usr/bin/bash</Data>
<Data Name="CommandLine">/bin/bash -c cat /etc/passwd</Data>
<Data Name="ParentProcessId">3565</Data>
<Data Name="ParentImage">-</Data>   <!-- empty! -->
```

You can't identify the agent by parent *name*. But you still have the `ParentProcessId`, so cluster by *how many children each PID spawned*.

<!-- Real limitation Daniel hit generating the data. The workaround IS the detection: count children per parent PID. -->

---

## Query 1: find the high spawners

```
tag=sysmon winlog EventID == 1 ParentProcessId
| count by ParentProcessId
| sort by count desc
| table ParentProcessId count
```

<span class="muted">`winlog` knows the Windows event schema; the general `xml` module does the same in three times the typing.</span>

The PID at the top of the list that isn't `systemd`… that's your suspect.

<!-- EventID 1 = process create. Whoever spawned the most children is either init or an agent. -->

---

## Query 2: what did that PID spawn?

```
tag=sysmon winlog EventID == 1 ParentProcessId == 3565 Image
| count by Image | sort by count desc | table Image count
```

<span class="cap">Real result: 73 × bash, 9 × cat, 4 × opencode... that's an agent.</span>

<!-- Pivot from "which PID" to "what did it run." A wall of bash/cat is not a human. -->

---

## Query 3: the actual commands

```
tag=sysmon winlog EventID == 1 ParentProcessId == 3565 Image ~ bash CommandLine
| table CommandLine
```

> `whoami` · `id` · `cat /etc/passwd` · reading SSH keys · hunting credential files…

<!-- Now you read what it did. In the sample data the agent went full recon: passwd, ssh keys, creds. This is the payoff, the receipts. -->

---

## Query 4: turn it into a detection

```
tag=sysmon winlog EventID == 1 Image ~ bash ParentProcessId
| count by ParentProcessId
| eval count > 10
| sort by count desc | table ParentPID count
```

Any parent PID spawning **>10 bash children** is worth a look.

<!-- Generalize from "PID 3565" to a rule. Tune the threshold to your environment's baseline. -->

---

## Other avenues

- **Browser extension** inventory (OSQuery)
- **Corelight Files**: what crossed the wire
- Baseline **normal developer** behavior, then alert on the outliers

<!-- Same philosophy as the network side: you're looking for the shape of a machine doing a human's job, faster and louder than a human would. -->

---

<!-- _class: lead -->
# Lab 03
## Find the rogue agent in real Sysmon data

<span class="muted">`git checkout stage-sysmon -- labs/03-endpoint-sysmon`</span>

<!-- 3.6 MB of real Sysmon-for-Linux XML. Cluster the PIDs, find the agent, read its commands. -->
