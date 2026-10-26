// 目录模型（纯 Dart，无 flutter 依赖——可被独立脚本/测试复用）
enum RuleType { registry, file, command, winsxs }

enum CheckStatus { installed, missing, outdated, unknown }

class DetectRule {
  final RuleType type;
  final String? key;
  final String? hive;  // registry：'hklm'（默认）| 'hkcu'
  final String? value;
  final Object? equals;
  final int? minInt;
  final String? minVersion;
  final String? versionValue;
  final String? path;
  final String? cmd, args, contains;
  final String? pattern;
  final bool or;

  const DetectRule({
    required this.type,
    this.key, this.hive, this.value, this.equals, this.minInt,
    this.minVersion, this.versionValue, this.path, this.cmd, this.args,
    this.contains, this.pattern, this.or = false,
  });

  factory DetectRule.fromJson(Map<String, dynamic> j) => DetectRule(
        type: RuleType.values.byName(j['type'] as String),
        key: j['key'], hive: j['hive'], value: j['value'], equals: j['equals'],
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
  // 命令直开（设置项）：{channel:"command", run:"reg add …", elevated:false}
  // run 是完整 cmd 命令行；elevated 标记该项是否需要管理员权限（提权判定在队列级）
  final ({String run, bool elevated})? command;
  const InstallSpec({this.winget, this.download, this.manual, this.command});

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
            : (url: j['manual']['url'] as String,
                label: j['manual']['label'] as String? ?? '官网'),
        command: j['channel'] == 'command' && j['run'] != null
            ? (run: j['run'] as String, elevated: j['elevated'] == true)
            : (j['command'] == null
                ? null
                : (run: j['command']['run'] as String,
                    elevated: j['command']['elevated'] == true)),
      );
}

class Component {
  final String id, name, short, category, importance, why;
  // 'component'（默认，可下载安装的运行库）| 'setting'（系统设置项，命令直开）
  final String kind;
  // 设置项建议动作：'on' 建议开启 | 'off' 建议关闭 | 'switch' 建议切换；null=不标
  final String? rec;
  final int sizeMb;
  final List<DetectRule> detect;
  final InstallSpec install;
  const Component({
    required this.id, required this.name, required this.short,
    required this.category, required this.importance, required this.why,
    this.kind = 'component', this.rec,
    required this.sizeMb, required this.detect, required this.install,
  });

  bool get isSetting => kind == 'setting';

  factory Component.fromJson(Map<String, dynamic> j) => Component(
        id: j['id'], name: j['name'], short: j['short'] ?? j['name'],
        category: j['category'], importance: j['importance'] ?? 'common',
        why: j['why'] ?? '', kind: j['kind'] ?? 'component', rec: j['rec'],
        sizeMb: j['sizeMb'] ?? 0,
        detect: (j['detect'] as List).map((e) => DetectRule.fromJson(e)).toList(),
        install: InstallSpec.fromJson(j['install']),
      );
}

class CheckResult {
  final Component component;
  final CheckStatus status;
  final String? installedVersion;
  final String evidence;
  const CheckResult({
    required this.component, required this.status,
    this.installedVersion, required this.evidence,
  });
}

class Catalog {
  final int version;
  final List<Component> components;
  const Catalog(this.version, this.components);

  factory Catalog.fromJson(Map<String, dynamic> j) => Catalog(j['version'] ?? 1,
      (j['components'] as List).map((e) => Component.fromJson(e)).toList());
}
