import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import 'core/app_controller.dart';
import 'native/win32.dart';
import 'theme/app_theme.dart';
import 'ui/app_scope.dart';
import 'ui/shell/app_shell.dart';
import 'ui/widgets/brand.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1120, 720),
    minimumSize: Size(1000, 640),
    center: true,
    backgroundColor: Color(0xFFF5F7FB),
    title: '星轨远控',
    titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
    // Keep the visible client area at the design size despite the invisible
    // native resize frame.
    final padding = WindowMetrics.clientPadding();
    final extraW = padding.$1 > 0 && padding.$1 < 40 ? padding.$1 : 16;
    final extraH = padding.$2 > 0 && padding.$2 < 40 ? padding.$2 : 8;
    await windowManager.setMinimumSize(
        Size(1000 + extraW.toDouble(), 640 + extraH.toDouble()));
    await windowManager
        .setSize(Size(1120 + extraW.toDouble(), 720 + extraH.toDouble()));
    await windowManager.center();
  });
  runApp(const OrbitLinkApp());
}

class OrbitLinkApp extends StatefulWidget {
  const OrbitLinkApp({super.key});

  @override
  State<OrbitLinkApp> createState() => _OrbitLinkAppState();
}

class _OrbitLinkAppState extends State<OrbitLinkApp> {
  late final AppController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = AppController();
    _controller.addListener(_onControllerChanged);
    _controller.init();
  }

  void _onControllerChanged() {
    if (_controller.initialized && !_ready) {
      setState(() => _ready = true);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: _controller,
      child: MaterialApp(
        title: '星轨远控',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        scaffoldMessengerKey: _controller.messengerKey,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) {
          final data = MediaQuery.of(context);
          return MediaQuery(
            data: data.copyWith(textScaler: TextScaler.noScaling),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: _ready ? const AppShell() : const _SplashScreen(),
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.bg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandMark(size: 64),
            SizedBox(height: 18),
            Text(
              '星轨远控',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 6),
            Text(
              '安全、轻盈的远程桌面',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
            SizedBox(height: 24),
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
