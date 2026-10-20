import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import 'app_theme.dart';
import 'demo_page.dart';

enum AppSection { explore, navigation, settings }

/// Main product shell. Camera resources only exist while Explore is visible.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.initialSection = AppSection.navigation,
    this.initialVisionMode = SourceMode.camera,
    required this.settings,
  });

  final AppSection initialSection;
  final SourceMode initialVisionMode;
  final AppSettings settings;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late AppSection _section = widget.initialSection;

  void _select(AppSection section) {
    if (_section == section) return;
    setState(() => _section = section);
  }

  Widget _page() => switch (_section) {
    AppSection.explore => DemoPage(
      initialMode: widget.initialVisionMode,
      settings: widget.settings,
    ),
    AppSection.navigation => NavigationHomePage(
      onOpenExplore: () => _select(AppSection.explore),
    ),
    AppSection.settings => SettingsPage(
      onOpenExplore: () => _select(AppSection.explore),
      settings: widget.settings,
    ),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: KeyedSubtree(key: ValueKey(_section), child: _page()),
      ),
      bottomNavigationBar: _AppNavigationBar(
        selected: _section,
        onSelected: _select,
      ),
    );
  }
}

class NavigationHomePage extends StatelessWidget {
  const NavigationHomePage({super.key, required this.onOpenExplore});

  final VoidCallback onOpenExplore;

