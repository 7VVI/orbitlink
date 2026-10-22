import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// LAN endpoint used by both relay-assisted P2P and relay-free direct
/// sessions. The host advertises itself over UDP 7082 and accepts either:
///  * `p2p_hello`   – video-only channel for a relay session (token auth)
///  * `direct_hello` – a complete session when no relay is available
///    (password auth; video, input and control share the socket)
class DirectVideoHost {
  HttpServer? _server;
  RawDatagramSocket? _discovery;
  WebSocket? _client;
  String? _sessionId;
  String? _token;
  List<String> _endpoints = const [];
  bool _disposed = false;
  bool _fullSession = false;
  bool _closing = false;

  String _hostId = '';
  String _hostName = '';
  String _hostPassword = '';
  bool Function()? _canAcceptSession;
  String? Function(String peer, String address)? _onSessionStart;
  void Function(Map<String, dynamic> message)? _onSessionMessage;
  void Function()? _onSessionEnded;

  int get port => _server?.port ?? 0;
  bool get active => _client != null;
  bool get fullSession => _fullSession;
  List<String> get endpoints => _endpoints;

  void configure({
    required String id,
    required String name,
    required String password,
    required bool Function() canAcceptSession,
    required String? Function(String peer, String address) onSessionStart,
    required void Function(Map<String, dynamic> message) onSessionMessage,
    required void Function() onSessionEnded,
  }) {
    _hostId = id;
    _hostName = name;
    _hostPassword = password;
    _canAcceptSession = canAcceptSession;
    _onSessionStart = onSessionStart;
    _onSessionMessage = onSessionMessage;
    _onSessionEnded = onSessionEnded;
  }

