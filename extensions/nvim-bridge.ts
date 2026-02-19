import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import * as net from "node:net";
import * as crypto from "node:crypto";
import * as fs from "node:fs";

function socketPath(cwd: string): string {
  const hash = crypto.createHash("sha256").update(cwd).digest("hex").slice(0, 16);
  return `/tmp/pi-bridge-${hash}.sock`;
}

interface Message {
  type: "context" | "prompt" | "health";
  text?: string;
  file?: string;
  filetype?: string;
  prompt?: string;
}

export default function (pi: ExtensionAPI) {
  let server: net.Server | null = null;
  let sock: string | null = null;

  pi.on("session_start", async (_event, ctx) => {
    sock = socketPath(ctx.cwd);

    try { fs.unlinkSync(sock); } catch {}

    server = net.createServer((conn) => {
      let buffer = "";

      conn.on("data", (data) => {
        buffer += data.toString();
        let newline: number;
        while ((newline = buffer.indexOf("\n")) !== -1) {
          const line = buffer.slice(0, newline);
          buffer = buffer.slice(newline + 1);
          handleMessage(conn, line, ctx);
        }
      });

      conn.on("error", () => {});
    });

    function handleMessage(conn: net.Socket, raw: string, ctx: { ui: { notify: (msg: string, type: string) => void } }) {
      let msg: Message;
      try {
        msg = JSON.parse(raw);
      } catch {
        conn.end(JSON.stringify({ error: "invalid JSON" }) + "\n");
        return;
      }

      if (msg.type === "health") {
        conn.end(JSON.stringify({ status: "ok", cwd: ctx.cwd }) + "\n");
        return;
      }

      if (!msg.text) {
        conn.end(JSON.stringify({ error: "missing 'text'" }) + "\n");
        return;
      }

      let content = "";
      if (msg.file) {
        content += `File: ${msg.file}`;
        if (msg.filetype) content += ` (${msg.filetype})`;
        content += "\n";
      }
      content += "```" + (msg.filetype || "") + "\n";
      content += msg.text;
      if (!msg.text.endsWith("\n")) content += "\n";
      content += "```";

      if (msg.type === "context") {
        pi.sendMessage(
          { customType: "nvim-context", content, display: true },
          { deliverAs: "nextTurn" }
        );
        ctx.ui.notify(`nvim: received ${msg.text.split("\n").length} lines`, "info");
        conn.end(JSON.stringify({ ok: true }) + "\n");
        return;
      }

      if (msg.type === "prompt") {
        let message = "";
        if (msg.prompt) message += msg.prompt + "\n\n";
        message += content;

        pi.sendUserMessage(message, { deliverAs: "followUp" });
        ctx.ui.notify(`nvim: prompting with ${msg.text.split("\n").length} lines`, "info");
        conn.end(JSON.stringify({ ok: true }) + "\n");
        return;
      }

      conn.end(JSON.stringify({ error: "unknown type" }) + "\n");
    }

    server.listen(sock, () => {
      ctx.ui.notify(`nvim bridge: ${sock}`, "info");
      ctx.ui.setStatus("nvim-bridge", ctx.ui.theme.fg("dim", "bridge:sock"));
    });

    server.on("error", (err: NodeJS.ErrnoException) => {
      ctx.ui.notify(`nvim bridge error: ${err.message}`, "error");
    });
  });

  pi.on("session_shutdown", async () => {
    if (server) {
      server.close();
      server = null;
    }
    if (sock) {
      try { fs.unlinkSync(sock); } catch {}
      sock = null;
    }
  });
}
