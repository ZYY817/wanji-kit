// 安装屏：逐项进度流 + 底部 mono 日志尾
import 'package:flutter/material.dart';
import '../../engine/catalog.dart';
import '../../engine/detect.dart';
import '../../engine/install.dart';
import '../../engine/log.dart';
import '../theme.dart';
import '../widgets.dart';

class InstallScreen extends StatefulWidget {
  final List<Component> items;
  final VoidCallback onDone;
  const InstallScreen({super.key, required this.items, required this.onDone});
  @override
  State<InstallScreen> createState() => _InstallScreenState();
}

class _InstallScreenState extends State<InstallScreen> {
  final _state = <String, String>{};   // id → phase
  final _log = <String>[];
  var _doneCount = 0;
  var _finished = false;
  KitLog? _kitLog;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    _kitLog = await KitLog.open();
    await _kitLog!.write('session', {
      'items': widget.items.map((c) => c.id).toList(),
      'os': DateTime.now().toIso8601String(),
    });
    await for (final e in Installer.installAll(widget.items,
        verify: (c) async =>
            (await Detector.check(c)).status == CheckStatus.installed,
        log: _kitLog!)) {
      setState(() {
        _state[e.componentId] = e.phase;
        _log.add('[${e.phase}] ${e.detail}');
        if (_log.length > 5) _log.removeAt(0);
        if (e.phase == 'done' || e.phase == 'failed') _doneCount++;
      });
    }
    setState(() => _finished = true);
    await Future.delayed(const Duration(seconds: 1));
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.items.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 16, 56, 36),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('INSTALLING', style: TextStyle(fontFamily: 'Consolas',
              fontSize: 10, letterSpacing: 3, color: K.fg3)),
          const Spacer(),
          Text('$_doneCount / $total', style: KT.mono.copyWith(fontSize: 11)),
        ]),
        const SizedBox(height: 16),
        Text('正在装齐', style: KT.serif.copyWith(fontSize: 44)),
        const SizedBox(height: 24),
        Expanded(child: ListView.builder(
          itemCount: widget.items.length,
          itemBuilder: (_, i) {
            final c = widget.items[i];
            final phase = _state[c.id];
            return _InstallRow(component: c, phase: phase);
          },
        )),
        const SizedBox(height: 12),
        // 日志尾
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: K.panel, border: Border.all(color: K.line),
            borderRadius: BorderRadius.circular(3)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ..._log.map((l) => Text(l,
                style: KT.mono.copyWith(fontSize: 10),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (_log.isEmpty)
              Text('等待开始…', style: KT.mono.copyWith(fontSize: 10)),
          ]),
        ),
        if (_finished)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('全部处理完毕', style: KT.mono.copyWith(color: K.ok)),
          ),
      ]),
    );
  }
}

class _InstallRow extends StatelessWidget {
  final Component component;
  final String? phase;
  const _InstallRow({required this.component, this.phase});

  @override
  Widget build(BuildContext context) {
    final (color, sym, label) = switch (phase) {
      'done' => (K.ok, '✓', '完成'),
      'failed' => (K.bad, '✗', '失败'),
      'verifying' => (K.accent, '…', '验证'),
      'installing' || 'downloading' || 'start' => (K.accent, '·', '进行中'),
      _ => (K.lineStrong, '—', '排队'),
    };
    final active = phase != null && phase != 'done' && phase != 'failed';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: active ? K.surface : K.panel,
        border: Border.all(color: active ? K.lineStrong : K.line),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(children: [
        StatusDot(color, sym, pulse: active),
        const SizedBox(width: 12),
        Expanded(child: Text(component.name,
            style: KT.body.copyWith(
                fontWeight: FontWeight.w700, fontSize: 13,
                color: phase == null ? K.fg3 : K.fg))),
        Text(label, style: KT.mono.copyWith(fontSize: 10, color: color)),
      ]),
    );
  }
}
