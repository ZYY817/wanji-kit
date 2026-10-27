// 雕塑舞台渲染器：奶油空间 + 预渲染雕塑(sculpt_a.png) + 程序化轨道节点。
// 混合方案——石头/玻璃环/金珠是抠图资产（材质真实感交给渲染图），
// 轨道线/26 组件节点/扫描光/安装飞行全部实时绘制（进度载体的活的部分）。
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../orb/orb_model.dart';

class SculptPainter extends CustomPainter {
  SculptPainter(this.m, this.sculpt) : super(repaint: m);
  final OrbModel m;
  final ui.Image? sculpt;

  // —— 每帧复用资源 ——
  // 背景整层烘成 ui.Image（含高斯光带）；柔光/金珠/椭圆影的渐变
  // shader 全部烘在「单位圆、原点中心」上，画时 translate+scale ——
  // paint 与位置半径解耦，量化 alpha 作缓存键，全帧共享。
  // 原实现逐帧 createShader 30+ 次、MaskFilter.blur 30+ 次。
  final _fillP = Paint();
  final _strokeP = Paint()..style = PaintingStyle.stroke;
  final _imgP = Paint()..filterQuality = FilterQuality.high;
  final Map<int, Paint> _glowP = {};
  final Map<int, Paint> _beadP = {};
  final Map<int, Paint> _shadowP = {};
  Size _sz = Size.zero;
  ui.Image? _bgImg;

  /// 尺寸相关静态层烘焙：整层奶油背景（4 渐变 + 模糊光带）一次烘成图，
  /// 仅窗口尺寸变化时重烘
  void _ensureSize(Size size) {
    if (_sz == size) return;
    _sz = size;
    _bgImg?.dispose();
    _bgImg = null;
    if (size.isEmpty) return;
    final rec = ui.PictureRecorder();
    _bg(Canvas(rec), size);
    _bgImg = rec
        .endRecording()
        .toImageSync(size.width.ceil(), size.height.ceil());
  }

  // —— 调色 ——
  static const ink = Color(0xFF1A1815);
  static const bgTop = Color(0xFFF1EDE5);
  static const bgBottom = Color(0xFFD8D3C9);
  static const floor = Color(0xFFCAC4B7);
  static const warm = Color(0xFFFFF9EC);
  static const gold = Color(0xFFA8874E);
  static const goldHi = Color(0xFFEDDCB4);
  static const goldDark = Color(0xFF5E4B28);
  static const missing = Color(0xFFC4552B);
  static const amber = Color(0xFFB98A2E);
  static const green = Color(0xFF2E5B4C);
  static const shadow = Color(0xFF7A7263);

