---
name: deepseek-reader
description: 从 DeepSeek 网页版 (chat.deepseek.com) 读取对话历史和内容。支持列出对话列表、读取指定对话、搜索对话内容。使用浏览器自动化实现，无需 API Key。
---

# DeepSeek Reader — 读取 DeepSeek 网页对话

从 chat.deepseek.com 提取你的对话历史和内容。通过浏览器自动化（Claude in Chrome / Edge / agent-browser）模拟用户操作，读取侧边栏对话列表和对话详情。

## 前置条件

- 已在浏览器中登录 chat.deepseek.com
- 浏览器已开启远程调试（Edge 需要 `--remote-debugging-port=9222`；Chrome 需要安装 Claude in Chrome 扩展）
- 或已安装 `agent-browser` CLI（`npm install -g agent-browser && agent-browser install`）

## 核心能力

### 1. 列出对话列表
获取 DeepSeek 侧边栏中的所有对话标题、ID 和时间。

### 2. 读取指定对话
根据对话标题或序号，提取完整对话内容（用户消息 + DeepSeek 回复）。

### 3. 搜索对话
在所有对话标题中搜索关键词，找到相关对话。

### 4. 读取最新对话
快速获取最近一次对话的完整内容。

## 使用方式

### 方式 A：Claude in Chrome（推荐）
直接使用已连接的 Chrome 浏览器，工具最完善。

### 方式 B：Edge Browser
使用 edge-browser 技能，需要 Edge 开启调试模式。

### 方式 C：Agent Browser CLI
纯命令行操作，适合无 GUI 场景。

---

## 工作流程

### 步骤 1：打开 DeepSeek 页面

导航到 `https://chat.deepseek.com/`，等待页面加载。

- **Claude in Chrome**: `navigate(url="https://chat.deepseek.com/", tabId=N)`
- **Edge**: 使用 `navigate` 工具
- **Agent Browser**: `agent-browser open https://chat.deepseek.com/ && agent-browser wait --load networkidle`

等待 3-5 秒确保页面完全加载（React 渲染 + 对话列表 API 请求完成）。

### 步骤 2：截图确认状态

先截图确认：
- 是否已登录（未登录会看到登录页面）
- 侧边栏对话列表是否已加载
- 页面是否有错误提示

如果未登录，提示用户先在浏览器中登录 DeepSeek，然后重试。

### 步骤 3：提取对话列表

执行以下 JavaScript 提取侧边栏对话列表：

```javascript
// DeepSeek 对话列表提取
(() => {
  const conversations = [];
  // DeepSeek 侧边栏对话项的常见选择器
  const selectors = [
    '.sidebar .conversation-item',
    '[class*="conversation"]',
    '[class*="chat-item"]',
    '[class*="session"]',
    'a[href^="/chat/"]',
    '[data-conversation-id]',
    'nav a[href*="/chat"]'
  ];

  let items = [];
  for (const sel of selectors) {
    try {
      const found = document.querySelectorAll(sel);
      if (found.length > 0) { items = Array.from(found); break; }
    } catch(e) {}
  }

  // 如果上述选择器都没匹配到，尝试从 React fiber 或全局状态获取
  if (items.length === 0) {
    // 尝试从所有链接中筛选
    const allLinks = document.querySelectorAll('a');
    items = Array.from(allLinks).filter(a => a.href && a.href.includes('/chat/'));
  }

  items.forEach((item, index) => {
    const titleEl = item.querySelector('[class*="title"], span, p, div');
    const title = titleEl ? titleEl.textContent.trim() : item.textContent.trim();
    const href = item.href || item.querySelector('a')?.href || '';
    const id = href.split('/').pop() || `item-${index}`;

    if (title && title.length > 0 && title.length < 200) {
      conversations.push({ index: index + 1, id, title });
    }
  });

  // 去重（按 title）
  const seen = new Set();
  const unique = conversations.filter(c => {
    if (seen.has(c.title)) return false;
    seen.add(c.title);
    return true;
  });

  return JSON.stringify(unique, null, 2);
})()
```

- **Claude in Chrome**: `javascript_tool(action="javascript_exec", text="...", tabId=N)`
- **Edge**: `execute_js(tabId, "...")`
- **Agent Browser**: `agent-browser evaluate "..."`

### 步骤 4：选择并打开对话

用户指定要读取的对话（按序号或标题关键词匹配）。执行 JS 点击对应对话：

```javascript
// 按序号点击对话
(() => {
  const index = __INDEX__; // 替换为目标序号（从1开始）
  const allLinks = Array.from(document.querySelectorAll('a'))
    .filter(a => a.href && a.href.includes('/chat/'));
  const target = allLinks[index - 1];
  if (target) {
    target.click();
    return JSON.stringify({ success: true, title: target.textContent.trim().substring(0, 100) });
  }
  return JSON.stringify({ success: false, error: `未找到第 ${index} 个对话` });
})()
```

或按标题关键词匹配：

```javascript
// 按关键词搜索并点击对话
(() => {
  const keyword = '__KEYWORD__'; // 替换为搜索关键词
  const allLinks = Array.from(document.querySelectorAll('a'))
    .filter(a => a.href && a.href.includes('/chat/'));
  const match = allLinks.find(a => a.textContent.toLowerCase().includes(keyword.toLowerCase()));
  if (match) {
    match.click();
    return JSON.stringify({ success: true, title: match.textContent.trim().substring(0, 100) });
  }
  return JSON.stringify({ success: false, error: `未找到包含 "${keyword}" 的对话` });
})()
```

点击后等待 2-3 秒让对话内容加载。

### 步骤 5：提取对话内容

