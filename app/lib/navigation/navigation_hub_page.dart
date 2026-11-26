import 'package:flutter/material.dart';

import '../settings/app_settings.dart';

class NavigationHubPage extends StatelessWidget {
  const NavigationHubPage({
    super.key,
    required this.settings,
    required this.onSearch,
    required this.onLibrary,
    required this.onRecord,
    this.onRecordOutdoor,
    required this.onBack,
  });
  final AppSettings settings;
  final VoidCallback? onRecordOutdoor;
  final VoidCallback onSearch, onLibrary, onRecord, onBack;
  String t(String zh, String en) =>
      settings.language == AppLanguage.english ? en : zh;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      key: const ValueKey('navigation-hub'),
      padding: const EdgeInsets.all(20),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            onPressed: onBack,
            tooltip: t('返回首頁', 'Home'),
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        Text(
          t('路線導航', 'Navigation'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(
          t(
            '搜尋目的地，或錄低實際行過嘅路線供日後重行。',
            'Search destinations or record a walk to retrace later.',
          ),
        ),
        const SizedBox(height: 24),
        _entry(
          t('搜尋目的地', 'Search destination'),
          t('搜尋地址，預覽步行路線再開始。', 'Find a place and preview the walking route.'),
          Icons.search,
          Colors.deepOrange.shade800,
          onSearch,
        ),
        _entry(
          t('我的路線', 'My routes'),
          t('開啟已錄嘅戶外同室內路線。', 'Open a recorded outdoor or indoor route.'),
          Icons.map_outlined,
          Colors.green.shade800,
          onLibrary,
        ),
        if (onRecordOutdoor != null)
          _entry(
            t('錄製戶外路線', 'Record outdoor route'),
            t('用 GPS 記低實際行過嘅路。', 'Use GPS to record the path you walk.'),
            Icons.directions_walk,
            Colors.blue.shade800,
            onRecordOutdoor!,
          ),
        _entry(
          t('錄製新路線', 'Record new route'),
          t(
            '邊走邊記錄路標、樓層及實際連接。',
            'Record landmarks, floors and the connections you walked.',
          ),
          Icons.radio_button_checked,
          Colors.teal.shade800,
          onRecord,
        ),
      ],
    ),
  );
  Widget _entry(
    String title,
    String detail,
    IconData icon,
    Color color,
    VoidCallback action,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(150),
        padding: const EdgeInsets.all(24),
      ),
      onPressed: action,
      child: Column(
        children: [
          Icon(icon, size: 44),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(detail, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
