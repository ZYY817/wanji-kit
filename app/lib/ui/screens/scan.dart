// 扫描屏：左大计数 + 右清单逐条浮现（✓/✗/! 翻牌动画）
import 'package:flutter/material.dart';
import '../../engine/catalog.dart';
import '../../engine/detect.dart';
import '../theme.dart';
import '../widgets.dart';

class ScanScreen extends StatefulWidget {
  final Catalog catalog;
  final void Function(List<CheckResult>) onDone;
  const ScanScreen({super.key, required this.catalog, required this.onDone});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _done = <String, CheckResult>{};
  var _current = 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final results = await Detector.scan(widget.catalog,
        onProgress: (i, _, __) => setState(() => _current = i),
        onResult: (r) => setState(() => _done[r.component.id] = r));
    await Future.delayed(const Duration(milliseconds: 500));
    widget.onDone(results);
  }

  @override
  Widget build(BuildContext context) {
    final comps = widget.catalog.components;
    final done = _done.length;
    final missing = _done.values.where((r) => r.status != CheckStatus.installed).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 16, 56, 40),
      child: Row(children: [
        // 左：大计数 + 状态
        Expanded(flex: 4, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('SCANNING', style: TextStyle(fontFamily: 'Consolas',
              fontSize: 10, letterSpacing: 3, color: K.fg3)),
          const SizedBox(height: 20),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic, children: [
            CountUp(done,
                style: KT.serif.copyWith(fontSize: 92, color: K.fg)),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text('/ ${comps.length}',
                  style: KT.serif.copyWith(fontSize: 28, color: K.fg3)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(missing == 0 ? '目前全部正常' : '已发现 $missing 项缺失/过旧',
              style: KT.body.copyWith(
                  color: missing == 0 ? K.fg2 : K.warn, fontSize: 13)),
          const SizedBox(height: 28),
          // 进度发丝线
          Stack(children: [
            Container(height: 1, color: K.line),
            AnimatedFractionallySizedBox(
              duration: const Duration(milliseconds: 300),
              widthFactor: comps.isEmpty ? 0 : done / comps.length,
              child: Container(height: 1, color: K.accent),
            ),
          ]),
        ])),
        const SizedBox(width: 48),
        // 右：清单
        Expanded(flex: 7, child: ListView.builder(
          itemCount: comps.length,
          itemBuilder: (_, i) {
            final c = comps[i];
            final r = _done[c.id];
            final scanning = r == null && i == _current;
            final waiting = r == null && i > _current;
            return AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: waiting ? 0.28 : 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  if (r != null)
                    StatusDot(_colorOf(r.status), _symbolOf(r.status))
                  else
                    StatusDot(scanning ? K.accent : K.lineStrong,
                        scanning ? '·' : '—', pulse: scanning),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(c.name,
                        style: KT.body.copyWith(
                            fontSize: 13,
                            color: waiting ? K.fg3 : K.fg)),
                  ),
                  if (r?.installedVersion != null)
                    Text('v${r!.installedVersion}',
                        style: KT.mono.copyWith(fontSize: 10)),
                  if (r != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: Text(_labelOf(r.status),
                          style: KT.mono.copyWith(
                              fontSize: 10, color: _colorOf(r.status))),
                    )
                  else if (scanning)
                    Text('检测中', style: KT.mono.copyWith(
                        fontSize: 10, color: K.accent)),
                ]),
              ),
            );
          },
        )),
      ]),
    );
  }

  Color _colorOf(CheckStatus s) => switch (s) {
        CheckStatus.installed => K.ok,
        CheckStatus.missing => K.bad,
        CheckStatus.outdated => K.warn,
        CheckStatus.unknown => K.unknown,
      };
  String _symbolOf(CheckStatus s) => switch (s) {
        CheckStatus.installed => '✓',
        CheckStatus.missing => '✗',
        CheckStatus.outdated => '!',
        CheckStatus.unknown => '?',
      };
  String _labelOf(CheckStatus s) => switch (s) {
        CheckStatus.installed => '已装',
        CheckStatus.missing => '缺失',
        CheckStatus.outdated => '过旧',
        CheckStatus.unknown => '未知',
      };
}

/// 分数宽度动画盒子（进度线用）
class AnimatedFractionallySizedBox extends StatelessWidget {
  final double widthFactor;
  final Duration duration;
  final Widget child;
  const AnimatedFractionallySizedBox({
    super.key, required this.widthFactor, required this.duration, required this.child});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: widthFactor),
        duration: duration,
        builder: (_, v, __) =>
            FractionallySizedBox(widthFactor: v, alignment: Alignment.centerLeft, child: child),
      );
}
