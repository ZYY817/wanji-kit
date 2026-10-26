// 安装引擎：winget 优先 → 官方直链兜底 → 手动链接；设置项走 command 直开（无下载）。
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../ui/strings.dart';
import 'catalog_model.dart';
import 'log.dart';

enum InstallOutcome { success, needReboot, alreadyNewer, failed, manualOnly }

class InstallEvent {
  final String componentId;
  final String phase; // start/downloading/installing/verifying/done/failed
  final String detail;
  final double? progress; // 0-1
  const InstallEvent(this.componentId, this.phase, this.detail, [this.progress]);
}

class Installer {
  static Future<bool> get hasWinget async {
    try {
      final r = await Process.run('winget', ['--version'], runInShell: true);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// 顺序安装队列；逐项发事件。需要管理员权限（调用方保证已提权）。
  static Stream<InstallEvent> installAll(
    List<Component> items, {
    required Future<bool> Function(Component) verify,
    required KitLog log,
  }) async* {
    final winget = await hasWinget;
    for (final c in items) {
      yield InstallEvent(c.id, 'start', c.name);
      await log.write('install_start', {'id': c.id, 'name': c.name});

      var outcome = InstallOutcome.failed;
      var detail = '';

      // 0) 设置项：命令直开（reg add / powercfg 等，无下载阶段）
      if (c.install.command != null) {
        final cmd = c.install.command!;
        yield InstallEvent(c.id, 'installing', cmd.run);
        final code = await _runCmdLine(cmd.run, log);
        outcome = code == 0 ? InstallOutcome.success : InstallOutcome.failed;
        detail = S.fmt('evCmdExit', {'code': code});
        await log.write('cmd_done', {'id': c.id, 'exit': code, 'run': cmd.run});
      }

      // 1) winget
      if (outcome == InstallOutcome.failed &&
          c.install.command == null &&
          winget && c.install.winget != null) {
        yield InstallEvent(c.id, 'installing', 'winget ${c.install.winget}');
        // --force：修复模式走同一通道，已装包强制重装；全新安装时无副作用
        final code = await _run('winget', [
          'install', '--id', c.install.winget!,
          '--silent', '--force', '--accept-source-agreements',
          '--accept-package-agreements', '--disable-interactivity'
        ]);
        outcome = _mapExit(code);
        detail = S.fmt('evWingetExit', {'code': code});
        await log.write('winget_done', {'id': c.id, 'exit': code});
      }

      // 2) 官方直链兜底
      if (outcome == InstallOutcome.failed && c.install.download != null) {
        final d = c.install.download!;
        yield InstallEvent(c.id, 'downloading', S.of('evDownloading'));
        final file = await _download(d.url, d.name ??
            '${c.id}${d.url.endsWith('.msi') ? '.msi' : '.exe'}',
            (pr) {}, log);
        if (file != null) {
          yield InstallEvent(c.id, 'installing', S.of('evInstalling'));
          final code = d.msiArgs != null
              ? await _run('msiexec',
                  d.msiArgs!.replaceAll('{file}', '"${file.path}"').split(' '))
              : await _run(file.path, d.args.isEmpty ? [] : d.args.split(' '));
          outcome = _mapExit(code);
          detail = S.fmt('evPkgExit', {'code': code});
          await log.write('pkg_done', {'id': c.id, 'exit': code, 'src': d.url});
        } else {
          detail = S.of('evDlFail');
        }
      }

      // 3) 只能手动
      if (outcome == InstallOutcome.failed && c.install.manual != null) {
        outcome = InstallOutcome.manualOnly;
        detail = S.of('evNoChannel');
      }

      // 4) 重扫验证
      if (outcome == InstallOutcome.success || outcome == InstallOutcome.needReboot ||
          outcome == InstallOutcome.alreadyNewer) {
        yield InstallEvent(c.id, 'verifying', S.of('evVerifying'));
        final ok = await verify(c);
        if (!ok && outcome != InstallOutcome.needReboot) {
          outcome = InstallOutcome.failed;
          detail = S.of('evVerifyFail');
        }
      }

      yield InstallEvent(
          c.id,
          outcome == InstallOutcome.failed || outcome == InstallOutcome.manualOnly
              ? 'failed'
              : 'done',
          detail);
      await log.write('install_end', {'id': c.id, 'outcome': outcome.name, 'detail': detail});
    }
  }

  static Future<int> _run(String exe, List<String> args) async {
    final r = await Process.run(exe, args, runInShell: true,
        stdoutEncoding: systemEncoding, stderrEncoding: systemEncoding);
    return r.exitCode;
  }

  /// 执行一整行 cmd 命令（可含引号/&&/||）：写成临时 .cmd 再跑——
  /// 直接 `cmd /c "<含引号命令>"` 会被外层 shell 二次拆串弄坏参数。
  static Future<int> _runCmdLine(String command, KitLog log) async {
    File? bat;
    try {
      final dir = Directory(p.join(
          Platform.environment['TEMP'] ?? '.', 'wanji-kit'));
      dir.createSync(recursive: true);
      bat = File(p.join(dir.path,
          'cmd_${DateTime.now().millisecondsSinceEpoch}.cmd'));
      await bat.writeAsString(
          '@echo off\r\n$command\r\nexit /b %errorlevel%\r\n');
      final r = await Process.run(bat.path, const [], runInShell: true,
          stdoutEncoding: systemEncoding, stderrEncoding: systemEncoding);
      return r.exitCode;
    } catch (e) {
      await log.write('cmd_error', {'run': command, 'err': '$e'});
      return -1;
    } finally {
      try {
        bat?.deleteSync();
      } catch (_) {}
    }
  }

  static Future<File?> _download(String url, String name,
      void Function(double) onProgress, KitLog log) async {
    try {
      final dir = Directory(p.join(
          Platform.environment['TEMP'] ?? '.', 'wanji-kit'));
      dir.createSync(recursive: true);
      final file = File(p.join(dir.path, name));
      final req = await http.Client().send(http.Request('GET', Uri.parse(url)));
      if (req.statusCode != 200) return null;
      final sink = file.openWrite();
      final total = req.contentLength ?? 0;
      var got = 0;
      await for (final chunk in req.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress(got / total);
      }
      await sink.close();
      return file;
    } catch (e) {
      await log.write('download_error', {'url': url, 'err': '$e'});
      return null;
    }
  }

  static InstallOutcome _mapExit(int code) => switch (code) {
        0 => InstallOutcome.success,
        3010 => InstallOutcome.needReboot,
        1638 => InstallOutcome.alreadyNewer, // 已装更新版
        _ => InstallOutcome.failed,
      };
}
