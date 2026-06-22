# OpenCode Mobile

Android 客户端，通过 SSH 加密隧道或本地回环连接任意 `opencode serve` 实例，将 AI 编程助手带到手机上。

## 构建

需要配置 **Android SDK**、**JDK 17**、**Flutter SDK**。

> 本地具体路径配置见 `BUILD.local.md`（已被 gitignore）。

## 架构

```
┌────────────────────────────┐   加密隧道 / 本地       ┌──────────────────────┐
│      OpenCode Mobile       │ ◄─────────────────────► │    opencode serve    │
│       (Flutter APK)        │    SSH / Localhost       │   (任意终端/服务器)    │
│                            │                          │                      │
│  ┌──────────────────────┐  │                          │  - AI 代码分析        │
│  │  Chat UI             │  │                          │  - 文件操作           │
│  │  Session 管理        │  │                          │  - Tool 调用          │
│  │  代码高亮 / Markdown │  │                          │  - LSP 支持           │
│  │  SSE 流式输出        │  │                          │  - 多 Provider 模型   │
│  └──────────────────────┘  │                          └──────────────────────┘
└────────────────────────────┘
```

App 本身不含服务端，所有通信均经过 **SSH 加密隧道**或本地回环，确保数据安全。

## 连接方式

### 方式一：SSH 安全隧道（推荐）

通过 SSH 隧道加密所有流量，将远程服务器或局域网 PC 的 `opencode serve` 端口安全地转发到手机本地：

```bash
# PC 端启动 opencode serve
opencode serve --port 4096 --hostname 127.0.0.1

# 手机端 Settings → SSH Tunnel 配置
# 主机：PC 的 IP 或域名
# 端口：22
# 用户名：SSH 登录名
# 密码或私钥
```

App 在手机本地建立 SSH 隧道，将远程服务映射到 `http://localhost:xxxx`，端到端加密，安全可靠。

### 方式二：Termux 本地运行

在同一台 Android 手机上通过 Termux 运行服务端，流量不出设备：

```bash
cd termux-bridge
bash setup_termux.sh
bash start_opencode.sh
```

手机端 Settings → 输入 `http://localhost:4096` → Save & Connect

## 项目结构

```
opencode-mobile/
├── app/                          # Flutter 主项目
│   ├── lib/
│   │   ├── main.dart             # 入口
│   │   ├── app.dart              # App Widget + 主题
│   │   ├── models/
│   │   │   ├── session.dart      # Session 数据模型
│   │   │   ├── message.dart      # Message 数据模型
│   │   │   └── part.dart        # Part (text/code/tool/reasoning)
│   │   ├── providers/
│   │   │   └── chat_provider.dart # 全局状态 (Provider)
│   │   ├── screens/
│   │   │   ├── chat_screen.dart  # 主聊天界面
│   │   │   ├── sessions_screen.dart # 会话列表
│   │   │   └── settings_screen.dart # 连接设置
│   │   ├── services/
│   │   │   ├── api_service.dart  # REST API 客户端
│   │   │   ├── event_service.dart # SSE 事件流
│   │   │   ├── ssh_tunnel_service.dart # SSH 隧道
│   │   │   └── theme_provider.dart
│   │   └── widgets/
│   │       ├── message_bubble.dart # 消息气泡 + Markdown 渲染
│   │       ├── code_block.dart    # 代码块 + 复制
│   │       ├── reason_block.dart  # 推理折叠块
│   │       └── thinking_indicator.dart # 生成中动画
│   ├── android/                  # Android 工程配置
│   └── pubspec.yaml
├── termux-bridge/                # Termux 辅助脚本
│   ├── setup_termux.sh           # 一键安装 opencode 到 Termux
│   └── start_opencode.sh         # 启动 opencode serve
└── README.md
```

## 构建 APK

```bash
cd app
flutter build apk --release
```

产物：`app/build/app/outputs/flutter-apk/app-release.apk`

## 技术栈

| 层 | 技术 |
|----|------|
| UI 框架 | Flutter + Material 3 |
| 状态管理 | Provider |
| 隧道通信 | SSH (dartssh2) |
| API 通信 | HTTP (REST) + Server-Sent Events (流式) |
| 后端 | opencode serve (独立运行，非嵌入) |

## API 对接

| 功能 | API |
|------|-----|
| 健康检查 | `GET /global/health` |
| 列出会话 | `GET /session` |
| 创建会话 | `POST /session` |
| 发送消息 | `POST /session/:id/message` |
| 获取消息 | `GET /session/:id/message` |
| 实时事件 | `GET /global/event` (SSE) |
| 中止生成 | `POST /session/:id/abort` |
| 获取模型 | `GET /provider` |
