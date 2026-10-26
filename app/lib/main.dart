// 玩机装机工具 —— 入口（临时：系统标题栏；开发者模式开启后恢复 window_manager 无边框）
// 调试参数：--install=ids 提权续装 · --autoscan 自动开扫 · --demo-report/--demo-install 视觉自查
import 'package:flutter/material.dart';
import 'ui/kit_app.dart';
import 'ui/strings.dart';
import 'ui/theme.dart';

void main(List<String> args) {
  List<String> preset = [];
  var autoScan = false, demoReport = false, demoInstall = false, about = false;
  var repair = false, exclSettings = false;
  for (final a in args) {
    if (a.startsWith('--install=')) {
      preset = a.substring('--install='.length).split(',').where((e) => e.isNotEmpty).toList();
    } else if (a == '--autoscan') {
      autoScan = true;
    } else if (a == '--demo-report') {
      demoReport = true;
    } else if (a == '--demo-install') {
      demoInstall = true;
    } else if (a == '--about') {
      about = true;
    } else if (a == '--repair') {
      repair = true;        // 截图调试：结果屏直入修复模式
    } else if (a == '--excl-settings') {
      exclSettings = true;  // 截图调试：优化组取消勾选态
    }
  }
  // 标题随语言切换（窗口标题栏文本）
  runApp(_Root(preset, autoScan, demoReport, demoInstall, about,
      repair, exclSettings));
}

class _Root extends StatefulWidget {
  final List<String> preset;
  final bool autoScan, demoReport, demoInstall, about, repair, exclSettings;
  const _Root(this.preset, this.autoScan, this.demoReport,
      this.demoInstall, this.about, this.repair, this.exclSettings);
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  @override
  void initState() {
    super.initState();
    S.onLangChange = (_) => mounted ? setState(() {}) : null;
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: S.of('appTitle'),
        theme: kitTheme(),
        home: KitApp(presetInstall: widget.preset, autoScan: widget.autoScan,
            demoReport: widget.demoReport, demoInstall: widget.demoInstall,
            about: widget.about,
            repair: widget.repair, exclSettings: widget.exclSettings),
      );
}
