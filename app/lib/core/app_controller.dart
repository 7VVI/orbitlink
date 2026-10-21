import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/controller_session.dart';
import '../engine/host_engine.dart';
import '../native/win32.dart';
import 'models.dart';

enum NavTab { assist, devices, settings }

enum SettingsTab { info, general, desktop, security, notification }

class FeedItem {
  FeedItem({
    required this.title,
    required this.body,
    required this.time,
    this.kind = 'system',
    this.read = false,
  });

  final String title;
  final String body;
  final DateTime time;
  final String kind;
  bool read;
}

class AppController extends ChangeNotifier {
  AppController();

  final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  late AppConfig config;
  late HostEngine host;
  ControllerSession? session;

  NavTab tab = NavTab.assist;
  SettingsTab settingsTab = SettingsTab.info;
  bool searchOpen = false;
  bool notificationsOpen = false;
  bool initialized = false;
  String? prefillTarget;

  final List<FeedItem> feed = [
    FeedItem(
      title: '安全提醒',
      body: '你的设备已开启「允许远程协助本机」，请妥善保管验证码。',
      time: DateTime.now().subtract(const Duration(minutes: 18)),
      kind: 'security',
    ),
    FeedItem(
      title: '设备动态',
      body: '本机已成功注册到中继服务器，可接受远程协助。',
      time: DateTime.now().subtract(const Duration(hours: 6)),
      kind: 'device',
    ),
  ];

  DeviceIdentity get identity => config.identity;
  AppSettings get settings => config.settings;
  String get displayId => formatDeviceId(identity.id);
  RelayStatus get relayStatus => host.status.value;
  HostSessionInfo? get hostSession => host.session.value;
  bool get inSession => session != null;

  Future<void> init() async {
    config = ConfigStore.load();
    host = HostEngine(identity: identity, settings: settings);
    host.onRemoteClipboard = (text) {
      Clipboard.setData(ClipboardData(text: text));
      showToast('已同步剪贴板内容');
    };
    host.onEvent = (message) {
      showToast(message);
      if (settings.notifyControl) {
        feed.insert(
            0,
            FeedItem(
              title: '远程控制',
              body: message,
              time: DateTime.now(),
              kind: 'session',
            ));
      }
      notifyListeners();
    };
    host.status.addListener(_onHostState);
    host.statusDetail.addListener(_onHostState);
    host.session.addListener(_onHostState);
    initialized = true;
    notifyListeners();
    SystemInfo.loadNetwork().then((_) => notifyListeners());
    host.start();
  }

  void _onHostState() {
    notifyListeners();
  }

  void showToast(String message) {
    final state = messengerKey.currentState;
    if (state == null) return;
    state
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        width: 420,
      ));
  }

  void setTab(NavTab next) {
    if (tab == next && !searchOpen && !notificationsOpen) return;
    tab = next;
    searchOpen = false;
    notificationsOpen = false;
    notifyListeners();
  }

  void prefillAssist(String id) {
    prefillTarget = id;
    tab = NavTab.assist;
    searchOpen = false;
    notificationsOpen = false;
    notifyListeners();
  }

  void setSettingsTab(SettingsTab next) {
    settingsTab = next;
    notifyListeners();
  }

  void toggleSearch([bool? open]) {
    searchOpen = open ?? !searchOpen;
    notificationsOpen = false;
    notifyListeners();
  }

  void toggleNotifications([bool? open]) {
    notificationsOpen = open ?? !notificationsOpen;
    searchOpen = false;
    notifyListeners();
  }

  void updateSettings(void Function(AppSettings s) mutate) {
    mutate(settings);
    ConfigStore.save(config);
    host.updateSettings(settings);
    notifyListeners();
  }

  void updateDeviceName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    identity.name = trimmed;
    ConfigStore.save(config);
    host.refreshRegistration();
    notifyListeners();
  }

  void regeneratePassword() {
    identity.password = generatePassword();
    ConfigStore.save(config);
    host.refreshRegistration();
    showToast('验证码已更新');
    notifyListeners();
  }

  void setRelayUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    settings.relayUrl = trimmed;
    ConfigStore.save(config);
    host.updateSettings(settings);
    notifyListeners();
  }

  void copyDeviceId() {
    Clipboard.setData(ClipboardData(text: identity.id));
    showToast('识别码已复制');
  }

  void copyPassword() {
    Clipboard.setData(ClipboardData(text: identity.password));
    showToast('验证码已复制');
  }

  ControllerSession? startSession({
    required String target,
    required String password,
    required String mode,
  }) {
    if (session != null) {
      showToast('已有远程会话进行中');
      return null;
    }
    _rememberConnection(target, password);
    final created = ControllerSession(
      relayUrl: settings.relayUrl,
      targetId: target,
      password: password,
      fromName: identity.name,
      onSessionStarted: (peerId, peerName, peerPlatform) {
        _rememberDevice(peerId, peerName, peerPlatform);
      },
      onClosed: (reason) {
        notifyListeners();
      },
    );
    session = created;
    created.state.addListener(_onSessionState);
    created.stats.addListener(_onSessionState);
    created.start();
    notifyListeners();
    return created;
  }

  void _onSessionState() {
    notifyListeners();
  }

  void closeSession() {
    final current = session;
    if (current == null) return;
    current.end();
    current.state.removeListener(_onSessionState);
    current.stats.removeListener(_onSessionState);
    current.dispose();
    session = null;
    notifyListeners();
  }

  void _rememberConnection(String target, String password) {
    config.lastTargetId = target;
    config.lastPassword = password;
    ConfigStore.save(config);
  }

  void _rememberDevice(String id, String name, String platform) {
    final now = DateTime.now();
    config.recents.removeWhere((device) => device.id == id);
    config.recents.insert(
      0,
      RecentDevice(
        id: id,
        name: name,
        platform: platform.isEmpty || platform == 'unknown' ? 'win' : platform,
        lastConnected: now,
      ),
    );
    if (config.recents.length > 12) config.recents.removeLast();
    ConfigStore.save(config);
    notifyListeners();
  }

  void markFeedRead() {
    for (final item in feed) {
      item.read = true;
    }
    notifyListeners();
  }

  int get unreadCount => feed.where((item) => !item.read).length;

  @override
  void dispose() {
    host.status.removeListener(_onHostState);
    host.statusDetail.removeListener(_onHostState);
    host.session.removeListener(_onHostState);
    host.dispose();
    final current = session;
    if (current != null) {
      current.dispose();
      session = null;
    }
    super.dispose();
  }
}
