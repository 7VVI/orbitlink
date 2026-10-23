import 'dart:io';

import 'package:flutter/services.dart';

class HostConfig {
  HostConfig({
    required this.id,
    required this.password,
    required this.name,
    required this.relayUrl,
    required this.allowRemote,
    this.stunUrl = 'stun:stun.l.google.com:19302',
    this.turnUrl = '',
    this.turnUsername = '',
    this.turnCredential = '',
  });

  final String id;
  final String password;
  final String name;
  final String relayUrl;
  final bool allowRemote;
  final String stunUrl;
  final String turnUrl;
  final String turnUsername;
  final String turnCredential;

  factory HostConfig.fromMap(Map<dynamic, dynamic> map) => HostConfig(
        id: (map['id'] as String?) ?? '000000000',
        password: (map['password'] as String?) ?? '------',
        name: (map['name'] as String?) ?? 'Android 设备',
        relayUrl: (map['relayUrl'] as String?) ?? 'ws://10.0.2.2:7080/ws',
        allowRemote: (map['allowRemote'] as bool?) ?? true,
        stunUrl: (map['stunUrl'] as String?) ?? 'stun:stun.l.google.com:19302',
        turnUrl: (map['turnUrl'] as String?) ?? '',
        turnUsername: (map['turnUsername'] as String?) ?? '',
        turnCredential: (map['turnCredential'] as String?) ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'password': password,
        'name': name,
        'relayUrl': relayUrl,
        'allowRemote': allowRemote,
        'stunUrl': stunUrl,
        'turnUrl': turnUrl,
        'turnUsername': turnUsername,
        'turnCredential': turnCredential,
      };

  HostConfig copyWith({
    String? relayUrl,
    bool? allowRemote,
    String? stunUrl,
    String? turnUrl,
    String? turnUsername,
    String? turnCredential,
  }) =>
      HostConfig(
        id: id,
        password: password,
        name: name,
        relayUrl: relayUrl ?? this.relayUrl,
        allowRemote: allowRemote ?? this.allowRemote,
        stunUrl: stunUrl ?? this.stunUrl,
        turnUrl: turnUrl ?? this.turnUrl,
        turnUsername: turnUsername ?? this.turnUsername,
        turnCredential: turnCredential ?? this.turnCredential,
      );
}

// Validate the original authority: Uri alone accepts empty ports and normalizes
// malformed input. ICE URLs use scheme:host, not the HTTP scheme://host form.
String? validateRelayUrl(String value) {
  final url = value.trim();
  final match =
      RegExp(r'^wss?://([^/?#]+)(?:[/?][^#]*)?$', caseSensitive: false)
          .firstMatch(url);
  if (match == null ||
      RegExp(r'[\s\x00-\x1f\x7f\\]').hasMatch(url) ||
      RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(url) ||
      !_isValidServerAddress(match.group(1)!) ||
      Uri.tryParse(url) == null) {
    return '请输入有效的 ws:// 或 wss:// 信令地址（主机及端口需有效）';
  }
  return null;
}

String? validateRtcSettings({
  required String stunUrl,
  required String turnUrl,
  required String turnUsername,
  required String turnCredential,
}) {
  if (!_isValidIceUrl(stunUrl.trim(), isTurn: false)) {
    return 'STUN URL 无效，请使用 stun: 或 stuns: 地址，或留空关闭';
  }
  if (!_isValidIceUrl(turnUrl.trim(), isTurn: true)) {
    return 'TURN URL 无效，请使用 turn: 或 turns: 地址，或留空关闭';
  }
  if (turnUrl.trim().isNotEmpty &&
      (turnUsername.trim().isEmpty || turnCredential.trim().isEmpty)) {
    return '启用 TURN 时必须填写 TURN 用户名和密码';
  }
  return null;
}

bool _isValidIceUrl(String value, {required bool isTurn}) {
  if (value.isEmpty) return true;
  final match = RegExp(
    r'^(stun|stuns|turn|turns):([^?]+)(?:\?transport=(udp|tcp))?$',
    caseSensitive: false,
  ).firstMatch(value);
  if (match == null || RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(value)) {
    return false;
  }
  final scheme = match.group(1)!.toLowerCase();
  return (isTurn ? scheme.startsWith('turn') : scheme.startsWith('stun')) &&
      _isValidServerAddress(match.group(2)!);
}

bool _isValidServerAddress(String value) {
  final match = RegExp(
    r'^(?:\[([0-9a-fA-F:.]+)\]|([^:\[\]/?#@\\]+))(?::([0-9]+))?$',
  ).firstMatch(value);
  if (match == null) return false;
  final portText = match.group(3);
  if (portText != null) {
    final port = int.tryParse(portText);
    if (port == null || port < 1 || port > 65535) return false;
  }
  final ipv6 = match.group(1);
  if (ipv6 != null) {
    return InternetAddress.tryParse(ipv6)?.type == InternetAddressType.IPv6;
  }
  final host = match.group(2)!;
  if (InternetAddress.tryParse(host) != null) return true;
  if (RegExp(r'^[0-9.]+$').hasMatch(host)) return false;
  final domain = host.endsWith('.') ? host.substring(0, host.length - 1) : host;
  final label = RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$');
  return domain.length <= 253 && domain.split('.').every(label.hasMatch);
}

class HostStatus {
  const HostStatus({
    this.running = false,
    this.relay = 'offline',
    this.detail,
    this.sessionActive = false,
    this.controllerName,
    this.width = 0,
    this.height = 0,
    this.fps = 0,
    this.accessibilityEnabled = false,
    this.notificationGranted = true,
  });

