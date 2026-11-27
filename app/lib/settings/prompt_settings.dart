import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'app_settings.dart';

class PromptSettingsButton extends StatefulWidget {
  const PromptSettingsButton({super.key, required this.settings});
  final AppSettings settings;
  @override
  State<PromptSettingsButton> createState() => _PromptSettingsButtonState();
}

class _PromptSettingsButtonState extends State<PromptSettingsButton> {
  final _button = GlobalKey();
  final _focus = FocusNode();
  bool _opened = false;
  String t(String zh, String en) =>
      widget.settings.language == AppLanguage.english ? en : zh;

  Future<void> _open() async {
    if (_opened) return;
    _opened = true;
    final settings = widget.settings;
    final route = ModalBottomSheetRoute<void>(
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: AnimatedBuilder(
            animation: settings,
            builder: (_, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(t('提示設定', 'Prompt settings')),
                ),
                RadioGroup<SceneDetail>(
                  groupValue: settings.sceneDetail,
                  onChanged: (value) {
                    if (value != null) settings.setSceneDetail(value);
                  },
                  child: Column(
                    children: [
                      ListTile(
                        title: Text(t('場景描述資訊量', 'Scene description detail')),
                      ),
                      for (final (detail, zh, en) in const [
                        (SceneDetail.quick, '快速', 'Quick'),
                        (SceneDetail.concise, '簡潔', 'Concise'),
                        (SceneDetail.detailed, '詳盡', 'Detailed'),
                      ])
                        RadioListTile(value: detail, title: Text(t(zh, en))),
                    ],
                  ),
                ),
                SwitchListTile(
                  title: Text(t('周圍物件提示', 'Surrounding object prompts')),
                  subtitle: Text(
                    t(
                      '目前提供物件名稱，距離選項待實測。',
                      'Object names are available. Distance options require field validation.',
                    ),
                  ),
                  value: settings.objectSpeech,
                  onChanged: settings.setObjectSpeech,
                ),
                ListTile(
                  title: Text(t('碰撞預警', 'Collision warnings')),
                  subtitle: Text(
                    t(
                      '本畫面未有可靠嘅碰撞量測。',
                      'Reliable collision measurements are unavailable here.',
                    ),
                  ),
                ),
                ListTile(
                  title: Text(t('路面通行提示', 'Surface guidance')),
                  subtitle: Text(
                    t(
                      '本畫面未能可靠判斷路面通行。',
                      'Reliable surface accessibility is unavailable here.',
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(t('完成', 'Done')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await Navigator.of(context).push(route);
    await route.completed;
    _opened = false;
    if (!mounted) return;
    _focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && MediaQuery.accessibleNavigationOf(context)) {
        _button.currentContext?.findRenderObject()?.sendSemanticsEvent(
          const FocusSemanticEvent(),
        );
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    key: _button,
    focusNode: _focus,
    color: Theme.of(context).colorScheme.primary,
    tooltip: t('提示設定', 'Prompt settings'),
    onPressed: _open,
    icon: const Icon(Icons.tune),
  );
}
