// 安装引擎：winget 优先 → 官方直链兜底 → 手动链接；设置项走 command 直开（无下载）。
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../ui/strings.dart';
import 'catalog_model.dart';
import 'env_path.dart';
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
      final r = await Process.run('winget', ['--version'],
              runInShell: true, environment: EnvPath.environment())
          .timeout(const Duration(seconds: 15));
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
        ], log);
        outcome = _mapExit(code);
        detail = S.fmt('evWingetExit', {'code': code});
        await log.write('winget_done', {'id': c.id, 'exit': code});
      }

      // 2) 官方直链兜底
      if (outcome == InstallOutcome.failed && c.install.download != null) {
        final d = c.install.download!;
        yield InstallEvent(c.id, 'downloading', S.of('evDownloading'));
        // 下载在后台进行；每 350ms 轮询进度发事件 → UI 显示百分比
        var lastPr = 0.0;
        var dlDone = false;
        final dlFuture = _download(d.url, d.name ??
                '${c.id}${d.url.endsWith('.msi') ? '.msi' : '.exe'}',
            (pr) => lastPr = pr, log)
            .whenComplete(() => dlDone = true);
        while (!dlDone) {
          await Future.delayed(const Duration(milliseconds: 350));
          if (lastPr > 0) {
            yield InstallEvent(c.id, 'downloading',
                S.fmt('evDlPct', {'pct': (lastPr * 100).round()}), lastPr);
          }
        }
        final file = await dlFuture;
        if (file != null) {
          yield InstallEvent(c.id, 'installing', S.of('evInstalling'));
          final code = d.msiArgs != null
              ? await _runCmdLine(
                  'msiexec ${d.msiArgs!.replaceAll('{file}', '"${file.path}"')}',
                  log)
              : await _run(
                  file.path, d.args.isEmpty ? [] : d.args.split(' '), log);
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

  /// 通用子进程：注入重建 PATH（winget/安装器可能是启动后新装的）。
  /// 超时只放弃等待——Process.run 无法强杀已拉起的子进程，记日志后按失败走。
  static Future<int> _run(String exe, List<String> args, KitLog log,
      {Duration timeout = const Duration(minutes: 10)}) async {
    try {
      final r = await Process.run(exe, args, runInShell: true,
              stdoutEncoding: systemEncoding, stderrEncoding: systemEncoding,
              environment: EnvPath.environment())
          .timeout(timeout);
      return r.exitCode;
    } on TimeoutException {
      await log.write('proc_timeout',
          {'exe': exe, 'args': args.join(' '), 'timeout_s': timeout.inSeconds});
      return -2;
    }
  }

  /// 执行一整行 cmd 命令（可含引号/&&/||）：写成临时 .cmd 再跑——
  /// 直接 `cmd /c "<含引号命令>"` 会被外层 shell 二次拆串弄坏参数。
  /// 注入重建 PATH（msiexec/dism 在系统 Path，一致性起见统一注入）。
  static Future<int> _runCmdLine(String command, KitLog log,
      {Duration timeout = const Duration(minutes: 10)}) async {
    File? bat;
    try {
      final dir = Directory(p.join(
          Platform.environment['TEMP'] ?? '.', 'wanji-kit'));
      dir.createSync(recursive: true);
      bat = File(p.join(dir.path,
          'cmd_${DateTime.now().millisecondsSinceEpoch}.cmd'));
      // 关键：cmd.exe 按 OEM 代码页解析 .cmd；UTF-8 写入会让 CJK 路径（如
      // 中文用户名 %TEMP% 下的 msiexec {file}）变乱码 → 必须用 systemEncoding
      await bat.writeAsBytes(systemEncoding.encode(
          '@echo off\r\n$command\r\nexit /b %errorlevel%\r\n'));
      final r = await Process.run(bat.path, const [], runInShell: true,
              stdoutEncoding: systemEncoding, stderrEncoding: systemEncoding,
              environment: EnvPath.environment())
          .timeout(timeout);
      return r.exitCode;
    } on TimeoutException {
      await log.write('cmd_timeout',
          {'run': command, 'timeout_s': timeout.inSeconds});
      return -2;
    } catch (e) {
      await log.write('cmd_error', {'run': command, 'err': '$e'});
      return -1;
    } finally {
      try {
        bat?.deleteSync();
      } catch (_) {}
    }
  }

  /// 下载：连接 30s 超时 + 流空闲 120s 超时（Stream.timeout 按事件间隔计），
  /// 异常/5xx 失败自动重试一次；onProgress 回报 0-1 供 UI 显示百分比。
  static Future<File?> _download(String url, String name,
      void Function(double) onProgress, KitLog log) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final client = http.Client();
      try {
        final dir = Directory(p.join(
            Platform.environment['TEMP'] ?? '.', 'wanji-kit'));
        dir.createSync(recursive: true);
        final file = File(p.join(dir.path, name));
        final req = await client
            .send(http.Request('GET', Uri.parse(url)))
            .timeout(const Duration(seconds: 30));
        if (req.statusCode != 200) {
          await log.write('download_http',
              {'url': url, 'code': req.statusCode, 'attempt': attempt + 1});
          // 5xx 值得重试一次；4xx 是死链直接放弃
          if (req.statusCode >= 500 && attempt == 0) {
            client.close();
            continue;
          }
          return null;
        }
        final sink = file.openWrite();
        final total = req.contentLength ?? 0;
        var got = 0;
        await for (final chunk in req.stream
            .timeout(const Duration(seconds: 120))) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) onProgress(got / total);
        }
        await sink.close();
        return file;
      } catch (e) {
        await log.write('download_error',
            {'url': url, 'attempt': attempt + 1, 'err': '$e'});
        if (attempt == 1) return null;
        await Future.delayed(const Duration(seconds: 1));
      } finally {
        client.close();
      }
    }
    return null;
  }

  static InstallOutcome _mapExit(int code) => switch (code) {
        0 => InstallOutcome.success,
        3010 => InstallOutcome.needReboot,
        1638 => InstallOutcome.alreadyNewer, // 已装更新版
        _ => InstallOutcome.failed,
      };
}
