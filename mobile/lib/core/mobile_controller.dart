import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:orbitlink_rtc/orbitlink_rtc.dart';

import '../engine/controller_session.dart';
import 'host_bridge.dart';

class RecentDevice {
  RecentDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.lastConnected,
  });

  final String id;
  final String name;
  final String platform;
  final DateTime lastConnected;

  factory RecentDevice.fromJson(Map<String, dynamic> json) => RecentDevice(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '远程设备',
        platform: json['platform'] as String? ?? 'unknown',
        lastConnected:
            DateTime.tryParse(json['lastConnected'] as String? ?? '') ??
                DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'platform': platform,
        'lastConnected': lastConnected.toIso8601String(),
      };
}

class MobileController extends ChangeNotifier {
  final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  HostConfig config = HostBridge.fallbackConfig;
  HostStatus status = const HostStatus();
  List<RecentDevice> recents = [];
  ControllerSession? session;
  int tabIndex = 0;
  bool ready = false;
  String? bridgeError;
  String? targetDraft;

  Timer? _poll;
  bool _polling = false;
  bool _disposed = false;

  Future<void> init() async {
    try {
      final raw = await HostBridge.loadRecentsJson();
      recents = _parseRecents(raw);
    } catch (_) {}
    try {
      config = await HostBridge.getHostConfig();
    } catch (_) {
      bridgeError = '被控端服务未就绪，请重试';
      config = HostBridge.fallbackConfig;
    }
    await _refreshStatus(forceNotify: false);
    ready = true;
    notifyListeners();
    _poll = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      _refreshStatus();
    });
  }

  Future<void> refreshOnResume() async {
    await _refreshStatus(forceNotify: true);
  }

  Future<void> _refreshStatus({bool forceNotify = false}) async {
    if (_disposed || _polling) return;
    _polling = true;
    try {
      final next = await HostBridge.getHostStatus();
      if (next != status || forceNotify) {
        status = next;
        if (!_disposed) notifyListeners();
      }
    } catch (e) {
      if (bridgeError == null) {
        bridgeError = '无法读取被控状态';
        if (!_disposed) notifyListeners();
      }
    } finally {
      _polling = false;
    }
  }

  void setTab(int index) {
    if (tabIndex == index) return;
    tabIndex = index;
    notifyListeners();
  }

  void showMessage(String message) {
    final messenger = messengerKey.currentState;
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> setAllowRemote(bool value) async {
    config = config.copyWith(allowRemote: value);
    notifyListeners();
    try {
      config = await HostBridge.saveHostConfig(config);
      await HostBridge.updateAllowRemote(value);
      if (status.running) {
        showMessage(value ? '已允许远程协助本机' : '已拒绝后续远程请求');
      }
    } catch (_) {
      showMessage('保存失败，请重试');
    }
    notifyListeners();
  }

  Future<void> saveRelayUrl(String url) async {
    final trimmed = url.trim();
    final error = validateRelayUrl(trimmed);
    if (error != null) {
      showMessage(error);
      return;
    }
    try {
      config =
          await HostBridge.saveHostConfig(config.copyWith(relayUrl: trimmed));
      showMessage(
          status.running ? '信令地址已保存，下次开启被控生效；当前服务未停止' : '信令地址已保存，下次会话生效');
    } catch (_) {
      showMessage('信令地址保存失败，请重试');
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> saveRtcSettings({
    required String stunUrl,
    required String turnUrl,
    required String turnUsername,
    required String turnCredential,
  }) async {
    final error = validateRtcSettings(
      stunUrl: stunUrl,
      turnUrl: turnUrl,
      turnUsername: turnUsername,
      turnCredential: turnCredential,
    );
    if (error != null) {
      showMessage(error);
      return;
    }
    try {
      config = await HostBridge.saveHostConfig(config.copyWith(
        stunUrl: stunUrl.trim(),
        turnUrl: turnUrl.trim(),
        turnUsername: turnUsername.trim(),
        // Passwords are opaque: preserve leading/trailing spaces.
        turnCredential: turnCredential,
      ));
      showMessage(status.running
          ? 'RTC 配置已保存：控制端下次会话、被控端下次开启服务生效；当前服务未停止'
          : 'RTC 配置已保存，下次会话或开启被控服务生效');
    } catch (_) {
      // Platform errors can contain channel arguments, including credentials.
      showMessage('RTC 配置保存失败，请重试');
    }
    if (!_disposed) notifyListeners();
  }

  Future<bool> startHosting() async {
    try {
      final started = await HostBridge.startHosting();
      if (started) {
        showMessage('正在开启被控服务');
        await _refreshStatus(forceNotify: true);
      }
      return started;
    } catch (e) {
      showMessage('开启失败：$e');
      return false;
    }
  }

  Future<void> stopHosting() async {
    try {
      await HostBridge.stopHosting();
      await _refreshStatus(forceNotify: true);
      showMessage('已停止本机被控');
    } catch (e) {
      showMessage('停止失败：$e');
    }
  }

  Future<void> regenerateIdentity() async {
    if (status.running) {
      showMessage('请先停止本机被控');
      return;
    }
    try {
      final ok = await HostBridge.regenerateIdentity();
      if (ok) {
        config = await HostBridge.getHostConfig();
        notifyListeners();
        showMessage('已生成新的识别码与验证码');
      }
    } catch (e) {
      showMessage('重置失败：$e');
    }
  }

  Future<void> openAccessibility() async {
    try {
      await HostBridge.openAccessibilitySettings();
      showMessage('请在系统设置中启用「星轨输入服务」');
    } catch (e) {
      showMessage('无法打开无障碍设置：$e');
    }
  }

  Future<void> openBatterySettings() async {
    try {
      await HostBridge.openBatteryOptimizationSettings();
    } catch (_) {}
  }

  Future<void> requestNotifications() async {
    try {
      await HostBridge.requestNotificationPermission();
      await _refreshStatus(forceNotify: true);
    } catch (_) {}
  }

  ControllerSession? startSession({
    required String target,
    required String password,
  }) {
    if (session != null) {
      showMessage('已有远程会话进行中');
      return null;
    }
    if (validateRelayUrl(config.relayUrl) != null) {
      showMessage('请先在设置中填写有效的 WS / WSS 信令地址');
      return null;
    }
    final created = ControllerSession(
      relayUrl: config.relayUrl,
      targetId: target,
      password: password,
      fromName: 'Android 控制端',
      // Each endpoint uses its own ICE configuration; do not signal credentials.
      iceServers: buildIceServers(
        stunUrl: config.stunUrl,
        turnUrl: config.turnUrl,
        turnUsername: config.turnUsername,
        turnCredential: config.turnCredential,
      ),
      onSessionStarted: (peerId, peerName, platform) {
        _rememberDevice(peerId, peerName, platform);
      },
      onClosed: (_) {
        if (!_disposed) notifyListeners();
      },
    );
    session = created;
    created.start();
    notifyListeners();
    return created;
  }

  void closeSession() {
    final current = session;
    if (current == null) return;
    current.end();
    current.dispose();
    session = null;
    notifyListeners();
  }

  void prefillTarget(String id) {
    targetDraft = id;
    tabIndex = 0;
    notifyListeners();
  }

  String? takeTargetDraft() {
    final value = targetDraft;
    targetDraft = null;
    return value;
  }

  void _rememberDevice(String id, String name, String platform) {
    if (id.isEmpty) return;
    recents.removeWhere((device) => device.id == id);
    recents.insert(
      0,
      RecentDevice(
        id: id,
        name: name,
        platform: platform,
        lastConnected: DateTime.now(),
      ),
    );
    if (recents.length > 12) recents.removeLast();
    _saveRecents();
    notifyListeners();
  }

  void removeRecent(String id) {
    recents.removeWhere((device) => device.id == id);
    _saveRecents();
    notifyListeners();
  }

  List<RecentDevice> _parseRecents(String raw) {
    if (raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => RecentDevice.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _saveRecents() {
    HostBridge.saveRecentsJson(
      jsonEncode(recents.map((e) => e.toJson()).toList()),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _poll = null;
    final current = session;
    if (current != null) {
      current.dispose();
      session = null;
    }
    super.dispose();
  }
}
