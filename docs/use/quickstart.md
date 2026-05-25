---
layout: default
title: Quickstart
description: Send dumps from any language. Pipe them through any shell command.
---

After [installing]({{ '/' | relative_url }}#install), Scratchpad lives in
your menu bar. Left-click toggles the window; the window stays above
other apps when shown and **never steals focus**.

Default HTTP port is `8473`, loopback-only. Override with
`SCRATCHPAD_PORT=…` in the environment.

![Scratchpad menu-bar icon and window]({{ '/assets/screenshots/menu-bar.png' | relative_url }})

---

## Send a dump from anywhere

Two transports, same payload semantics — pick whichever is easiest.

### `sp` (the bundled CLI — shortest form)

```bash
echo "hello" | sp
sp ./payload.json
sp -m "inline literal"
```

### Bash / curl (HTTP)

```bash
echo "hello" | curl -X POST --data-binary @- http://127.0.0.1:8473/dump
```

### Bash / netcat (UNIX socket — lowest latency)

```bash
echo "hello" | nc -U "$HOME/Library/Application Support/Scratchpad/dump.sock"
```

### Python (stdlib only)

```python
import json, urllib.request

payload = json.dumps({"event": "login", "user": "aaron"}).encode()
urllib.request.urlopen(
    urllib.request.Request(
        "http://127.0.0.1:8473/dump", data=payload, method="POST"
    )
)
```

### Node.js (stdlib only)

```js
const http = require("node:http");

http.request({
  host: "127.0.0.1", port: 8473, path: "/dump", method: "POST",
}).end(JSON.stringify({ event: "login", user: "aaron" }));
```

### Go (stdlib only)

```go
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
require "net/http"

Net::HTTP.post(
  URI("http://127.0.0.1:8473/dump"),
  '{"event":"login","user":"aaron"}',
  "Content-Type" => "application/json",
)
```

### PHP (stdlib only)

```php
<?php
$ctx = stream_context_create(["http" => [
    "method"  => "POST",
    "header"  => "Content-Type: application/json\r\n",
    "content" => json_encode(["event" => "login", "user" => "aaron"]),
]]);
file_get_contents("http://127.0.0.1:8473/dump", false, $ctx);
```

### Rust (with reqwest, blocking)

```rust
fn main() {
    reqwest::blocking::Client::new()
        .post("http://127.0.0.1:8473/dump")
        .body(r#"{"event":"login","user":"aaron"}"#)
        .send()
        .ok();
}
```

### From any process via a one-line shell

```bash
my-program 2>&1 | sp
```

---

## The shell input bar

The bottom of the window has a `$ ` prompt. Type any shell command, press
Enter — the most recent dump is piped to its stdin, and the output
replaces the dump in the display.

![Input bar piping a dump through jq]({{ '/assets/screenshots/input-bar.png' | relative_url }})

Examples after sending a JSON payload:

| Command  | What happens |
|----------|--------------|
| `cat`    | Echoes the dump back, verbatim |
| `jq .`   | Pretty-prints JSON |
| `wc -c`  | Counts bytes |
| `grep error` | Filters lines |
| `xargs -n1 echo`  | One token per line |

Chain commands by running them in sequence — each command pipes the
**currently displayed** event, not just the original dump. So `jq .data`
followed by `grep id` runs grep against jq's output, not the raw dump.

### Keyboard shortcuts

| Key       | Action |
|-----------|--------|
| `⌘L`      | Focus the input bar |
| `⌘[` / `⌘]` | Walk back / forward through dump + command history |
| `↑` / `↓` | Recall earlier input-bar commands (last 10k, persisted) |
| `⌃R`      | Search command history (substring, newest-first) |
| `Esc`     | Close search overlay, then hide the window |
| `⌘W`      | Hide the window (the app keeps running) |
| Cmd-Click Copy button | Copy the displayed content to the clipboard |

![Ctrl-R history search overlay]({{ '/assets/screenshots/history-search.png' | relative_url }})

---

## Threat model

The input bar runs arbitrary shell commands you typed against bytes you
(or any local process) dumped. Defaults: `/bin/sh -c`, `$HOME` cwd,
inherited env, 10 s timeout (override with `SCRATCHPAD_SHELL_TIMEOUT`),
4 MiB output cap.

Dumps are passed via stdin, never interpolated into the command string,
so a malicious payload can't escape into shell syntax. Full reasoning in
[decision-2](https://github.com/aaronmyatt/scratchpad/blob/main/backlog/decisions/decision-2%20-%20Threat-model-and-safety-defaults-for-the-shell-input-bar.md).

Single-user dev tooling assumption. Don't run Scratchpad on a shared
kiosk.

---

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `SCRATCHPAD_PORT` | `8473` | HTTP listener port (server) and target port (`sp` CLI). |
| `SCRATCHPAD_SOCKET_PATH` | `~/Library/Application Support/Scratchpad/dump.sock` | UNIX socket path (server) and target (`sp` CLI). |
| `SCRATCHPAD_SHELL_TIMEOUT` | `10` | Shell-command timeout in seconds. |
| `SCRATCHPAD_HISTORY_FILE` | `~/Library/Application Support/Scratchpad/input_history` | Path to the input-bar command history file. |
