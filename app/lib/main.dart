// 玩机装机工具 —— 入口：无边框窗 980×620 + 参数解析（--elevated --install=ids）
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'ui/kit_app.dart';
import 'ui/theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const opts = WindowOptions(
    size: Size(980, 620),
    minimumSize: Size(880, 560),
    center: true,
    title: '玩机装机工具',
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(opts, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // --install=id1,id2（管理员模式带参数）
  List<String> preset = [];
  for (final a in args) {
    if (a.startsWith('--install=')) {
      preset = a.substring('--install='.length).split(',').where((e) => e.isNotEmpty).toList();
    }
  }

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: kitTheme(),
    home: KitApp(presetInstall: preset),
  ));
}
