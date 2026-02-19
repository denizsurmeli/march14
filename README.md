# pi ↔ nvim bridge

Send code from Neovim to a running pi session. No config, no ports — they find each other automatically via the working directory.

## Install

### 1. Pi extension

```bash
cp extensions/nvim-bridge.ts ~/.pi/agent/extensions/
```

Loads automatically on every `pi` session.

### 2. Neovim plugin

```bash
cp lua/pi-bridge.lua ~/.config/nvim/lua/
```

Add to your nvim config (e.g. `lua/config/keymaps.lua`):

```lua
require("pi-bridge").setup()
vim.keymap.set('v', '<leader>ps', ':PiSend<CR>', { noremap = true, silent = true })
vim.keymap.set('v', '<leader>pa', ':PiAsk<CR>', { noremap = true, silent = true })
```

### Requirement

Neovim ≥ 0.10 (for `vim.uv`). No external dependencies.

## Usage

1. Open a terminal in your project, run `pi`
2. Open the same project in Neovim
3. Visual-select some code, then:

| Key | What happens |
|-----|-------------|
| `<leader>ps` | Sends selection to pi as context. Sits there until your next prompt in pi. |
| `<leader>pa` | Sends selection to pi with a prompt. A floating input appears — type your question, hit Enter. Pi responds immediately. |

Escape dismisses the floating input without sending.

You can also skip the popup:

```
:'<,'>PiAsk explain this function
```

### Health check

```
:PiHealth
```

## How it works

Both sides derive a Unix socket path from `sha256(cwd)`:

```
/tmp/pi-bridge-<hash>.sock
```

Same directory → same socket → they connect. Different projects run in parallel without conflicts.

### Protocol

JSON lines over a Unix socket. One JSON object per line, newline-delimited.

```json
{"type": "context", "text": "code", "file": "/path", "filetype": "go"}
{"type": "prompt", "text": "code", "prompt": "explain this"}
{"type": "health"}
```

Response:

```json
{"ok": true}
{"status": "ok", "cwd": "/path/to/project"}
{"error": "reason"}
```

## Credits

Inspired by [pi.nvim](https://github.com/pablopunk/pi.nvim) by [@pablopunk](https://github.com/pablopunk).
