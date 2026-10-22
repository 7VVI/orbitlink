import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// OrbitLink relay: host registration, password-checked pairing and
/// transparent forwarding of control messages / JPEG frames.
///
/// Run: dart run bin/server.dart [port]
/// Env: PORT (default 7080), BIND (default 0.0.0.0)
/// Endpoints: ws://<host>:7080/ws, http://<host>:7080/health
Future<void> main(List<String> args) async {
  final options = _ServerOptions.parse(args);
  final relay = RelayServer(
    port: options.port,
    bindAddress: _resolveBind(options.bind),
  );

  final subscriptions = <StreamSubscription<ProcessSignal>>[];
  Future<void> shutdown(ProcessSignal signal) async {
    stdout.writeln('received $signal, stopping relay');
    await relay.stop();
    exit(0);
  }

  subscriptions.add(ProcessSignal.sigint.watch().listen(shutdown));
  if (!Platform.isWindows) {
    subscriptions.add(ProcessSignal.sigterm.watch().listen(shutdown));
  }

  try {
    await relay.start();
  } catch (error) {
    stderr.writeln('failed to start relay: $error');
    exitCode = 1;
  } finally {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }
}

class _ServerOptions {
  const _ServerOptions({required this.port, required this.bind});

  final int port;
  final String bind;

  static _ServerOptions parse(List<String> args) {
    var port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 7080;
    var bind = (Platform.environment['BIND'] ?? '').trim();
    if (bind.isEmpty) bind = '0.0.0.0';

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--port' && i + 1 < args.length) {
        port = int.tryParse(args[++i]) ?? port;
      } else if (arg.startsWith('--port=')) {
        port = int.tryParse(arg.substring('--port='.length)) ?? port;
      } else if (arg == '--bind' && i + 1 < args.length) {
        bind = args[++i];
      } else if (arg.startsWith('--bind=')) {
        bind = arg.substring('--bind='.length);
      } else if (!arg.startsWith('-')) {
        port = int.tryParse(arg) ?? port;
      }
    }
    if (port < 1 || port > 65535) {
      stderr.writeln('invalid port: $port (expected 1..65535)');
      exit(64);
    }
    return _ServerOptions(port: port, bind: bind);
  }
}

InternetAddress _resolveBind(String bind) {
  if (bind == '0.0.0.0' || bind == 'any' || bind == '*') {
    return InternetAddress.anyIPv4;
  }
  if (bind == '::' || bind == 'any6') return InternetAddress.anyIPv6;
  final address = InternetAddress.tryParse(bind);
  if (address == null) {
    stderr.writeln('invalid bind address: $bind');
    exit(64);
  }
  return address;
}

class _Client {
  _Client(this.socket, this.remote);

  final WebSocket socket;
  final String remote;
  String? role;
  String? hostId;
  String name = '';
  String password = '';
  bool allowRemote = true;
  _Session? session;

  bool get alive => socket.readyState == WebSocket.open;

  void sendJson(Map<String, dynamic> message) {
    if (alive) socket.add(jsonEncode(message));
  }

  void sendRaw(List<int> data) {
    if (alive) socket.add(data);
  }
}

class _Host {
  _Host(this.client, this.id);

  final _Client client;
  final String id;
  String name = '';
  String password = '';
  String platform = 'unknown';
  bool allowRemote = true;
  _Session? activeSession;

  int get onlineSessions => activeSession == null ? 0 : 1;
}

class _Session {
  _Session({
    required this.id,
    required this.host,
    required this.controller,
    required this.mode,
    this.controllerPlatform = 'unknown',
  });

  final String id;
  final _Client host;
  final _Client controller;
  final String mode;
  final String controllerPlatform;
  bool active = false;
  DateTime createdAt = DateTime.now();
  Timer? timeout;

  _Client peerOf(_Client client) => identical(client, host) ? controller : host;
}

class RelayServer {
  RelayServer({required this.port, required this.bindAddress});

  final int port;
  final InternetAddress bindAddress;
  final Map<String, _Host> _hosts = {};
  final Map<String, _Session> _sessions = {};
  final Set<_Client> _clients = {};
  final Random _random = Random.secure();
  final DateTime startedAt = DateTime.now();
  HttpServer? _http;
  bool _stopping = false;

