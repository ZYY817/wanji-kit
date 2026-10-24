// 开屏：超大宋体标语 + 系统信息 mono + 唯一橙色 CTA
import 'dart:io';
import 'package:flutter/material.dart';
import '../../engine/catalog.dart';
import '../theme.dart';
import '../widgets.dart';

class BootScreen extends StatelessWidget {
  final Catalog catalog;
  final VoidCallback onStart;
  const BootScreen({super.key, required this.catalog, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final os = Platform.operatingSystemVersion;
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 20, 56, 44),
      child: Row(children: [
        // 左：标语 + CTA
        Expanded(
          flex: 7,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('WANJI KIT · 游戏运行环境工具',
                style: TextStyle(fontFamily: 'Consolas', fontSize: 11,
                    letterSpacing: 2.5, color: K.fg3)),
            const SizedBox(height: 26),
            Text('给游戏，', style: KT.serif.copyWith(fontSize: 58)),
            Text('一个能跑的家。',
                style: KT.serif.copyWith(fontSize: 58, color: K.accent)),
            const SizedBox(height: 24),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text('检测系统缺哪些游戏运行库，一键从官方源装齐。'
                  '不捆绑、可验证、每步留日志。',
                  style: KT.body.copyWith(color: K.fg2, fontSize: 14)),
            ),
            const Spacer(),
            Row(children: [
              KitButton('开始检测', icon: Icons.arrow_forward, onTap: onStart),
              const SizedBox(width: 14),
              Text('约 10 秒 · 无需管理员',
                  style: KT.mono.copyWith(fontSize: 11)),
            ]),
            const SizedBox(height: 20),
            Text('WINDOWS · X64 · 组件库 ${catalog.components.length} 项 · '
                '目录 V${catalog.version}',
                style: KT.mono),
          ]),
        ),
        const SizedBox(width: 40),
        // 右：检查项预告（mono 竖排列表）
        Expanded(
          flex: 5,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: K.panel,
              border: Border.all(color: K.line),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('将检查', style: TextStyle(fontFamily: 'Consolas',
                  fontSize: 10, letterSpacing: 2, color: K.fg3)),
              const SizedBox(height: 12),
              ...catalog.components.take(9).map((c) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.5),
                    child: Row(children: [
                      Container(width: 4, height: 4, color: K.lineStrong),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(c.short,
                              style: KT.body.copyWith(fontSize: 12.5))),
                      Text('${c.sizeMb}MB',
                          style: KT.mono.copyWith(fontSize: 10)),
                    ]),
                  )),
              if (catalog.components.length > 9)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('…等 ${catalog.components.length} 项',
                      style: KT.mono.copyWith(fontSize: 10)),
                ),
              const Spacer(),
              Text('OS: ${_shortOs(os)}', style: KT.mono.copyWith(fontSize: 9.5)),
            ]),
          ),
        ),
      ]),
    );
  }

  String _shortOs(String v) =>
      v.length > 40 ? '${v.substring(0, 40)}…' : v;
}
