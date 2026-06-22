import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

enum EventType {
  serverConnected,
  messageStart,
  messageDelta,
  messageDone,
  messageError,
  toolStart,
  toolDone,
  sessionIdle,
  sessionStatus,
  sessionError,
  sessionUpdated,
  unknown,
}

class SseEvent {
  final EventType type;
  final Map<String, dynamic> data;
  final String rawEventType;

  SseEvent({required this.type, required this.data, this.rawEventType = ''});
}

class EventService {
  http.Client? _client;
  StreamSubscription? _subscription;
  final _controller = StreamController<SseEvent>.broadcast();
  final ApiService _api = ApiService();

  final List<String> _logs = [];
  List<String> get logs => List.unmodifiable(_logs);

  void _logSse(String msg) {
    final ts = DateTime.now().toString().substring(11, 23);
    _logs.add('$ts $msg');
    if (_logs.length > 100) _logs.removeAt(0);
    print('[SSE] $msg');
  }

  void clearLogs() => _logs.clear();

  Stream<SseEvent> get events => _controller.stream;
  bool get isConnected => _subscription != null;

  void connect() {
    disconnect();
    _logSse('Connecting to ${_api.eventUri}...');
    _client = http.Client();
    final request = http.Request('GET', _api.eventUri);
    _client!.send(request).then((response) {
      _logSse('Connected! status=${response.statusCode}');
      final stream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      String currentEvent = '';
      StringBuffer dataBuffer = StringBuffer();
      _subscription = stream.listen(
        (line) {
          if (line.startsWith('event: ')) {
            currentEvent = line.substring(7).trim();
          } else if (line.startsWith('data: ')) {
            dataBuffer.write(line.substring(6));
          } else if (line.isEmpty && currentEvent.isNotEmpty) {
            _processEvent(currentEvent, dataBuffer.toString());
            currentEvent = '';
            dataBuffer = StringBuffer();
          }
        },
        onError: (error) {
          _logSse('ERROR: $error');
          _scheduleReconnect();
        },
        onDone: () {
          _logSse('STREAM CLOSED');
          _scheduleReconnect();
        },
      );
    }).catchError((error) {
      _logSse('CONNECT FAILED: $error');
      _scheduleReconnect();
    });
  }

  void _processEvent(String eventType, String rawData) {
    try {
      final parsed = jsonDecode(rawData);
      Map<String, dynamic> data;
      String resolvedType = eventType;

      if (parsed is Map<String, dynamic>) {
        if (parsed.containsKey('payload') && parsed['payload'] is Map) {
          final payload = parsed['payload'] as Map<String, dynamic>;
          resolvedType = (payload['type'] as String?) ?? eventType;
          data = (payload['properties'] as Map<String, dynamic>?) ?? {};
          data['_directory'] = parsed['directory'] as String? ?? '';
        } else {
          data = parsed;
        }
      } else {
        data = {'raw': rawData};
      }

      // Add sessionID from top-level if available (for session isolation)
      if (parsed is Map<String, dynamic>) {
        final sessionID = parsed['sessionID'] as String?
            ?? parsed['sessionId'] as String?
            ?? parsed['session'] as String?;
        if (sessionID != null) {
          data['_sessionId'] = sessionID;
        }
      }

      final mappedType = _mapEventType(resolvedType);
      final preview = rawData.length > 100 ? rawData.substring(0, 100) + '...' : rawData;
      _logSse('EVENT: "$eventType" -> "$resolvedType" (mapped: $mappedType) data=$preview');

      _controller.add(SseEvent(
        type: mappedType,
        data: data,
        rawEventType: resolvedType,
      ));
    } catch (e) {
      _logSse('EVENT PARSE ERROR: "$eventType" raw=$rawData err=$e');
      _controller.add(SseEvent(
        type: EventType.unknown,
        data: {'raw': rawData},
        rawEventType: eventType,
      ));
    }
  }

  EventType _mapEventType(String eventType) {
    switch (eventType) {
      case 'server.connected':
        return EventType.serverConnected;
      case 'message.part.updated':
      case 'message.updated':
      case 'message.delta':
      case 'stream.delta':
      case 'content.delta':
      case 'text.delta':
        return EventType.messageDelta;
      case 'session.idle':
      case 'message.done':
      case 'message.complete':
      case 'stream.end':
      case 'generation.done':
        return EventType.messageDone;
      case 'session.status':
        return EventType.sessionStatus;
      case 'session.error':
        return EventType.sessionError;
      case 'session.updated':
        return EventType.sessionUpdated;
      case 'tool.start':
      case 'tool.run':
        return EventType.toolStart;
      case 'tool.done':
      case 'tool.end':
        return EventType.toolDone;
      default:
        return EventType.unknown;
    }
  }

  void _scheduleReconnect() {
    disconnect();
    Timer(const Duration(seconds: 3), () {
      if (!isConnected) connect();
    });
  }

  void disconnect() {
    _subscription?.cancel();
    _subscription = null;
    _client?.close();
    _client = null;
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
