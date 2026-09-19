# Before you arrive: what your laptop needs

> **Instructor:** replace `<lab-host>` and `<lab-host-ip>` below with your lab host's DNS name and
> IPv4 address, then send this with the abstract, weeks ahead. Attendees have been unable to open
> the course slides, let alone reach their lab machine, because a corporate policy blocked SSH or a
> non-standard HTTPS port, and an exception takes days to approve rather than minutes.

Everything hands-on in this course runs on a lab host we provide. **You install nothing and you
need no admin rights on your laptop.** You need a terminal that can SSH, a browser, and a network
that lets those two reach one host.

## The short version, to forward to your security or network team

> I am attending a hands-on training course. All lab work runs on a remote host operated by the
> instructor; nothing is installed locally and no data from my employer is involved. From the
> venue network (and, if I want to prepare, from my usual network) I need outbound access from my
> laptop to a single host, `<lab-host>` (IPv4 `<lab-host-ip>`), on three things: **TCP 22**
> for SSH, **TCP 443** for the course materials over HTTPS, and **TCP 10443 to 29443**, which is
> HTTPS to the per-attendee lab web UI. No inbound access is required and no other destination is
> needed: the course's own outbound calls are made by the remote host, not by my laptop.

## Destinations

| Destination | Port | Protocol | What it is |
|---|---|---|---|
| `<lab-host>` | TCP 22 | SSH | Your lab seat. Every lab is typed in a terminal on this host |
| `<lab-host>` | TCP 443 | HTTPS | The course site: handouts and slide decks, to read and to copy commands from |
| `<lab-host>` | TCP 10443-29443 | HTTPS | Your own analysis UI. Each attendee gets one port in this range, derived from their seat number |
| `<lab-host>` | TCP 39443 | HTTPS | Optional. One instructor demo late in the course, view only |

The IPv4 address is `<lab-host-ip>`. It is stable for the delivery; ask the instructor to confirm it
on the day if your policy team pins addresses rather than names. The certificate is a normal
publicly trusted one, so a browser shows no warning.

**If your network does TLS inspection**, add the host to the inspection bypass list if you can. It
is not fatal if you cannot: the browser will still work. It is SSH, and blocked high ports, that
stop the day.

## Test it before you travel

Run these from the laptop you are bringing, on a network like the one you will use. They prove each
piece works, and none of them needs a password or an account.

**macOS, Linux, or Windows PowerShell:**

```bash
ssh -p 22 -o BatchMode=yes nobody@<lab-host>
```

You want `Permission denied (publickey,password)` or a prompt for a password. That is success: it
means you reached the SSH service. `Connection timed out` or `Connection refused` means port 22 is
blocked, and that is the one to escalate.

```bash
curl -sS -o /dev/null -w "%{http_code}\n" https://<lab-host>/
```

You want **401**. The site asks for a password that the instructor reads out at the start; a 401
proves you can reach it. A hang or a certificate error is the problem to report.

Then open <https://<lab-host>/> in your browser and confirm you get a password prompt
rather than a corporate block page.

**Windows without PowerShell:** PuTTY (`<lab-host>`, port 22) shows a login prompt if
SSH is open, and Edge or Chrome to the same URL covers the HTTPS check.

**The high-port check** only works during the course, when your seat's stack is running, so there
is nothing to test in advance. Ask your network team to approve the whole 10443-29443 range: which
port is yours is decided on the day.

## What you do **not** need

- No software to install, and no administrator rights.
- No accounts, API keys, or cloud subscriptions. The lab host holds the credentials the labs use.
- **No access to AI services from your laptop.** If your employer blocks ChatGPT, Claude, Copilot
  and friends, nothing in this course breaks: every call to a model is made by the lab host.
- No VPN, and nothing inbound to your machine.

## Bring

- A laptop with a working terminal and browser, and its charger.
- Comfort with a command line is helpful but not assumed. Everything you type is written out in the
  handouts, and you get a cheatsheet with every command in it on the first morning.

## If the exception is refused

Tell the instructor before the day rather than on it. Two workarounds usually save it: a personal
phone hotspot bypasses the corporate network entirely, and a personal laptop has no policy on it at
all. Neither needs anything from your employer. If you have neither, say so in advance and we will
sort out a shared machine.