  final bool running;
  final String relay;
  final String? detail;
  final bool sessionActive;
  final String? controllerName;
  final int width;
  final int height;
  final int fps;
  final bool accessibilityEnabled;
  final bool notificationGranted;

  factory HostStatus.fromMap(Map<dynamic, dynamic> map) => HostStatus(
        running: (map['running'] as bool?) ?? false,
        relay: (map['relay'] as String?) ?? 'offline',
        detail: map['detail'] as String?,
        sessionActive: (map['sessionActive'] as bool?) ?? false,
        controllerName: map['controllerName'] as String?,
        width: (map['width'] as num?)?.toInt() ?? 0,
        height: (map['height'] as num?)?.toInt() ?? 0,
        fps: (map['fps'] as num?)?.toInt() ?? 0,
        accessibilityEnabled: (map['accessibilityEnabled'] as bool?) ?? false,
        notificationGranted: (map['notificationGranted'] as bool?) ?? true,
      );

  HostStatus copyWith({
    bool? running,
    String? relay,
    String? detail,
    bool? sessionActive,
    String? controllerName,
    int? width,
    int? height,
    int? fps,
    bool? accessibilityEnabled,
    bool? notificationGranted,
  }) =>
      HostStatus(
        running: running ?? this.running,
        relay: relay ?? this.relay,
        detail: detail ?? this.detail,
        sessionActive: sessionActive ?? this.sessionActive,
        controllerName: controllerName ?? this.controllerName,
        width: width ?? this.width,
        height: height ?? this.height,
        fps: fps ?? this.fps,
        accessibilityEnabled: accessibilityEnabled ?? this.accessibilityEnabled,
        notificationGranted: notificationGranted ?? this.notificationGranted,
      );

  @override
  bool operator ==(Object other) =>
      other is HostStatus &&
      other.running == running &&
      other.relay == relay &&
      other.detail == detail &&
      other.sessionActive == sessionActive &&
      other.controllerName == controllerName &&
      other.width == width &&
      other.height == height &&
      other.fps == fps &&
      other.accessibilityEnabled == accessibilityEnabled &&
      other.notificationGranted == notificationGranted;

  @override
  int get hashCode => Object.hash(
      running,
      relay,
      detail,
      sessionActive,
      controllerName,
      width,
      height,
      fps,
      accessibilityEnabled,
      notificationGranted);
}

class HostBridge {
  HostBridge._();

  static const MethodChannel _channel =
      MethodChannel('com.orbitlink.remote/host');

  static bool get _android => Platform.isAndroid;

  static HostConfig _fallbackConfig = HostConfig(
    id: '123456789',
    password: 'demo123',
    name: 'Android 模拟设备',
    relayUrl: 'ws://10.0.2.2:7080/ws',
    allowRemote: true,
  );

  static HostConfig get fallbackConfig => _fallbackConfig;

  static Future<HostConfig> getHostConfig() async {
    if (!_android) return _fallbackConfig;
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getHostConfig',
    );
    return HostConfig.fromMap(result ?? const {});
  }

  static Future<HostConfig> saveHostConfig(HostConfig config) async {
    if (!_android) {
      _fallbackConfig = config;
      return config;
    }
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'saveHostConfig',
      config.toMap(),
    );
    return HostConfig.fromMap(result ?? config.toMap());
  }

  static Future<bool> startHosting() async {
    if (!_android) return false;
    return await _channel.invokeMethod<bool>('startHosting') ?? false;
  }

  static Future<void> stopHosting() async {
    if (!_android) return;
    await _channel.invokeMethod('stopHosting');
  }

  static Future<HostStatus> getHostStatus() async {
    if (!_android) {
      return const HostStatus(
        accessibilityEnabled: false,
        notificationGranted: true,
      );
    }
    final status = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getHostStatus',
    );
    final access = await isAccessibilityEnabled();
    final notif = await isNotificationGranted();
    return HostStatus.fromMap(status ?? const {}).copyWith(
      accessibilityEnabled: access,
      notificationGranted: notif,
    );
  }

  static Future<bool> isAccessibilityEnabled() async {
    if (!_android) return false;
    return await _channel.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
  }

  static Future<void> openAccessibilitySettings() async {
    if (!_android) return;
    await _channel.invokeMethod('openAccessibilitySettings');
  }

  static Future<bool> isNotificationGranted() async {
    if (!_android) return true;
    return await _channel
            .invokeMethod<bool>('isNotificationPermissionGranted') ??
        false;
  }

  static Future<void> requestNotificationPermission() async {
    if (!_android) return;
    await _channel.invokeMethod('requestNotificationPermission');
  }

  static Future<void> openBatteryOptimizationSettings() async {
    if (!_android) return;
    await _channel.invokeMethod('openBatteryOptimizationSettings');
  }

  static Future<bool> regenerateIdentity() async {
    if (!_android) return false;
    return await _channel.invokeMethod<bool>('regenerateIdentity') ?? false;
  }

  static Future<void> updateAllowRemote(bool value) async {
    if (!_android) return;
    await _channel.invokeMethod('updateAllowRemote', {'value': value});
  }

  static Future<String> getDeviceName() async {
    if (!_android) return 'Android 模拟设备';
    return await _channel.invokeMethod<String>('getDeviceName') ?? 'Android';
  }

  static Future<void> setKeepScreenOn(bool value) async {
    if (!_android) return;
    await _channel.invokeMethod('setKeepScreenOn', {'value': value});
  }

  static Future<String> loadRecentsJson() async {
    if (!_android) return '';
    return await _channel.invokeMethod<String>('loadRecentsJson') ?? '';
  }

  static Future<void> saveRecentsJson(String json) async {
    if (!_android) return;
    await _channel.invokeMethod('saveRecentsJson', {'json': json});
  }
}
