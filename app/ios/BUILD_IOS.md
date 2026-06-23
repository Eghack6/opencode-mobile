# OpenCode Mobile — iOS 构建指南

## 前提条件

- **macOS** 电脑（iOS 构建只能在 macOS 上进行）
- **Xcode 15+**（从 App Store 安装）
- **CocoaPods**（`sudo gem install cocoapods`）
- **Flutter SDK 3.16+**（`flutter --version` 确认）
- **Apple Developer 账号**（真机部署需要，模拟器不需要）

## 第一步：在你的项目中启用 iOS 平台

由于你的项目是纯 Flutter，Dart 代码已经跨平台。只需要在项目根目录运行：

```bash
cd app   # 进入你的 Flutter 项目目录

# 让 Flutter 自动生成 iOS 工程骨架
flutter create --platforms=ios .
```

这会在 `ios/` 目录下生成完整的 Xcode 项目骨架。

## 第二步：替换 Info.plist

用 `ios/Runner/Info.plist` 替换 Flutter 自动生成的版本，关键配置：

- `NSAllowsLocalNetworking: true` — 允许连接本地 opencode server
- `NSAllowsArbitraryLoads: true` — 允许 HTTP（SSH 隧道 / Termux 场景）
- `keychain-access-groups` — flutter_secure_storage 需要

## 第三步：更新 Podfile

用本目录下的 `ios/Podfile` 替换自动生成的版本，它包含：

- `platform :ios, '14.0'` — 最低 iOS 14
- `libssh2` pod — dartssh2 的底层依赖

## 第四步：安装依赖

```bash
cd ios
pod install
cd ..
flutter pub get
```

## 第五步：配置 Xcode 签名

1. 用 Xcode 打开项目：
   ```bash
   open ios/Runner.xcworkspace
   ```
2. 选择 **Runner** target → **Signing & Capabilities**
3. 勾选 **Automatically manage signing**
4. 选择你的 **Team**（Apple Developer 账号）
5. 修改 **Bundle Identifier** 为唯一值，如 `com.yourname.opencode-mobile`

## 第六步：构建 & 运行

### 模拟器
```bash
flutter run -d iPhone
```

### 真机
```bash
flutter run -d <你的设备ID>
```

### 打包 IPA
```bash
flutter build ios --release
```

产物位置：`build/ios/iphoneos/Runner.app`

要导出 IPA，用 Xcode：
1. `open ios/Runner.xcworkspace`
2. Product → Archive
3. Distribute App → Development / Ad Hoc / App Store

## 依赖兼容性检查

| 依赖 | iOS 支持 | 备注 |
|------|---------|------|
| `http` | ✅ | 纯 Dart，全平台 |
| `provider` | ✅ | 纯 Dart |
| `shared_preferences` | ✅ | 使用 NSUserDefaults |
| `flutter_secure_storage` | ✅ | 使用 iOS Keychain |
| `dartssh2` | ✅ | 依赖 libssh2 (C 库) |
| `flutter_highlight` | ✅ | 纯 Dart |
| `url_launcher` | ✅ | 使用 iOS URL Scheme |
| `scrollable_positioned_list` | ✅ | 纯 Dart |
| `web_socket_channel` | ✅ | 纯 Dart |

## 已知差异（Android vs iOS）

| 项目 | Android | iOS |
|------|---------|-----|
| Termux 桥接 | ✅ 支持（本机运行 opencode） | ❌ iOS 无 Termux |
| SSH 隧道 | ✅ | ✅ |
| 本机连接 | ✅ localhost:4096 | ✅ localhost:4096（模拟器）|
| 安全存储 | Android Keystore | iOS Keychain |
| 后台运行 | 较宽松 | iOS 会挂起后台进程 |

### 关于 Termux

iOS 上无法使用 Termux（Apple 不允许），所以 **方式一（本机 Termux）在 iOS 上不可用**。
iOS 用户应使用：
- **方式二**：局域网 PC
- **方式三**：远程服务器 + SSH 隧道
- **方式四**：内网穿透

## iOS 特有优化建议

1. **后台保活**：iOS 会挂起 SSE 连接。建议在 `WidgetsBindingObserver` 中监听生命周期，进入后台时断开 SSE，恢复时重连。

2. **网络安全描述**：在 `Info.plist` 中加入 `NSLocalNetworkUsageDescription`，说明为何需要局域网访问：
   ```xml
   <key>NSLocalNetworkUsageDescription</key>
   <string>OpenCode Mobile 需要访问本地网络以连接 opencode 服务器</string>
   ```

3. **最低版本**：iOS 14.0+ 支持所有需要的 API。
