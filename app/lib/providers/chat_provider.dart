import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/session.dart';
import '../models/message.dart';
import '../models/part.dart';
import '../services/api_service.dart';
import '../services/event_service.dart';
import '../services/ssh_tunnel_service.dart';

class ModelOption {
  final String id;
  final String providerName;
  final String modelName;

  ModelOption({required this.id, required this.providerName, required this.modelName});

  String get displayName => '$providerName / $modelName';
}

class _FailedMessage {
  final String text;
  final DateTime time;
  _FailedMessage(this.text, this.time);
}

class ChatProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  final EventService _eventService = EventService();
  final SshTunnelService _sshTunnel = SshTunnelService();

  List<Session> _sessions = [];
  Session? _currentSession;
  bool _isLoading = false;
  bool _isConnected = false;
  bool _useSshTunnel = false;
  String? _error;
  List<ModelOption> _availableModels = [];
  String? _selectedModel;

  // Per-session state (keyed by sessionId)
  final Map<String, List<Message>> _sessionMessages = {};
  final Set<String> _generatingSessions = {};
  final Map<String, Message> _streamingMessages = {};
  final Map<String, Timer> _generationTimers = {};
  final Map<String, _FailedMessage> _sessionFailedMessages = {};
  final Set<String> _generationDone = {};
  final Set<String> _abortedSessions = {};

  StreamSubscription? _eventSubscription;
  StreamSubscription? _sshStatusSubscription;

  int _sseEventCount = 0;
  bool _initialized = false;

  final List<String> _debugLogs = [];
  static const int _maxDebugLogs = 200;

  // Periodic polling for multi-device sync
  Timer? _pollingTimer;
  static const Duration _pollingInterval = Duration(seconds: 5);

  List<Session> get sessions => _sessions;
  Session? get currentSession => _currentSession;
  List<Message> get messages =>
      _currentSession != null ? (_sessionMessages[_currentSession!.id] ?? []) : [];
  bool get isLoading => _isLoading;
  bool get isConnected => _isConnected;
  bool get isGenerating =>
      _currentSession != null ? _generatingSessions.contains(_currentSession!.id) : false;
  bool get useSshTunnel => _useSshTunnel;
  SshTunnelStatus get sshTunnelStatus => _sshTunnel.status;
  String? get sshTunnelError => _sshTunnel.lastError;
  String? get error => _error;
  String get serverUrl => _api.baseUrl;
  List<ModelOption> get availableModels => _availableModels;
  String? get selectedModel => _selectedModel;
  SshTunnelService get sshTunnel => _sshTunnel;
  bool get hasFailedMessage =>
      _currentSession != null && _sessionFailedMessages.containsKey(_currentSession!.id);
  String? get lastFailedMessageText =>
      _currentSession != null ? _sessionFailedMessages[_currentSession!.id]?.text : null;
  int get sseEventCount => _sseEventCount;
  List<String> get debugLogs {
    final combined = <String>[];
    combined.addAll(_eventService.logs);
    combined.addAll(_debugLogs);
    combined.sort();
    return combined;
  }

  void _log(String msg) {
    final ts = DateTime.now().toString().substring(11, 23);
    _debugLogs.add('$ts $msg');
    if (_debugLogs.length > _maxDebugLogs) _debugLogs.removeAt(0);
    print('[OC] $msg');
  }

  void clearDebugLogs() {
    _debugLogs.clear();
    notifyListeners();
  }

  void clearError() {
    _error = null;
    if (_currentSession != null) {
      _sessionFailedMessages.remove(_currentSession!.id);
    }
    notifyListeners();
  }

  Future<void> init() async {
    await _api.loadConfig();
    await _loadSelectedModel();
    await _loadSshTunnelPref();
    await _loadLastConnectionMode();

    _sshStatusSubscription?.cancel();
    _sshStatusSubscription = _sshTunnel.onStatusChanged.listen((status) {
      if (status == SshTunnelStatus.failed && _useSshTunnel) {
        _isConnected = false;
        _error = _sshTunnel.lastError ?? 'SSH tunnel failed';
        notifyListeners();
      } else if (status == SshTunnelStatus.connected && _useSshTunnel && _initialized) {
        _api.setBaseUrl(_sshTunnel.localUrl);
        _checkAndConnect();
      }
    });

    if (_useSshTunnel) {
      final config = await SshConfig.load();
      if (config.isValid) {
        final ok = await _sshTunnel.connect(config);
        if (ok) {
          await _api.setBaseUrl(_sshTunnel.localUrl);
        }
      }
    }

    _isConnected = await _api.checkHealth();
    _initialized = true;
    notifyListeners();
    if (_isConnected) {
      _connectEvents();
      await loadSessions();
      await _refreshModels();
    }
  }

  Future<void> _checkAndConnect() async {
    _isConnected = await _api.checkHealth();
    if (_isConnected) {
      _connectEvents();
      await loadSessions();
      await _refreshModels();
    }
    notifyListeners();
  }

  Future<bool> connect(String serverUrl) async {
    if (_useSshTunnel) {
      await _sshTunnel.disconnect();
      final config = await SshConfig.load();
      if (config.isValid) {
        final ok = await _sshTunnel.connect(config);
        if (ok) {
          await _api.setBaseUrl(_sshTunnel.localUrl);
        } else {
          _isConnected = false;
          _error = _sshTunnel.lastError ?? 'SSH tunnel failed';
          notifyListeners();
          return false;
        }
      } else {
        _error = 'SSH config is incomplete';
        _isConnected = false;
        notifyListeners();
        return false;
      }
    } else {
      await _api.setBaseUrl(serverUrl);
    }

    await _saveLastConnectionMode();

    _isConnected = await _api.checkHealth();
    if (_isConnected) {
      _connectEvents();
      await loadSessions();
      await _refreshModels();
    }
    notifyListeners();
    return _isConnected;
  }

  Future<void> setSshTunnelEnabled(bool enabled) async {
    _useSshTunnel = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_ssh_tunnel', enabled);
    if (!enabled && _sshTunnel.isConnected) {
      await _sshTunnel.disconnect();
    }
    notifyListeners();
  }

  Future<void> _loadSshTunnelPref() async {
    final prefs = await SharedPreferences.getInstance();
    _useSshTunnel = prefs.getBool('use_ssh_tunnel') ?? false;
  }

  Future<void> _saveLastConnectionMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_ssh_tunnel', _useSshTunnel);
    if (!_useSshTunnel) {
      await prefs.setString('last_server_url', _api.baseUrl);
    }
  }

  Future<void> _loadLastConnectionMode() async {
    final prefs = await SharedPreferences.getInstance();
    _useSshTunnel = prefs.getBool('use_ssh_tunnel') ?? false;
    if (!_useSshTunnel) {
      final lastUrl = prefs.getString('last_server_url');
      if (lastUrl != null) {
        _api.setBaseUrl(lastUrl);
      }
    }
  }

  Future<void> _loadSelectedModel() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedModel = prefs.getString('selected_model');
  }

  Future<void> _saveSelectedModel() async {
    final prefs = await SharedPreferences.getInstance();
    if (_selectedModel != null) {
      await prefs.setString('selected_model', _selectedModel!);
    }
  }

  Future<void> _refreshModels() async {
    try {
      final data = await _api.fetchProviders();
      final all = (data['all'] as List<dynamic>?) ?? [];

      final models = <ModelOption>[];
      for (final provider in all) {
        final p = provider as Map<String, dynamic>;
        final pid = p['id'] as String? ?? '';
        final pname = p['name'] as String? ?? pid;
        final pmodels = p['models'] as Map<String, dynamic>? ?? {};
        for (final entry in pmodels.entries) {
          final m = entry.value as Map<String, dynamic>? ?? {};
          final mname = m['name'] as String? ?? entry.key;
          models.add(ModelOption(
            id: '$pid/${entry.key}',
            providerName: pname,
            modelName: mname,
          ));
        }
      }

      // Sort: Opencode provider models first, Zen models at the very top
      models.sort((a, b) {
        final aIsOpeencode = a.id.startsWith('opencode/');
        final bIsOpeencode = b.id.startsWith('opencode/');
        if (aIsOpeencode && !bIsOpeencode) return -1;
        if (!aIsOpeencode && bIsOpeencode) return 1;
        final aIsZen = a.modelName.toLowerCase().contains('zen');
        final bIsZen = b.modelName.toLowerCase().contains('zen');
        if (aIsZen && !bIsZen) return -1;
        if (!aIsZen && bIsZen) return 1;
        return 0;
      });

      _availableModels = models;
      if (models.isNotEmpty) {
        if (_selectedModel == null || !models.any((m) => m.id == _selectedModel)) {
          _selectedModel = models.first.id;
          _saveSelectedModel();
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  void setModel(String modelId) {
    _selectedModel = modelId;
    _saveSelectedModel();
    notifyListeners();
  }

  void _connectEvents() {
    _eventSubscription?.cancel();
    _eventService.connect();
    _eventSubscription = _eventService.events.listen(_handleEvent);
  }

  Future<void> _handleEvent(SseEvent event) async {
    _sseEventCount++;
    if (event.type != EventType.messageDelta) {
      _log('SSE: ${event.rawEventType}');
    }

    switch (event.type) {
      case EventType.serverConnected:
        _log('SSE: server connected');
        break;
      case EventType.messageDelta:
        // Extract which session this delta belongs to
        String? eventSessionId = event.data['sessionID'] as String?
            ?? event.data['sessionId'] as String?
            ?? event.data['_sessionId'] as String?;
        if (eventSessionId == null || eventSessionId.isEmpty) {
          // Fallback: if only one session is generating, assume it's for that session
          if (_generatingSessions.length == 1) {
            eventSessionId = _generatingSessions.first;
          }
        }
        if (eventSessionId == null || eventSessionId.isEmpty) break;

        final delta = event.data['delta'] as String? ??
            event.data['content'] as String? ??
            event.data['text'] as String? ??
            '';
        if (delta.isNotEmpty) {
          final sessionMsgs = _sessionMessages.putIfAbsent(eventSessionId, () => []);
          var streaming = _streamingMessages[eventSessionId];
          if (streaming != null) {
            final oldText = streaming.textContent;
            final updatedParts = [Part(type: 'text', content: oldText + delta)];
            streaming = Message(
              id: streaming.id,
              sessionId: streaming.sessionId,
              role: 'assistant',
              parts: updatedParts,
              createdAt: streaming.createdAt,
            );
          } else {
            streaming = Message(
              id: 'streaming_${DateTime.now().millisecondsSinceEpoch}',
              sessionId: eventSessionId,
              role: 'assistant',
              parts: [Part(type: 'text', content: delta)],
              createdAt: DateTime.now(),
            );
          }
          _streamingMessages[eventSessionId] = streaming;

          final msgs = List<Message>.from(sessionMsgs);
          final existIdx = msgs.indexWhere((m) => m.id == streaming!.id);
          if (existIdx >= 0) {
            msgs[existIdx] = streaming;
          } else {
            msgs.add(streaming);
          }
          _sessionMessages[eventSessionId] = msgs;

          // Only notify if this is the currently viewed session
          if (_currentSession?.id == eventSessionId) {
            notifyListeners();
          }
        }
        break;
      case EventType.messageDone:
        // Try to determine which session completed
        String? doneSessionId = event.data['sessionID'] as String?
            ?? event.data['sessionId'] as String?
            ?? event.data['_sessionId'] as String?;
        if (doneSessionId == null || doneSessionId.isEmpty) {
          if (_generatingSessions.length == 1) {
            doneSessionId = _generatingSessions.first;
          }
        }
        if (doneSessionId != null && doneSessionId.isNotEmpty) {
          _streamingMessages.remove(doneSessionId);
          _generatingSessions.remove(doneSessionId);
          _generationTimers[doneSessionId]?.cancel();
          _generationTimers.remove(doneSessionId);
          // Refresh the session's messages from API
          _refreshMessagesFor(doneSessionId);
          // Also refresh sessions list (title may have been auto-updated)
          loadSessions();
        }
        if (_currentSession == null || _currentSession!.id == doneSessionId) {
          notifyListeners();
        }
        break;
      case EventType.sessionError:
        String? errSessionId = event.data['sessionID'] as String?
            ?? event.data['sessionId'] as String?
            ?? event.data['_sessionId'] as String?;
        if (errSessionId == null && _generatingSessions.length == 1) {
          errSessionId = _generatingSessions.first;
        }
        if (errSessionId != null) {
          _generatingSessions.remove(errSessionId);
          _generationTimers[errSessionId]?.cancel();
          _generationTimers.remove(errSessionId);
          final errorData = event.data['error'] as Map<String, dynamic>?;
          if (errorData != null) {
            _error = errorData['message'] as String? ?? 'Session error';
          }
        }
        notifyListeners();
        break;
      case EventType.sessionStatus:
      case EventType.toolStart:
      case EventType.toolDone:
        break;
      case EventType.sessionUpdated:
        final info = event.data['info'] as Map<String, dynamic>?;
        if (info != null) {
          final updated = Session.fromJson(info);
          if (_currentSession?.id == updated.id) {
            _currentSession = updated;
          }
          final idx = _sessions.indexWhere((s) => s.id == updated.id);
          if (idx >= 0) _sessions[idx] = updated;
          notifyListeners();
        }
        break;
      default:
        break;
    }
  }

  Future<void> _refreshMessagesFor(String sessionId) async {
    try {
      final msgs = await _api.listMessages(sessionId);
      // Filter out empty assistant messages (e.g. from aborted generations)
      final filtered = msgs.where((m) => !m.isAssistant || m.textContent.trim().isNotEmpty).toList();
      final hasStreaming = _streamingMessages.containsKey(sessionId);
      if (!hasStreaming) {
        _sessionMessages[sessionId] = filtered;
      } else {
        // Merge: keep streaming message at end
        final streaming = _streamingMessages[sessionId]!;
        final withoutStreaming = filtered.where((m) => m.id != streaming.id).toList();
        _sessionMessages[sessionId] = [...withoutStreaming, streaming];
      }
      if (_currentSession?.id == sessionId) {
        notifyListeners();
      }
    } catch (e) {
      _log('refreshMsgFor $sessionId: ERROR $e');
    }
  }

  Future<void> _finishGenerationFor(String sessionId) async {
    _generatingSessions.remove(sessionId);
    _streamingMessages.remove(sessionId);
    _generationTimers[sessionId]?.cancel();
    _generationTimers.remove(sessionId);
    await _refreshMessagesFor(sessionId);
  }

  Future<void> loadSessions() async {
    _isLoading = true;
    notifyListeners();
    try {
      _sessions = await _api.listSessions();
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> createSession({String? title}) async {
    _isLoading = true;
    notifyListeners();
    try {
      final session = await _api.createSession(title: title);
      _sessions.insert(0, session);
      _currentSession = session;
      _sessionMessages[session.id] = [];
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    _restartPolling();
    notifyListeners();
  }

  Future<void> selectSession(String id) async {
    if (_currentSession?.id == id) return;
    _isLoading = true;
    _currentSession = null;
    notifyListeners();
    try {
      final session = await _api.getSession(id);
      _currentSession = session;
      // Always refresh messages from server to support multi-device sync
      await _refreshMessagesFor(session.id);
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    _restartPolling();
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    clearError();
    if (_currentSession == null) {
      _log('sendMessage: session is null, creating...');
      await createSession();
      if (_currentSession == null) {
        _error ??= 'No session available. Try creating a new session first.';
        _log('  createSession FAILED');
        notifyListeners();
        return;
      }
      _log('  created session: ${_currentSession!.id}');
    }

    final sessionId = _currentSession!.id;

    // Check if this specific session is already generating
    if (_generatingSessions.contains(sessionId)) {
      _error = '当前会话正在生成中，请稍后再试';
      notifyListeners();
      return;
    }

    final userMsg = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      sessionId: sessionId,
      role: 'user',
      parts: [Part(type: 'text', content: text)],
      createdAt: DateTime.now(),
    );

    // Add to this session's message list
    _sessionMessages.putIfAbsent(sessionId, () => []);
    _sessionMessages[sessionId] = [..._sessionMessages[sessionId]!, userMsg];
    _generatingSessions.add(sessionId);
    _generationDone.remove(sessionId);
    _log('  local msg added, msgs=${_sessionMessages[sessionId]?.length}, generating=true');
    notifyListeners();

    _generationTimers[sessionId]?.cancel();
    _generationTimers[sessionId] = Timer(const Duration(seconds: 120), () async {
      if (_generatingSessions.contains(sessionId)) {
        _log('timer 120s timeout -> finishGeneration for $sessionId');
        await _finishGenerationFor(sessionId);
        if (_currentSession?.id == sessionId) {
          notifyListeners();
        }
      }
    });

    try {
      _log('  calling API sendMessage for session $sessionId...');
      final responseMsg = await _api.sendMessage(
        sessionId,
        text,
        model: _selectedModel,
      );
      _log('  API returned: role=${responseMsg.role}, id=${responseMsg.id}');

      // If user already switched away, still update the cache for that session
      _generatingSessions.remove(sessionId);
      _generationTimers[sessionId]?.cancel();
      _generationTimers.remove(sessionId);

      if (responseMsg.isUser) {
        // Replace the local user message with server version
        final msgs = _sessionMessages[sessionId] ?? [];
        _sessionMessages[sessionId] = msgs.map((m) {
          if (m.role == 'user' && m.id == userMsg.id) return responseMsg;
          return m;
        }).toList();
        _log('  replaced local user msg with server version');
      } else if (responseMsg.isAssistant) {
        final msgs = _sessionMessages[sessionId] ?? [];
        _sessionMessages[sessionId] = [...msgs, responseMsg];
        _log('  added assistant msg for session $sessionId');
      }
      // Refresh from API to get any server-side parts
      await _refreshMessagesFor(sessionId);
      if (_currentSession?.id == sessionId) {
        notifyListeners();
      }
    } catch (e) {
      _log('  API ERROR for session $sessionId: $e');
      _generatingSessions.remove(sessionId);
      _generationTimers[sessionId]?.cancel();
      _generationTimers.remove(sessionId);
      // If the user intentionally aborted, don't show error or failed message
      if (_abortedSessions.remove(sessionId)) {
        _log('  aborted by user, skipping error');
        if (_currentSession?.id == sessionId) {
          notifyListeners();
        }
        return;
      }
      _error = e.toString();
      _sessionFailedMessages[sessionId] = _FailedMessage(text, DateTime.now());
      if (_currentSession?.id == sessionId) {
        notifyListeners();
      }
    }
  }

  Future<void> retryLastMessage() async {
    if (_currentSession == null) return;
    final sessionId = _currentSession!.id;
    final failed = _sessionFailedMessages.remove(sessionId);
    if (failed == null) return;
    _error = null;
    notifyListeners();
    await sendMessage(failed.text);
  }

  Future<void> deleteSession(String id) async {
    try {
      await _api.deleteSession(id);
      _sessions.removeWhere((s) => s.id == id);
      _sessionMessages.remove(id);
      _generatingSessions.remove(id);
      _streamingMessages.remove(id);
      _generationTimers.remove(id);
      _sessionFailedMessages.remove(id);
      if (_currentSession?.id == id) {
        final newSession = _sessions.isNotEmpty ? _sessions.first : null;
        _currentSession = newSession;
        if (newSession != null) {
          await _refreshMessagesFor(newSession.id);
        }
      }
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  final Map<String, List<String>> _searchCache = {};
  static const int _searchMaxSessions = 20;
  static const int _searchCacheMaxSize = 50;

  void _cacheSearchQuery(String query, List<String> ids) {
    _searchCache[query] = ids;
    if (_searchCache.length > _searchCacheMaxSize) {
      final removeCount = _searchCache.length - _searchCacheMaxSize;
      final keysToRemove = _searchCache.keys.take(removeCount).toList();
      for (final key in keysToRemove) {
        _searchCache.remove(key);
      }
    }
  }

  Future<List<Session>> searchSessions(String query) async {
    if (query.trim().isEmpty) return _sessions;
    final lowerQuery = query.toLowerCase();

    if (_searchCache.containsKey(lowerQuery)) {
      final ids = _searchCache[lowerQuery]!;
      return _sessions.where((s) => ids.contains(s.id)).toList();
    }

    final titleMatches = _sessions.where((s) =>
        (s.title?.toLowerCase().contains(lowerQuery) ?? false) ||
        s.id.toLowerCase().contains(lowerQuery)).toList();

    final recent = _sessions.take(_searchMaxSessions).toList();
    final nonTitleMatches = recent.where((s) =>
        !titleMatches.contains(s) &&
        !(s.title?.toLowerCase().contains(lowerQuery) ?? false) &&
        !s.id.toLowerCase().contains(lowerQuery)).toList();

    if (nonTitleMatches.isEmpty) {
      _cacheSearchQuery(lowerQuery, titleMatches.map((s) => s.id).toList());
      return titleMatches;
    }

    final contentMatches = <Session>[];
    await Future.wait(
      nonTitleMatches.map((session) async {
        try {
          final msgs = await _api.listMessages(session.id, limit: 20)
              .timeout(const Duration(seconds: 2));
          final hasMatch = msgs.any((m) =>
              m.textContent.toLowerCase().contains(lowerQuery));
          if (hasMatch) contentMatches.add(session);
        } catch (_) {}
      }),
    );

    final result = [...titleMatches, ...contentMatches];
    _cacheSearchQuery(lowerQuery, result.map((s) => s.id).toList());
    return result;
  }

  void clearSearchCache() {
    _searchCache.clear();
  }

  Future<void> abortGeneration() async {
    if (_currentSession == null) return;
    final sessionId = _currentSession!.id;
    _generatingSessions.remove(sessionId);
    _generationTimers[sessionId]?.cancel();
    _generationTimers.remove(sessionId);
    _abortedSessions.add(sessionId);

    // Remove the streaming message from _sessionMessages so the partial /
    // empty assistant bubble does not stay visible after abort.
    final streamingMsg = _streamingMessages.remove(sessionId);
    if (streamingMsg != null) {
      final msgs = _sessionMessages[sessionId];
      if (msgs != null) {
        _sessionMessages[sessionId] =
            msgs.where((m) => m.id != streamingMsg.id).toList();
      }
    }

    // Cancel the pending HTTP request immediately so the UI updates right away
    _api.cancelPendingRequest();
    try {
      await _api.abortSession(sessionId);
    } catch (_) {}
    notifyListeners();

    // Refresh from server after a short delay to get a clean message list
    // (the server may have persisted a partial message before processing abort).
    Future.delayed(const Duration(seconds: 1), () {
      if (_currentSession?.id == sessionId) {
        _refreshMessagesFor(sessionId);
      }
    });
  }

  // -- Periodic polling for multi-device sync --

  void _restartPolling() {
    _pollingTimer?.cancel();
    if (_currentSession != null && _isConnected) {
      _pollingTimer = Timer.periodic(_pollingInterval, (_) => _pollCurrentSession());
    }
  }

  Future<void> _pollCurrentSession() async {
    if (_currentSession == null || !_isConnected) return;
    // Skip polling if the session is currently generating (SSE handles it)
    if (_generatingSessions.contains(_currentSession!.id)) return;
    try {
      final sessionId = _currentSession!.id;
      final msgs = await _api.listMessages(sessionId);
      // Filter out empty assistant messages (e.g. from aborted generations),
      // consistent with _refreshMessagesFor().
      final filtered = msgs
          .where((m) => !m.isAssistant || m.textContent.trim().isNotEmpty)
          .toList();
      final cached = _sessionMessages[sessionId] ?? [];
      // Only update and notify if message count changed (avoid unnecessary rebuilds)
      if (filtered.length != cached.length ||
          (filtered.isNotEmpty &&
              cached.isNotEmpty &&
              filtered.last.id != cached.last.id)) {
        _sessionMessages[sessionId] = filtered;
        _log('poll: session $sessionId updated (${cached.length} -> ${filtered.length} msgs)');
        if (_currentSession?.id == sessionId) {
          notifyListeners();
        }
      }
    } catch (e) {
      _log('poll: ERROR $e');
    }
  }

  /// Called when the app comes back to foreground.
  /// Refreshes sessions list and current session messages.
  Future<void> onAppResumed() async {
    if (!_isConnected || !_initialized) return;
    _log('app resumed -> refreshing');
    _restartPolling();
    // Refresh session list (other device may have created/deleted sessions)
    await loadSessions();
    // Refresh current session messages
    if (_currentSession != null) {
      await _refreshMessagesFor(_currentSession!.id);
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    for (final timer in _generationTimers.values) {
      timer.cancel();
    }
    _generationTimers.clear();
    _eventSubscription?.cancel();
    _sshStatusSubscription?.cancel();
    _eventService.dispose();
    _sshTunnel.disconnect();
    super.dispose();
  }
}