  Future<void> start() async {
    if (_server != null || _disposed) return;
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _server = server;
      _endpoints = await _collectEndpoints(server.port);
      server.listen(_handleRequest, onError: (Object _) {});
    } catch (_) {
      _server = null;
      _endpoints = const [];
    }
  }

  Future<void> setDiscoverable(bool enabled) async {
    if (!enabled) {
      _discovery?.close();
      _discovery = null;
      return;
    }
    if (_discovery != null || _disposed || _server == null) return;
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        7082,
        reuseAddress: true,
      );
      _discovery = socket;
      socket.broadcastEnabled = true;
      socket.listen(_onDiscovery, onError: (Object _) {});
    } catch (_) {
      _discovery = null;
    }
  }

  void authorize(String sessionId, String token) {
    revoke();
    _sessionId = sessionId;
    _token = token;
    _closing = false;
  }

  void revoke() {
    _closing = true;
    _sessionId = null;
    _token = null;
    _fullSession = false;
    final client = _client;
    _client = null;
    try {
      client?.close();
    } catch (_) {}
  }

  void send(Uint8List frame) {
    final client = _client;
    if (client == null) return;
    try {
      client.add(frame);
    } catch (_) {
      _client = null;
    }
  }

  void sendJson(Map<String, dynamic> message) {
    final client = _client;
    if (client == null) return;
    try {
      client.add(jsonEncode(message));
    } catch (_) {}
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    revoke();
    _discovery?.close();
    _discovery = null;
    final server = _server;
    _server = null;
    _endpoints = const [];
    try {
      await server?.close(force: true);
    } catch (_) {}
  }

  void _onDiscovery(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _discovery;
    if (socket == null) return;
    while (true) {
      final datagram = socket.receive();
      if (datagram == null) break;
      try {
        final message = (jsonDecode(utf8.decode(datagram.data)) as Map)
            .cast<String, dynamic>();
        if (message['t'] != 'orbitlink_discover' ||
            message['target'] != _hostId ||
            port == 0) {
          continue;
        }
        final canAccept = _canAcceptSession?.call() == true;
        final response = jsonEncode({
          't': 'orbitlink_host',
          'id': _hostId,
          'name': _hostName,
          'platform': 'windows',
          'port': port,
          'busy': !canAccept,
        });
        socket.send(utf8.encode(response), datagram.address, datagram.port);
      } catch (_) {}
    }
  }

  Future<List<String>> _collectEndpoints(int port) async {
    final endpoints = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: true,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.isLoopback) continue;
          if (address.address.startsWith('169.254.')) continue;
          final endpoint = '${address.address}:$port';
          if (!endpoints.contains(endpoint)) endpoints.add(endpoint);
        }
      }
    } catch (_) {}
    endpoints.add('127.0.0.1:$port');
    return endpoints;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.uri.path != '/direct' ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      try {
        await request.response.close();
      } catch (_) {}
      return;
    }
    final remote = request.connectionInfo?.remoteAddress.address ?? '';
    WebSocket socket;
    try {
      socket = await WebSocketTransformer.upgrade(request);
    } catch (_) {
      return;
    }
    var authorized = false;
    final guard = Timer(const Duration(seconds: 3), () {
      if (!authorized) {
        try {
          socket.close();
        } catch (_) {}
      }
    });
    socket.listen(
      (data) {
        if (!authorized) {
          if (data is! String) {
            try {
              socket.close();
            } catch (_) {}
            return;
          }
          Map<String, dynamic>? message;
          try {
            message = (jsonDecode(data) as Map).cast<String, dynamic>();
          } catch (_) {}
          if (message == null) {
            try {
              socket.close();
            } catch (_) {}
            return;
          }

          if (message['t'] == 'p2p_hello') {
            final valid = !_fullSession &&
                _sessionId != null &&
                message['session'] == _sessionId &&
                message['token'] == _token;
            if (!valid) {
              try {
                socket.close();
              } catch (_) {}
              return;
            }
            authorized = true;
            guard.cancel();
            final previous = _client;
            _client = socket;
            _fullSession = false;
            _closing = false;
            if (previous != null && !identical(previous, socket)) {
              try {
                previous.close();
              } catch (_) {}
            }
            socket.add(jsonEncode({'t': 'p2p_ok'}));
            return;
          }

          if (message['t'] == 'direct_hello') {
            final target = message['target'];
            final password = message['password'];
            String reason;
            if (target != _hostId) {
              reason = 'bad_target';
            } else if (password != _hostPassword) {
              reason = 'bad_password';
            } else if (_canAcceptSession?.call() != true) {
              reason = 'host_busy';
            } else {
              final peerRaw = (message['from'] as String?)?.trim() ?? '';
              final peer = peerRaw.isEmpty ? '远程用户' : peerRaw;
              final sessionId = _onSessionStart?.call(peer, remote);
              if (sessionId == null) {
                reason = 'host_busy';
              } else {
                authorized = true;
                guard.cancel();
                final previous = _client;
                _client = socket;
                _fullSession = true;
                _closing = false;
                _sessionId = sessionId;
                _token = null;
                if (previous != null && !identical(previous, socket)) {
                  try {
                    previous.close();
                  } catch (_) {}
                }
                socket.add(jsonEncode({
                  't': 'direct_ok',
                  'session': sessionId,
                  'peer': _hostName,
                  'platform': 'windows',
                }));
                return;
              }
            }
            try {
              socket.add(jsonEncode({'t': 'direct_error', 'reason': reason}));
              socket.close();
            } catch (_) {}
            return;
          }

          try {
            socket.close();
          } catch (_) {}
          return;
        }

        if (_fullSession && data is String) {
          try {
            final message = (jsonDecode(data) as Map).cast<String, dynamic>();
            _onSessionMessage?.call(message);
          } catch (_) {}
        }
      },
      onDone: () {
        guard.cancel();
        if (identical(_client, socket)) {
          final wasFull = _fullSession;
          _client = null;
          _fullSession = false;
          if (wasFull && !_closing) _onSessionEnded?.call();
        }
      },
      onError: (Object _) {
        guard.cancel();
        if (identical(_client, socket)) {
          final wasFull = _fullSession;
          _client = null;
          _fullSession = false;
          if (wasFull && !_closing) _onSessionEnded?.call();
        }
      },
      cancelOnError: true,
    );
  }
}
