// 目录加载：exe 旁 catalog/runtimes.json（热更新）→ 内置 asset 兜底
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'catalog_model.dart';

export 'catalog_model.dart';

Future<Catalog> loadCatalog() async {
  String? raw;
  final sidecar = File(p.join(File(Platform.resolvedExecutable).parent.path,
      'catalog', 'runtimes.json'));
  try {
    raw = sidecar.existsSync()
        ? await sidecar.readAsString()
        : await rootBundle.loadString('catalog/runtimes.json');
  } catch (_) {
    raw = await rootBundle.loadString('catalog/runtimes.json');
  }
  return Catalog.fromJson(jsonDecode(raw));
}
