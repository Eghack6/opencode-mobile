# OpenCode Mobile

Android 客户端，通过 HTTP/SSE 连接任意 `opencode serve` 实例，将 AI 编程助手带到手机上。

## 构建

需要配置 **Android SDK**、**JDK 17**、**Flutter SDK**。

> 本地具体路径配置见 `BUILD.local.md`（已被 gitignore）。

## 架构

```
┌────────────────────────────┐        HTTP / SSE         ┌──────────────────────┐
│      OpenCode Mobile       │ ◄────────────────────────► │    opencode serve    │
│       (Flutter APK)        │       任意 URL:4096        │   (任意终端/服务器)    │
│                            │                            │                      │
│  ┌──────────────────────┐  │                            │  - AI 代码分析        │
│  │  Chat UI             │  │                            │  - 文件操作           │
│  │  Session 管理        │  │                            │  - Tool 调用          │
│  │  代码高亮 / Markdown │  │                            │  - LSP 支持           │
│  │  SSE 流式输出        │  │                            │  - 多 Provider 模型   │
│  └──────────────────────┘  │                            └──────────────────────┘
└────────────────────────────┘
```

App 本身不含服务端，只需一个 URL 即可连接到任何运行的 `opencode serve` 实例——本地 Termux、局域网 PC、或远程服务器。

## 连接方式

### 方式一：远程服务器（最简单）

在任意机器上启动 opencode serve，手机输入 URL 即可：

```bash
opencode serve --port 4096 --hostname 0.0.0.0 --cors "*"
```

手机端 Settings → 输入 `http://<服务器IP>:4096` → Save & Connect

### 方式二：Termux 本地运行

在同一台 Android 手机上通过 Termux 运行服务端：

```bash
# 安装
cd termux-bridge
bash setup_termux.sh

# 启动
bash start_opencode.sh
# 或手动: opencode serve --port 4096 --hostname 127.0.0.1
```

手机端 Settings → 输入 `http://localhost:4096` → Save & Connect

### 方式三：局域网 PC

```bash
# PC 端
opencode serve --port 4096 --hostname 0.0.0.0 --cors "*"

# 手机端 Settings 输入 PC 的局域网 IP
# http://192.168.x.x:4096
```

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
│   │   │   └── termux_bridge.dart # Termux MethodChannel 桥接（原生端未实现）
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

## 已知问题

### 1. TermuxBridge 原生端未实现

`termux_bridge.dart` 通过 MethodChannel `com.opencode.mobile/native` 调用原生方法（检查 Termux 安装状态、执行 Termux 命令等），但 Android 端 `MainActivity.kt` 未注册该 channel，所有调用均返回 false/unknown。Termux 集成需手动在 Termux 中运行脚本，无法从 App 内自动完成。

### 2. SSE 解析脆弱

`event_service.dart` 假设每个 SSE 事件只有单行 `data:`，但 SSE 规范允许多行 `data:` 字段拼接。若服务端发送多行 data，当前实现会覆盖而非拼接内容。

### 3. 首次启动无引导

App 启动后直接进入 ChatScreen，未连接服务器时显示 Setup Guide，但没有自动发现或引导用户配置服务端地址的流程。
