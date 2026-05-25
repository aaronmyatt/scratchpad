---
layout: default
title: Scratchpad
description: A pinned, menu-bar-resident dump receiver for macOS.
---

A pinned, menu-bar-resident desktop window for macOS that receives arbitrary
data dumps from anywhere — HTTP, local socket, or a CLI pipe — and lets you
pipe the most recent dump through any shell command. No language SDKs, no
config. If your program can `POST`, write to stdout, or open a socket, it
can talk to Scratchpad.

![Scratchpad receiving a JSON dump]({{ '/assets/screenshots/hero.png' | relative_url }})

---

## Install

Three install paths, listed in order of recommended preference. All produce
the same app — pick whichever fits your habits.

### Homebrew *(coming soon)*

```bash
brew install aaronmyatt/scratchpad/scratchpad
```

Homebrew strips the macOS quarantine attribute automatically, so the app
launches with no Gatekeeper prompt. *(Tap repo lands with TASK-32.)*

[Full Homebrew instructions →]({{ '/install/brew' | relative_url }})

### curl | bash

```bash
curl -fsSL https://raw.githubusercontent.com/aaronmyatt/scratchpad/main/install.sh | bash
```

`curl` doesn't set the macOS quarantine attribute that browsers do, so the
installed app launches without Gatekeeper friction. The script verifies a
sha256 checksum against the published release before extracting anything.

[Full curl install details →]({{ '/install/curl' | relative_url }})

### Direct DMG download

Grab `Scratchpad.dmg` from the
[latest GitHub Release](https://github.com/aaronmyatt/scratchpad/releases/latest),
double-click to mount, drag into `/Applications`. *Hits Gatekeeper on first
launch* — easily worked around.

[Direct download + Gatekeeper workaround →]({{ '/install/direct' | relative_url }})

---

## Send a dump from anywhere

Two transports, same payload semantics. Bytes go in, bytes appear in the
window. No headers, no schema.

```bash
# Bash — pipe via the bundled sp CLI (shortest)
echo "hello" | sp

# Bash — raw curl (no install required beyond curl)
echo "hello" | curl -X POST --data-binary @- http://127.0.0.1:8473/dump
```

```python
# Python (stdlib only)
import urllib.request
urllib.request.urlopen(
    urllib.request.Request(
        "http://127.0.0.1:8473/dump",
        data=b'{"event":"login","user":"aaron"}',
        method="POST",
    )
)
```

```js
// Node.js (stdlib only)
require("node:http").request({
  host: "127.0.0.1", port: 8473, path: "/dump", method: "POST",
}).end(JSON.stringify({ event: "login", user: "aaron" }));
```

[Quickstart with more languages →]({{ '/use/quickstart' | relative_url }})

---

## The shell input bar

The bottom of the window has a `$ ` prompt. Type any shell command, press
Enter — the most recent dump is piped to its stdin, and the output replaces
the dump in the display.

![Input bar piping the displayed dump through jq]({{ '/assets/screenshots/input-bar.png' | relative_url }})

| Command  | What happens |
|----------|--------------|
| `jq .`   | Pretty-prints JSON |
| `wc -c`  | Counts bytes |
| `grep error` | Filters lines |
| `xargs -n1 echo`  | One token per line |

Chain commands by running them in sequence — each pipes the *currently
displayed* event, not just the original dump.

---

## More

- [Quickstart + multi-language examples →]({{ '/use/quickstart' | relative_url }})
- [Source code on GitHub](https://github.com/aaronmyatt/scratchpad)
- [Why Scratchpad exists (Vision doc)](https://github.com/aaronmyatt/scratchpad/blob/main/backlog/docs/doc-1%20-%20Vision.md)