  Future<void> start() async {
    final http = await HttpServer.bind(bindAddress, port);
    _http = http;
    http.autoCompress = false;
    final isAny =
        bindAddress.address == '0.0.0.0' || bindAddress.address == '::';
    _log('relay listening on ${bindAddress.address}:$port');
    if (isAny) {
      for (final address in await _localAddresses()) {
        _log('  ws://$address:$port/ws');
      }
    } else {
      _log('  ws://${bindAddress.address}:$port/ws');
    }
    await for (final request in http) {
      try {
        await _handleHttp(request);
      } catch (error) {
        _log('http error: $error');
        try {
          request.response.statusCode = 500;
          await request.response.close();
        } catch (_) {}
      }
    }
  }

  /// Closes active sessions and sockets. Safe to call from SIGTERM/SIGINT.
  Future<void> stop() async {
    if (_stopping) return;
    _stopping = true;
    _log('stopping relay...');
    for (final session in _sessions.values.toList()) {
      _endSession(session, reason: 'server_shutdown', notify: true);
    }
    for (final client in _clients.toList()) {
      try {
        await client.socket.close(WebSocketStatus.goingAway, 'server_shutdown');
      } catch (_) {}
    }
    final http = _http;
    _http = null;
    if (http != null) {
      try {
        await http.close(force: true);
      } catch (_) {}
    }
    _log('relay stopped');
  }

  Future<void> _handleHttp(HttpRequest request) async {
    final path = request.uri.path;
    if (path == '/ws' && WebSocketTransformer.isUpgradeRequest(request)) {
      final socket = await WebSocketTransformer.upgrade(
        request,
        compression: CompressionOptions.compressionOff,
      );
      socket.pingInterval = const Duration(seconds: 25);
      _accept(
          socket,
          '${request.connectionInfo?.remoteAddress.address ?? '?'}:'
          '${request.connectionInfo?.remotePort ?? 0}');
      return;
    }
    if (path == '/health') {
      request.response.headers.contentType = ContentType.json;
      request.response.headers.set('Cache-Control', 'no-store');
      request.response.write(jsonEncode({
        'ok': true,
        'version': '1.0.0',
        'hosts': _hosts.length,
        'sessions': _sessions.values.where((s) => s.active).length,
        'clients': _clients.length,
        'bind': bindAddress.address,
        'time': DateTime.now().toIso8601String(),
        'uptimeSeconds': DateTime.now().difference(startedAt).inSeconds,
      }));
      await request.response.close();
      return;
    }
    request.response.headers.contentType = ContentType.html;
    request.response.write('''
<!doctype html><meta charset="utf-8">
<title>OrbitLink Relay</title>
<style>body{background:#f5f7fb;color:#101828;font:14px "Microsoft YaHei UI",sans-serif;padding:44px}
h1{color:#5a55f2;font-size:24px}code{color:#0b8f83;background:#e6f8f5;padding:2px 6px;border-radius:5px}
.card{background:#fff;border:1px solid #e7eaf0;border-radius:16px;padding:24px;max-width:640px;box-shadow:0 8px 24px #1018280d}
</style>
<div class="card">
<h1>星轨远控 · 中继服务器</h1>
<p>运行中。客户端连接地址：<code>ws://本机IP:$port/ws</code></p>
<p>在线主机：${_hosts.length} · 活动会话：${_sessions.values.where((s) => s.active).length}</p>
<p>健康检查：<code>/health</code></p>
</div>
''');
    await request.response.close();
  }

  void _accept(WebSocket socket, String remote) {
    final client = _Client(socket, remote);
    _clients.add(client);
    _log('connect $remote');
    socket.listen(
      (data) {
        try {
          _onData(client, data);
        } catch (error, stack) {
          _log('message error: $error\n$stack');
          _onClose(client);
        }
      },
      onDone: () => _onClose(client),
      onError: (Object error) {
        _log('socket error $remote: $error');
        _onClose(client);
      },
      cancelOnError: true,
    );
  }

