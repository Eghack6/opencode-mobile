import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app.dart';
import '../models/connection_config.dart';
import '../providers/chat_provider.dart';
import '../services/ssh_tunnel_service.dart';
import '../services/theme_provider.dart';
import '../services/update_service.dart';
import '../widgets/toast.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _urlController;
  late TextEditingController _sshHostController;
  late TextEditingController _sshPortController;
  late TextEditingController _sshUsernameController;
  late TextEditingController _sshPasswordController;
  late TextEditingController _sshKeyController;
  late TextEditingController _sshRemoteHostController;
  late TextEditingController _sshRemotePortController;
  late TextEditingController _sshQuickFillController;
  late TextEditingController _configNameController;
  bool _testing = false;
  bool _useSsh = false;
  bool _obscurePassword = true;
  bool _obscureKey = true;
  bool _checkingUpdate = false;
  String? _appVersion;
  ThemeMode _themeMode = ThemeMode.system;
  List<ConnectionConfig> _savedConfigs = [];

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
    _sshHostController = TextEditingController();
    _sshPortController = TextEditingController(text: '22');
    _sshUsernameController = TextEditingController();
    _sshPasswordController = TextEditingController();
    _sshKeyController = TextEditingController();
    _sshRemoteHostController = TextEditingController(text: 'localhost');
    _sshRemotePortController = TextEditingController(text: '4096');
    _sshQuickFillController = TextEditingController();
    _configNameController = TextEditingController();
    _loadConfig();
    _loadSavedConfigs();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final pkg = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = pkg.version);
  }

  Future<void> _checkUpdate() async {
    setState(() => _checkingUpdate = true);
    final service = UpdateService();
    final info = await service.checkForUpdate();
    if (!mounted) return;
    setState(() => _checkingUpdate = false);

    if (info.error != null) {
      showToast(context, info.error!, bgColor: Colors.orange);
      return;
    }

    if (!info.hasUpdate) {
      showToast(context, '当前已是最新版本 (v${info.currentVersion})',
          bgColor: Colors.green);
      return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('发现新版本 v${info.latestVersion}'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前版本: v${info.currentVersion}'),
              const SizedBox(height: 8),
              if (info.releaseNotes != null && info.releaseNotes!.isNotEmpty)
                Text(
                  info.releaseNotes!,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 10,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后再说'),
          ),
          if (info.downloadUrl != null)
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                launchUrl(Uri.parse(info.downloadUrl!),
                    mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.download, size: 18),
              label: const Text('下载 APK'),
            ),
        ],
      ),
    );
  }

  Future<void> _loadConfig() async {
    final provider = context.read<ChatProvider>();
    _useSsh = provider.useSshTunnel;
    _urlController.text = provider.serverUrl;

    final config = await SshConfig.load();
    _sshHostController.text = config.host;
    _sshPortController.text = config.port.toString();
    _sshUsernameController.text = config.username;
    _sshPasswordController.text = config.password ?? '';
    _sshKeyController.text = config.privateKey ?? '';
    _sshRemoteHostController.text = config.remoteHost;
    _sshRemotePortController.text = config.remotePort.toString();

    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt('theme_mode') ?? 0;
    _themeMode = ThemeMode.values[themeIndex];

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _urlController.dispose();
    _sshHostController.dispose();
    _sshPortController.dispose();
    _sshUsernameController.dispose();
    _sshPasswordController.dispose();
    _sshKeyController.dispose();
    _sshRemoteHostController.dispose();
    _sshRemotePortController.dispose();
    _sshQuickFillController.dispose();
    _configNameController.dispose();
    super.dispose();
  }

  SshConfig _buildSshConfig() => SshConfig(
        host: _sshHostController.text.trim(),
        port: int.tryParse(_sshPortController.text.trim()) ?? 22,
        username: _sshUsernameController.text.trim(),
        password: _sshPasswordController.text.isNotEmpty
            ? _sshPasswordController.text
            : null,
        privateKey:
            _sshKeyController.text.isNotEmpty ? _sshKeyController.text : null,
        remoteHost: _sshRemoteHostController.text.trim().isNotEmpty
            ? _sshRemoteHostController.text.trim()
            : 'localhost',
        remotePort:
            int.tryParse(_sshRemotePortController.text.trim()) ?? 4096,
      );

  void _applyQuickFill() {
    final input = _sshQuickFillController.text.trim();
    if (input.isEmpty) return;
    final parsed = SshConfig.parse(input);
    setState(() {
      _sshHostController.text = parsed.host;
      _sshPortController.text = parsed.port.toString();
      _sshUsernameController.text = parsed.username;
      _sshQuickFillController.clear();
    });
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', mode.index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<ChatProvider>();
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        gradient: isDark ? GlassColors.darkBgGradient : GlassColors.lightBgGradient,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                color: isDark
                    ? Colors.black.withOpacity(0.2)
                    : Colors.white.withOpacity(0.3),
              ),
            ),
          ),
          title: const Text('设置'),
          centerTitle: true,
        ),
      body: ListView(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + kToolbarHeight + 12,
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).padding.bottom + 16,
        ),
        children: [
          _buildSavedConfigsCard(theme, provider),
          const SizedBox(height: 16),
          _buildConnectionCard(theme, provider),
          const SizedBox(height: 16),
          _buildThemeCard(theme),
          const SizedBox(height: 16),
          _buildAboutCard(theme),
        ],
      ),
    ),
    );
  }

  Widget _buildConnectionCard(ThemeData theme, ChatProvider provider) {
    final isDark = theme.brightness == Brightness.dark;
    final sshStatus = provider.sshTunnelStatus;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _useSsh ? Icons.vpn_lock : Icons.dns,
                    color: theme.colorScheme.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('连接方式', style: theme.textTheme.titleMedium),
                    Text(
                      _useSsh ? 'SSH 隧道 · 加密通信' : '直连 · 局域网',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withOpacity(0.45),
                      ),
                    ),
                  ],
                ),
                if (!_useSsh && provider.isConnected)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.check_circle, color: Colors.green, size: 16),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // Mode selector: Direct vs SSH
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('直连'),
                  icon: Icon(Icons.dns),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('SSH 隧道'),
                  icon: Icon(Icons.vpn_lock),
                ),
              ],
              selected: {_useSsh},
              onSelectionChanged: (modes) async {
                final useSsh = modes.first;
                setState(() => _useSsh = useSsh);
                await provider.setSshTunnelEnabled(useSsh);
              },
            ),

            // ── Direct connection form ──
            if (!_useSsh) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _urlController,
                decoration: InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'http://192.168.1.100:4096',
                  prefixIcon: const Icon(Icons.link),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _testing ? null : _testDirect,
                      icon: _testing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_find),
                      label: Text(_testing ? '测试中...' : '测试连接'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saveDirect,
                      icon: const Icon(Icons.save),
                      label: const Text('连接'),
                    ),
                  ),
                ],
              ),
            ],

            // ── SSH tunnel form ──
            if (_useSsh) ...[
              const SizedBox(height: 8),
              _sshStatusBar(theme, provider, sshStatus),
              const Divider(height: 24),
              TextField(
                controller: _sshQuickFillController,
                decoration: InputDecoration(
                  labelText: '快速填写',
                  hintText: 'user@host:22',
                  prefixIcon: const Icon(Icons.paste),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    tooltip: '应用',
                    onPressed: _applyQuickFill,
                  ),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
                onSubmitted: (_) => _applyQuickFill(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sshHostController,
                decoration: const InputDecoration(
                  labelText: 'SSH 主机',
                  hintText: '192.168.1.100 或 your-server.com',
                  prefixIcon: Icon(Icons.dns_outlined),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _sshUsernameController,
                      decoration: const InputDecoration(
                        labelText: '用户名',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      autocorrect: false,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _sshPortController,
                      decoration: const InputDecoration(
                        labelText: '端口',
                        prefixIcon: Icon(Icons.numbers),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sshPasswordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: '密码',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () => setState(
                        () => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text('或使用私钥',
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withOpacity(0.5))),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _sshKeyController,
                obscureText: _obscureKey,
                maxLines: _obscureKey ? 1 : 3,
                minLines: 1,
                decoration: InputDecoration(
                  labelText: '私钥 (PEM)',
                  prefixIcon: const Icon(Icons.key),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureKey
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _obscureKey = !_obscureKey),
                  ),
                ),
              ),
              const Divider(height: 24),
              Text('远程服务', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Text(
                'SSH 服务器所看到的 opencode 服务地址。',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _sshRemoteHostController,
                      decoration: const InputDecoration(
                        labelText: '远程主机',
                        hintText: 'localhost',
                      ),
                      autocorrect: false,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _sshRemotePortController,
                      decoration: const InputDecoration(
                        labelText: '端口',
                        hintText: '4096',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: sshStatus == SshTunnelStatus.connecting
                      ? null
                      : _connectSsh,
                  icon: sshStatus == SshTunnelStatus.connecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.vpn_lock),
                  label: Text(sshStatus == SshTunnelStatus.connecting
                      ? '连接中...'
                      : _sshConnected(provider)
                          ? '重新连接 SSH'
                          : '通过 SSH 连接'),
                ),
              ),
              if (_sshConnected(provider))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _disconnectSsh(provider),
                      icon: const Icon(Icons.link_off),
                      label: const Text('断开连接'),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildThemeCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.palette, color: theme.colorScheme.primary, size: 18),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('外观', style: theme.textTheme.titleMedium),
                    Text(
                      '主题设置',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withOpacity(0.45),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('跟随系统'),
                    icon: Icon(Icons.brightness_auto)),
                ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('浅色'),
                    icon: Icon(Icons.light_mode)),
                ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('深色'),
                    icon: Icon(Icons.dark_mode)),
              ],
              selected: {_themeMode},
              onSelectionChanged: (modes) {
                _setThemeMode(modes.first);
                OpenCodeThemeProvider.setThemeMode(modes.first);
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _sshConnected(ChatProvider provider) =>
      provider.sshTunnelStatus == SshTunnelStatus.connected;

  Widget _sshStatusBar(
      ThemeData theme, ChatProvider provider, SshTunnelStatus status) {
    final (color, icon, text) = switch (status) {
      SshTunnelStatus.connected => (
          Colors.green,
          Icons.check_circle,
          '已连接 (端口 ${provider.sshTunnel.localPort})'
        ),
      SshTunnelStatus.connecting => (
          Colors.orange,
          Icons.sync,
          '连接中...'
        ),
      SshTunnelStatus.failed => (
          Colors.red,
          Icons.error_outline,
          provider.sshTunnelError ?? '连接失败'
        ),
      SshTunnelStatus.disconnected => (
          Colors.grey,
          Icons.cloud_off,
          '未连接'
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(text,
                style: TextStyle(fontSize: 13, color: color),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.info_outline, color: theme.colorScheme.primary, size: 18),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('关于', style: theme.textTheme.titleMedium),
                    Text(
                      '应用信息',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withOpacity(0.45),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            _infoRow(theme, '应用', 'OpenCode Mobile'),
            _infoRow(theme, '版本', _appVersion != null ? 'v$_appVersion' : '加载中...'),
            _infoRow(theme, '作者', 'Eghack6'),
            _infoRow(theme, '架构', 'Flutter + opencode serve + SSH'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _checkingUpdate ? null : _checkUpdate,
                icon: _checkingUpdate
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.system_update_outlined, size: 18),
                label: Text(_checkingUpdate ? '检查中...' : '检查更新'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ),
          Text(value, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  // -- Saved connection configs --

  Future<void> _loadSavedConfigs() async {
    final configs = await ConfigStore.loadAll();
    if (mounted) setState(() => _savedConfigs = configs);
  }

  Future<void> _saveCurrentConfig() async {
    final name = _configNameController.text.trim();
    if (name.isEmpty) {
      showToast(context, '请填写配置名称', bgColor: Colors.red);
      return;
    }
    final config = ConnectionConfig(
      name: name,
      serverUrl: _urlController.text.trim(),
      useSshTunnel: _useSsh,
      sshHost: _sshHostController.text.trim(),
      sshPort: int.tryParse(_sshPortController.text.trim()) ?? 22,
      sshUsername: _sshUsernameController.text.trim(),
      sshPassword: _sshPasswordController.text.isNotEmpty
          ? _sshPasswordController.text
          : null,
      sshPrivateKey: _sshKeyController.text.isNotEmpty
          ? _sshKeyController.text
          : null,
      sshRemoteHost: _sshRemoteHostController.text.trim().isNotEmpty
          ? _sshRemoteHostController.text.trim()
          : 'localhost',
      sshRemotePort: int.tryParse(_sshRemotePortController.text.trim()) ?? 4096,
    );
    await ConfigStore.add(config);
    _configNameController.clear();
    await _loadSavedConfigs();
    if (mounted) showToast(context, '配置「$name」已保存');
  }

  Future<void> _applyConfig(ConnectionConfig config) async {
    setState(() {
      _urlController.text = config.serverUrl;
      _useSsh = config.useSshTunnel;
      _sshHostController.text = config.sshHost;
      _sshPortController.text = config.sshPort.toString();
      _sshUsernameController.text = config.sshUsername;
      _sshPasswordController.text = config.sshPassword ?? '';
      _sshKeyController.text = config.sshPrivateKey ?? '';
      _sshRemoteHostController.text = config.sshRemoteHost;
      _sshRemotePortController.text = config.sshRemotePort.toString();
    });
    final provider = context.read<ChatProvider>();
    await provider.setSshTunnelEnabled(config.useSshTunnel);
    bool connected = false;
    if (config.useSshTunnel) {
      final sshConfig = SshConfig(
        host: config.sshHost,
        port: config.sshPort,
        username: config.sshUsername,
        password: config.sshPassword,
        privateKey: config.sshPrivateKey,
        remoteHost: config.sshRemoteHost,
        remotePort: config.sshRemotePort,
      );
      if (sshConfig.isValid) {
        await sshConfig.save();
        connected = await provider.connect('');
      } else {
        if (mounted) {
          showToast(context, '已加载「${config.name}」，请补充 SSH 信息后连接',
              bgColor: Colors.orange);
        }
        return;
      }
    } else {
      if (config.serverUrl.isNotEmpty) {
        connected = await provider.connect(config.serverUrl);
      } else {
        if (mounted) {
          showToast(context, '已加载「${config.name}」，请补充地址后连接',
              bgColor: Colors.orange);
        }
        return;
      }
    }

    if (!mounted) return;
    if (connected) {
      showToast(context, '已连接「${config.name}」', bgColor: Colors.green);
      Navigator.pop(context); // back to chat
    } else {
      final err = config.useSshTunnel
          ? (provider.sshTunnelError ?? '未知错误')
          : '';
      showToast(context, '连接失败${err.isNotEmpty ? '：$err' : ''}',
          bgColor: Colors.red);
    }
  }

  Future<void> _deleteConfig(int index) async {
    final name = _savedConfigs[index].name;
    await ConfigStore.remove(index);
    await _loadSavedConfigs();
    if (mounted) showToast(context, '已删除「$name」');
  }

  Widget _buildSavedConfigsCard(ThemeData theme, ChatProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.bookmark, color: theme.colorScheme.primary, size: 18),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('设备配置', style: theme.textTheme.titleMedium),
                    Text(
                      '一键切换',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withOpacity(0.45),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (_savedConfigs.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${_savedConfigs.length} 个',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.primary)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // Save current config
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _configNameController,
                    decoration: const InputDecoration(
                      labelText: '配置名称',
                      hintText: '如：家里电脑、公司服务器',
                      prefixIcon: Icon(Icons.label_outline),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _saveCurrentConfig,
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('保存'),
                ),
              ],
            ),
            // List saved configs
            if (_savedConfigs.isNotEmpty) ...[
              const Divider(height: 24),
              ...List.generate(_savedConfigs.length, (i) {
                final config = _savedConfigs[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerHigh,
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        config.useSshTunnel ? Icons.vpn_lock : Icons.dns,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      title: Text(config.name,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500)),
                      subtitle: Text(config.subtitle,
                          style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface
                                  .withOpacity(0.5))),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.play_arrow,
                                size: 20, color: Colors.green[600]),
                            tooltip: '连接',
                            onPressed: () => _applyConfig(config),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline,
                                size: 18,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.3)),
                            tooltip: '删除',
                            onPressed: () => _deleteConfig(i),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _testDirect() async {
    setState(() => _testing = true);
    final provider = context.read<ChatProvider>();
    await provider.connect(_urlController.text.trim());
    setState(() => _testing = false);
  }

  Future<void> _saveDirect() async {
    final provider = context.read<ChatProvider>();
    final connected = await provider.connect(_urlController.text.trim());
    if (!mounted) return;
    showToast(context, connected ? '连接成功' : '连接失败',
        bgColor: connected ? Colors.green : Colors.red);
  }

  Future<void> _connectSsh() async {
    final config = _buildSshConfig();
    if (!config.isValid) {
      showToast(context, '请填写 SSH 主机、用户名和密码或私钥', bgColor: Colors.red);
      return;
    }
    final provider = context.read<ChatProvider>();
    await config.save();
    final connected = await provider.connect('');
    if (!mounted) return;
    showToast(context,
        connected
            ? 'SSH 隧道已连接，端口 ${provider.sshTunnel.localPort}'
            : 'SSH 连接失败：${provider.sshTunnelError ?? "未知错误"}',
        bgColor: connected ? Colors.green : Colors.red);
  }

  Future<void> _disconnectSsh(ChatProvider provider) async {
    await provider.sshTunnel.disconnect();
    provider.setSshTunnelEnabled(false);
    setState(() => _useSsh = false);
  }
}
