// 完成屏：结果汇总 + 重新检测/打开日志/完成
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../theme.dart';
import '../widgets.dart';

class DoneScreen extends StatelessWidget {
  final VoidCallback onRescan;
  final VoidCallback onClose;
  const DoneScreen({super.key, required this.onRescan, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 20, 56, 44),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('DONE', style: TextStyle(fontFamily: 'Consolas',
            fontSize: 10, letterSpacing: 3, color: K.fg3)),
        const SizedBox(height: 24),
        Text('装好了。', style: KT.serif.copyWith(fontSize: 64, color: K.fg)),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Text('运行库已按官方源补齐。建议再跑一次检测确认；'
              '如个别组件标注「需重启」，重启后即生效。',
              style: KT.body.copyWith(color: K.fg2)),
        ),
        const Spacer(),
        Row(children: [
          KitButton('重新检测', icon: Icons.refresh, onTap: onRescan),
          const SizedBox(width: 12),
          KitButton('打开日志目录', outline: true, onTap: _openLogDir),
          const Spacer(),
          KitButton('完成', outline: true, onTap: onClose),
        ]),
        const SizedBox(height: 16),
        Text('日志保存在 %APPDATA%\\WanjiKit\\logs —— 装了什么、从哪下的、'
            '退出码，全部留痕可查。', style: KT.mono.copyWith(fontSize: 10)),
      ]),
    );
  }

  void _openLogDir() {
    final dir = p.join(Platform.environment['APPDATA'] ?? '.', 'WanjiKit', 'logs');
    Directory(dir).createSync(recursive: true);
    Process.run('explorer', [dir], runInShell: true);
  }
}
