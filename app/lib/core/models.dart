import 'dart:convert';
import 'dart:io';
import 'dart:math';

String formatDeviceId(String id) {
  final digits = id.replaceAll(RegExp(r'\D'), '');
  if (digits.length != 9) return id;
  return '${digits.substring(0, 3)} ${digits.substring(3, 6)} ${digits.substring(6)}';
}

String generateDeviceId() {
  final rnd = Random.secure();
  final first = 1 + rnd.nextInt(9);
  final rest = List.generate(8, (_) => rnd.nextInt(10)).join();
  return '$first$rest';
}

String generatePassword([int length = 6]) {
  const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
  final rnd = Random.secure();
  return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
}

class DeviceIdentity {
  DeviceIdentity({
    required this.id,
    required this.password,
    required this.name,
    required this.createdAt,
  });

  final String id;
  String password;
  String name;
  final DateTime createdAt;

  factory DeviceIdentity.create() => DeviceIdentity(
        id: generateDeviceId(),
        password: generatePassword(),
        name: Platform.localHostname,
        createdAt: DateTime.now(),
      );

  factory DeviceIdentity.fromJson(Map<String, dynamic> json) => DeviceIdentity(
        id: json['id'] as String? ?? generateDeviceId(),
        password: json['password'] as String? ?? generatePassword(),
        name: json['name'] as String? ?? Platform.localHostname,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'password': password,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
      };
}

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
        name: json['name'] as String? ?? '未知设备',
        platform: json['platform'] as String? ?? 'win',
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

class AppSettings {
  AppSettings({
    this.relayUrl = 'ws://127.0.0.1:7080/ws',
    this.allowRemote = true,
    this.autoAcceptKnown = false,
    this.maxWidth = 1920,
    this.jpegQuality = 85,
    this.fps = 30,
    this.videoProfile = 2,
    this.passwordType = '长期验证码',
    this.autoStart = false,
    this.minimizeToTray = false,
    this.autoUpdate = true,
    this.notifyDevice = true,
    this.notifyControl = true,
    this.notifyPush = true,
    this.fullscreenOnConnect = false,
    this.syncClipboard = false,
    this.imageMode = '高清',
    this.renderMode = 'D3D渲染',
    this.deviceNote = '',
    this.showEmptyGroups = true,
    this.gameDriver = false,
    this.virtualScreen = false,
    this.hotkeyEnabled = false,
    this.requireConfirm = false,
    this.updatePolicy = '更新提醒',
    this.themeMode = '深色',
  });

  String relayUrl;
  bool allowRemote;
  bool autoAcceptKnown;
  int maxWidth;
  int jpegQuality;
  int fps;
  String passwordType;
  bool autoStart;
  bool minimizeToTray;
  bool autoUpdate;
  bool notifyDevice;
  bool notifyControl;
  bool notifyPush;
  bool fullscreenOnConnect;
  bool syncClipboard;
  String imageMode;
  String renderMode;
  String deviceNote;
  bool showEmptyGroups;
  bool gameDriver;
  bool virtualScreen;
  bool hotkeyEnabled;
  bool requireConfirm;
  String updatePolicy;
  String themeMode;
  int videoProfile;

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final d = AppSettings();
    d.relayUrl = json['relayUrl'] as String? ?? d.relayUrl;
    d.allowRemote = json['allowRemote'] as bool? ?? d.allowRemote;
    d.autoAcceptKnown = json['autoAcceptKnown'] as bool? ?? d.autoAcceptKnown;
    d.maxWidth = (json['maxWidth'] as num?)?.toInt() ?? d.maxWidth;
    d.jpegQuality = (json['jpegQuality'] as num?)?.toInt() ?? d.jpegQuality;
    d.fps = (json['fps'] as num?)?.toInt() ?? d.fps;
    d.passwordType = json['passwordType'] as String? ?? d.passwordType;
    d.autoStart = json['autoStart'] as bool? ?? d.autoStart;
    d.minimizeToTray = json['minimizeToTray'] as bool? ?? d.minimizeToTray;
    d.autoUpdate = json['autoUpdate'] as bool? ?? d.autoUpdate;
    d.notifyDevice = json['notifyDevice'] as bool? ?? d.notifyDevice;
    d.notifyControl = json['notifyControl'] as bool? ?? d.notifyControl;
    d.notifyPush = json['notifyPush'] as bool? ?? d.notifyPush;
    d.fullscreenOnConnect =
        json['fullscreenOnConnect'] as bool? ?? d.fullscreenOnConnect;
    d.syncClipboard = json['syncClipboard'] as bool? ?? d.syncClipboard;
    d.imageMode = json['imageMode'] as String? ?? d.imageMode;
    d.renderMode = json['renderMode'] as String? ?? d.renderMode;
    d.deviceNote = json['deviceNote'] as String? ?? d.deviceNote;
    d.showEmptyGroups = json['showEmptyGroups'] as bool? ?? d.showEmptyGroups;
    d.gameDriver = json['gameDriver'] as bool? ?? d.gameDriver;
    d.virtualScreen = json['virtualScreen'] as bool? ?? d.virtualScreen;
    d.hotkeyEnabled = json['hotkeyEnabled'] as bool? ?? d.hotkeyEnabled;
    d.requireConfirm = json['requireConfirm'] as bool? ?? d.requireConfirm;
    d.updatePolicy = json['updatePolicy'] as String? ?? d.updatePolicy;
    d.themeMode = json['themeMode'] as String? ?? d.themeMode;
    d.videoProfile = (json['videoProfile'] as num?)?.toInt() ?? 0;
    if (d.videoProfile < 2) {
      // Upgrade older profiles to the high-frame-rate 4:4:4 stream settings.
      d.videoProfile = 2;
      d.maxWidth = 1920;
      d.jpegQuality = 85;
      d.fps = 30;
    }
    return d;
  }

  Map<String, dynamic> toJson() => {
        'relayUrl': relayUrl,
        'allowRemote': allowRemote,
        'autoAcceptKnown': autoAcceptKnown,
        'maxWidth': maxWidth,
        'jpegQuality': jpegQuality,
        'fps': fps,
        'passwordType': passwordType,
        'autoStart': autoStart,
        'minimizeToTray': minimizeToTray,
        'autoUpdate': autoUpdate,
        'notifyDevice': notifyDevice,
        'notifyControl': notifyControl,
        'notifyPush': notifyPush,
        'fullscreenOnConnect': fullscreenOnConnect,
        'syncClipboard': syncClipboard,
        'imageMode': imageMode,
        'renderMode': renderMode,
        'deviceNote': deviceNote,
        'showEmptyGroups': showEmptyGroups,
        'gameDriver': gameDriver,
        'virtualScreen': virtualScreen,
        'hotkeyEnabled': hotkeyEnabled,
        'requireConfirm': requireConfirm,
        'updatePolicy': updatePolicy,
        'themeMode': themeMode,
        'videoProfile': videoProfile,
      };
}

