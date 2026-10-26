// catalog 自检：JSON 结构 + 每条规则字段完整性（纯 Dart，不需要 Flutter）
// 用法：dart scripts/check_catalog.dart
import 'dart:convert';
import 'dart:io';

void main() {
  final j = jsonDecode(File('catalog/runtimes.json').readAsStringSync());
  final comps = j['components'] as List;
  var errors = 0;
  void err(String id, String msg) {
    errors++;
    stderr.writeln('  x $id: $msg');
  }

  for (final c in comps) {
    final id = c['id'] as String;
    for (final f in ['name', 'short', 'category', 'importance', 'why', 'sizeMb', 'detect', 'install']) {
      if (c[f] == null) err(id, '缺字段 $f');
    }
    final kind = c['kind'] ?? 'component';
    if (kind != 'component' && kind != 'setting') err(id, '未知 kind $kind');
    final rec = c['rec'];
    if (rec != null && rec != 'on' && rec != 'off' && rec != 'switch') {
      err(id, '未知 rec $rec');
    }
    for (final d in (c['detect'] as List)) {
      switch (d['type']) {
        case 'registry':
          if (d['key'] == null) err(id, 'registry 缺 key');
          if (d['hive'] != null && d['hive'] != 'hkcu' && d['hive'] != 'hklm') {
            err(id, 'registry 未知 hive ${d['hive']}');
          }
        case 'file':
          if (d['path'] == null) err(id, 'file 缺 path');
        case 'command':
          if (d['cmd'] == null || d['contains'] == null) err(id, 'command 缺 cmd/contains');
        case 'winsxs':
          if (d['pattern'] == null) err(id, 'winsxs 缺 pattern');
        default:
          err(id, '未知 detect 类型 ${d['type']}');
      }
    }
    final i = c['install'] as Map;
    final isCmd = i['channel'] == 'command' || i['command'] != null;
    if (isCmd && (i['run'] ?? i['command']?['run']) == null) {
      err(id, 'command 渠道缺 run');
    }
    if (i['winget'] == null && i['download'] == null &&
        i['manual'] == null && !isCmd) {
      err(id, '无任何安装渠道');
    }
  }
  stdout.writeln('catalog: ${comps.length} 组件，$errors 错误');
  if (errors > 0) exit(1);
}
