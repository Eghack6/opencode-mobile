import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum SshTunnelStatus {
  disconnected,
  connecting,
  connected,
  failed,
}

class SshConfig {
  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKey;
  final String remoteHost;
  final int remotePort;

  const SshConfig({
    this.host = '',
    this.port = 22,
    this.username = '',
    this.password,
    this.privateKey,
    this.remoteHost = 'localhost',
    this.remotePort = 4096,
  });

  bool get isValid =>
      host.isNotEmpty && username.isNotEmpty && (password != null || privateKey != null);

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'privateKey': privateKey,
        'remoteHost': remoteHost,
        'remotePort': remotePort,
      };

  factory SshConfig.fromJson(Map<String, dynamic> json) => SshConfig(
        host: json['host'] as String? ?? '',
        port: json['port'] as int? ?? 22,
        username: json['username'] as String? ?? '',
        password: json['password'] as String?,
        privateKey: json['privateKey'] as String?,
        remoteHost: json['remoteHost'] as String? ?? 'localhost',
        remotePort: json['remotePort'] as int? ?? 4096,
      );

  factory SshConfig.parse(String input) {
    final trimmed = input.trim();
    String host = '';
    int port = 22;
    String username = '';

    final atIdx = trimmed.indexOf('@');
    if (atIdx > 0) {
      username = trimmed.substring(0, atIdx);
      final rest = trimmed.substring(atIdx + 1);
      final colonIdx = rest.indexOf(':');
      if (colonIdx > 0) {
        host = rest.substring(0, colonIdx);
        port = int.tryParse(rest.substring(colonIdx + 1)) ?? 22;
      } else {
        host = rest;
      }
    } else {
      host = trimmed;
    }

    return SshConfig(host: host, port: port, username: username);
  }

  static const _storage = FlutterSecureStorage();
  static const _storageKey = 'ssh_config';

  static Future<SshConfig> load() async {
    try {
      final json = await _storage.read(key: _storageKey);
      if (json == null) return const SshConfig();
      return SshConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return const SshConfig();
    }
  }

  Future<void> save() async {
    await _storage.write(key: _storageKey, value: jsonEncode(toJson()));
  }

  static Future<void> clear() async {
    await _storage.delete(key: _storageKey);
  }
}

class SshTunnelService {
  static final SshTunnelService _instance = SshTunnelService._();
  factory SshTunnelService() => _instance;
  SshTunnelService._();

  SSHClient? _client;
  ServerSocket? _serverSocket;
  final List<Socket> _localSockets = [];
  final List<SSHForwardChannel> _forwardChannels = [];

  SshTunnelStatus _status = SshTunnelStatus.disconnected;
  String? _lastError;
  int? _localPort;
  SshConfig? _config;
  int _retryCount = 0;
  Timer? _reconnectTimer;
  static const int _maxRetries = 3;
  static const List<int> _retryDelays = [2, 5, 10];

  SshTunnelStatus get status => _status;
  String? get lastError => _lastError;
  int? get localPort => _localPort;
  bool get isConnected => _status == SshTunnelStatus.connected;
  SshConfig? get config => _config;
  int get retryCount => _retryCount;

  final _statusController = StreamController<SshTunnelStatus>.broadcast();
  Stream<SshTunnelStatus> get onStatusChanged => _statusController.stream;

  void _setStatus(SshTunnelStatus status) {
    _status = status;
    _statusController.add(status);
  }

  Future<bool> connect(SshConfig config, {bool autoRetry = true}) async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (_status == SshTunnelStatus.connected) await disconnect();
    _config = config;
    _lastError = null;
    _setStatus(SshTunnelStatus.connecting);

