// PATH 重建验证：本进程 PATH 弄坏后，EnvPath 重建的环境仍应找得到命令。
// 用法：env "PATH=X:\\broken" dart run bin/path_test.dart
import 'dart:io';
import 'package:wanji_kit/engine/env_path.dart';

Future<void> main() async {
  stdout.writeln('进程 PATH: ${Platform.environment['PATH']}');
  final rebuilt = EnvPath.rebuild();
  stdout.writeln('重建 PATH 含 system32: '
      '${rebuilt.toLowerCase().contains(r'windows\system32'.toLowerCase())}');
  final env = EnvPath.environment();
  // 用重建环境跑 where dotnet / where java —— 进程 PATH 已坏，能找到=重建生效
  for (final cmd in ['dotnet', 'java', 'powercfg']) {
    final r = await Process.run('where', [cmd],
        runInShell: true, environment: env, stdoutEncoding: systemEncoding);
    stdout.writeln('where $cmd → exit ${r.exitCode}: '
        '${(r.stdout as String).split('\n').first.trim()}');
  }
}
