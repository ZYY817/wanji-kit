// 检测引擎：执行 catalog 里的 detect 规则。规则间默认 AND；or:true 与前一条 OR。
import 'dart:io';
import 'package:win32_registry/win32_registry.dart';
import 'catalog_model.dart';

class Detector {
  /// 扫描全部组件：onProgress 在某项开始检测前触发，onResult 在每项完成时触发。
  static Future<List<CheckResult>> scan(
    Catalog catalog, {
    void Function(int index, int total, Component current)? onProgress,
    void Function(CheckResult result)? onResult,
  }) async {
    final results = <CheckResult>[];
    for (var i = 0; i < catalog.components.length; i++) {
      final c = catalog.components[i];
      onProgress?.call(i, catalog.components.length, c);
      final r = await check(c);
      results.add(r);
      onResult?.call(r);
      await Future.delayed(const Duration(milliseconds: 60)); // 让 UI 动画跟得上
    }
    return results;
  }

  static Future<CheckResult> check(Component c) async {
    var allOk = true;
    String? version;
    var evidence = '';
    var prevOr = false;

    for (final r in c.detect) {
      final hit = await _eval(r);
      if (hit.version != null) version ??= hit.version;
      evidence = evidence.isEmpty ? hit.evidence : evidence;
      if (r.or && prevOr) {
        allOk = allOk || hit.ok;
      } else {
        allOk = allOk && hit.ok;
      }
      prevOr = r.or;
      if (hit.outdated) {
        return CheckResult(
            component: c,
            status: CheckStatus.outdated,
            installedVersion: version,
            evidence: evidence);
      }
    }

    return CheckResult(
        component: c,
        status: allOk ? CheckStatus.installed : CheckStatus.missing,
        installedVersion: version,
        evidence: evidence.isEmpty ? '—' : evidence);
  }

  static Future<_Hit> _eval(DetectRule r) async {
    try {
      switch (r.type) {
        case RuleType.registry:
          return _registry(r);
        case RuleType.file:
          return _file(r);
        case RuleType.command:
          return await _command(r);
        case RuleType.winsxs:
          return await _winsxs(r);
      }
    } catch (_) {
      return _Hit(false, '检测异常');
    }
  }

  static _Hit _registry(DetectRule r) {
    final hkcu = r.hive == 'hkcu';
    final evidence = '${hkcu ? 'HKCU' : 'HKLM'}\\${r.key}';
    RegistryKey? key;
    try {
      key = Registry.openPath(
          hkcu ? RegistryHive.currentUser : RegistryHive.localMachine,
          path: r.key!);
    } catch (_) {
      return _Hit(false, evidence); // 键不存在 = 未安装/未开启
    }
    try {
      int? intOf(RegistryValue? v) =>
          v is Int32Value ? v.value : v is Int64Value ? v.value : null;
      if (r.value != null) {
        final rv = key.getValue(r.value!);
        if (r.equals is int) {
          if (intOf(rv) != r.equals) return _Hit(false, evidence);
        } else if (r.minInt != null) {
          final n = intOf(rv);
          if (n == null || n < r.minInt!) return _Hit(false, evidence);
        } else if (rv == null) {
          return _Hit(false, evidence);
        }
      }
      String? ver;
      if (r.versionValue != null) {
        final rv = key.getValue(r.versionValue!);
        if (rv is StringValue) ver = rv.value.replaceAll(RegExp(r'[^0-9.]'), '');
        if (ver != null && r.minVersion != null && _cmpVersion(ver, r.minVersion!) < 0) {
          return _Hit(false, evidence, version: ver, outdated: true);
        }
      }
      return _Hit(true, evidence, version: ver);
    } finally {
      key.close();
    }
  }

  static _Hit _file(DetectRule r) {
    final path = _expandEnv(r.path!);
    return File(path).existsSync()
        ? _Hit(true, path)
        : _Hit(false, path);
  }

  static Future<_Hit> _command(DetectRule r) async {
    try {
      final res = await Process.run(r.cmd!, r.args!.split(' '),
          runInShell: true, stdoutEncoding: systemEncoding);
      if (res.exitCode != 0) return _Hit(false, '${r.cmd} ${r.args}');
      final ok = (res.stdout as String).contains(r.contains!);
      return _Hit(ok, '${r.cmd} ${r.args}');
    } catch (_) {
      return _Hit(false, '${r.cmd}（未安装命令）');
    }
  }

  static Future<_Hit> _winsxs(DetectRule r) async {
    final res = await Process.run(
        'cmd', ['/c', 'dir', '/b', '/s', '%WINDIR%\\WinSxS\\${r.pattern}'],
        runInShell: true, stdoutEncoding: systemEncoding);
    final ok = res.exitCode == 0 && (res.stdout as String).trim().isNotEmpty;
    return _Hit(ok, 'WinSxS:${r.pattern}');
  }

  /// 数字段版本比较："14.44.35211.0" vs "14.30"
  static int _cmpVersion(String a, String b) {
    final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < pb.length; i++) {
      final av = i < pa.length ? pa[i] : 0;
      if (av != pb[i]) return av - pb[i];
    }
    return 0;
  }

  static String _expandEnv(String s) => s.replaceAllMapped(
      RegExp(r'%([^%]+)%'), (m) => Platform.environment[m[1]] ?? m[0]!);
}

class _Hit {
  final bool ok;
  final String evidence;
  final String? version;
  final bool outdated;
  const _Hit(this.ok, this.evidence, {this.version, this.outdated = false});
}
