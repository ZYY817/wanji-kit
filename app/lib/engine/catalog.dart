// 目录模型 + 加载：内置 asset + 外挂 catalog.json（运行时热更新，免重编）
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

enum RuleType { registry, file, command, winsxs }

enum CheckStatus { installed, missing, outdated, unknown }

class DetectRule {
  final RuleType type;
  final String? key;          // registry key path
  final String? value;        // registry value name
  final Object? equals;       // expected value (int/string)
  final int? minInt;          // min int value (e.g. .NET Release)
  final String? minVersion;   // min version (e.g. "14.30")
  final String? versionValue; // registry value holding version
  final String? path;         // file path (env vars allowed)
  final String? cmd, args, contains; // command probe
  final String? pattern;      // winsxs pattern
  final bool or;              // OR with previous rule

  const DetectRule({
    required this.type,
    this.key, this.value, this.equals, this.minInt, this.minVersion,
    this.versionValue, this.path, this.cmd, this.args, this.contains,
    this.pattern, this.or = false,
  });

  factory DetectRule.fromJson(Map<String, dynamic> j) => DetectRule(
        type: RuleType.values.byName(j['type'] as String),
        key: j['key'], value: j['value'], equals: j['equals'],
        minInt: j['minInt'], minVersion: j['minVersion'],
        versionValue: j['versionValue'], path: j['path'],
        cmd: j['cmd'], args: j['args'], contains: j['contains'],
        pattern: j['pattern'], or: j['or'] == true,
      );
}

class InstallSpec {
  final String? winget;
  final ({String url, String args, String? name, String? msiArgs})? download;
  final ({String url, String label})? manual;
  const InstallSpec({this.winget, this.download, this.manual});

  factory InstallSpec.fromJson(Map<String, dynamic> j) => InstallSpec(
        winget: j['winget'],
        download: j['download'] == null
            ? null
            : (
                url: j['download']['url'] as String,
                args: (j['download']['args'] ?? '') as String,
                name: j['download']['name'] as String?,
                msiArgs: j['download']['msiArgs'] as String?,
              ),
        manual: j['manual'] == null
            ? null
            : (url: j['manual']['url'] as String, label: j['manual']['label'] as String? ?? '官网'),
      );
}

class Component {
  final String id, name, short, category, importance, why;
  final int sizeMb;
  final List<DetectRule> detect;
  final InstallSpec install;
  const Component({
    required this.id, required this.name, required this.short,
    required this.category, required this.importance, required this.why,
    required this.sizeMb, required this.detect, required this.install,
  });

  factory Component.fromJson(Map<String, dynamic> j) => Component(
        id: j['id'], name: j['name'], short: j['short'] ?? j['name'],
        category: j['category'], importance: j['importance'] ?? 'common',
        why: j['why'] ?? '', sizeMb: j['sizeMb'] ?? 0,
        detect: (j['detect'] as List).map((e) => DetectRule.fromJson(e)).toList(),
        install: InstallSpec.fromJson(j['install']),
      );
}

class CheckResult {
  final Component component;
  final CheckStatus status;
  final String? installedVersion;
  final String evidence; // 检测依据（注册表路径/文件/命令）——给用户看的
  const CheckResult({
    required this.component, required this.status,
    this.installedVersion, required this.evidence,
  });
}

class Catalog {
  final int version;
  final List<Component> components;
  const Catalog(this.version, this.components);

  /// 优先读 exe 旁/工作目录的 catalog/runtimes.json（热更新），否则用内置 asset
  static Future<Catalog> load() async {
    String raw;
    final sidecar = File(p.join(File(Platform.resolvedExecutable).parent.path,
        'catalog', 'runtimes.json'));
    try {
      raw = sidecar.existsSync()
          ? await sidecar.readAsString()
          : await rootBundle.loadString('catalog/runtimes.json');
    } catch (_) {
      raw = await rootBundle.loadString('catalog/runtimes.json');
    }
    final j = jsonDecode(raw);
    return Catalog(j['version'] ?? 1,
        (j['components'] as List).map((e) => Component.fromJson(e)).toList());
  }
}
