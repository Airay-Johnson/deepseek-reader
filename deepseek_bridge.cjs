/**
 * DeepSeek Bridge v3 — Robust conversation extraction
 * CDP client for Edge. Extracts conversation list and full content.
 * Usage: node deepseek_bridge.cjs <list|read|search> [args]
 * Output: writes to deepseek_result.json
 */
const http = require("http");
const fs = require("fs");
const path = require("path");

const CDP_HOST = "127.0.0.1";
const CDP_PORT = 9222;
const CDP_BASE = `http://${CDP_HOST}:${CDP_PORT}`;
const RESULT_FILE = path.join(__dirname, "deepseek_result.json");

const action = process.argv[2] || "list";
const arg = process.argv[3] || "";

function httpGetJSON(url) {
  return new Promise((resolve, reject) => {
    http.get(url, (res) => {
      let data = "";
      res.on("data", (chunk) => (data += chunk));
      res.on("end", () => {
        try { resolve(JSON.parse(data)); }
        catch (e) { reject(new Error("JSON parse: " + e.message)); }
      });
    }).on("error", reject);
  });
}

async function listTabs() {
  const targets = await httpGetJSON(`${CDP_BASE}/json`);
  return targets.filter((t) => t.type === "page");
}

class CDPClient {
  constructor(wsUrl) {
    this.wsUrl = wsUrl;
    this.ws = null;
    this.id = 0;
    this.pending = new Map();
  }

  async connect() {
    return new Promise((resolve, reject) => {
      this.ws = new WebSocket(this.wsUrl);
      const timeout = setTimeout(() => {
        if (this.ws.readyState !== WebSocket.OPEN) {
          this.ws.close();
          reject(new Error("WebSocket connect timeout"));
        }
      }, 10000);
      this.ws.onopen = () => { clearTimeout(timeout); resolve(); };
      this.ws.onerror = (err) => { clearTimeout(timeout); reject(err); };
      this.ws.onmessage = (event) => {
        const msg = JSON.parse(event.data);
        if (msg.id && this.pending.has(msg.id)) {
          const { resolve } = this.pending.get(msg.id);
          this.pending.delete(msg.id);
          resolve(msg);
        }
      };
    });
  }

  async send(method, params = {}) {
    const id = ++this.id;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.ws.send(JSON.stringify({ id, method, params }));
      setTimeout(() => {
        if (this.pending.has(id)) {
          this.pending.delete(id);
          reject(new Error(`CDP timeout: ${method}`));
        }
      }, 20000);
    });
  }

  close() { this.ws.close(); }
}

function saveResult(data) {
  fs.writeFileSync(RESULT_FILE, JSON.stringify(data, null, 2), "utf-8");
  console.log("OK: " + RESULT_FILE + " (" + JSON.stringify(data).length + " bytes)");
}

async function getDeepSeekTarget() {
  const targets = await listTabs();
  let target = targets.find((t) => t.url && t.url.includes("chat.deepseek.com"));

  if (!target) {
    const navResult = await new Promise((resolve, reject) => {
      const req = http.request(`${CDP_BASE}/json/new?https://chat.deepseek.com/`, { method: "PUT" }, (res) => {
        let data = "";
        res.on("data", (c) => (data += c));
        res.on("end", () => { try { resolve(JSON.parse(data)); } catch (e) { reject(e); } });
      });
      req.on("error", reject);
      req.end();
    });
    target = navResult;
    await new Promise((r) => setTimeout(r, 5000));
  }
  return target;
}

// ─── LIST conversations ───────────────────────────────────────────

async function doList() {
  const target = await getDeepSeekTarget();
  const wsUrl = target.webSocketDebuggerUrl;
  if (!wsUrl) { saveResult({ error: "No WebSocket URL" }); return; }

  const client = new CDPClient(wsUrl);
  await client.connect();
  await client.send("Runtime.enable");
  await new Promise((r) => setTimeout(r, 500));

  const jsCode = `(() => {
    const conversations = [];
    const allLinks = Array.from(document.querySelectorAll('a'))
      .filter(a => a.href && a.href.includes('/chat/'));
    const seen = new Set();
    allLinks.forEach((item) => {
      const title = item.textContent.trim();
      const href = item.href;
      const id = href.split('/').pop();
      if (title && title.length > 0 && title.length < 200 && !seen.has(title)) {
        seen.add(title);
        conversations.push({ index: conversations.length + 1, id, title: title.substring(0, 150) });
      }
    });
    return JSON.stringify({
      isLogin: !window.location.href.includes('sign_in'),
      url: window.location.href,
      title: document.title,
      count: conversations.length,
      conversations: conversations
    });
  })()`;

  const result = await client.send("Runtime.evaluate", { expression: jsCode, returnByValue: true });
  client.close();

  if (result.result && result.result.result && result.result.result.value) {
    saveResult(JSON.parse(result.result.result.value));
  } else {
    saveResult({ error: "No result", raw: JSON.stringify(result).substring(0, 500) });
  }
}