  @override
  void paint(Canvas canvas, Size size) {
    final minS = math.min(size.width, size.height);
    final idle = m.phase == OrbPhase.idle || m.phase == OrbPhase.complete;
    final motion = m.reduceMotion ? 0.0 : 1.0;

    // 雕塑中心：偏左中上；呼吸悬浮（完成/失焦时收敛）
    final C = Offset(size.width * 0.372, size.height * 0.435) +
        Offset(0, math.sin(m.t * 1.05) * minS * 0.008 * motion);
    // 鼠标视差：只作用在雕塑与影子上，产生前后景深
    final para = m.reduceMotion
        ? Offset.zero
        : (m.pointer - size.center(Offset.zero)) * 0.011 * m.hoverAmt;
    final imgW = minS * 0.80;
    final imgH = imgW * (353 / 493);
    final sculptScale = 0.88 + m.coreScale.x.clamp(0.3, 1.1) * 0.12;

    // 主轨道参数：倾斜椭圆环抱着雕塑
    final rx = minS * 0.395, ry = minS * 0.395 * 0.415;
    const tilt = -0.26;
    final cosT = math.cos(tilt), sinT = math.sin(tilt);
    Offset orbitPt(double psi) => C +
        Offset(math.cos(psi) * rx * cosT - math.sin(psi) * ry * sinT,
            math.cos(psi) * rx * sinT + math.sin(psi) * ry * cosT);

    _ensureSize(size);
    final bg = _bgImg;
    if (bg != null) {
      canvas.drawImage(bg, Offset.zero, _imgP);
    } else {
      _bg(canvas, size);
    }
    // 雕塑背后一层极淡的冷灰晕，把白色玻璃从奶油底里分离出来
    _glow(canvas, C, const Color(0xFF9E9789), 0.16, imgW * 0.62);
    _floorShadow(canvas, C + para * -0.35, imgW, imgH, minS, m);

    // ═══ 粒子位置解算 ═══
    final n = m.particles.length;
    final drift = m.t * 0.02 * motion;
    final solved = <_N>[];
    var fixIdx = 0;
    final fixTotal = m.particles.where((p) => p.fixable).length;
    for (final p in m.particles) {
      if (p.status == PStatus.absorbed) continue;
      final psi = p.index * 2 * math.pi / n + drift;
      var pos = orbitPt(psi);
      var depth = math.sin(psi); // >0 前半
      var front = false;
      int fIdx = -1;
      // 结果态：缺失/过旧节点前移放大，排成雕塑前方一行
      if (p.front.x > 0.001) {
        final gap = math.min(104.0, size.width * 0.50 / math.max(1, fixTotal));
        final fx = (fixIdx - (fixTotal - 1) / 2) * gap;
        final fp = C +
            Offset(fx, imgH * 0.47 +
                math.sin(m.t * 1.8 + p.seed) * 2.5 * motion);
        pos = Offset.lerp(pos, fp, p.front.x.clamp(0, 1.12))!;
        front = p.front.x > 0.55;
        depth = 2;
        fIdx = fixIdx;
        fixIdx++;
      }
      // 已装项退为远景尘埃
      if (p.dust.x > 0.001) {
        final ang = p.seed * 2.13;
        final dp = C +
            Offset(math.cos(ang), math.sin(ang) * 0.72) *
                minS * (0.50 + (p.index % 4) * 0.05) +
            Offset(math.sin(m.t * 0.5 + p.seed) * 6 * motion,
                math.cos(m.t * 0.4 + p.seed * 2) * 4 * motion);
        pos = Offset.lerp(pos, dp, p.dust.x.clamp(0, 1))!;
      }
      // 安装飞行：贝塞尔归入雕塑核心
      if (p.flying) {
        final e = Curves.easeInCubic.transform(p.flyT.clamp(0.0, 1.0));
        pos = _quadBez(p.flyFrom, p.flyCtrl, Offset.zero, e) + C;
        depth = 2;
      }
      m.lastPos[p.index] = pos - C;
      solved.add(_N(p, pos, depth, front, fIdx));
    }

    // ═══ 后半轨道线 + 后半节点（被雕塑遮挡）═══
    _orbitArc(canvas, C, rx, ry, tilt, true, idle ? 0.10 : 0.16);
    _decoArcs(canvas, C, minS, true);
    for (final s in solved) {
      if (s.p.dust.x > 0.4 && !s.p.flying) _dustDot(canvas, s);
    }
    for (final s in solved) {
      if (s.depth <= 0 && !s.front && !s.p.flying && s.p.dust.x <= 0.4) {
        _node(canvas, s, minS: minS);
      }
    }

    // ═══ 雕塑本体（抠图）═══
    _sculpture(canvas, C + para, imgW * sculptScale, imgH * sculptScale);
    // 吸纳光（安装进度反馈）：雕塑核心暖光
    if (m.bloom.x > 0.01) {
      _glow(canvas, C, goldHi, 0.30 * m.bloom.x, imgW * 0.30);
    }

    // ═══ 扫描光：沿轨道流过 ═══
    if (m.phase == OrbPhase.scanning && n > 0) {
      _sweepLight(canvas, orbitPt, n);
    } else if (idle && n > 0 && motion > 0) {
      _idleGlint(canvas, orbitPt, n);
    }

    // ═══ 前半轨道 + 前半节点 ═══
    _decoArcs(canvas, C, minS, false);
    _orbitArc(canvas, C, rx, ry, tilt, false, idle ? 0.14 : 0.22);
    for (final s in solved) {
      if (s.depth > 0 && !s.front && !s.p.flying && s.p.dust.x <= 0.4) {
        _node(canvas, s, minS: minS);
      }
    }

    // ═══ 涟漪 / 完成冲击波 ═══
    _ripples(canvas, C, rx, ry, tilt);
    // ═══ 前移的缺失节点：只显状态（可装=赤陶环/手动=灰虚线环），
    //     不印名字——名称/大小/指引全在右侧清单 ═══
    for (final s in solved) {
      if (s.front && !s.p.flying) {
        _node(canvas, s, scale: 1.5, minS: minS);
      }
    }
    // ═══ 飞行彗星 ═══
    for (final s in solved) {
      if (s.p.flying) {
        s.p.trail.insert(0, s.pos);
        if (s.p.trail.length > 14) s.p.trail.removeLast();
        _comet(canvas, s);
      }
    }
  }

