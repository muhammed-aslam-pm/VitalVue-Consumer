import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../auth/auth_token_store.dart';
import 'sse_events.dart';

/// Connects to the server-sent-events endpoint
/// `GET /api/v1/vitals/stream?token=<access_token>` and emits typed
/// [SseEvent]s, reconnecting automatically after any drop.
class VitalsSseService {
  VitalsSseService({
    required String baseUrl,
    required AuthTokenStore tokenStore,
  })  : _baseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/',
        _tokenStore = tokenStore;

  final String _baseUrl;
  final AuthTokenStore _tokenStore;
  HttpClient? _httpClient;

  String get _endpoint => '${_baseUrl}api/v1/stream/assigned/stream';

  /// Returns a [Stream] of [SseEvent]s that reconnects automatically.
  /// Cancel the returned [StreamSubscription] to stop the service.
  Stream<SseEvent> connect() {
    late StreamController<SseEvent> ctrl;
    ctrl = StreamController<SseEvent>(
      onCancel: () {
        _httpClient?.close(force: true);
        _httpClient = null;
      },
    );
    _loop(ctrl);
    return ctrl.stream;
  }

  Future<void> _loop(StreamController<SseEvent> ctrl) async {
    while (!ctrl.isClosed) {
      try {
        final token = await _tokenStore.accessToken ?? '';
        if (token.isEmpty) {
          await Future.delayed(const Duration(seconds: 5));
          continue;
        }

        _httpClient = HttpClient()
          ..connectionTimeout = const Duration(seconds: 30);

        final uri = Uri.parse(_endpoint).replace(
          queryParameters: {'token': token},
        );

        print('SSE: Connecting to $uri...');

        final req = await _httpClient!.getUrl(uri);
        req.headers
          ..set(HttpHeaders.acceptHeader, 'text/event-stream')
          ..set(HttpHeaders.cacheControlHeader, 'no-cache');

        final resp = await req.close();

        print('SSE: HTTP ${resp.statusCode}');

        if (resp.statusCode != 200) {
          throw Exception('SSE HTTP ${resp.statusCode}');
        }

        if (!ctrl.isClosed) {
          print('SSE: Connected successfully!');
          ctrl.add(const SseConnectedEvent());
        }

        String? eventType;
        String? dataBuf;

        await for (final line in resp
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          if (ctrl.isClosed) break;

          if (line.startsWith('event: ')) {
            eventType = line.substring(7).trim();
          } else if (line.startsWith('data: ')) {
            dataBuf = line.substring(6).trim();
          } else if (line.isEmpty) {
            // Empty line = end of event block
            if (eventType != null && dataBuf != null) {
              print('SSE: Received event: $eventType\nSSE Data: $dataBuf');
              final ev = _parse(eventType, dataBuf);
              if (ev != null && !ctrl.isClosed) ctrl.add(ev);
            }
            eventType = null;
            dataBuf = null;
          }
          // Lines starting with ':' are pings/comments — ignore
        }
      } catch (e) {
        print('SSE: Connection error: $e');
        if (!ctrl.isClosed) {
          ctrl.add(SseDisconnectedEvent(e.toString()));
        }
      } finally {
        _httpClient?.close(force: true);
        _httpClient = null;
      }

      // Reconnect delay
      if (!ctrl.isClosed) {
        await Future.delayed(const Duration(seconds: 3));
      }
    }
  }

  SseEvent? _parse(String type, String data) {
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      switch (type) {
        case 'patient_vital_update':
          return SseVitalUpdateEvent.fromJson(json);
        case 'critical_alert':
          return SseCriticalAlertEvent.fromJson(json);
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }
}