  void _showComingSoon(
    BuildContext context, {
    required String title,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              CircleAvatar(
                radius: 30,
                backgroundColor: color.withValues(alpha: 0.16),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              const _DevelopmentBadge(),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  onOpenExplore();
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
                icon: const Icon(Icons.visibility_rounded),
                label: const Text('先使用即時辨識'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        key: const ValueKey('navigation-home'),
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            sliver: SliverList.list(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.assistant_navigation,
                        color: AppColors.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '領路通',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            '你的無障礙步行助手',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const _DevelopmentBadge(compact: true),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  '想去哪裡？',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  '選擇導航方式；路線功能將在未來版本提供。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                _FeatureCard(
                  color: AppColors.destination,
                  icon: Icons.travel_explore_rounded,
                  title: '搜尋目的地',
                  subtitle: '輸入地址，自動規劃步行路線',
                  onTap: () => _showComingSoon(
                    context,
                    title: '搜尋目的地',
                    description: '未來可輸入地址，並結合無障礙路況規劃步行路線。',
                    icon: Icons.travel_explore_rounded,
                    color: AppColors.destination,
                  ),
                ),
                const SizedBox(height: 14),
                _FeatureCard(
                  color: AppColors.routes,
                  icon: Icons.map_rounded,
                  title: '我的路線',
                  subtitle: '選擇已儲存路線開始導航',
                  onTap: () => _showComingSoon(
                    context,
                    title: '我的路線',
                    description: '未來可儲存常用路線，快速開始語音導航。',
                    icon: Icons.map_rounded,
                    color: AppColors.routes,
                  ),
                ),
                const SizedBox(height: 14),
                _FeatureCard(
                  color: AppColors.record,
                  icon: Icons.radio_button_checked_rounded,
                  title: '錄製新路線',
                  subtitle: '錄製 GPS 軌跡並加入路標',
                  onTap: () => _showComingSoon(
                    context,
                    title: '錄製新路線',
                    description: '未來可記錄 GPS 軌跡，並在重要位置加入語音路標。',
                    icon: Icons.radio_button_checked_rounded,
                    color: AppColors.record,
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: onOpenExplore,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    side: const BorderSide(color: AppColors.border),
                    foregroundColor: AppColors.text,
                  ),
                  icon: const Icon(
                    Icons.visibility_rounded,
                    color: AppColors.primary,
                  ),
                  label: const Text('開啟即時環境辨識'),
                ),
                const SizedBox(height: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.onOpenExplore,
    required this.settings,
  });

  final VoidCallback onOpenExplore;
  final AppSettings settings;

  Future<void> _showSpeechSpeedPicker(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: settings,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('播報速度', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  '只會調整粵語播報的速度；不會改變音量或音調。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                for (final speed in SpeechSpeed.values)
                  _SpeechSpeedChoice(
                    speed: speed,
                    selected: settings.speechSpeed == speed,
                    onTap: () async {
                      await settings.setSpeechSpeed(speed);
                      if (sheetContext.mounted) {
                        Navigator.of(sheetContext).pop();
                      }
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showFutureInfo(
    BuildContext context, {
    required String title,
    required String description,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const _DevelopmentBadge(),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 18),
              Text(
                '此版本不會要求新的系統權限，也不會開始下載或連接網絡服務。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text('知道了'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AnimatedBuilder(
        animation: settings,
        builder: (context, _) => ListView(
          key: const ValueKey('settings-page'),
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
          children: <Widget>[
            Text('設定', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 6),
            Text('管理播報及即時辨識功能。', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            _NativeSettingsSection(
              title: '語音及即時辨識',
              children: <Widget>[
                _NativeSettingsRow(
                  key: const ValueKey<String>('speech-speed-row'),
                  icon: Icons.volume_up_rounded,
                  title: '播報速度',
                  value: settings.speechSpeed.label,
                  semanticLabel: '播報速度，目前為 ${settings.speechSpeed.label}',
                  onTap: () => _showSpeechSpeedPicker(context),
                ),
                _NativeSettingsRow(
                  icon: Icons.visibility_rounded,
                  title: '即時辨識設定',
                  value: '探索頁',
                  semanticLabel: '即時辨識設定，前往探索頁調整',
                  onTap: onOpenExplore,
                ),
              ],
            ),
            const SizedBox(height: 24),
            _NativeSettingsSection(
              title: '未來功能',
              children: <Widget>[
                _futureRow(
                  context,
                  title: '懸空障礙物偵測',
                  description: '需要可靠的深度距離資料，才可分辨頭部高度的障礙物。',
                  icon: Icons.height_rounded,
                ),
                _futureRow(
                  context,
                  title: '碰撞預警',
                  description: '需要距離感測與行進風險判斷，現有物件框不足以安全預警。',
                  icon: Icons.warning_amber_rounded,
                ),
                _futureRow(
                  context,
                  title: '場景描述分析',
                  description: '需要另一個專用的場景描述模型；本 App 目前只提供物件辨識。',
                  icon: Icons.auto_awesome_rounded,
                ),
                _futureRow(
                  context,
                  title: '導航地圖',
                  description: '需要定位和地圖資料；目前沒有接入地圖、GPS 或路線服務。',
                  icon: Icons.map_rounded,
                ),
                _futureRow(
                  context,
                  title: '方向表達',
                  description: '需要可靠的裝置方向與指南針資料，才能提供安全的鐘點方向提示。',
                  icon: Icons.explore_rounded,
                ),
                _futureRow(
                  context,
                  title: '相機偏離暫停偵測',
                  description: '需要裝置姿態資料及經過驗證的暫停規則，目前尚未實作。',
                  icon: Icons.screen_rotation_alt_rounded,
                ),
              ],
            ),
            const SizedBox(height: 24),
            _NativeSettingsSection(
              title: '模型與下載',
              children: <Widget>[
                const _NativeSettingsRow(
                  icon: Icons.memory_rounded,
                  title: '即時物件辨識模型',
                  value: '已安裝 · 2.87 MB',
                  semanticLabel: '即時物件辨識模型，已安裝，大小 2.87 MB',
                ),
                _NativeSettingsRow(
                  icon: Icons.auto_awesome_outlined,
                  title: '場景描述模型',
                  value: '未提供',
                  semanticLabel: '場景描述模型，未提供，開發中',
                  onTap: () => _showFutureInfo(
                    context,
                    title: '場景描述模型',
                    description: '目前沒有可下載的場景描述模型，也不會顯示虛構的檔案大小或下載按鈕。',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const _NativeSettingsSection(
              title: '私隱',
              children: <Widget>[
                _NativeSettingsRow(
                  icon: Icons.shield_outlined,
                  title: '私隱保障',
                  value: '僅限裝置端',
                  semanticLabel: '私隱保障，相機畫面只在裝置上處理，不錄影、不儲存、不上傳',
                  detail: '相機畫面只在裝置上處理，不錄影、不儲存、不上傳。',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _futureRow(
    BuildContext context, {
    required String title,
    required String description,
    required IconData icon,
  }) {
    return _NativeSettingsRow(
      icon: icon,
      title: title,
      value: '開發中',
      semanticLabel: '$title，開發中',
      onTap: () =>
          _showFutureInfo(context, title: title, description: description),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title，$subtitle，功能開發中',
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 154),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Icon(icon, color: Colors.white, size: 42),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 15,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpeechSpeedChoice extends StatelessWidget {
  const _SpeechSpeedChoice({
    required this.speed,
    required this.selected,
    required this.onTap,
  });

  final SpeechSpeed speed;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '播報速度 ${speed.label}${selected ? '，已選取' : ''}',
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.13)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      speed.label,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (selected)
                    const Icon(
                      Icons.check_rounded,
                      color: AppColors.primary,
                      semanticLabel: '已選取',
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NativeSettingsSection extends StatelessWidget {
  const _NativeSettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(18),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: <Widget>[
              for (var index = 0; index < children.length; index++) ...<Widget>[
                if (index > 0)
                  const Padding(
                    padding: EdgeInsets.only(left: 49),
                    child: Divider(height: 1, color: AppColors.border),
                  ),
                children[index],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _NativeSettingsRow extends StatelessWidget {
  const _NativeSettingsRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.semanticLabel,
    this.detail,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final String semanticLabel;
  final String? detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final interactive = onTap != null;
    return Semantics(
      button: interactive,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Icon(icon, color: AppColors.primary, size: 21),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 5,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (detail != null) ...<Widget>[
                          const SizedBox(height: 3),
                          Text(
                            detail!,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    flex: 4,
                    child: Text(
                      value,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: value == '開發中'
                            ? AppColors.warning
                            : AppColors.textMuted,
                        fontSize: 15,
                        height: 1.2,
                      ),
                    ),
                  ),
                  if (interactive) ...<Widget>[
                    const SizedBox(width: 3),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textMuted,
                      size: 25,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DevelopmentBadge extends StatelessWidget {
  const _DevelopmentBadge({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 12,
        vertical: compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '開發中',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.warning,
          fontSize: compact ? 11 : 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AppNavigationBar extends StatelessWidget {
  const _AppNavigationBar({required this.selected, required this.onSelected});

  final AppSection selected;
  final ValueChanged<AppSection> onSelected;

  @override
  Widget build(BuildContext context) {
    // At accessibility sizes the label is intentionally kept visible rather
    // than clipped. Give the bar enough height for the scaled label plus its
    // icon; the page above remains scrollable.
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final navigationHeight = textScale > 1.3 ? 84.0 : 68.0;
    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Container(
          height: navigationHeight,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(28),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              _NavItem(
                section: AppSection.explore,
                selected: selected,
                icon: Icons.visibility_rounded,
                label: '探索',
                onSelected: onSelected,
              ),
              _NavItem(
                section: AppSection.navigation,
                selected: selected,
                icon: Icons.assistant_navigation,
                label: '導航',
                onSelected: onSelected,
              ),
              _NavItem(
                section: AppSection.settings,
                selected: selected,
                icon: Icons.settings_rounded,
                label: '設定',
                onSelected: onSelected,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.section,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onSelected,
  });

  final AppSection section;
  final AppSection selected;
  final IconData icon;
  final String label;
  final ValueChanged<AppSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final active = section == selected;
    return Expanded(
      child: Semantics(
        selected: active,
        button: true,
        label: label,
        child: InkWell(
          onTap: () => onSelected(section),
          borderRadius: BorderRadius.circular(23),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            constraints: const BoxConstraints(minHeight: 58),
            decoration: BoxDecoration(
              color: active ? AppColors.surfaceRaised : Colors.transparent,
              borderRadius: BorderRadius.circular(23),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  icon,
                  size: 25,
                  color: active ? AppColors.primary : AppColors.textMuted,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: active ? AppColors.primary : AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