  // ═════════ 奶油空间背景 ═════════
  void _bg(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [bgTop, bgBottom]).createShader(Offset.zero & size));
    // 左上方向性暖光
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(colors: [
            warm.withValues(alpha: 0.75),
            warm.withValues(alpha: 0.0),
          ]).createShader(Rect.fromCircle(
              center: Offset(size.width * -0.08, size.height * -0.15),
              radius: size.width * 0.85)));
    // 地面：底部压一条浅暗带 + 一道地平线似的柔过渡
    final floorRect = Rect.fromLTRB(
        0, size.height * 0.70, size.width, size.height);
    canvas.drawRect(
        floorRect,
        Paint()
          ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                floor.withValues(alpha: 0.0),
                floor.withValues(alpha: 0.55),
              ]).createShader(floorRect));
    // 一道斜入的光带（ref_C 的窗影光）——非常克制
    canvas.save();
    canvas.translate(size.width * 0.62, size.height * 0.2);
    canvas.rotate(-0.62);
    canvas.drawRect(
        Rect.fromCenter(center: Offset.zero,
            width: size.width * 1.6, height: size.height * 0.16),
        Paint()
          ..shader = LinearGradient(colors: [
            Colors.transparent,
            warm.withValues(alpha: 0.30),
            Colors.transparent,
          ], stops: const [0.15, 0.5, 0.85]).createShader(Rect.fromCenter(
              center: Offset.zero,
              width: size.width * 1.6, height: size.height * 0.16))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40));
    canvas.restore();
  }

  // ═════════ 雕塑地面投影 ═════════
  void _floorShadow(Canvas canvas, Offset c, double imgW, double imgH,
      double minS, OrbModel m) {
    final lift = (1 - math.sin(m.t * 1.05) * 0.5).clamp(0.5, 1.5);
    // 两层投影：贴身扁影 + 大范围环境影。原实现叠 MaskFilter.blur 逐帧高斯；
    // 径向渐变本身已淡出到透明，去模糊后视觉几乎无差，每帧省两次大模糊
    _ovalShadow(canvas, c + Offset(0, imgH * 0.58),
        imgW * 1.30 / lift, minS * 0.095 / lift, 0.115 * (2 - lift));
    _ovalShadow(canvas, c + Offset(0, imgH * 0.62),
        imgW * 2.05 / lift, minS * 0.20 / lift, 0.07 * (2 - lift));
  }

  /// 径向渐变椭圆影：单位圆 shader + 非均匀缩放成椭圆，alpha 1/64 量化入键
  void _ovalShadow(Canvas canvas, Offset c, double w, double h, double a) {
    if (a <= 0.003 || w <= 0 || h <= 0) return;
    final aQ = (a * 64).round().clamp(1, 255);
    final paint = _shadowP.putIfAbsent(aQ, () => Paint()
      ..shader = RadialGradient(colors: [
        shadow.withValues(alpha: aQ / 64),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: Offset.zero, radius: 1)));
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(w / 2, h / 2);
    canvas.drawCircle(Offset.zero, 1, paint);
    canvas.restore();
  }

  // ═════════ 雕塑：抠图绘制 ═════════
  void _sculpture(Canvas canvas, Offset c, double w, double h) {
    final img = sculpt;
    if (img == null) return;
    final dst = Rect.fromCenter(center: c, width: w, height: h);
    canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        dst,
        _imgP);
  }

  // ═════════ 轨道线：按前后半分开画，得到遮挡景深 ═════════
  void _orbitArc(Canvas canvas, Offset c, double rx, double ry, double tilt,
      bool back, double alpha) {
    final cosT = math.cos(tilt), sinT = math.sin(tilt);
    final path = Path();
    var pen = false;
    for (var i = 0; i <= 160; i++) {
      final psi = i * 2 * math.pi / 160;
      final front = math.sin(psi) > 0;
      if (front == back) {
        pen = false;
        continue;
      }
      final pt = c +
          Offset(math.cos(psi) * rx * cosT - math.sin(psi) * ry * sinT,
              math.cos(psi) * rx * sinT + math.sin(psi) * ry * cosT);
      if (!pen) {
        path.moveTo(pt.dx, pt.dy);
        pen = true;
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    canvas.drawPath(
        path,
        _strokeP
          ..strokeWidth = 0.9
          ..color = gold.withValues(alpha: alpha));
  }

  // ═════════ 装饰弧：外侧金轨道(带一颗流浪金珠) + 内侧玻璃短弧 ═════════
  void _decoArcs(Canvas canvas, Offset c, double minS, bool back) {
    final rx2 = minS * 0.455, ry2 = rx2 * 0.36;
    const tilt2 = -0.18;
    final cosT = math.cos(tilt2), sinT = math.sin(tilt2);
    Offset pt2(double psi) => c +
        Offset(math.cos(psi) * rx2 * cosT - math.sin(psi) * ry2 * sinT,
            math.cos(psi) * rx2 * sinT + math.sin(psi) * ry2 * cosT);
    // 外侧轨道只有一段（-2.6 → 0.9），不是整圆——避免同心圆感
    final path = Path();
    var pen = false;
    const a0 = -2.6, a1 = 0.9;
    for (var i = 0; i <= 120; i++) {
      final psi = a0 + (a1 - a0) * i / 120;
      final front = math.sin(psi) > 0;
      if (front == back) {
        pen = false;
        continue;
      }
      final pt = pt2(psi);
      if (!pen) {
        path.moveTo(pt.dx, pt.dy);
        pen = true;
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    canvas.drawPath(
        path,
        _strokeP
          ..strokeWidth = 0.7
          ..color = gold.withValues(alpha: back ? 0.10 : 0.20));
    // 流浪金珠：沿外轨道缓行（与 26 节点无关，纯雕塑感）
    if (!back) {
      final psiB = a0 + (m.t * 0.05) % (a1 - a0);
      _goldBead(canvas, pt2(psiB), minS * 0.009, 1.0);
    }
    // 垂直标记发丝线（参考图的中轴刻度）
    if (!back) {
      final top = c + Offset(0, -minS * 0.34);
      canvas.drawLine(
          top, top + Offset(0, minS * 0.055),
          _strokeP
            ..strokeWidth = 0.8
            ..color = ink.withValues(alpha: 0.14));
      canvas.drawRect(
          Rect.fromCenter(center: top - Offset(0, minS * 0.008),
              width: 2.5, height: 2.5),
          _fillP..color = ink.withValues(alpha: 0.20));
    }
  }

  // ═════════ 节点（26 组件 = 轨道珠）═════════
  void _node(Canvas canvas, _N s, {double scale = 1.0, double minS = 720}) {
    final p = s.p;
    final depthF = (0.7 + 0.3 * (s.depth + 1) / 2).clamp(0.55, 1.0);
    final emphasize = 0.72 + 0.28 * p.spread.x.clamp(0, 1); // 待机时珠子收敛
    final sf = (minS / 640).clamp(0.82, 1.15);
    var r = 4.8 * sf * scale * depthF * emphasize *
        p.scale.x.clamp(0.3, 1.8);
    if (p.status == PStatus.checking) {
      r *= 1 + 0.20 * math.sin(m.t * 9);
    }
    r *= 1 + p.flash * 0.45;
    final pos = s.pos;
    final alpha = depthF;

    final manual = p.component != null && !p.component!.autoInstall;
    switch (p.status) {
      case PStatus.missing:
        if (manual) {
          // 需手动：灰色虚线环（线型区分，不靠颜色）
          _dashedRing(canvas, pos, r * 1.05,
              const Color(0xFF6B675C).withValues(alpha: 0.85 * alpha));
          canvas.drawCircle(pos, r * 0.18,
              _fillP..color = const Color(0xFF6B675C)
                  .withValues(alpha: 0.9 * alpha));
          break;
        }
        // 赤陶橙镂空环 = 可自动安装
        _glow(canvas, pos, missing, 0.22 * alpha, r * 3.0);
        canvas.drawCircle(
            pos,
            r * 1.05,
            _strokeP
              ..strokeWidth = 1.7
              ..color = missing.withValues(alpha: 0.95 * alpha));
        canvas.drawCircle(
            pos + Offset(-r * 0.3, -r * 0.35), r * 0.22,
            _fillP..color = Colors.white.withValues(alpha: 0.55 * alpha));
      case PStatus.outdated:
        if (manual) {
          _dashedRing(canvas, pos, r * 1.05,
              amber.withValues(alpha: 0.8 * alpha));
          break;
        }
        // 琥珀：环 + 实心核
        _glow(canvas, pos, amber, 0.24 * alpha, r * 2.8);
        canvas.drawCircle(
            pos,
            r * 1.05,
            _strokeP
              ..strokeWidth = 1.4
              ..color = amber.withValues(alpha: 0.9 * alpha));
        _goldBead(canvas, pos, r * 0.55, alpha, tint: amber);
      case PStatus.installed:
        // 墨绿深点 + 奶油描边
        _glow(canvas, pos, green, 0.16 + p.flash * 0.20, r * 2.6);
        canvas.drawCircle(pos, r * 0.82,
            _fillP..color = green.withValues(alpha: 0.95 * alpha));
        canvas.drawCircle(
            pos,
            r * 0.82,
            _strokeP
              ..strokeWidth = 0.8
              ..color = bgTop.withValues(alpha: 0.7 * alpha));
        canvas.drawCircle(
            pos + Offset(-r * 0.22, -r * 0.26), r * 0.2,
            _fillP..color = Colors.white.withValues(alpha: 0.5 * alpha));
      case PStatus.checking:
        _glow(canvas, pos, goldHi, 0.40, r * 3.0);
        _goldBead(canvas, pos, r * 0.9, alpha);
        canvas.drawCircle(
            pos,
            r * 1.5,
            _strokeP
              ..strokeWidth = 1
              ..color = gold.withValues(alpha: 0.55 * alpha));
      case PStatus.pending:
      default:
        _goldBead(canvas, pos, r * 0.62, alpha * (0.62 + 0.3 * emphasize));
    }
    // 落定脉冲
    if (p.flash > 0.02) {
      canvas.drawCircle(
          pos,
          r * (1.25 + (1 - p.flash) * 2.4),
          _strokeP
            ..strokeWidth = 1.3 * p.flash
            ..color = goldHi.withValues(alpha: 0.6 * p.flash));
    }
  }

  /// 虚线圆环：手动项专用线型
  void _dashedRing(Canvas canvas, Offset pos, double r, Color color) {
    const segs = 8, gapRatio = 0.38;
    final paint = _strokeP
      ..strokeWidth = 1.3
      ..color = color;
    final rect = Rect.fromCircle(center: pos, radius: r);
    for (var i = 0; i < segs; i++) {
      final a0 = i * 2 * math.pi / segs;
      canvas.drawArc(rect, a0, 2 * math.pi / segs * (1 - gapRatio),
          false, paint);
    }
  }

  /// 球面金珠：光位左上的三段径向渐变。shader 烘在单位空间（原点中心、
  /// 光位 (-0.35,-0.4)、梯度半径 2），画时 translate+scale(r)——
  /// paint 只依赖 (tint, alpha量化)，26+ 颗/帧共享缓存
  void _goldBead(Canvas canvas, Offset pos, double r, double alpha,
      {Color tint = gold}) {
    final aQ = (alpha.clamp(0.0, 1.0) * 32).round();
    if (aQ <= 0 || r <= 0) return;
    final key = (tint.toARGB32() << 6) | aQ;
    final paint = _beadP.putIfAbsent(key, () => Paint()
      ..shader = ui.Gradient.radial(
          const Offset(-0.35, -0.4), 2.0, [
        const Color(0xFFFFFDF2).withValues(alpha: aQ / 32),
        tint.withValues(alpha: aQ / 32),
        goldDark.withValues(alpha: aQ / 32),
      ], const [0, 0.55, 1]));
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.scale(r);
    canvas.drawCircle(Offset.zero, 1, paint);
    canvas.restore();
    canvas.drawCircle(
        pos + Offset(-r * 0.3, -r * 0.36), r * 0.26,
        _fillP..color = Colors.white.withValues(alpha: 0.85 * alpha));
  }

  /// 中心向四周淡出的柔光：单位圆 shader + 缩放，(颜色, alpha量化) 共享缓存
  void _glow(Canvas canvas, Offset pos, Color c, double a, double rr) {
    if (a <= 0.003 || rr <= 0) return;
    final aQ = (a * 32).round().clamp(1, 63);
    final key = (c.toARGB32() << 6) | aQ;
    final paint = _glowP.putIfAbsent(key, () => Paint()
      ..shader = RadialGradient(colors: [
        c.withValues(alpha: aQ / 32),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: Offset.zero, radius: 1)));
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.scale(rr);
    canvas.drawCircle(Offset.zero, 1, paint);
    canvas.restore();
  }

  // ═════════ 尘埃（已装项退远）═════════
  void _dustDot(Canvas canvas, _N s) {
    final tw = 0.5 + 0.5 * math.sin(m.t * 1.7 + s.p.seed * 3);
    final a = (0.10 + 0.16 * tw) * s.p.dust.x.clamp(0, 1);
    canvas.drawCircle(s.pos, 1.6 + tw,
        _fillP..color = gold.withValues(alpha: a));
  }

  // ═════════ 扫描光：一道暖光沿轨道流过 ═════════
  void _sweepLight(Canvas canvas, Offset Function(double) orbitPt, int n) {
    // 当前被检粒子的轨道角；没有则按进度推
    var idx = m.particles.indexWhere((p) => p.status == PStatus.checking);
    if (idx < 0) idx = m.doneCount.clamp(0, n - 1);
    final psiHead = idx * 2 * math.pi / n + m.t * 0.02;
    // 尾迹：一串渐隐的光点（半径/alpha 微调代替逐点 1.6px 高斯——
    // 原实现 22 次 MaskFilter/帧，占掉 painter 大半模糊预算）
    for (var k = 22; k >= 1; k--) {
      final f = 1 - k / 22;
      final pt = orbitPt(psiHead - k * 0.055);
      canvas.drawCircle(
          pt,
          2.8 * f + 0.5,
          _fillP..color = goldHi.withValues(alpha: 0.40 * f));
    }
    final head = orbitPt(psiHead);
    _glow(canvas, head, const Color(0xFFFFF3D0), 0.85, 26);
    _goldBead(canvas, head, 5.2, 1.0);
  }

  // ═════════ 待机微光：偶尔有光沿轨道慢慢走 ═════════
  void _idleGlint(Canvas canvas, Offset Function(double) orbitPt, int n) {
    final cyc = (m.t % 7.0) / 7.0;
    if (cyc > 0.42) return;
    final psi = cyc / 0.42 * 2 * math.pi;
    for (var k = 14; k >= 1; k--) {
      final f = 1 - k / 14;
      final pt = orbitPt(psi - k * 0.05);
      canvas.drawCircle(pt, 1.8 * f + 0.3,
          _fillP..color = goldHi.withValues(alpha: 0.16 * f));
    }
    _glow(canvas, orbitPt(psi), goldHi, 0.4, 14);
  }

  // ═════════ 涟漪/冲击波：与轨道同倾角的扩散椭圆 ═════════
  void _ripples(Canvas canvas, Offset c, double rx, double ry, double tilt) {
    for (final r in m.ripples) {
      final age = (m.t - r.born) / 1.4;
      final f = 1 - age;
      if (f <= 0) continue;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(tilt);
      canvas.drawOval(
          Rect.fromCenter(center: Offset.zero,
              width: rx * 2 * (0.9 + age * 0.5),
              height: ry * 2 * (0.9 + age * 0.5)),
          _strokeP
            ..strokeWidth = 1.4 * f
            ..color = gold.withValues(alpha: r.alpha * 0.5 * f));
      canvas.restore();
    }
    if (m.shock >= 0) {
      final s = m.shock;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(tilt);
      canvas.drawOval(
          Rect.fromCenter(center: Offset.zero,
              width: rx * 2 * (1 + s * 0.9), height: ry * 2 * (1 + s * 0.9)),
          _strokeP
            ..strokeWidth = 2.2 * (1 - s)
            ..color = goldHi.withValues(alpha: 0.55 * (1 - s)));
      canvas.restore();
      // 完成瞬间的整屏柔光
      _glow(canvas, c, warm, 0.30 * (1 - s), rx * 1.6);
    }
  }

  // ═════════ 飞行彗星 ═════════
  void _comet(Canvas canvas, _N s) {
    final tr = s.p.trail;
    for (var i = tr.length - 1; i >= 1; i--) {
      final f = 1 - i / tr.length;
      canvas.drawCircle(
          tr[i],
          5.5 * f * (1 - s.p.flyT * 0.25) + 0.5,
          _fillP..color = gold.withValues(alpha: 0.35 * f));
    }
    _glow(canvas, s.pos, goldHi, 0.7, 20);
    _goldBead(canvas, s.pos, 5.4, 1.0);
  }

  static Offset _quadBez(Offset a, Offset c, Offset b, double t) {
    final mt = 1 - t;
    return a * (mt * mt) + c * (2 * mt * t) + b * (t * t);
  }

  @override
  bool shouldRepaint(SculptPainter old) =>
      old.sculpt != sculpt || old.m != m;
}

class _N {
  final OrbParticle p;
  final Offset pos;
  final double depth;
  final bool front;
  final int frontIdx;
  const _N(this.p, this.pos, this.depth, this.front, this.frontIdx);
}
