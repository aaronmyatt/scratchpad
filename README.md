# Scratchpad

A pinned, menu-bar-resident desktop window for macOS that receives arbitrary
data dumps from anywhere — HTTP, local socket, a watched file, or a CLI pipe —
and lets you pipe the most recent dump through any shell command. No language
SDKs, no config. If your program can `POST`, write to a file, write to stdout,
or open a socket, it can talk to Scratchpad.

Inspired by [Laradumps](https://laradumps.dev/), but transport-first and
language-agnostic.

The full design rationale lives in [`backlog/docs/doc-1 - Vision.md`](backlog/docs/doc-1%20-%20Vision.md).

---

## Install

Three install paths, listed in order of recommended preference for end users.
All produce the same app — pick whichever fits your habits.

### 1. Homebrew (preferred — friction-free)

```bash
brew install aaronmyatt/scratchpad/scratchpad
```

Our Cask strips the macOS quarantine attribute in a postflight step, so
the app launches with no Gatekeeper prompt. *(Tap repo lands with
TASK-32; this one-liner becomes live then.)*

### 2. curl | bash (also friction-free)

```bash
curl -fsSL https://raw.githubusercontent.com/aaronmyatt/scratchpad/main/install.sh | bash
```

`curl` doesn't set the macOS quarantine attribute that browsers do, so the
installed app launches without Gatekeeper friction. The script verifies a
sha256 checksum against the published release before extracting anything.
[Inspect it first](install.sh) if you're (rightly) cautious about
`curl … | bash` patterns.

### 3. Direct download (DMG from GitHub Releases)

Grab `Scratchpad.dmg` from the
[latest GitHub Release](https://github.com/aaronmyatt/scratchpad/releases/latest),
double-click to mount, then drag `Scratchpad.app` into `/Applications`.

> **Heads-up:** Scratchpad isn't code-signed by Apple
> ([decision-3](backlog/decisions/decision-3%20-%20Skip-Apple-notarization-for-v1.md)).
> The Homebrew and curl paths above bypass macOS Gatekeeper entirely; this
> direct-download path will hit it on first launch because browsers attach
> the `com.apple.quarantine` extended attribute to downloaded files.

If you'd rather not deal with the warning, **use brew or curl above** — same
binary, no Gatekeeper. If you want to use the DMG, one of these three works:

**macOS 14 (Sonoma):** Right-click the app in `/Applications` → **Open** →
confirm in the dialog. One extra click, once.

**macOS 15+ (Sequoia):** Apple removed the right-click → Open shortcut for
unsigned apps. Double-click once (you'll see "*not opened*"), then open
**System Settings → Privacy & Security**, scroll to the *Scratchpad was
blocked* note near the bottom, and click **"Open Anyway"**.

**Terminal alternative (any version):** Strip the quarantine flag yourself —
this is exactly what Homebrew does for you on the brew path.
```bash
xattr -dr com.apple.quarantine /Applications/Scratchpad.app
```

Why the warning happens: macOS attaches `com.apple.quarantine` to anything a
browser downloads, then Gatekeeper checks that attribute on first launch.
Unsigned apps from the internet get blocked by default — a sensible safety
behaviour. brew and curl don't set the attribute (different download path),
so the warning never appears.

---

## Development

Requires Swift 6 toolchain (`swift --version` ≥ 6.3) on macOS 14+.

```sh
swift build                          # builds Scratchpad (app) + sp (CLI)
swift run Scratchpad                 # launches the menu-bar app
swift test                           # runs the Swift suite (pure-logic regressions)
bats Tests/install.bats              # install-hygiene regression guards — see Tests/README.md
./scripts/preflight-release.sh       # full release-blocking chain (~60-90s)
```

Pre-commit hooks (lefthook — runs `swift test` + `shellcheck` on every
commit, ~3–5s) need a one-time setup:

```sh
brew install lefthook shellcheck     # also: brew install bats-core (for the bats suite)
lefthook install                     # registers .git/hooks/pre-commit
```

`git commit --no-verify` bypasses the hook for a single commit when you
need it.

The app appears in your menu bar as a small note icon. Left-click toggles the
window; right-click opens Show / Hide / Quit. The window stays above other
apps when shown and never steals focus when dumps arrive.

Default HTTP port is `8473` (loopback-only). Override with `SCRATCHPAD_PORT=…`
in the environment.

To build the release artifacts (signed packaging is deferred — see
decision-3):
```sh
./scripts/build-app.sh        # build/Scratchpad.app
./scripts/build-tarball.sh    # build/Scratchpad-arm64.tar.gz + .sha256
./scripts/build-dmg.sh        # build/Scratchpad.dmg
```

---

## Send a dump from anywhere

Three transports, same payload semantics — pick whichever is easiest:

1. **HTTP** — `POST` to `http://127.0.0.1:8473/dump` with the dump as the body.
   Works from any language with a stdlib HTTP client.
2. **UNIX domain socket** — connect to
   `~/Library/Application Support/Scratchpad/dump.sock`, write bytes, half-close.
   No HTTP framing, lower latency. The `sp` CLI prefers this and falls back
   to HTTP automatically; from the shell, `nc -U <path>` is the equivalent.
3. **Watched file** — write your payload to `/tmp/sp`. Scratchpad polls the
   path (200ms) and ingests any change. Zero dependencies in the writer —
   `echo "$msg" > /tmp/sp` is the whole integration. Designed for Docker
   containers and other sandboxes where reaching the loopback HTTP port or
   the user-scoped socket is awkward.

No headers, no schema. Bytes go in, bytes appear in the window.

### Bash / curl (HTTP)
```bash
echo 'hello' | curl -X POST --data-binary @- http://127.0.0.1:8473/dump
```

### Bash / netcat (UNIX socket — lowest latency)
```bash
echo 'hello' | nc -U "$HOME/Library/Application Support/Scratchpad/dump.sock"
```

### Bash / file (zero deps, container-friendly)
```bash
echo 'hello' > /tmp/sp
```

### `sp` (the bundled CLI — shortest form)
```bash
echo 'hello' | sp
sp ./payload.json
sp -m 'inline literal'
sp --version          # which Scratchpad am I running?
```

After `swift build`, symlink it onto PATH:
```bash
ln -sf "$PWD/.build/arm64-apple-macosx/debug/sp" /usr/local/bin/sp
```

### Python (stdlib only)
```python
# https://docs.python.org/3/library/urllib.request.html
import json, urllib.request

payload = json.dumps({"event": "login", "user": "aaron"}).encode()
urllib.request.urlopen(
    urllib.request.Request("http://127.0.0.1:8473/dump", data=payload, method="POST")
)
```

### Node.js (stdlib only)
```js
// https://nodejs.org/api/http.html#httprequestoptions-callback
const http = require("node:http");

const req = http.request({
  host: "127.0.0.1",
  port: 8473,
  path: "/dump",
  method: "POST",
});
req.end(JSON.stringify({ event: "login", user: "aaron" }));
```

### Go (stdlib only)
```go
// https://pkg.go.dev/net/http
package main

import (
    "bytes"
    "net/http"
)

func main() {
    body := bytes.NewBufferString(`{"event":"login","user":"aaron"}`)
    http.Post("http://127.0.0.1:8473/dump", "application/json", body)
}
```

### Ruby (stdlib only)
```ruby
# https://docs.ruby-lang.org/en/3.3/Net/HTTP.html
require "net/http"

Net::HTTP.post(
  URI("http://127.0.0.1:8473/dump"),
  '{"event":"login","user":"aaron"}',
  "Content-Type" => "application/json"
)
```

### PHP (stdlib only)
```php
<?php
// https://www.php.net/manual/en/function.file-get-contents.php
$ctx = stream_context_create(["http" => [
    "method"  => "POST",
    "header"  => "Content-Type: application/json\r\n",
    "content" => json_encode(["event" => "login", "user" => "aaron"]),
]]);
file_get_contents("http://127.0.0.1:8473/dump", false, $ctx);
```

### Rust (with reqwest, blocking)
```rust
// https://docs.rs/reqwest
fn main() {
    reqwest::blocking::Client::new()
        .post("http://127.0.0.1:8473/dump")
        .body(r#"{"event":"login","user":"aaron"}"#)
        .send()
        .ok();
}
```

(Rust's stdlib has no HTTP client; `reqwest` or `ureq` are the conventional
zero-config choices.)

### From any process via a one-line shell
```bash
# Anywhere a program can spawn a shell, this works:
my-program 2>&1 | sp
```

### From inside a Docker container

The HTTP and socket transports are awkward to reach from inside a container —
loopback means the container, not the host, and the socket lives in a
user-scoped directory. The watched-file transport sidesteps both. Bind-mount
the host's `/tmp/sp` into the container at the same path:

```yaml
# docker-compose.yml
services:
  your-service:
    volumes:
      - /tmp/sp:/tmp/sp
```

```bash
# docker run
docker run -v /tmp/sp:/tmp/sp your-image
```

Then write to it from anywhere inside the container, in any language. No
`curl`, no `nc`, no SDK install:

```bash
echo "$payload" > /tmp/sp
```

```js
// Node.js
require("node:fs").writeFileSync("/tmp/sp", JSON.stringify(payload))
```

```python
# Python
open("/tmp/sp", "wb").write(payload)
```

Scratchpad **truncates `/tmp/sp` on every launch**, so the host-side path is
always present and the bind-mount works without a prior `touch /tmp/sp`. The
file is owned by the user who launched Scratchpad (mode 0600), so other local
users can't inject dumps into your session.

---

## The shell input bar

The bottom of the window has a `$ ` prompt. Type any shell command and press
Enter — the most recent dump is piped to its stdin, and the output replaces
the dump in the display.

Examples after sending a JSON payload:

| Command  | What happens |
|----------|--------------|
| `cat`    | Echoes the dump back, verbatim |
| `jq .`   | Pretty-prints JSON |
| `wc -c`  | Counts bytes |
| `grep error` | Filters lines |
| `xargs -n1 echo`  | One token per line |

Chain commands by running them in sequence — each command pipes the **currently
displayed** event, not just the original dump. So `jq .data` followed by
`grep id` runs grep against jq's output, not the raw dump.

### Keyboard shortcuts

| Key       | Action |
|-----------|--------|
| `⌘L`      | Focus the input bar |
| `⌘[` / `⌘]` | Walk back / forward through dump + command history |
| `↑` / `↓` | Recall earlier input-bar commands (last 10k, persisted) |
| `⌃R`      | Search command history (substring, newest-first) |
| `Esc`     | Close search overlay, then hide the window |
| `⌘W`      | Hide the window (the app keeps running) |
| `Cmd-Click` Copy button | Copy the displayed content to the clipboard |

### Threat model

The input bar runs arbitrary shell commands you typed against bytes you (or any
local process) dumped. Defaults: `/bin/sh -c`, `$HOME` cwd, inherited env, 10 s
timeout (override with `SCRATCHPAD_SHELL_TIMEOUT`), 4 MiB output cap.

Dumps are passed via stdin, never interpolated into the command string, so a
malicious payload can't escape into shell syntax. Full reasoning in
[`backlog/decisions/decision-2`](backlog/decisions/decision-2%20-%20Threat-model-and-safety-defaults-for-the-shell-input-bar.md).

Single-user dev tooling assumption. Don't run Scratchpad on a shared kiosk.

---

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `SCRATCHPAD_PORT`           | `8473` | HTTP listener port (server) and target port (`sp` CLI). |
| `SCRATCHPAD_SOCKET_PATH`    | `~/Library/Application Support/Scratchpad/dump.sock` | UNIX socket path (server) and target (`sp` CLI). |
| `SCRATCHPAD_SHELL_TIMEOUT`  | `10`   | Shell-command timeout in seconds. |
| `SCRATCHPAD_HISTORY_FILE`   | `~/Library/Application Support/Scratchpad/input_history` | Path to the input-bar command history file. |

The watched-file transport is fixed at `/tmp/sp` by design — one well-known
path, no configuration, designed for bind-mounting into containers where a
host-derived env var wouldn't be portable anyway. The file is truncated to
zero bytes on every Scratchpad launch.

---

## Project status

v1, single-user dev tooling on macOS. Linux/Windows ports deferred. Roadmap
and detailed history live under [`backlog/`](backlog/) (the project uses
[Backlog.md](https://backlog.md) for task tracking).