  void _onData(_Client client, dynamic data) {
    if (data is! String) {
      _onBinary(client, data as List<int>);
      return;
    }
    Map<String, dynamic> message;
    try {
      message = (jsonDecode(data) as Map).cast<String, dynamic>();
    } catch (_) {
      client.sendJson({'t': 'error', 'reason': 'bad_json'});
      return;
    }
    final type = message['t'] as String? ?? '';
    switch (type) {
      case 'hello':
        _onHello(client, message);
        break;
      case 'connect':
        _onConnect(client, message);
        break;
      case 'accept':
        _onAccept(client, message);
        break;
      case 'reject':
        _onReject(client, message);
        break;
      case 'end':
        _onEnd(client, message);
        break;
      case 'ping':
        client.sendJson(
            {'t': 'pong', 'ts': DateTime.now().millisecondsSinceEpoch});
        break;
      case 'input':
      case 'clipboard':
      case 'control':
      case 'stats':
      case 'p2p':
        _forward(client, message);
        break;
      default:
        client.sendJson({'t': 'error', 'reason': 'unknown_type'});
    }
  }

  void _onBinary(_Client client, List<int> data) {
    final session = client.session;
    if (session == null || !session.active) return;
    if (!identical(client, session.host)) return;
    session.controller.sendRaw(data);
  }

