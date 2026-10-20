import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';

import 'ui/app_shell.dart';
import 'ui/app_theme.dart';
import 'ui/demo_page.dart';
import 'settings/app_settings.dart';

/// 領路通 · PathGuide HK。
///
/// 導航首頁先展示目的地搜尋、已儲存路線及路線錄製的未來產品方向；
/// 這些入口會明確標示為開發中，不會假裝已連接導航 API。
/// Android 與 iOS 的「探索」頁均使用原生相機及同一個裝置端模型，也可
/// 切換三類模擬框，並共用繁體中文閾值、標籤及粵語播報控制。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Preferences are loaded before the first UI frame, so the selected speech
  // speed applies to the very first Cantonese announcement after a relaunch.
  final settings = await AppSettings.load();

  // 室外强光下演示，深色系统栏更省电也更清楚。
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: AppColors.background,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(PathGuideApp(settings: settings));
}

class PathGuideApp extends StatefulWidget {
  const PathGuideApp({
    super.key,
    this.initialMode = SourceMode.camera,
    this.initialSection = AppSection.navigation,
    this.settings,
  });

  final SourceMode initialMode;
  final AppSection initialSection;
  final AppSettings? settings;

  @override
  State<PathGuideApp> createState() => _PathGuideAppState();
}

class _PathGuideAppState extends State<PathGuideApp> {
  late final AppSettings _settings = widget.settings ?? AppSettings.memory();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '領路通',
      locale: const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
        countryCode: 'HK',
      ),
      supportedLocales: const <Locale>[
        Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hant',
          countryCode: 'HK',
        ),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: AppShell(
        initialSection: widget.initialSection,
        initialVisionMode: widget.initialMode,
        settings: _settings,
      ),
    );
  }
}
