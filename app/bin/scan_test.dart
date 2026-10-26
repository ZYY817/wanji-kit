// 独立真机扫描：dart run bin/scan_test.dart —— 不需要 Flutter 运行时
import 'dart:convert';
import 'dart:io';
import 'package:wanji_kit/engine/catalog_model.dart';
import 'package:wanji_kit/engine/detect.dart';

Future<void> main() async {
  final j = jsonDecode(File('catalog/runtimes.json').readAsStringSync());
  final catalog = Catalog.fromJson(j);
  stdout.writeln('扫描 ${catalog.components.length} 项…\n');
  final results = await Detector.scan(catalog);
  var missing = 0, outdated = 0, ok = 0;
  for (final r in results) {
    final (mark, label) = switch (r.status) {
      CheckStatus.installed => ('✓', '已装'),
      CheckStatus.missing => ('✗', '缺失'),
      CheckStatus.outdated => ('!', '过旧'),
      CheckStatus.unknown => ('?', '未知'),
    };
    if (r.status == CheckStatus.installed) ok++;
    if (r.status == CheckStatus.missing) missing++;
    if (r.status == CheckStatus.outdated) outdated++;
    stdout.writeln('$mark ${r.component.short.padRight(22)} $label'
        '${r.installedVersion != null ? '  v${r.installedVersion}' : ''}   [${r.evidence}]');
  }
  stdout.writeln('\n已装 $ok · 缺失 $missing · 过旧 $outdated');
}