  void _onHello(_Client client, Map<String, dynamic> message) {
    final role = message['role'] as String? ?? '';
    _log('hello role=$role id=${message['id']}');
    if (role != 'host') {
      client.sendJson({'t': 'error', 'reason': 'bad_role'});
      return;
    }
    final id = (message['id'] as String? ?? '').replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^\d{9}$').hasMatch(id)) {
      client.sendJson({'t': 'error', 'reason': 'bad_id'});
      return;
    }
    final existing = _hosts[id];
    if (existing != null && !identical(existing.client, client)) {
      existing.client.sendJson({'t': 'kicked', 'reason': 'id_replaced'});
      _endSession(existing.client.session,
          reason: 'host_replaced', notify: true);
      _hosts.remove(id);
      try {
        existing.client.socket.close();
      } catch (_) {}
    }
    client.role = 'host';
    client.hostId = id;
    client.name = message['name'] as String? ?? '未命名设备';
    client.password = message['password'] as String? ?? '';
    client.allowRemote = message['allowRemote'] as bool? ?? true;
    final meta = message['meta'];
    final platform =
        meta is Map ? (meta['platform'] as String? ?? 'unknown') : 'unknown';
    final host = _Host(client, id)
      ..name = client.name
      ..password = client.password
      ..platform = platform
      ..allowRemote = client.allowRemote;
    _hosts[id] = host;
    client.sendJson({
      't': 'hello_ok',
      'id': id,
      'serverTime': DateTime.now().millisecondsSinceEpoch,
    });
    _log('host $id (${client.name}) registered from ${client.remote}');
  }

  void _onConnect(_Client client, Map<String, dynamic> message) {
    final target =
        (message['target'] as String? ?? '').replaceAll(RegExp(r'\D'), '');
    final password = message['password'] as String? ?? '';
    final mode = message['mode'] as String? ?? 'desktop';
    client.name = message['from'] as String? ?? '远程用户';
    final host = _hosts[target];
    if (host == null) {
      client.sendJson({'t': 'error', 'reason': 'host_offline'});
      return;
    }
    if (host.password.isNotEmpty && host.password != password) {
      client.sendJson({'t': 'error', 'reason': 'bad_password'});
      return;
    }
    if (!host.allowRemote) {
      client.sendJson({'t': 'error', 'reason': 'host_refuses'});
      return;
    }
    if (host.activeSession != null) {
      client.sendJson({'t': 'error', 'reason': 'host_busy'});
      return;
    }
    if (client.session != null) {
      _endSession(client.session, reason: 'replaced', notify: true);
    }
    client.role = 'controller';
    final session = _Session(
      id: _sessionId(),
      host: host.client,
      controller: client,
      mode: mode,
      controllerPlatform: message['platform'] as String? ?? 'unknown',
    );
    _sessions[session.id] = session;
    client.session = session;
    host.client.session = session;
    host.client.sendJson({
      't': 'incoming',
      'session': session.id,
      'from': client.name,
      'address': client.remote,
      'mode': mode,
    });
    client.sendJson({'t': 'ringing', 'session': session.id});
    session.timeout = Timer(const Duration(seconds: 15), () {
      if (!session.active) {
        _endSession(session, reason: 'accept_timeout', notify: true);
      }
    });
    _log('connect request ${client.name} -> $target (${session.id})');
  }

  void _onAccept(_Client client, Map<String, dynamic> message) {
    final id = message['session'] as String? ?? '';
    final session = _sessions[id];
    if (session == null || !identical(client, session.host)) return;
    if (session.active) return;
    session.timeout?.cancel();
    session.active = true;
    session.createdAt = DateTime.now();
    final host = _hosts[session.host.hostId];
    if (host != null) host.activeSession = session;
    session.host.sendJson({
      't': 'session_start',
      'session': session.id,
      'peer': session.controller.name,
      'peerId': '',
      'mode': session.mode,
      'peerPlatform': session.controllerPlatform,
    });
    final controllerHost = _hosts[session.host.hostId];
    session.controller.sendJson({
      't': 'session_start',
      'session': session.id,
      'peer': session.host.name,
      'peerId': session.host.hostId ?? '',
      'mode': session.mode,
      'platform': controllerHost?.platform ?? 'unknown',
    });
    _log('session ${session.id} active: ${session.host.hostId} <- '
        '${session.controller.name}');
  }

  void _onReject(_Client client, Map<String, dynamic> message) {
    final id = message['session'] as String? ?? '';
    final session = _sessions[id];
    if (session == null || !identical(client, session.host)) return;
    final reason = message['reason'] as String? ?? 'rejected';
    _endSession(session, reason: reason, notify: true);
  }

  void _onEnd(_Client client, Map<String, dynamic> message) {
    final session = client.session;
    if (session == null) return;
    final reason = message['reason'] as String? ?? 'ended';
    _endSession(session, reason: reason, notify: true, exclude: client);
  }

  void _forward(_Client client, Map<String, dynamic> message) {
    final session = client.session;
    if (session == null || !session.active) return;
    final peer = session.peerOf(client);
    peer.sendJson(message);
  }

  void _endSession(
    _Session? session, {
    required String reason,
    bool notify = true,
    _Client? exclude,
  }) {
    if (session == null) return;
    session.timeout?.cancel();
    _sessions.remove(session.id);
    if (session.host.session == session) session.host.session = null;
    if (session.controller.session == session)
      session.controller.session = null;
    final host = _hosts[session.host.hostId];
    if (host != null && identical(host.activeSession, session)) {
      host.activeSession = null;
    }
    if (notify) {
      final payload = {'t': 'end', 'session': session.id, 'reason': reason};
      if (session.active) {
        if (!identical(session.host, exclude)) session.host.sendJson(payload);
        if (!identical(session.controller, exclude)) {
          session.controller.sendJson(payload);
        }
      } else {
        session.controller
            .sendJson({'t': 'error', 'reason': reason, 'session': session.id});
      }
    }
    _log('session ${session.id} ended: $reason');
  }

  void _onClose(_Client client) {
    _clients.remove(client);
    _log('disconnect ${client.remote} ${client.hostId ?? ''}');
    if (client.session != null) {
      _endSession(client.session,
          reason: client.role == 'host' ? 'host_offline' : 'peer_offline',
          notify: true,
          exclude: client);
    }
    if (client.role == 'host' && client.hostId != null) {
      final host = _hosts[client.hostId];
      if (host != null && identical(host.client, client)) {
        _hosts.remove(client.hostId);
        _log('host ${client.hostId} offline');
      }
    }
  }

  String _sessionId() {
    final now = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final salt = _random.nextInt(0xFFFFFF).toRadixString(36);
    return '$now-$salt';
  }

  Future<List<String>> _localAddresses() async {
    final result = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback) result.add(address.address);
        }
      }
    } catch (_) {}
    if (!result.contains('127.0.0.1')) result.insert(0, '127.0.0.1');
    return result;
  }

  void _log(String message) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    stdout.writeln('[$ts] $message');
  }
}