// ─── READ conversation ────────────────────────────────────────────

async function doRead(index) {
  const target = await getDeepSeekTarget();
  const wsUrl = target.webSocketDebuggerUrl;
  if (!wsUrl) { saveResult({ error: "No WebSocket URL" }); return; }

  const client = new CDPClient(wsUrl);
  await client.connect();
  await client.send("Runtime.enable");
  await new Promise((r) => setTimeout(r, 500));

  // Step 1: Click the conversation in sidebar
  const clickJS = `(() => {
    const idx = ${index - 1};
    const allLinks = Array.from(document.querySelectorAll('a'))
      .filter(a => a.href && a.href.includes('/chat/'));
    if (idx < allLinks.length) {
      allLinks[idx].click();
      return JSON.stringify({ success: true, clicked: allLinks[idx].textContent.trim().substring(0, 100), total: allLinks.length });
    }
    return JSON.stringify({ success: false, error: 'Index out of range', total: allLinks.length });
  })()`;

  const clickResult = await client.send("Runtime.evaluate", { expression: clickJS, returnByValue: true });
  const clickData = JSON.parse(clickResult.result.result.value);

  // Wait for conversation to load
  await new Promise((r) => setTimeout(r, 3000));

  // Step 2: Extract messages using multiple strategies
  const extractJS = `(() => {
    // Strategy 1: Look for markdown/MathJax content blocks
    let messages = [];

    // Try finding all paragraphs, headings, lists — DeepSeek renders markdown
    const mainArea = document.querySelector('main') ||
                     document.querySelector('[role="main"]') ||
                     document.querySelector('.chat-container') ||
                     document.querySelector('[class*="chat"]');

    if (!mainArea) {
      // Strategy 2: Get all substantial text from the page
      const body = document.body.innerText;
      // Remove sidebar text (first 500 chars usually sidebar)
      const mainText = body.substring(Math.min(500, body.length / 4));
      return JSON.stringify({
        total: 1,
        messages: [{ role: 'mixed', content: mainText.substring(0, 10000) }]
      });
    }

    // Strategy 3: Find user vs assistant blocks by structure
    // DeepSeek uses alternating user/AI blocks with distinct styling
    const allDivs = mainArea.querySelectorAll('div');
    const blocks = [];

    allDivs.forEach(div => {
      const text = div.textContent.trim();
      const childCount = div.children.length;

      // Heuristic: message blocks typically have many children (nested markdown)
      if (text.length > 30 && childCount >= 3 && text.length < 20000) {
        // Check if it's a distinct message (not nested inside another message)
        const parentText = div.parentElement ? div.parentElement.textContent.trim() : '';
        if (parentText.length - text.length < 100 || childCount > 5) {
          blocks.push({
            text: text,
            childCount: childCount,
            className: div.className || ''
          });
        }
      }
    });

    // Deduplicate: remove blocks that are subsets of others
    const deduped = [];
    blocks.forEach(block => {
      const isSubset = deduped.some(d => d.text.includes(block.text) && d.text.length > block.text.length + 50);
      if (!isSubset) {
        deduped.push(block);
      }
    });

    // Classify as user or AI
    deduped.forEach((block, i) => {
      const isUser = block.className.toLowerCase().includes('user') ||
                     block.className.toLowerCase().includes('human');
      messages.push({
        index: i + 1,
        role: isUser ? 'user' : 'deepseek',
        content: block.text.substring(0, 5000)
      });
    });

    // Merge consecutive same-role
    const merged = [];
    messages.forEach(msg => {
      const last = merged[merged.length - 1];
      if (last && last.role === msg.role) {
        last.content += '\\n\\n---\\n\\n' + msg.content;
      } else {
        merged.push(msg);
      }
    });

    // If we still got nothing, fallback to plain text
    if (merged.length === 0) {
      const allText = mainArea.innerText || mainArea.textContent || '';
      return JSON.stringify({
        total: 1,
        messages: [{ role: 'mixed', content: allText.substring(0, 10000) }]
      });
    }

    return JSON.stringify({ total: merged.length, messages: merged });
  })()`;

  const extractResult = await client.send("Runtime.evaluate", { expression: extractJS, returnByValue: true });
  client.close();

  const extractData = JSON.parse(extractResult.result.result.value);
  saveResult({ action: "read", index: index, clicked: clickData, conversation: extractData });
}

// ─── Main ──────────────────────────────────────────────────────────

async function main() {
  try {
    if (action === "list") {
      await doList();
    } else if (action === "read") {
      const idx = parseInt(arg) || 1;
      await doRead(idx);
    } else {
      saveResult({ error: "Unknown action: " + action + ". Use: list | read <index>" });
    }
  } catch (err) {
    saveResult({ error: err.message, stack: err.stack });
  }
}

main();
