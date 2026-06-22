import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/session.dart';
import '../models/message.dart';

class ApiLogEntry {
  final DateTime time;
  final String method;
  final String url;
  final String? requestBody;
  final int? statusCode;
  final String? responseBody;
  final String? error;

  ApiLogEntry({
    required this.time,
    required this.method,
    required this.url,
    this.requestBody,
    this.statusCode,
    this.responseBody,
    this.error,
  });
}

class ApiService {
  String _baseUrl = 'http://localhost:4096';
  bool _debug = false;
  final List<ApiLogEntry> _logs = [];
  static const int _maxLogs = 200;

  static final ApiService _instance = ApiService._();
  factory ApiService() => _instance;
  ApiService._();

  String get baseUrl => _baseUrl;
  bool get debug => _debug;
  List<ApiLogEntry> get logs => List.unmodifiable(_logs);

  void setDebug(bool enabled) => _debug = enabled;
  void clearLogs() => _logs.clear();

  void _log(String method, String url, {String? body, int? status, String? response, String? error}) {
    if (!_debug) return;
    _logs.add(ApiLogEntry(
      time: DateTime.now(),
      method: method,
      url: url,
      requestBody: body,
      statusCode: status,
      responseBody: response,
      error: error,
    ));
    if (_logs.length > _maxLogs) _logs.removeAt(0);
  }