    try {
      final socket = await SSHSocket.connect(
        config.host,
        config.port,
        timeout: const Duration(seconds: 15),
      );

      List<SSHKeyPair>? identities;
      if (config.privateKey != null && config.privateKey!.isNotEmpty) {
        final keyPairs = SSHKeyPair.fromPem(config.privateKey!);
        if (keyPairs.isNotEmpty) identities = keyPairs;
      }

      final completer = Completer<void>();
      bool authSucceeded = false;

      _client = SSHClient(
        socket,
        username: config.username,
        identities: identities,
        onPasswordRequest: () => config.password ?? '',
        onAuthenticated: () {
          authSucceeded = true;
          if (!completer.isCompleted) completer.complete();
        },
      );

      _client!.done.then((_) {
        if (_status == SshTunnelStatus.connected) {
          _lastError = 'SSH connection lost';
          _setStatus(SshTunnelStatus.failed);
          if (autoRetry) _scheduleReconnect();
        }
      });

      await completer.future.timeout(const Duration(seconds: 15));

      if (!authSucceeded) {
        throw Exception('SSH authentication failed');
      }

      _serverSocket = await ServerSocket.bind('127.0.0.1', 0);
      _localPort = _serverSocket!.port;

      _serverSocket!.listen((localSocket) {
        _forwardTunnel(localSocket);
      });

      _retryCount = 0;
      _setStatus(SshTunnelStatus.connected);
      return true;
    } catch (e) {
      _lastError = e.toString();
      _setStatus(SshTunnelStatus.failed);
      await _cleanup();
      if (autoRetry) _scheduleReconnect();
      return false;
    }
  }

  void _scheduleReconnect() {
    if (_retryCount >= _maxRetries) return;
    final delay = _retryDelays[_retryCount.clamp(0, _retryDelays.length - 1)];
    _retryCount++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delay), () async {
      if (_config != null && _status != SshTunnelStatus.connected) {
        await connect(_config!, autoRetry: true);
      }
    });
  }

  void _forwardTunnel(Socket localSocket) async {
    _localSockets.add(localSocket);
    if (_client == null) {
      try { localSocket.destroy(); } catch (_) {}
      _localSockets.remove(localSocket);
      return;
    }
    try {
      final forward = await _client!.forwardLocal(
        config!.remoteHost,
        config!.remotePort,
      );
      _forwardChannels.add(forward);

      forward.stream.listen(
        (data) {
          try {
            localSocket.add(data);
          } catch (_) {}
        },
        onError: (_) {
          try { localSocket.destroy(); } catch (_) {}
          _localSockets.remove(localSocket);
          _forwardChannels.remove(forward);
        },
        onDone: () {
          try { localSocket.destroy(); } catch (_) {}
          _localSockets.remove(localSocket);
          _forwardChannels.remove(forward);
        },
      );

      localSocket.listen(
        (data) {
          try {
            forward.sink.add(data);
          } catch (_) {}
        },
        onError: (_) {
          try { forward.close(); } catch (_) {}
          _forwardChannels.remove(forward);
          _localSockets.remove(localSocket);
        },
        onDone: () {
          try { forward.close(); } catch (_) {}
          _forwardChannels.remove(forward);
          _localSockets.remove(localSocket);
        },
      );
    } catch (e) {
      try { localSocket.destroy(); } catch (_) {}
      _localSockets.remove(localSocket);
    }
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _retryCount = 0;
    await _cleanup();
    _setStatus(SshTunnelStatus.disconnected);
  }

  Future<void> _cleanup() async {
    for (final s in _localSockets.toList()) {
      try { s.destroy(); } catch (_) {}
    }
    _localSockets.clear();

    for (final ch in _forwardChannels.toList()) {
      try { ch.close(); } catch (_) {}
    }
    _forwardChannels.clear();

    try { await _serverSocket?.close(); } catch (_) {}
    _serverSocket = null;
    _localPort = null;

    try { _client?.close(); } catch (_) {}
    _client = null;
  }

  String get localUrl {
    if (_localPort == null) return '';
    return 'http://127.0.0.1:$_localPort';
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _cleanup();
    _statusController.close();
  }
}
