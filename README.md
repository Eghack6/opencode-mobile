# OpenCode Mobile

**你手机上的全能 AI 管家 —— 能聊天问答、能帮你管电脑、管服务器、管文件，数据全在你自己手里。**

OpenCode Mobile 是一款 Android 客户端，通过加密隧道或本地连接接入任意 `opencode serve` 实例，将一个功能完整的 AI 助手带到你的手机上。它不只聊天 —— 还能帮你在远程设备上执行命令、管理文件、运行脚本，并且支持自由切换多种 AI 模型。

---

## 为什么需要它？

> 你用过 ChatGPT 吧？想象一下，如果 AI **不光能跟你聊天**，还能**直接帮你操作你的电脑和服务器** —— 比如找文件、整理文件夹、查服务器状态、跑脚本 —— 而且这一切都**在你手机上完成**，**数据不经过任何第三方**。

### 核心特性

| | |
|---|---|
| 🤖 **全能 AI 助手** | 日常问答、方案讨论、内容创作、翻译润色 —— 什么都能聊 |
| 📂 **远程文件管理** | 让 AI 帮你在远程电脑/服务器上查找、阅读、整理文件 |
| ⚡ **远程命令执行** | 查服务器状态、跑脚本、看日志 —— 一句话搞定 |
| 🔀 **多模型自由切换** | 一个 App 接入多种 AI 模型，不满意这个换那个 |
| 🔒 **SSH 加密隧道** | 端到端加密，公共 WiFi 下也安全 |
| 🏠 **完全自建** | 服务跑在你自己的设备上，聊天记录不上传任何第三方 |
| 📱 **手机随时随地** | 通勤、排队、躺床上 —— 碎片时间全都能利用 |
| 💰 **免费开源** | App 免费、服务端开源，无需订阅 |

### 真实使用场景

- **出门在外，电脑里的文件急用** —— 掏出手机跟 AI 说："帮我在桌面的项目文件夹里找到那个报价单"，AI 直接帮你找到并告诉你内容。
- **半夜服务器报警，但你不在电脑前** —— 躺在床上打开手机："帮我检查一下服务器磁盘空间和内存"，AI 跑命令、给你报告结果。
- **排队等咖啡，突然想讨论一个方案** —— 打开手机跟 AI 聊，它认真分析、给出建议，你边喝咖啡边看完了。
- **想整理下载文件夹** —— "帮我看看有哪些超过 30 天没动过的文件"，AI 帮你扫描列出来，你决定删还是留。
- **不确定哪个 AI 更好** —— 同一个问题切换不同模型对比回答，一个 App 全搞定。

---

## 快速开始

### 前提

在任意设备上安装并启动 `opencode serve`：

```bash
npm install -g opencode-ai
opencode serve --port 4096
```

