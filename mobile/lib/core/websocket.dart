import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final HttpClient _directClient = HttpClient()
  ..findProxy = ((Uri uri) => 'DIRECT')
  ..connectionTimeout = const Duration(seconds: 8);

WebSocketChannel connectRelay(String url) {
  return IOWebSocketChannel.connect(
    Uri.parse(url),
    customClient: _directClient,
    connectTimeout: const Duration(seconds: 8),
    pingInterval: const Duration(seconds: 20),
  );
}
