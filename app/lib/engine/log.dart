// 日志：JSONL 写 %APPDATA%\WanjiKit\logs\，可回查"装了什么/从哪下的/退出码"
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

class KitLog {
  final File file;
  KitLog._(this.file);

  static Future<KitLog> open() async {
    final dir = Directory(p.join(
        Platform.environment['APPDATA'] ?? '.', 'WanjiKit', 'logs'));
    dir.createSync(recursive: true);
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    return KitLog._(File(p.join(dir.path, '$ts.log')));
  }

  String get dir => file.parent.path;

  Future<void> write(String event, Map<String, Object?> data) async {
    final line = jsonEncode({
      't': DateTime.now().toIso8601String(),
      'event': event,
      ...data,
    });
    await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
  }
}