> 详细配置和 API Key 设置请参考 [opencode 项目文档](https://github.com/nicepkg/opencode)。

根据你的实际情况，选择以下任一连接方式：

---

### 方式一：安卓本机（Termux）

> **最适合**：不想依赖其他设备、希望完全离线使用的用户。
> AI 服务直接跑在手机上，流量不出设备。

**Step 1：安装 Termux**

从 [F-Droid](https://f-droid.org/packages/com.termux/) 下载 Termux（Google Play 版本已过时，请勿使用）。

**Step 2：在 Termux 中安装 opencode**

打开 Termux，依次运行：

```bash
# 更新包管理器并安装依赖
pkg update -y && pkg upgrade -y
pkg install -y nodejs-lts git curl openssh

# 安装 opencode
npm install -g opencode-ai
```

或者使用项目内的一键脚本：

```bash
# 将本项目 termux-bridge 目录传到手机上后
bash setup_termux.sh
```

**Step 3：启动服务**

```bash
opencode serve --port 4096 --hostname 127.0.0.1
```

或使用项目内的启动脚本：

```bash
bash start_opencode.sh
```

**Step 4：连接 App**

打开 OpenCode Mobile → 首次启动选择 **「本机」** → 按引导完成 → Settings 中输入：

```
http://localhost:4096
```

点击 **连接** 即可开始使用。

---

### 方式二：局域网 PC

> **最适合**：家里有电脑长期开着、想在同一网络下用手机访问的用户。
> 服务跑在电脑上，手机通过局域网直连，速度快、延迟低。

**Step 1：在电脑上启动服务**

```bash
# 注意 hostname 设为 0.0.0.0 以允许局域网访问
opencode serve --port 4096 --hostname 0.0.0.0 --cors "*"
```

**Step 2：查看电脑 IP**

- **Windows**：打开 CMD 运行 `ipconfig`，找到 `IPv4 地址`（如 `192.168.1.100`）
- **macOS**：打开终端运行 `ifconfig | grep inet`
- **Linux**：运行 `ip addr` 或 `hostname -I`

**Step 3：连接 App**

确保手机和电脑在同一 WiFi 下，打开 OpenCode Mobile → Settings 中输入：

```
http://192.168.1.100:4096
```

（替换为你的电脑实际 IP）点击 **连接**。

> **提示**：如果连接失败，请检查电脑防火墙是否放行了 4096 端口。

---

### 方式三：远程服务器（SSH 隧道）

> **最适合**：有云服务器 / VPS 的用户，或在外出时需要访问家中电脑的用户。
> 所有流量通过 SSH 加密隧道传输，安全可靠。

**Step 1：在服务器上启动服务**

```bash
# 绑定到 localhost 即可，SSH 隧道会做端口转发
opencode serve --port 4096 --hostname 127.0.0.1
```

> 确保服务器已开启 SSH 服务（默认端口 22）。

**Step 2：配置 App**

打开 OpenCode Mobile → Settings → 开启 **「SSH 隧道」** 开关 → 填写：

| 字段 | 说明 | 示例 |
|------|------|------|
| SSH 主机 | 服务器 IP 或域名 | `your-server.com` 或 `1.2.3.4` |
| 端口 | SSH 端口 | `22` |
| 用户名 | SSH 登录用户名 | `root` |
| 密码 / 私钥 | SSH 认证凭据 | 密码或 PEM 格式私钥 |

> **快速填写**：在 `快速填写` 输入框中输入 `user@host:22` 格式，一键自动填充。

点击 **通过 SSH 连接**，App 会自动建立加密隧道并连接服务。

**安全说明**：
- SSH 凭据通过 `flutter_secure_storage` 加密存储
- 密码和私钥字段默认隐藏，点击眼睛图标可查看
- 所有 API 流量经 SSH 隧道端到端加密，即使服务器在公网也安全

---

### 方式四：内网穿透 + SSH 隧道

> **最适合**：电脑在家里/公司内网、没有公网 IP、也没有云服务器的用户。
> 通过内网穿透工具将本机暴露到公网，再通过 SSH 隧道安全连接。

这种方式的核心思路是：**用内网穿透把你的电脑变成一个"远程服务器"**，然后按方式三连接。

#### 方案 A：FRP（推荐，自建可控）

**Step 1：准备一台有公网 IP 的中转服务器**（最便宜的 VPS 即可）

**Step 2：在 VPS 上部署 frps（服务端）**

```bash
# frps.toml
bindPort = 7000
```

```bash
./frps -c frps.toml
```

**Step 3：在家里电脑上部署 frpc（客户端）**

```bash
# frpc.toml
serverAddr = "你的VPS公网IP"
serverPort = 7000

[[proxies]]
name = "opencode"
type = "tcp"
localIP = "127.0.0.1"
localPort = 4096
remotePort = 4096

# 如果 VPS 也开了 SSH，可以把 SSH 也穿透出来
[[proxies]]
name = "ssh"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = 6000
```

```bash
# 在家里电脑上启动 opencode
opencode serve --port 4096 --hostname 127.0.0.1

# 同时启动 frpc
./frpc -c frpc.toml
```

**Step 4：手机连接**

按 **方式三** 配置 SSH 隧道，主机填 VPS 的公网 IP，端口填穿透后的 SSH 端口（如 6000）。

> 如果没有单独的 SSH 穿透，也可以直接穿透 opencode 端口，然后用直连模式（Settings 中填 `http://VPS公网IP:4096`），但这样没有加密。建议始终穿透 SSH 并使用隧道模式。

#### 方案 B：Tailscale / ZeroTier（最简单，零配置组网）

**Step 1：在家里电脑和手机上都安装 [Tailscale](https://tailscale.com/) 或 [ZeroTier](https://zerotier.com/)**

**Step 2：两台设备登录同一账号，自动组网**

**Step 3：在家里电脑上启动服务**

```bash
opencode serve --port 4096 --hostname 0.0.0.0 --cors "*"
```

**Step 4：手机连接**

打开 OpenCode Mobile → Settings 中输入 Tailscale 分配的内网 IP：

```
http://100.x.x.x:4096
```

> Tailscale/ZeroTier 自带加密，无需额外配置 SSH 隧道，使用体验和局域网直连完全一致。

#### 方案 C：Cloudflare Tunnel（免费、无需公网 IP）

**Step 1：安装 [cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)**

**Step 2：创建隧道**

```bash
cloudflared tunnel --url http://localhost:4096
```

会生成一个类似 `https://xxx.trycloudflare.com` 的公网地址。

**Step 3：手机直连**

Settings 中输入生成的公网地址即可。

> **注意**：Cloudflare Tunnel 免费方案每次启动地址会变；如需固定域名，需配置 Cloudflare 账号和 DNS。

---

## 架构

```
┌────────────────────────────┐   加密隧道 / 本地       ┌──────────────────────┐
│      OpenCode Mobile       │ ◄─────────────────────► │    opencode serve    │
│       (Flutter APK)        │    SSH / Localhost       │   (任意终端/服务器)    │
│                            │                          │                      │
│  ┌──────────────────────┐  │                          │  - AI 对话 & 问答    │
│  │  Chat UI             │  │                          │  - 文件操作           │
│  │  Session 管理        │  │                          │  - Tool 调用          │
│  │  代码高亮 / Markdown │  │                          │  - 命令执行           │
│  │  SSE 流式输出        │  │                          │  - 多 Provider 模型   │
│  └──────────────────────┘  │                          └──────────────────────┘
└────────────────────────────┘
```

App 本身不含后端逻辑，是一个纯前端客户端。所有智能能力由 `opencode serve` 提供，两者之间通过 REST + SSE (Server-Sent Events) 通信。

远程连接时，所有流量经过 **SSH 加密隧道**传输，确保数据安全。

### 连接方式对比

| | 本机 (Termux) | 局域网 PC | 远程服务器 (SSH) | 内网穿透 |
|---|---|---|---|---|
| **难度** | 简单 | 简单 | 中等 | 中等 |
| **是否需要额外设备** | 否 | 同一 WiFi 下的电脑 | 云服务器 / VPS | 穿透工具 + 可选中转服务器 |
| **是否可离线** | 是 | 否（需局域网） | 否 | 否 |
| **外出可用** | 是 | 否 | 是 | 是 |
| **安全性** | 最高（不出设备） | 中（局域网） | 高（SSH 加密） | 取决于方案 |

---

## 构建

### 环境要求

- **Flutter SDK** (Dart SDK ^3.2.0)
- **Android SDK**
- **JDK 17**

### 构建 APK

```bash
cd app
flutter build apk --release
```

产物位置：`app/build/app/outputs/flutter-apk/app-release.apk`

> 本地具体路径配置见 `BUILD.local.md`（已被 gitignore）。

---

## 项目结构

```
opencode-mobile-clean/
├── app/                              # Flutter 主项目
│   ├── lib/
│   │   ├── main.dart                 # 入口
│   │   ├── app.dart                  # App Widget + Material 3 主题
│   │   ├── models/
│   │   │   ├── session.dart          # Session 数据模型
│   │   │   ├── message.dart          # Message 数据模型
│   │   │   └── part.dart             # Part (text/code/tool/reasoning)
│   │   ├── providers/
│   │   │   └── chat_provider.dart    # 全局状态管理 (Provider)
│   │   ├── screens/
│   │   │   ├── chat_screen.dart      # 主聊天界面 + 引导页
│   │   │   ├── sessions_screen.dart  # 会话列表 + 搜索
│   │   │   └── settings_screen.dart  # 连接设置 + 主题
│   │   ├── services/
│   │   │   ├── api_service.dart      # REST API 客户端
│   │   │   ├── event_service.dart    # SSE 事件流
│   │   │   ├── ssh_tunnel_service.dart # SSH 隧道管理
│   │   │   ├── termux_bridge.dart    # Termux 本地桥接
│   │   │   └── theme_provider.dart   # 主题管理
│   │   └── widgets/
│   │       ├── message_bubble.dart   # 消息气泡 + Markdown 渲染
│   │       ├── code_block.dart       # 语法高亮代码块
│   │       ├── reason_block.dart     # 推理过程折叠块
│   │       ├── scroll_wheel.dart     # 会话导航滚轮
│   │       ├── thinking_indicator.dart # 思考中动画
│   │       └── toast.dart            # Toast 通知
│   ├── android/                      # Android 工程配置
│   └── pubspec.yaml                  # 依赖配置
├── termux-bridge/                    # Termux 辅助脚本
│   ├── setup_termux.sh              # 一键安装 opencode 到 Termux
│   └── start_opencode.sh            # 启动 opencode serve
└── README.md
```

---

## 技术栈

| 层 | 技术 |
|----|------|
| UI 框架 | Flutter + Material 3 |
| 状态管理 | Provider (ChangeNotifier) |
| 隧道通信 | SSH (`dartssh2`) |
| API 通信 | HTTP REST + Server-Sent Events (流式输出) |
| 凭据存储 | `flutter_secure_storage` (加密存储) |
| 代码高亮 | `highlight` + `flutter_highlight` |
| 后端 | `opencode serve` (独立运行，非嵌入) |

---

## API 对接

| 功能 | API |
|------|-----|
| 健康检查 | `GET /global/health` |
| 列出会话 | `GET /session` |
| 创建会话 | `POST /session` |
| 获取会话 | `GET /session/:id` |
| 删除会话 | `DELETE /session/:id` |
| 发送消息 | `POST /session/:id/message` |
| 获取消息 | `GET /session/:id/message` |
| 实时事件 | `GET /global/event` (SSE) |
| 中止生成 | `POST /session/:id/abort` |
| 获取模型 | `GET /provider` |

---

## 开源协议

本项目基于 [GNU General Public License v3.0](LICENSE) 开源。