  Future<void> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('server_url') ?? 'http://localhost:4096';
  }

  Future<void> setBaseUrl(String url) async {
    _baseUrl = url;
    if (url.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_url', url);
    }
  }

  Map<String, String> get _headers => {'Content-Type': 'application/json'};

  Future<bool> checkHealth() async {
    final uri = Uri.parse('$_baseUrl/global/health');
    _log('GET', uri.toString());
    try {
      final response = await http.get(uri, headers: _headers).timeout(
            const Duration(seconds: 5),
          );
      _log('GET', uri.toString(), status: response.statusCode, response: response.body);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['healthy'] == true;
      }
      return false;
    } catch (e) {
      _log('GET', uri.toString(), error: e.toString());
      return false;
    }
  }

  Future<List<Session>> listSessions() async {
    final uri = Uri.parse('$_baseUrl/session');
    _log('GET', uri.toString());
    try {
      final response = await http.get(uri, headers: _headers);
      _log('GET', uri.toString(), status: response.statusCode, response: response.body);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((j) => Session.fromJson(j)).toList();
      }
      throw Exception('Failed to list sessions: ${response.statusCode}');
    } catch (e) {
      _log('GET', uri.toString(), error: e.toString());
      rethrow;
    }
  }

  Future<Session> createSession({String? parentID, String? title}) async {
    final uri = Uri.parse('$_baseUrl/session');
    final body = <String, dynamic>{};
    if (parentID != null) body['parentID'] = parentID;
    if (title != null) body['title'] = title;
    final bodyStr = jsonEncode(body);
    _log('POST', uri.toString(), body: bodyStr);
    try {
      final response = await http.post(uri, headers: _headers, body: bodyStr);
      _log('POST', uri.toString(), status: response.statusCode, response: response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return Session.fromJson(jsonDecode(response.body));
      }
      throw Exception('Failed to create session: ${response.statusCode}');
    } catch (e) {
      _log('POST', uri.toString(), error: e.toString());
      rethrow;
    }
  }

  Future<Session> getSession(String id) async {
    final uri = Uri.parse('$_baseUrl/session/$id');
    _log('GET', uri.toString());
    try {
      final response = await http.get(uri, headers: _headers);
      _log('GET', uri.toString(), status: response.statusCode, response: response.body);
      if (response.statusCode == 200) {
        return Session.fromJson(jsonDecode(response.body));
      }
      throw Exception('Failed to get session: ${response.statusCode}');
    } catch (e) {
      _log('GET', uri.toString(), error: e.toString());
      rethrow;
    }
  }

  Future<bool> deleteSession(String id) async {
    final uri = Uri.parse('$_baseUrl/session/$id');
    _log('DELETE', uri.toString());
    try {
      final response = await http.delete(uri, headers: _headers);
      _log('DELETE', uri.toString(), status: response.statusCode, response: response.body);
      return response.statusCode == 200;
    } catch (e) {
      _log('DELETE', uri.toString(), error: e.toString());
      rethrow;
    }
  }

  Future<List<Message>> listMessages(String sessionId, {int limit = 50, String? searchQuery}) async {
    var uriStr = '$_baseUrl/session/$sessionId/message?limit=$limit';
    if (searchQuery != null && searchQuery.isNotEmpty) {
      uriStr += '&search=${Uri.encodeComponent(searchQuery)}';
    }
    final uri = Uri.parse(uriStr);
    _log('GET', uri.toString());
    try {
      final response = await http.get(uri, headers: _headers);
      _log('GET', uri.toString(), status: response.statusCode, response: response.body);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((j) {
          final info = j['info'] as Map<String, dynamic>;
          final parts = j['parts'] as List<dynamic>? ?? [];
          info['parts'] = parts;
          return Message.fromJson(info);
        }).toList();
      }
      throw Exception('Failed to list messages: ${response.statusCode}');
    } catch (e) {
      _log('GET', uri.toString(), error: e.toString());
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchProviders() async {
    final uri = Uri.parse('$_baseUrl/provider');
    _log('GET', uri.toString());
    try {
      final response = await http.get(uri, headers: _headers);
      _log('GET', uri.toString(), status: response.statusCode, response: response.body);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw Exception('Failed to fetch providers: ${response.statusCode}');
    } catch (e) {
      _log('GET', uri.toString(), error: e.toString());
      rethrow;
    }
  }

  Map<String, dynamic>? _parseModel(String? model) {
    if (model == null) return null;
    final slash = model.indexOf('/');
    if (slash <= 0 || slash >= model.length - 1) return null;
    return {
      'providerID': model.substring(0, slash),
      'modelID': model.substring(slash + 1),
    };
  }

  Future<Message> sendMessage(String sessionId, String text,
      {String? messageID, String? model}) async {
    final uri = Uri.parse('$_baseUrl/session/$sessionId/message');
    final body = <String, dynamic>{
      if (messageID != null) 'messageID': messageID,
      if (model != null) 'model': _parseModel(model),
      'parts': [
        {'type': 'text', 'text': text}
      ],
    };
    final bodyStr = jsonEncode(body);
    _log('POST', uri.toString(), body: bodyStr);
    final client = http.Client();
    try {
      final request = http.Request('POST', uri);
      request.headers.addAll(_headers);
      request.body = bodyStr;
      final streamedResponse = await client.send(request).timeout(
            const Duration(seconds: 300),
          );
      final responseBody = await streamedResponse.stream.bytesToString();
      _log('POST', uri.toString(),
          status: streamedResponse.statusCode, response: responseBody);
      if (streamedResponse.statusCode == 200) {
        final data = jsonDecode(responseBody);
        final info = data['info'] as Map<String, dynamic>;
        final parts = data['parts'] as List<dynamic>? ?? [];
        info['parts'] = parts;
        return Message.fromJson(info);
      }
      final errMsg =
          responseBody.isNotEmpty ? responseBody : 'Status ${streamedResponse.statusCode}';
      throw Exception('Failed to send message: $errMsg');
    } finally {
      client.close();
    }
  }

  Future<bool> abortSession(String sessionId) async {
    final uri = Uri.parse('$_baseUrl/session/$sessionId/abort');
    _log('POST', uri.toString());
    try {
      final response = await http.post(uri, headers: _headers);
      _log('POST', uri.toString(), status: response.statusCode, response: response.body);
      return response.statusCode == 200;
    } catch (e) {
      _log('POST', uri.toString(), error: e.toString());
      rethrow;
    }
  }

  Uri get eventUri => Uri.parse('$_baseUrl/global/event');
}
