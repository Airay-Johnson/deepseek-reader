# DeepSeek Reader

> 从 DeepSeek 网页版自动提取对话历史和内容。零 API Key，纯浏览器自动化。

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## 功能

| 功能 | 说明 |
|------|------|
| 📋 列出对话 | 提取 DeepSeek 侧边栏中所有对话标题和 ID |
| 📖 读取对话 | 按序号提取完整对话内容（用户 + AI 消息） |
| 🔍 搜索对话 | 在标题中匹配关键词 |
| 🤖 Cowork 集成 | 作为 Skill 在 Cowork 中直接使用 |

## 架构

```
Claude (VM) ──JSON──> Windows Agent ──CDP──> Edge Browser ──> chat.deepseek.com
     │                    │                        │
     │              sys-cmd-*.json              WebSocket CDP
     │                    │                        │
     └──<── sys-result.json <──<── JS eval <──────┘
```

## 前置条件

1. **Windows** + **Microsoft Edge**
2. **Windows Agent** 在运行（见 `agent.ps1`）
3. 已在 Edge 中登录 [chat.deepseek.com](https://chat.deepseek.com/)

## 快速开始

### 1. 启动 Edge 调试模式 + Agent

```batch
setup-deepseek-bridge.bat
```

这会自动：
- 重启 Windows Agent
- 以调试模式 (CDP port 9222) 启动 Edge
- 打开 DeepSeek 页面

### 2. 列出对话

```bash
node deepseek_bridge.cjs list
```

结果写入 `deepseek_result.json`：

```json
{
  "isLogin": true,
  "count": 99,
  "conversations": [
    { "index": 1, "id": "xxx", "title": "Claude无法读取DeepSeek API" },
    ...
  ]
}
```

### 3. 读取对话

```bash
node deepseek_bridge.cjs read 1    # 读第 1 个对话
node deepseek_bridge.cjs read 17   # 读第 17 个对话
```

### 4. 在 Cowork 中使用

安装 `deepseek-reader` 技能后，直接在 Cowork 中说：

> "列出我的 DeepSeek 对话"
> "读取 DeepSeek 第 3 个对话"

## 移植到自己的设备

### 方式一：下载 Release（推荐）

从 [Releases](https://github.com/Airay-Johnson/deepseek-reader/releases) 下载 `deepseek-reader-v1.0.0.zip`，解压后：

```batch
setup-deepseek-bridge.bat       # 一键启动
node deepseek_bridge.cjs list  # 列出对话
```

### 方式二：克隆仓库

```bash
git clone https://github.com/Airay-Johnson/deepseek-reader.git
cd deepseek-reader
setup-deepseek-bridge.bat
```

### 依赖

| 依赖 | 说明 | 安装方式 |
|------|------|---------|
| Node.js 18+ | 运行桥接脚本 | `winget install OpenJS.NodeJS` |
| Microsoft Edge | 浏览器自动化 | Windows 自带 |
| DeepSeek 账号 | 登录 chat.deepseek.com | 免费注册 |

### 目录结构

```
deepseek-reader/
├── deepseek_bridge.cjs       # 核心：CDP 客户端（零依赖）
├── setup-deepseek-bridge.bat # 一键启动
├── agent.ps1                 # Windows Agent（后台轮询）
├── edge-auto-start.ps1       # Edge 调试模式启动
├── push-standalone.ps1       # GitHub 自动推送
├── SKILL.md                  # Cowork 技能定义
├── README.md                 # 本文件
└── LICENSE                   # MIT
```

## 技术细节

- **CDP 协议**: 通过 Edge DevTools Protocol 执行 JavaScript 提取 DOM 数据
- **零依赖**: `deepseek_bridge.cjs` 仅使用 Node.js 内置模块 (http, fs, path)
- **Agent**: PowerShell 脚本，轮询 `sys-cmd-*.json` 文件执行命令
- **安全性**: CDP 仅监听 `127.0.0.1:9222`，不暴露到网络

## License

MIT
