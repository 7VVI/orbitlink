import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final HttpClient _directClient = HttpClient()
  ..findProxy = ((Uri uri) => 'DIRECT')
  ..connectionTimeout = const Duration(seconds: 6);

/// Remote-control relays are normally LAN/localhost endpoints. Honouring the
/// machine-wide HTTP_PROXY setting here makes the WebSocket handshake get
/// answered by the proxy (HTTP 200) instead of the relay, so keep it direct.
WebSocketChannel connectRelay(String url) {
  return IOWebSocketChannel.connect(
    Uri.parse(url),
    customClient: _directClient,
    connectTimeout: const Duration(seconds: 6),
    pingInterval: const Duration(seconds: 20),
  );
}

/// Opens a LAN P2P video socket without going through a system proxy.
Future<WebSocket> connectDirectSocket(
  String url, {
  Duration timeout = const Duration(seconds: 2),
}) {
  return WebSocket.connect(url, customClient: _directClient).timeout(timeout);
}
