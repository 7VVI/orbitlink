import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/mobile_controller.dart';
import 'core/mobile_scope.dart';
import 'ui/brand.dart';
import 'ui/root_shell.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OrbitLinkMobileApp());
}

class OrbitLinkMobileApp extends StatefulWidget {
  const OrbitLinkMobileApp({super.key});

  @override
  State<OrbitLinkMobileApp> createState() => _OrbitLinkMobileAppState();
}

class _OrbitLinkMobileAppState extends State<OrbitLinkMobileApp>
    with WidgetsBindingObserver {
  final MobileController _controller = MobileController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: AppColors.background,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.surface,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));
    _controller.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.refreshOnResume();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MobileScope(
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
        home: const _Bootstrap(),
      ),
    );
  }
}

class _Bootstrap extends StatelessWidget {
  const _Bootstrap();

  @override
  Widget build(BuildContext context) {
    final controller = MobileScope.of(context);
    if (!controller.ready) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandMark(size: 60),
              SizedBox(height: 18),
              Text('星轨远控', style: AppText.h1),
              SizedBox(height: 6),
              Text('安全、轻盈的远程桌面', style: AppText.caption),
              SizedBox(height: 22),
              SizedBox(
                width: 20,
                height: 20,
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
    return const RootShell();
  }
}
