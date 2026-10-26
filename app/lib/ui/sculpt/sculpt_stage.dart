// 雕塑舞台：加载抠图雕塑 + 全屏自绘 + 指针视差
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../orb/orb_model.dart';
import 'sculpt_painter.dart';

class SculptStage extends StatefulWidget {
  final OrbModel model;
  const SculptStage({super.key, required this.model});

  @override
  State<SculptStage> createState() => _SculptStageState();
}

class _SculptStageState extends State<SculptStage> {
  ui.Image? _sculpt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await rootBundle.load('assets/sculpt_a.png');
      final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (mounted) setState(() => _sculpt = frame.image);
    } catch (_) {/* 雕塑缺失时场景仍可运行：轨道+节点照常 */}
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    return MouseRegion(
      onHover: (e) => m.pointer = e.localPosition,
      onEnter: (_) => m.hoverTarget = 1,
      onExit: (_) => m.hoverTarget = 0,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: SculptPainter(m, _sculpt),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