执行 JS 提取对话区域的全部消息：

```javascript
// 提取 DeepSeek 对话内容
(() => {
  const messages = [];

  // DeepSeek 消息容器的常见选择器（按优先级尝试）
  const containerSelectors = [
    '[class*="message"]',
    '[class*="chat-message"]',
    '[class*="conversation-turn"]',
    '[class*="bubble"]',
    '[role="log"] [role="article"]',
    '.chat-container [class*="item"]',
    'main [class*="message"]'
  ];

  let messageElements = [];
  for (const sel of containerSelectors) {
    try {
      const found = document.querySelectorAll(sel);
      if (found.length >= 2) { messageElements = Array.from(found); break; }
    } catch(e) {}
  }

  // 回退：直接取 main 区域的所有大块文本
  if (messageElements.length === 0) {
    const main = document.querySelector('main, [role="main"], .chat-container, .conversation');
    if (main) {
      messageElements = Array.from(main.querySelectorAll('div[class*="message"], div[class*="turn"], div[class*="item"]'));
    }
  }

  // 最后回退：取所有可能的文本块
  if (messageElements.length === 0) {
    messageElements = Array.from(document.querySelectorAll('main *'))
      .filter(el => {
        const text = el.textContent.trim();
        return text.length > 20 && el.children.length === 0;
      });
  }

  messageElements.forEach((el, i) => {
    const text = el.textContent.trim();
    if (text.length > 5 && text.length < 50000) {
      // 判断是用户消息还是 AI 回复
      const isUser = el.className.toLowerCase().includes('user') ||
                     el.closest('[class*="user"]') !== null ||
                     (i % 2 === 0); // 偶数为用户消息（常见模式）
      messages.push({
        index: i + 1,
        role: isUser ? 'user' : 'deepseek',
        content: text
      });
    }
  });

  // 合并连续的相同角色消息
  const merged = [];
  messages.forEach(msg => {
    const last = merged[merged.length - 1];
    if (last && last.role === msg.role) {
      last.content += '\n\n' + msg.content;
    } else {
      merged.push(msg);
    }
  });

  return JSON.stringify({
    total: merged.length,
    messages: merged.map(m => ({
      role: m.role,
      content: m.content.substring(0, 3000) // 截断过长内容
    }))
  }, null, 2);
})()
```

### 步骤 6：格式化输出

将提取的 JSON 格式化为可读的对话文本：

```
=== DeepSeek 对话 ===
标题: {对话标题}
消息数: {total}

--- 用户 ---
{用户消息}

--- DeepSeek ---
{DeepSeek 回复}

--- 用户 ---
{下一条用户消息}

--- DeepSeek ---
{下一条 DeepSeek 回复}
```

---

## 快速场景

### 场景 1：列出我的 DeepSeek 对话
```
用户: "列出我的 DeepSeek 对话"
→ 执行步骤 1-3，展示对话列表
```

### 场景 2：读取最新对话
```
用户: "读取我 DeepSeek 里最新的对话"
→ 执行步骤 1-6，index=1
```

### 场景 3：按关键词搜索对话
```
用户: "在 DeepSeek 里找到关于 React 的对话"
→ 执行步骤 1-3，在对话列表中筛选，执行步骤 4-6 打开匹配的对话
```

### 场景 4：读取指定序号的对话
```
用户: "读取 DeepSeek 第 3 个对话"
→ 执行步骤 1-3，执行步骤 4-6（index=3）
```

---

## DeepSeek 页面结构参考

```
chat.deepseek.com
├── 侧边栏 (.sidebar / nav)
│   ├── 新建对话按钮
│   ├── 对话列表
│   │   ├── 对话项 1 (a href="/chat/xxx")
│   │   ├── 对话项 2
│   │   └── ...
│   └── 设置/用户信息
└── 主区域 (main)
    ├── 对话标题
    ├── 消息列表
    │   ├── 用户消息 (.user / [class*="user"])
    │   ├── AI 回复 (.assistant / [class*="assistant"])
    │   └── ...
    └── 输入框
```

DeepSeek 使用 React 构建，class 名经过 hash 处理，因此选择器需要使用属性/结构匹配而非精确 class 名。上述 JS 代码已覆盖多种回退策略。

---

## 故障排查

| 问题 | 解决方案 |
|------|---------|
| 页面显示登录界面 | 提示用户先在浏览器中登录 chat.deepseek.com |
| 对话列表为空 | 等待更长时间（5-10s），或刷新页面 |
| 对话内容提取不全 | DeepSeek 可能使用了虚拟滚动，需要先滚动到底部加载全部内容 |
| 提取到乱码 | 检查是否有 Markdown/代码块未被正确解析 |
| 点击对话无反应 | 使用 `window.location` 直接跳转 URL 替代 click |

### 处理虚拟滚动（对话很长时）

```javascript
// 滚动到底部加载所有消息
(async () => {
  const main = document.querySelector('main, [role="main"], .chat-container');
  if (!main) return 'no main area found';
  let lastHeight = 0;
  for (let i = 0; i < 10; i++) {
    main.scrollTop = main.scrollHeight;
    await new Promise(r => setTimeout(r, 500));
    if (main.scrollHeight === lastHeight) break;
    lastHeight = main.scrollHeight;
  }
  return `scrolled to height: ${main.scrollHeight}`;
})()
```

## 技术说明

- 此技能不依赖 DeepSeek API，通过浏览器 DOM 提取数据
- 用户必须已在浏览器中登录 DeepSeek
- 提取的内容仅在本会话中使用，不会上传到任何服务器
- 页面结构可能随 DeepSeek 更新而变化，如提取失败需调整选择器
