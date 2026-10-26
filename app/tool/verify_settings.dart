// 真机验证：直接驱动引擎 detect/install 验证 6 个设置项。
// 用法：cd app && dart ../scripts/verify_settings.dart
import 'dart:convert';
import 'dart:io';
import 'package:wanji_kit/engine/catalog_model.dart';
import 'package:wanji_kit/engine/detect.dart';
import 'package:wanji_kit/engine/install.dart';
import 'package:wanji_kit/engine/log.dart';

void main(List<String> args) async {
  final j = jsonDecode(
      File('catalog/runtimes.json').readAsStringSync());
  final cat = Catalog.fromJson(j);
  stdout.writeln('== 全量检测（${cat.components.length} 项）==');
  final results = <String, CheckResult>{};
  for (final c in cat.components) {
    final r = await Detector.check(c);
    results[c.id] = r;
    stdout.writeln(
        '${c.isSetting ? "[设置]" : "[运行库]"} ${c.id.padRight(20)} '
        '${r.status.name.padRight(9)} ${r.evidence}');
  }

  if (args.contains('--install-test')) {
    stdout.writeln(
        '\n== command 渠道安装测试（免提权 4 项；hags 需管理员不在此测）==');
    final log = await KitLog.open();
    final picks = ['power-high', 'gamemode', 'game-dvr-off', 'fullscreen-opt']
        .map((id) => cat.components.firstWhere((c) => c.id == id))
        .toList();
    await for (final e in Installer.installAll(picks,
        verify: (c) async =>
            (await Detector.check(c)).status == CheckStatus.installed,
        log: log)) {
      stdout.writeln('${e.componentId}: ${e.phase} ${e.detail}');
    }
    stdout.writeln('\n== 安装后再检测 ==');
    for (final c in picks) {
      final r = await Detector.check(c);
      stdout.writeln('${c.id}: ${r.status.name} (${r.evidence})');
    }
  }
  exit(0);
}