class AppConfig {
  AppConfig({
    required this.identity,
    required this.settings,
    List<RecentDevice>? recents,
    this.lastTargetId = '',
    this.lastPassword = '',
  }) : recents = recents ?? [];

  DeviceIdentity identity;
  AppSettings settings;
  List<RecentDevice> recents;
  String lastTargetId;
  String lastPassword;

  factory AppConfig.initial() => AppConfig(
        identity: DeviceIdentity.create(),
        settings: AppSettings(),
      );

  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
        identity: DeviceIdentity.fromJson(
            (json['identity'] as Map?)?.cast<String, dynamic>() ?? const {}),
        settings: AppSettings.fromJson(
            (json['settings'] as Map?)?.cast<String, dynamic>() ?? const {}),
        recents: ((json['recents'] as List?) ?? const [])
            .map((e) =>
                RecentDevice.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        lastTargetId: json['lastTargetId'] as String? ?? '',
        lastPassword: json['lastPassword'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'identity': identity.toJson(),
        'settings': settings.toJson(),
        'recents': recents.map((e) => e.toJson()).toList(),
        'lastTargetId': lastTargetId,
        'lastPassword': lastPassword,
      };

  AppConfig copy() => AppConfig.fromJson(
      jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>);
}

class AppPaths {
  AppPaths._();

  static String get dataDir {
    final override = Platform.environment['ORBITLINK_DATA_DIR'];
    if (override != null && override.trim().isNotEmpty) {
      return override;
    }
    final appData = Platform.environment['APPDATA'] ??
        '${Platform.environment['USERPROFILE'] ?? '.'}\\AppData\\Roaming';
    return '$appData\\OrbitLink';
  }

  static String get configFile => '$dataDir\\config.json';

  static String ensure() {
    Directory(dataDir).createSync(recursive: true);
    return dataDir;
  }
}

class ConfigStore {
  static AppConfig load() {
    try {
      AppPaths.ensure();
      final file = File(AppPaths.configFile);
      if (file.existsSync()) {
        final raw = file.readAsStringSync();
        if (raw.trim().isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final config = AppConfig.fromJson(decoded.cast<String, dynamic>());
            final settings = decoded['settings'];
            final storedProfile =
                settings is Map ? settings['videoProfile'] : null;
            if (storedProfile == null) {
              // Persist the upgraded stream profile so the file matches the UI.
              save(config);
            }
            return config;
          }
        }
      }
    } catch (_) {
      // A corrupt config must never stop the client from starting.
    }
    final fresh = AppConfig.initial();
    save(fresh);
    return fresh;
  }

  static void save(AppConfig config) {
    try {
      AppPaths.ensure();
      final tmp = File('${AppPaths.configFile}.tmp');
      tmp.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(config.toJson()),
        flush: true,
      );
      tmp.renameSync(AppPaths.configFile);
    } catch (_) {}
  }
}
