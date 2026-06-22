import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../app.dart';
import '../providers/chat_provider.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../services/ssh_tunnel_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/scroll_wheel.dart';
import '../widgets/toast.dart';
import 'sessions_screen.dart';
import 'settings_screen.dart';

enum _DeployOption { local, lan, server }

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final _itemScrollController = ItemScrollController();
  final _itemPositionsListener = ItemPositionsListener.create();
  bool _autoScroll = true;
  bool _programmaticScroll = false;
  int _lastContentLength = 0;
  String? _lastSessionId;
  List<int> _userPairIndices = [];
  int _currentPairIndex = 0;
  bool _isAtBottom = true;
  int _messageCount = 0;

  _DeployOption? _deployOption;
  late AnimationController _borderAnimController;

  @override
  void initState() {
    super.initState();
    _borderAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _focusNode.addListener(_onFocusChange);
    WidgetsBinding.instance.addObserver(this);
    _itemPositionsListener.itemPositions.addListener(_onPositionsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstRunAndInit();
    });
  }

  void _onPositionsChanged() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty || _messageCount == 0) return;

    // FAB visibility: hide when last item is anywhere in viewport
    _isAtBottom = positions.any((p) => p.index == _messageCount - 1 && p.itemLeadingEdge < 1.0);

    // Auto-scroll: only when last item's trailing edge is near bottom (accounts for 6px padding)
    final nearBottom = positions.any((p) => p.index == _messageCount - 1 && p.itemTrailingEdge >= 0.99);

    // Update scroll wheel pair index based on topmost item
    final uIndices = _userPairIndices;
    bool needRebuild = false;
    if (uIndices.isNotEmpty) {
      final topPos = positions.where((p) => p.itemLeadingEdge >= 0 && p.itemLeadingEdge < 1);
      final firstVisible = topPos.isEmpty ? positions.first.index : topPos.first.index;
      var nearest = 0;
      var minD = 999999;
      for (var i = 0; i < uIndices.length; i++) {
        final d = (uIndices[i] - firstVisible).abs();
        if (d < minD) { minD = d; nearest = i; }
      }
      if (nearest != _currentPairIndex) {
        _currentPairIndex = nearest;
        needRebuild = true;
      }
    }

    // Always update _autoScroll – previously an early return skipped this,
    // causing _autoScroll to stay true while the user was browsing old messages,
    // which then triggered unwanted jumps on the next poll / content update.
    if (nearBottom) {
      if (!_autoScroll) needRebuild = true;
      _autoScroll = true;
      _unreadCount = 0;
    } else if (!_programmaticScroll) {
      if (_autoScroll) needRebuild = true;
      _autoScroll = false;
    }

    if (needRebuild) {
      setState(() {});
    }
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      // Keyboard is appearing – scroll to bottom after layout settles
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        _autoScroll = true;
        _scrollToLastItem();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _itemPositionsListener.itemPositions.removeListener(_onPositionsChanged);
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _textController.dispose();
    _borderAnimController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came back to foreground: refresh messages for multi-device sync
      context.read<ChatProvider>().onAppResumed();
    }
  }

  void _scrollToLastItem({bool animate = true}) {
    if (_messageCount == 0) return;
    _programmaticScroll = true;
    final generating = context.read<ChatProvider>().isGenerating;
    // If generating, scroll to the last item (streaming AI reply).
    // Otherwise scroll to second-to-last (user message) so the AI response
    // is visible below it.
    final target = generating
        ? _messageCount - 1
        : _messageCount > 1
            ? _messageCount - 2
            : 0;
    if (animate) {
      _itemScrollController.scrollTo(
        index: target,
        alignment: 0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
      Future.delayed(const Duration(milliseconds: 200), () {
        _programmaticScroll = false;
      });
    } else {
      _itemScrollController.jumpTo(index: target, alignment: 0);
      _programmaticScroll = false;
    }
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    _autoScroll = true;
    context.read<ChatProvider>().sendMessage(text);
    _scrollToLastItem();
  }

  List<int> _getUserIndices(List<Message> messages) {
    final indices = <int>[];
    for (int i = 0; i < messages.length; i++) {
      if (messages[i].isUser) indices.add(i);
    }
    return indices;
  }

  int _unreadCount = 0;

  void _scrollToPair(int pairIndex) {
    final indices = _userPairIndices;
    if (pairIndex >= indices.length || _messageCount <= 1) return;
    _autoScroll = false;
    _programmaticScroll = true;
    final msgIdx = indices[pairIndex];
    _itemScrollController.scrollTo(
      index: msgIdx,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _programmaticScroll = false;
    });
  }

  Future<void> _checkFirstRunAndInit() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasRun = prefs.getBool('has_run_before') ?? false;
      if (!hasRun && mounted) {
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        );
        await prefs.setBool('has_run_before', true);
        if (result == true) {
          if (!mounted) return;
          Navigator.push(
              context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
        }
      }
      if (mounted) {
        context.read<ChatProvider>().init();
      }
    } catch (_) {}
  }

  void _showModelPicker(ChatProvider provider) {
    final searchController = TextEditingController();
    ValueNotifier<String> searchQuery = ValueNotifier('');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final query = searchQuery.value.toLowerCase();
            final models = provider.availableModels.where((m) {
              if (query.isEmpty) return true;
              return m.modelName.toLowerCase().contains(query) ||
                  m.providerName.toLowerCase().contains(query) ||
                  m.id.toLowerCase().contains(query);
            }).toList();

            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xDD141428)
                        : const Color(0xF2F5F6FA),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.08)
                          : Colors.white.withOpacity(0.5),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Drag handle
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withOpacity(0.15)
                                : Colors.black.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                        child: Row(
                          children: [
                            Icon(Icons.auto_awesome,
                                size: 20, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 8),
                            Text('选择模型',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.3,
                                    color: Theme.of(context).colorScheme.onSurface)),
                            const Spacer(),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: Icon(Icons.close,
                                  size: 20,
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                              style: IconButton.styleFrom(
                                backgroundColor: isDark
                                    ? Colors.white.withOpacity(0.06)
                                    : Colors.black.withOpacity(0.04),
                                shape: const CircleBorder(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: searchController,
                          decoration: InputDecoration(
                            hintText: '搜索模型...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            filled: true,
                            fillColor: isDark
                                ? Colors.white.withOpacity(0.06)
                                : Colors.white.withOpacity(0.7),
                            suffixIcon: searchQuery.value.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      searchController.clear();
                                      searchQuery.value = '';
                                      setSheetState(() {});
                                    },
                                  )
                                : null,
                          ),
                          onChanged: (v) {
                            searchQuery.value = v;
                            setSheetState(() {});
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Divider(height: 1,
                          color: isDark
                              ? Colors.white.withOpacity(0.06)
                              : Colors.black.withOpacity(0.05)),
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.4,
                        child: models.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.search_off,
                                        size: 40,
                                        color: Theme.of(context)
                                            .colorScheme.onSurface
                                            .withOpacity(0.2)),
                                    const SizedBox(height: 8),
                                    Text('没有匹配的模型',
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withOpacity(0.4))),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                itemCount: models.length,
                                itemBuilder: (context, index) {
                                  final model = models[index];
                                  final isSelected =
                                      model.id == provider.selectedModel;
                                  return Padding(
                                    padding: EdgeInsets.only(
                                      left: 12,
                                      right: 12,
                                      top: index == 0 ? 4 : 2,
                                      bottom: index == models.length - 1 ? 4 : 2,
                                    ),
                                    child: Material(
                                      color: isSelected
                                          ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(14),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(14),
                                        onTap: () {
                                          provider.setModel(model.id);
                                          Navigator.pop(context);
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 12),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 36,
                                                height: 36,
                                                decoration: BoxDecoration(
                                                  color: isSelected
                                                      ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
                                                      : isDark
                                                          ? Colors.white.withOpacity(0.05)
                                                          : Colors.black.withOpacity(0.03),
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: Icon(
                                                  isSelected
                                                      ? Icons.check_circle
                                                      : Icons.smart_toy_outlined,
                                                  size: 18,
                                                  color: isSelected
                                                      ? Theme.of(context).colorScheme.primary
                                                      : Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(model.modelName,
                                                        style: TextStyle(
                                                            fontSize: 14,
                                                            fontWeight: isSelected
                                                                ? FontWeight.w600
                                                                : FontWeight.w500,
                                                            color: isSelected
                                                                ? Theme.of(context).colorScheme.primary
                                                                : null)),
                                                    const SizedBox(height: 2),
                                                    Text(model.providerName,
                                                        style: TextStyle(
                                                            fontSize: 12,
                                                            color: Theme.of(context)
                                                                .colorScheme.onSurface
                                                                .withOpacity(0.45))),
                                                  ],
                                                ),
                                              ),
                                              Text(model.id.split('/').last,
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      fontFamily: 'monospace',
                                                      color: Colors.grey[500])),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      SizedBox(height: MediaQuery.of(context).padding.bottom + 4),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _showSshInfo(ChatProvider provider) {
    final ssh = provider.sshTunnel;
    final config = ssh.config;
    showModalBottomSheet(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        final statusColor = switch (ssh.status) {
          SshTunnelStatus.connected => Colors.green,
          SshTunnelStatus.connecting => Colors.orange,
          SshTunnelStatus.failed => Colors.red,
          SshTunnelStatus.disconnected => Colors.grey,
        };
        final statusText = switch (ssh.status) {
          SshTunnelStatus.connected => '已连接',
          SshTunnelStatus.connecting => '连接中',
          SshTunnelStatus.failed => '失败',
          SshTunnelStatus.disconnected => '未连接',
        };
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.vpn_lock, color: statusColor),
                  const SizedBox(width: 8),
                  Text('SSH 隧道',
                      style: theme.textTheme.titleLarge),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(statusText,
                        style: TextStyle(fontSize: 12, color: statusColor)),
                  ),
                ],
              ),
              const Divider(height: 24),
              if (config != null) ...[
                _infoRow('主机', config.host),
                _infoRow('端口', '${config.port}'),
                _infoRow('用户名', config.username),
              ],
              if (ssh.localPort != null)
                _infoRow('本地端口', '${ssh.localPort}'),
              if (ssh.lastError != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(ssh.lastError!,
                      style: const TextStyle(fontSize: 12, color: Colors.red)),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _openSettings();
                  },
                  child: const Text('SSH 设置'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 14),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  void _showDebugLogs() {
    final api = ApiService();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.8,
              maxChildSize: 0.9,
              minChildSize: 0.3,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          const Text('API 日志',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          TextButton.icon(
                            icon: const Icon(Icons.delete, size: 18),
                            label: const Text('清空'),
                            onPressed: () {
                              api.clearLogs();
                              setSheetState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: api.logs.isEmpty
                          ? const Center(
                              child: Text(
                                  '暂无 API 调用记录。长按标题栏可开启调试模式。'))
                          : ListView.separated(
                              controller: scrollController,
                              padding: const EdgeInsets.all(8),
                              itemCount: api.logs.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 4),
                              itemBuilder: (context, index) {
                                final entry =
                                    api.logs.reversed.toList()[index];
                                final color = entry.error != null
                                    ? Colors.red
                                    : (entry.statusCode != null &&
                                            entry.statusCode! >= 200 &&
                                            entry.statusCode! < 300
                                        ? Colors.green
                                        : Colors.orange);
                                return Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color:
                                                    color.withOpacity(0.15),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                entry.method,
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    fontSize: 12,
                                                    color: color),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                entry.url.replaceFirst(
                                                    api.baseUrl, ''),
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    fontFamily: 'monospace'),
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (entry.statusCode != null)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: color
                                                      .withOpacity(0.15),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          4),
                                                ),
                                                child: Text(
                                                  '${entry.statusCode}',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12,
                                                      color: color),
                                                ),
                                              ),
                                          ],
                                        ),
                                        if (entry.requestBody != null &&
                                            entry.requestBody!.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text('请求:',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color:
                                                      Colors.grey[600])),
                                          const SizedBox(height: 2),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.withOpacity(0.08),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: SelectableText(
                                              _formatJson(entry.requestBody!),
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  fontFamily: 'monospace'),
                                            ),
                                          ),
                                        ],
                                        if (entry.responseBody != null &&
                                            entry.responseBody!.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text('响应:',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color:
                                                      Colors.grey[600])),
                                          const SizedBox(height: 2),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.withOpacity(0.08),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: SelectableText(
                                              entry.responseBody!.length > 1000
                                                  ? '${entry.responseBody!.substring(0, 1000)}...'
                                                  : entry.responseBody!,
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  fontFamily: 'monospace'),
                                            ),
                                          ),
                                        ],
                                        if (entry.error != null) ...[
                                          const SizedBox(height: 6),
                                          Text('错误:',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.red[700])),
                                          const SizedBox(height: 2),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: Colors.red.withOpacity(0.05),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: SelectableText(
                                              entry.error!,
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  fontFamily: 'monospace',
                                                  color: Colors.red),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _openSessions() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SessionsScreen()),
    );
  }

  String _formatJson(String json) {
    try {
      final parsed = jsonDecode(json);
      return const JsonEncoder.withIndent('  ').convert(parsed);
    } catch (_) {
      return json;
    }
  }

  void _showToast(BuildContext context, String message, {Color? bgColor}) {
    showToast(context, message, bgColor: bgColor);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        gradient: isDark ? GlassColors.darkBgGradient : GlassColors.lightBgGradient,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        resizeToAvoidBottomInset: true,
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
        title: GestureDetector(
          onLongPress: () {
            final api = ApiService();
            api.setDebug(!api.debug);
            if (mounted) setState(() {});
            if (mounted) {
              _showToast(context, api.debug ? '调试模式已开启' : '调试模式已关闭');
            }
          },
          child: Consumer<ChatProvider>(
            builder: (context, provider, _) {
              final title = provider.currentSession?.title;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                          child: Text(title ?? 'OpenCode',
                              style: const TextStyle(fontSize: 18))),
                      if (ApiService().debug)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(Icons.bug_report,
                              size: 14, color: theme.colorScheme.error),
                        ),
                    ],
                  ),
                  if (provider.isConnected && provider.selectedModel != null)
                    Text(
                      provider.selectedModel!.split('/').last,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              );
            },
          ),
        ),
        automaticallyImplyLeading: false,
        actions: [
          Consumer<ChatProvider>(
            builder: (context, provider, _) {
              final status = provider.sshTunnelStatus;
              final color = switch (status) {
                SshTunnelStatus.connected => Colors.green,
                SshTunnelStatus.connecting => Colors.orange,
                SshTunnelStatus.failed => Colors.red,
                SshTunnelStatus.disconnected => null,
              };
              return IconButton(
                icon: Icon(Icons.vpn_lock, color: color),
                tooltip: status.name,
                onPressed: () => _showSshInfo(provider),
              );
            },
          ),
          if (ApiService().debug)
            IconButton(
              icon: const Icon(Icons.list_alt),
              tooltip: 'API 日志',
              onPressed: _showDebugLogs,
            ),
          Consumer<ChatProvider>(
            builder: (context, provider, _) {
              if (provider.availableModels.isEmpty) {
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: const Icon(Icons.tune),
                tooltip: '切换模型',
                onPressed: () => _showModelPicker(provider),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '会话列表',
            onPressed: _openSessions,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: _openSettings,
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(0),
          child: SizedBox.shrink(),
        ),
      ),
      body: Consumer<ChatProvider>(
        builder: (context, provider, _) {
          // Loading state for session switching
          if (provider.isLoading && provider.currentSession == null && provider.sessions.isNotEmpty) {
            return _buildLoadingIndicator(theme);
          }

          if (_lastSessionId != provider.currentSession?.id) {
            _lastSessionId = provider.currentSession?.id;
            _lastContentLength = 0;
            _autoScroll = true;
            _isAtBottom = true;
          }
          if (_autoScroll && provider.messages.isNotEmpty) {
            final curContentLen = provider.messages.last.textContent.length;
            if (_lastContentLength != curContentLen) {
              _lastContentLength = curContentLen;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _scrollToLastItem(animate: true);
              });
            }
          } else if (provider.messages.isNotEmpty) {
            final curContentLen = provider.messages.last.textContent.length;
            if (_lastContentLength != curContentLen) {
              _lastContentLength = curContentLen;
              _unreadCount++;
            }
          } else {
            _lastContentLength = 0;
          }

          if (!provider.isConnected) {
            return _buildSetupGuide(theme, provider);
          }
          final msgs = provider.messages;
          _messageCount = msgs.length;
          _userPairIndices = _getUserIndices(msgs);
          return Stack(
            children: [
              // Chat content (extends behind floating input bar)
              Column(
                children: [
                  if (provider.error != null && msgs.isNotEmpty)
                    _buildErrorBanner(theme, provider),
                  Expanded(
                    child: msgs.isEmpty
                        ? _buildWelcome(theme, provider)
                        : Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => FocusScope.of(context).unfocus(),
                                  child: ScrollablePositionedList.builder(
                                    itemScrollController: _itemScrollController,
                                    itemPositionsListener: _itemPositionsListener,
                                    padding: EdgeInsets.only(
                                      // Top padding: status bar + AppBar height + small gap
                                      top: MediaQuery.of(context).padding.top + kToolbarHeight + 4,
                                      // Bottom padding: input bar height + SafeArea bottom + gap
                                      bottom: MediaQuery.of(context).padding.bottom + 76,
                                    ),
                                    itemCount: msgs.length,
                                    physics: const ClampingScrollPhysics(),
                                    itemBuilder: (context, index) {
                                      return MessageBubble(
                                        message: msgs[index],
                                        animate: index == msgs.length - 1,
                                      );
                                    },
                                  ),
                                ),
                              ),
                              if (_userPairIndices.length > 1)
                                ScrollWheel(
                                  itemCount: _userPairIndices.length,
                                  activeIndex: _currentPairIndex,
                                  onIndexChanged: _scrollToPair,
                                  themeColor: theme.colorScheme.primary,
                                ),
                            ],
                          ),
                  ),
                ],
              ),
              // Floating input bar
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildInputBar(theme),
              ),
              // Scroll to bottom FAB
              if (!_isAtBottom)
                Positioned(
                  right: (_userPairIndices.length > 1 ? 40 : 12),
                  bottom: 76,
                  child: _buildScrollToBottomFAB(theme),
                ),
            ],
          );
        },
      ),
    ),
    );
  }

  Widget _buildLoadingIndicator(ThemeData theme) {
    return Center(
      key: const ValueKey('session_loading'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(height: 16),
          Text('切换会话…', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4))),
        ],
      ),
    );
  }

  Widget _buildScrollToBottomFAB(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark
                ? Colors.black.withOpacity(0.2)
                : Colors.white.withOpacity(0.3),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.06),
              width: 1,
            ),
          ),
          child: GestureDetector(
            onTap: () {
              _autoScroll = true;
              _unreadCount = 0;
              _isAtBottom = true;
              setState(() {});
              _scrollToLastItem();
            },
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(Icons.arrow_downward,
                    size: 18,
                    color: theme.colorScheme.onSurface.withOpacity(0.6)),
                if (_unreadCount > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(ThemeData theme, ChatProvider provider) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + kToolbarHeight + 4,
        left: 16,
        right: 16,
        bottom: 8,
      ),
      color: theme.colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(Icons.error_outline,
              size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              provider.error!,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          if (provider.hasFailedMessage)
            IconButton(
              icon: Icon(Icons.refresh,
                  size: 16, color: theme.colorScheme.error),
              tooltip: '重试',
              onPressed: () => provider.retryLastMessage(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          IconButton(
            icon: Icon(Icons.close,
                size: 16, color: theme.colorScheme.error),
            onPressed: () => provider.clearError(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupGuide(ThemeData theme, ChatProvider provider) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + kToolbarHeight + 16,
        left: 20,
        right: 20,
        bottom: 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Center(
            child: Icon(Icons.smart_toy,
                size: 72,
                color: theme.colorScheme.primary.withOpacity(0.3)),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text('OpenCode Mobile',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                )),
          ),
          const SizedBox(height: 24),
          Text('opencode 部署在哪里？', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          // 3 deploy options
          Row(
            children: [
              Expanded(child: _deployOptionCard(theme, _DeployOption.local, Icons.phone_android, '本机', '在手机上运行')),
              const SizedBox(width: 8),
              Expanded(child: _deployOptionCard(theme, _DeployOption.lan, Icons.computer, '局域网 PC', '在电脑上运行')),
              const SizedBox(width: 8),
              Expanded(child: _deployOptionCard(theme, _DeployOption.server, Icons.cloud, '服务器', '远程连接')),
            ],
          ),
          const SizedBox(height: 20),
          // Conditional guide based on selection
          if (_deployOption != null)
            _buildDeployGuide(theme, provider),
          if (provider.error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.error, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(provider.error!,
                        style: TextStyle(
                            color: theme.colorScheme.onErrorContainer)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _deployOptionCard(ThemeData theme, _DeployOption option, IconData icon, String title, String subtitle) {
    final selected = _deployOption == option;
    return GestureDetector(
      onTap: () => setState(() => _deployOption = option),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.5)),
            const SizedBox(height: 6),
            Text(title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface)),
            Text(subtitle,
                style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withOpacity(0.4))),
          ],
        ),
      ),
    );
  }

  Widget _buildDeployGuide(ThemeData theme, ChatProvider provider) {
    switch (_deployOption!) {
      case _DeployOption.local:
        return Column(
          children: [
            _stepCard(
              theme: theme,
              step: '1',
              title: '安装 Termux',
              desc: '从 F-Droid 下载 Termux 以获得最佳兼容性。',
              action: FilledButton.icon(
                onPressed: () =>
                    _launchUrl('https://f-droid.org/packages/com.termux/'),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('打开 F-Droid'),
              ),
            ),
            const SizedBox(height: 12),
            _stepCard(
              theme: theme,
              step: '2',
              title: '安装 proot-distro 和 Ubuntu',
              desc: '在 Termux 中运行：',
              action: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const SelectableText(
                  'pkg install -y proot-distro\nproot-distro install ubuntu',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _stepCard(
              theme: theme,
              step: '3',
              title: '安装依赖',
              desc: '在 Ubuntu 中安装 Node.js 和 opencode：',
              action: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const SelectableText(
                  'proot-distro login ubuntu\napt update && apt install -y nodejs npm\nnpm install -g opencode-ai',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _stepCard(
              theme: theme,
              step: '4',
              title: '启动服务',
              desc: '保持 Termux 运行，启动 opencode serve：',
              action: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const SelectableText(
                  'proot-distro login ubuntu -- bash -c\n  \'opencode serve --port 4096 --hostname 0.0.0.0 --cors "*"\'',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _connectLocal(provider),
                icon: const Icon(Icons.wifi),
                label: const Text('一键连接'),
              ),
            ),
          ],
        );
      case _DeployOption.lan:
        return Column(
          children: [
            _stepCard(
              theme: theme,
              step: '1',
              title: '在电脑上启动 opencode',
              desc: '在电脑终端中运行：',
              action: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const SelectableText(
                  'opencode serve --port 4096 --hostname 0.0.0.0 --cors "*"',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _stepCard(
              theme: theme,
              step: '2',
              title: '在设置中输入电脑 IP',
              desc: '确保手机和电脑在同一局域网内。在设置页面输入电脑的局域网 IP 地址。',
              action: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings),
                  label: const Text('打开设置'),
                ),
              ),
            ),
          ],
        );
      case _DeployOption.server:
        return Column(
          children: [
            _stepCard(
              theme: theme,
              step: '1',
              title: '配置 SSH 连接',
              desc: '在设置页面填写 SSH 服务器信息（主机、端口、用户名、密码或私钥）。',
              action: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings),
                  label: const Text('打开设置'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _stepCard(
              theme: theme,
              step: '2',
              title: '启用 SSH 隧道',
              desc: '在设置页面开启「使用 SSH 隧道」开关，应用将通过加密隧道连接到远程服务器。',
              action: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.vpn_lock, size: 18, color: Colors.green),
                    SizedBox(width: 8),
                    Text('SSH 隧道加密所有通信流量', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
          ],
        );
    }
  }

  Future<void> _connectLocal(ChatProvider provider) async {
    final ok = await provider.connect('http://localhost:4096');
    if (mounted) {
      _showToast(context, ok ? '连接成功！' : '连接失败',
          bgColor: ok ? Colors.green : Colors.red);
    }
  }

  void _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _stepCard({
    required ThemeData theme,
    required String step,
    required String title,
    required String desc,
    required Widget action,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: theme.colorScheme.primary,
                  child: Text(step,
                      style: TextStyle(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      )),
                ),
                const SizedBox(width: 12),
                Text(title, style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(desc,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                )),
            const SizedBox(height: 12),
            action,
          ],
        ),
      ),
    );
  }

  Widget _buildWelcome(ThemeData theme, ChatProvider provider) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + kToolbarHeight + 24,
          left: 24,
          right: 24,
          bottom: MediaQuery.of(context).padding.bottom + 80,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy,
                size: 80,
                color: theme.colorScheme.primary.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text('OpenCode Mobile',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                )),
            if (provider.error != null) ...[
              const SizedBox(height: 16),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(provider.error!,
                          style: TextStyle(
                              color:
                                  theme.colorScheme.onErrorContainer)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: Consumer<ChatProvider>(
          builder: (context, provider, _) {
            // Control animation based on generating state
            if (provider.isGenerating && !_borderAnimController.isAnimating) {
              _borderAnimController.repeat();
            } else if (!provider.isGenerating && _borderAnimController.isAnimating) {
              _borderAnimController.stop();
              _borderAnimController.reset();
            }

            final inputChild = ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.black.withOpacity(0.2)
                        : Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(28),
                    border: provider.isGenerating
                        ? null
                        : Border.all(
                            color: isDark
                                ? Colors.white.withOpacity(0.08)
                                : Colors.black.withOpacity(0.06),
                            width: 1,
                          ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // TextField
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          focusNode: _focusNode,
                          enabled: provider.isConnected && !provider.isGenerating,
                          decoration: InputDecoration(
                            hintText: provider.isConnected
                                ? '输入消息...'
                                : '请先连接服务器...',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            filled: false,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 22, vertical: 12),
                          ),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w300,
                            color: theme.colorScheme.onSurface,
                          ),
                          maxLines: 6,
                          minLines: 1,
                          textInputAction: TextInputAction.send,
                          onSubmitted: !provider.isConnected || provider.isGenerating
                              ? null
                              : (_) => _sendMessage(),
                        ),
                      ),
                      // Send / Stop button (outside TextField so it's always tappable)
                      GestureDetector(
                        onTap: !provider.isConnected
                            ? null
                            : (provider.isGenerating
                                ? () => provider.abortGeneration()
                                : _sendMessage),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: provider.isGenerating
                              ? Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFFE74C3C).withOpacity(0.15),
                                    border: Border.all(
                                      color: const Color(0xFFE74C3C).withOpacity(0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE74C3C),
                                        borderRadius: BorderRadius.circular(2.5),
                                      ),
                                    ),
                                  ),
                                )
                              : Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: provider.isConnected
                                        ? GlassColors.primaryGradient
                                        : null,
                                    color: !provider.isConnected
                                        ? theme.colorScheme.onSurface.withOpacity(0.1)
                                        : null,
                                    boxShadow: provider.isConnected
                                        ? [
                                            BoxShadow(
                                              color: GlassColors.primaryStart.withOpacity(0.25),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Icon(
                                    Icons.arrow_upward,
                                    size: 13,
                                    color: provider.isConnected
                                        ? Colors.white
                                        : theme.colorScheme.onSurface.withOpacity(0.3),
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );

            if (!provider.isGenerating) return inputChild;

            // Animated border when generating
            return AnimatedBuilder(
              animation: _borderAnimController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _AnimatedBorderPainter(
                    progress: _borderAnimController.value,
                    borderRadius: 28,
                    color1: GlassColors.primaryStart,
                    color2: GlassColors.accentStart,
                    isDark: isDark,
                  ),
                  child: inputChild,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pages = [
      _OnboardingPage(
        icon: Icons.phone_android,
        title: 'OpenCode Mobile',
        description: '将AI助手带到你的手机上，还能帮你管理远程服务器。',
        color: theme.colorScheme.primary,
      ),
      const _OnboardingPage(
        icon: Icons.wifi,
        title: '多种连接方式',
        description: '连接到任意 opencode serve 实例——本地 Termux、局域网电脑或远程服务器。',
        color: Colors.green,
      ),
      const _OnboardingPage(
        icon: Icons.vpn_lock,
        title: 'SSH 安全隧道',
        description: '通过 SSH 隧道加密所有通信流量，保障数据安全。',
        color: Colors.orange,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: pages.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (_, i) => pages[i],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  pages.length,
                  (i) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _currentPage ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _currentPage
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    if (_currentPage < pages.length - 1) {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    } else {
                      Navigator.pop(context, true);
                    }
                  },
                  icon: Icon(
                    _currentPage < pages.length - 1
                        ? Icons.arrow_forward
                        : Icons.settings,
                  ),
                  label: Text(
                    _currentPage < pages.length - 1 ? '下一步' : '配置连接',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 56, color: color),
          ),
          const SizedBox(height: 32),
          Text(title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Text(description,
              style: TextStyle(
                fontSize: 16,
                height: 1.5,
                color:
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
               textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// Draws an animated gradient stroke along a rounded rectangle border.
class _AnimatedBorderPainter extends CustomPainter {
  final double progress;
  final double borderRadius;
  final Color color1;
  final Color color2;
  final bool isDark;

  _AnimatedBorderPainter({
    required this.progress,
    required this.borderRadius,
    required this.color1,
    required this.color2,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(borderRadius),
    );
    final path = Path()..addRRect(rrect);

    // Static dim border underneath
    final basePaint = Paint()
      ..color = isDark
          ? Colors.white.withOpacity(0.06)
          : Colors.black.withOpacity(0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(rrect, basePaint);

    // Animated gradient stroke — seamless loop
    final angle = progress * 2 * 3.14159265;
    final shader = SweepGradient(
      startAngle: 0,
      endAngle: 2 * 3.14159265,
      colors: [
        color1.withOpacity(0.0),
        color1.withOpacity(0.7),
        color2.withOpacity(0.9),
        color1.withOpacity(0.7),
        color1.withOpacity(0.0),
      ],
      stops: const [0.0, 0.2, 0.35, 0.5, 0.65],
      tileMode: TileMode.clamp,
      transform: GradientRotation(angle),
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final strokePaint = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, strokePaint);

    // Soft outer glow
    final glowPaint = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawPath(path, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _AnimatedBorderPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
