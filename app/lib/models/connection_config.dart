import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ConnectionConfig {
  final String name;
  final String serverUrl;
  final bool useSshTunnel;
  final String sshHost;
  final int sshPort;
  final String sshUsername;
  final String? sshPassword;
  final String? sshPrivateKey;
  final String sshRemoteHost;
  final int sshRemotePort;

  ConnectionConfig({
    required this.name,
    this.serverUrl = '',
    this.useSshTunnel = false,
    this.sshHost = '',
    this.sshPort = 22,
    this.sshUsername = '',
    this.sshPassword,
    this.sshPrivateKey,
    this.sshRemoteHost = 'localhost',
    this.sshRemotePort = 4096,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'serverUrl': serverUrl,
        'useSshTunnel': useSshTunnel,
        'sshHost': sshHost,
        'sshPort': sshPort,
        'sshUsername': sshUsername,
        'sshPassword': sshPassword,
        'sshPrivateKey': sshPrivateKey,
        'sshRemoteHost': sshRemoteHost,
        'sshRemotePort': sshRemotePort,
      };

  factory ConnectionConfig.fromJson(Map<String, dynamic> json) =>
      ConnectionConfig(
        name: json['name'] as String? ?? '',
        serverUrl: json['serverUrl'] as String? ?? '',
        useSshTunnel: json['useSshTunnel'] as bool? ?? false,
        sshHost: json['sshHost'] as String? ?? '',
        sshPort: json['sshPort'] as int? ?? 22,
        sshUsername: json['sshUsername'] as String? ?? '',
        sshPassword: json['sshPassword'] as String?,
        sshPrivateKey: json['sshPrivateKey'] as String?,
        sshRemoteHost: json['sshRemoteHost'] as String? ?? 'localhost',
        sshRemotePort: json['sshRemotePort'] as int? ?? 4096,
      );

  /// Display subtitle for the config card
  String get subtitle {
    if (useSshTunnel) {
      return 'SSH: $sshUsername@$sshHost:$sshPort';
    }
    return serverUrl.isNotEmpty ? serverUrl : '未配置地址';
  }
}

class ConfigStore {
  static const String _key = 'saved_connection_configs';

  static Future<List<ConnectionConfig>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => ConnectionConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveAll(List<ConnectionConfig> configs) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(configs.map((c) => c.toJson()).toList());
    await prefs.setString(_key, raw);
  }

  static Future<void> add(ConnectionConfig config) async {
    final configs = await loadAll();
    configs.add(config);
    await saveAll(configs);
  }

  static Future<void> remove(int index) async {
    final configs = await loadAll();
    if (index >= 0 && index < configs.length) {
      configs.removeAt(index);
      await saveAll(configs);
    }
  }

  static Future<void> replace(int index, ConnectionConfig config) async {
    final configs = await loadAll();
    if (index >= 0 && index < configs.length) {
      configs[index] = config;
      await saveAll(configs);
    }
  }
}
