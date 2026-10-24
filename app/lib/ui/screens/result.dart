// 结果屏：分组清单（缺失/过旧/已装）+ 汇总条 + 「一键装齐」
import 'package:flutter/material.dart';
import '../../engine/catalog.dart';
import '../../engine/elevate.dart';
import '../theme.dart';
import '../widgets.dart';

class ResultScreen extends StatelessWidget {
  final List<CheckResult> results;
  final void Function(List<Component>) onInstall;
  final VoidCallback onRescan;
  const ResultScreen({super.key, required this.results,
      required this.onInstall, required this.onRescan});

  @override
  Widget build(BuildContext context) {
    final missing = results.where((r) => r.status == CheckStatus.missing).toList();
    final outdated = results.where((r) => r.status == CheckStatus.outdated).toList();
    final ok = results.where((r) => r.status == CheckStatus.installed).toList();
    final fixable = [...missing, ...outdated]
        .where((r) => r.component.install.winget != null || r.component.install.download != null)
        .toList();
    final totalMb = fixable.fold(0, (s, r) => s + r.component.sizeMb);
    final allOk = fixable.isEmpty && missing.every((r) => r.component.install.manual != null);

    return Column(children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(56, 12, 56, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 左：大结论
            Expanded(flex: 4, child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('REPORT', style: TextStyle(fontFamily: 'Consolas',
                  fontSize: 10, letterSpacing: 3, color: K.fg3)),
              const SizedBox(height: 18),
              Text(allOk ? '环境完好。' : '缺 ${fixable.length} 项。',
                  style: KT.serif.copyWith(fontSize: 52)),
              const SizedBox(height: 14),
              _meta('已装', ok.length, K.ok),
              _meta('过旧', outdated.length, K.warn),
              _meta('缺失', missing.length, K.bad),
              const SizedBox(height: 18),
              if (fixable.isNotEmpty)
                Text('预计下载 $totalMb MB · 安装时需管理员权限',
                    style: KT.mono.copyWith(fontSize: 10.5)),
            ])),
            const SizedBox(width: 40),
            // 右：分组清单
            Expanded(flex: 7, child: ListView(children: [
              if (missing.isNotEmpty) _group('缺失', missing, K.bad, '✗'),
              if (outdated.isNotEmpty) _group('过旧', outdated, K.warn, '!'),
              _group('已装', ok, K.fg3, '✓', collapsed: true),
            ])),
          ]),
        ),
      ),
      // 底部行动条
      Container(
        height: 72,
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: K.line))),
        padding: const EdgeInsets.symmetric(horizontal: 56),
        child: Row(children: [
          if (fixable.isNotEmpty)
            KitButton('一键装齐 ${fixable.length} 项', icon: Icons.bolt,
                onTap: () async {
                  if (!await Elevation.isAdmin) {
                    await Elevation.relaunchElevated(
                        fixable.map((c) => c.component.id).toList());
                    return;
                  }
                  onInstall(fixable.map((r) => r.component).toList());
                })
          else
            Text('没有需要处理的组件', style: KT.body.copyWith(color: K.fg2)),
          const SizedBox(width: 16),
          KitButton('重新检测', outline: true, onTap: onRescan),
          const Spacer(),
          Text('只从官方源安装 · 全部操作写日志',
              style: KT.mono.copyWith(fontSize: 10)),
        ]),
      ),
    ]);
  }

  Widget _meta(String label, int n, Color c) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Container(width: 8, height: 8, color: c.withValues(alpha: 0.9)),
          const SizedBox(width: 10),
          Text('$label ${n.toString().padLeft(2, '0')}',
              style: KT.mono.copyWith(color: K.fg2, fontSize: 12)),
        ]),
      );

  Widget _group(String title, List<CheckResult> items, Color c, String sym,
      {bool collapsed = false}) {
    if (collapsed && items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Row(children: [
          Text(title, style: KT.body.copyWith(
              fontWeight: FontWeight.w800, fontSize: 13, color: c)),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: K.line)),
          Text('${items.length}', style: KT.mono.copyWith(fontSize: 10)),
        ]),
      ),
      ...items.map((r) => _row(r, c, sym, dim: collapsed)),
    ]);
  }

  Widget _row(CheckResult r, Color c, String sym, {bool dim = false}) {
    final manual = r.component.install.manual;
    return Opacity(
      opacity: dim ? 0.5 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: K.panel,
          border: Border.all(color: K.line),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(children: [
          StatusDot(c, sym),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.component.short,
                style: KT.body.copyWith(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 2),
            Text(r.component.why,
                style: KT.mono.copyWith(fontSize: 9.5, color: K.fg3),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          if (r.installedVersion != null)
            Text('v${r.installedVersion}',
                style: KT.mono.copyWith(fontSize: 10)),
          if (!dim && manual != null)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text('需手动', style: KT.mono.copyWith(
                  fontSize: 10, color: K.warn)),
            ),
        ]),
      ),
    );
  }
}
