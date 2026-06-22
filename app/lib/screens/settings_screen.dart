import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/chat_provider.dart';
import '../services/ssh_tunnel_service.dart';
import '../services/theme_provider.dart';
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
  bool _testing = false;
  bool _useSsh = false;
  bool _obscurePassword = true;
  bool _obscureKey = true;
  ThemeMode _themeMode = ThemeMode.system;

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
    _loadConfig();
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildDirectConnectionCard(theme, provider),
          const SizedBox(height: 16),
          _buildSshTunnelCard(theme, provider),
          const SizedBox(height: 16),
          _buildThemeCard(theme),
          const SizedBox(height: 16),
          _buildAboutCard(theme),
        ],
      ),
    );
  }

  Widget _buildDirectConnectionCard(ThemeData theme, ChatProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dns, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('直连', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '直接连接到局域网内的 opencode serve 实例。',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: '服务器地址',
                hintText: 'http://192.168.1.100:4096',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.link),
                suffixIcon: provider.isConnected && !provider.useSshTunnel
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _useSsh ? null : (_testing ? null : _testDirect),
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_find),
                    label: Text(_testing ? '测试中...' : '测试连接'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _useSsh ? null : _saveDirect,
                    icon: const Icon(Icons.save),
                    label: const Text('连接'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSshTunnelCard(ThemeData theme, ChatProvider provider) {
    final sshStatus = provider.sshTunnelStatus;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.vpn_lock, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child:
                      Text('SSH 隧道', style: theme.textTheme.titleMedium),
                ),
                Switch(
                  value: _useSsh,
                  onChanged: (v) async {
                    await provider.setSshTunnelEnabled(v);
                    setState(() => _useSsh = v);
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '通过 SSH 隧道加密所有通信流量，比直连更安全。',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            if (_useSsh) ...[
              const SizedBox(height: 8),
              _sshStatusBar(theme, provider, sshStatus),
              const Divider(height: 24),
              TextField(
                controller: _sshQuickFillController,
                decoration: InputDecoration(
                  labelText: '快速填写',
                  hintText: 'user@host:22',
                  border: const OutlineInputBorder(),
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
                  border: OutlineInputBorder(),
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
                        border: OutlineInputBorder(),
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
                        border: OutlineInputBorder(),
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
                  border: const OutlineInputBorder(),
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
                  border: const OutlineInputBorder(),
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
                        border: OutlineInputBorder(),
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
                        border: OutlineInputBorder(),
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
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.palette, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('外观', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('关于', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            _infoRow(theme, '应用', 'OpenCode Mobile'),
            _infoRow(theme, '版本', '1.0.0'),
            _infoRow(theme, '架构', 'Flutter + opencode serve + SSH'),
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
    await config.save();
    final provider = context.read<ChatProvider>();
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
