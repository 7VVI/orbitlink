import 'dart:async';
import 'dart:convert';
import 'dart:io';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

class Peer {
  Peer(this.socket) {
    subscription = socket.listen((value) {
      messages.add(value);
      ready?.complete();
      ready = null;
    }, onDone: () {
      closed = true;
      ready?.complete();
      ready = null;
    });
  }
  final WebSocket socket;
  final messages = <dynamic>[];
  late final StreamSubscription<dynamic> subscription;
  Completer<void>? ready;
  bool closed = false;
  void send(Map<String, dynamic> value) => socket.add(jsonEncode(value));
  Future<Map<String, dynamic>> next(String type) async {
    while (messages.isEmpty) {
      check(!closed, 'Socket closed');
      ready = Completer<void>();
      await ready!.future.timeout(const Duration(seconds: 5));
    }
    final value = messages.removeAt(0);
    check(value is String, 'Unexpected binary media on signaling');
    final message =
        (jsonDecode(value as String) as Map).cast<String, dynamic>();
    check(message['t'] == type, 'Expected $type, received ${message['t']}');
    return message;
  }

  Future<void> close() async {
    await socket.close();
    await subscription.cancel();
  }
}

Future<void> main(List<String> args) async {
  final url = args.isEmpty ? 'ws://127.0.0.1:7088/ws' : args.single;
  final http = HttpClient()..findProxy = (_) => 'DIRECT';
  final peers = <Peer>[];
  Future<Peer> connect() async {
    final peer = Peer(
      await WebSocket.connect(url, customClient: http),
    );
    peers.add(peer);
    return peer;
  }

  try {
    var index = 0;
    for (final hostRtc in [false, true]) {
      for (final controllerRtc in [false, true]) {
        final host = await connect();
        final controller = await connect();
        final id = '12345678${index++}';
        host.send({
          't': 'hello',
          'role': 'host',
          'id': id,
          'password': 'smoke-test',
          'name': 'smoke-host',
          'meta': {'platform': 'windows', 'rtc': hostRtc},
        });
        await host.next('hello_ok');
        final request = {
          't': 'connect',
          'target': id,
          'password': 'smoke-test',
          'from': 'smoke-controller',
          'rtc': controllerRtc,
        };
        controller.send(request);
        final incoming = await host.next('incoming');
        await controller.next('ringing');
        final session = incoming['session'];
        host.send({'t': 'accept', 'session': session});
        final hostStart = await host.next('session_start');
        final controllerStart = await controller.next('session_start');
        final useRtc = hostRtc && controllerRtc;
        check(
          hostStart['rtc'] == useRtc && controllerStart['rtc'] == useRtc,
          'Both endpoints must negotiate the same transport',
        );
        if (useRtc) {
          host.send({
            't': 'control',
            'session': 'stale',
            'action': 'rtc_offer',
            'sdp': 'ignored',
          });
          host.socket.add([1, 2, 3]);
          host.send({
            't': 'control',
            'session': session,
            'action': 'rtc_offer',
            'sdp': 'offer',
            'type': 'offer',
          });
          final offer = await controller.next('control');
          check(
            offer['sdp'] == 'offer' && offer['session'] == session,
            'Stale offer/media forwarded',
          );
          controller.send({
            't': 'control',
            'session': session,
            'action': 'rtc_offer',
            'sdp': 'wrong-role',
          });
          controller.send({
            't': 'control',
            'session': 'stale',
            'action': 'rtc_candidate',
          });
          controller.send({
            't': 'control',
            'session': session,
            'action': 'rtc_answer',
            'sdp': 'answer',
            'type': 'answer',
          });
          final answer = await host.next('control');
          check(
            answer['sdp'] == 'answer',
            'Wrong-role or stale signal forwarded',
          );
        }
        controller.send({'t': 'end', 'reason': 'smoke_done'});
        await host.next('end');
        controller.send(request);
        final again = await host.next('incoming');
        await controller.next('ringing');
        host.send({
          't': 'reject',
          'session': again['session'],
          'reason': 'test_reject',
        });
        await controller.next('error');
        await host.close();
        await controller.close();
        peers.remove(host);
        peers.remove(controller);
      }
    }
    stdout.writeln(
      'PASS: 4 transport combinations, scoped SDP/ICE, RTC media isolation, end/reconnect',
    );
  } finally {
    for (final peer in peers) {
      await peer.close();
    }
    http.close(force: true);
  }
}
