// HUD 覆盖件：错峰入场 / 黑圆箭头 CTA / 细字链接 / 缺失清单行 / 发丝进度
import 'package:flutter/material.dart';
import 'theme.dart';

/// 错峰入场：上移 + 淡入（系统「关闭动画」时直接呈现，不散射）
class EnterAnim extends StatelessWidget {
  final Widget child;
  final int index;
  final int staggerMs;
  const EnterAnim({super.key, required this.child,
      this.index = 0, this.staggerMs = 110});
  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reduce
          ? Duration.zero
          : Duration(milliseconds: 620 + index * staggerMs),
      curve: Interval(
          index == 0 ? 0 : (index * staggerMs) / (620 + index * staggerMs),
          1, curve: Curves.easeOutCubic),
      builder: (_, v, _) => Opacity(opacity: v,
          child: Transform.translate(
              offset: Offset(0, 16 * (1 - v)), child: child)),
    );
  }
}

/// 黑圆底白箭头 + 右侧文字（ref_D 样式）：hover 箭头前移，按下微沉
class ArrowCta extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  const ArrowCta(this.label, {super.key, this.onTap});
  @override
  State<ArrowCta> createState() => _ArrowCtaState();
}

class _ArrowCtaState extends State<ArrowCta> {
  var _hover = false, _down = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() { _hover = false; _down = false; }),
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          // 外圈发丝环 + 黑圆
          SizedBox(width: 62, height: 62, child: Stack(children: [
            Center(child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _hover && enabled ? 62 : 58,
              height: _hover && enabled ? 62 : 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: K.ink.withValues(alpha: _hover ? 0.35 : 0.18)),
              ))),
            Center(child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              transform: Matrix4.translationValues(
                  0, _down ? 1.5 : (_hover && enabled ? -1.5 : 0), 0),
              width: 52, height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: enabled ? K.ink : K.ink.withValues(alpha: 0.35),
                boxShadow: _hover && enabled
                    ? [BoxShadow(color: K.shadow.withValues(alpha: 0.45),
                        blurRadius: 22, offset: const Offset(0, 10))]
                    : [BoxShadow(color: K.shadow.withValues(alpha: 0.25),
                        blurRadius: 12, offset: const Offset(0, 6))],
              ),
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 180),
                offset: Offset(_hover && enabled ? 0.08 : 0, 0),
                child: const Icon(Icons.arrow_forward,
                    color: Color(0xFFF5F1E8), size: 20),
              ))),
          ])),
          const SizedBox(width: 16),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            style: KT.ui.copyWith(
                fontSize: 16, fontWeight: FontWeight.w600,
                letterSpacing: _hover ? 2 : 1,
                color: enabled ? K.ink : K.fg3),
            child: Text(widget.label),
          ),
        ]),
      ),
    );
  }
}

/// 细字链接：hover 墨色 + 下划
class HaloLink extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  const HaloLink(this.label, {super.key, this.onTap});
  @override
  State<HaloLink> createState() => _HaloLinkState();
}

class _HaloLinkState extends State<HaloLink> {
  var _hover = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Text(widget.label, style: KT.ui.copyWith(
              fontSize: 13,
              color: enabled ? (_hover ? K.ink : K.fg2) : K.fg3,
              decoration: _hover && enabled
                  ? TextDecoration.underline : TextDecoration.none,
              decorationColor: K.missing)),
        ),
      ),
    );
  }
}

/// 缺失清单行：状态点 + 名称 | 大小(右对齐定宽) | 状态(右对齐定宽)，
/// 行高 44 + 发丝分隔；手动项可点开官方指引。三列定宽→行与行严格对齐。
/// checkable 模式（修复清单）：状态点换成可选中空环，点行=勾选/取消。
class MissRow extends StatefulWidget {
  final String name;
  final int sizeMb;
  final String? sizeLabel;   // 覆盖默认的「N MB」（设置项显示「开关」）
  final String status;       // 缺失 / 过旧 / 未开启 / 需手动 / 已装
  final Color color;
  final bool last;
  final VoidCallback? onTap;
  final bool checkable, checked;
  final VoidCallback? onToggle;
  const MissRow(this.name, {super.key, this.sizeMb = 0, this.sizeLabel,
      required this.status, required this.color,
      this.last = false, this.onTap,
      this.checkable = false, this.checked = false, this.onToggle});
  @override
  State<MissRow> createState() => _MissRowState();
}

class _MissRowState extends State<MissRow> {
  var _hover = false;
  @override
  Widget build(BuildContext context) {
    final clickable = widget.onTap != null ||
        (widget.checkable && widget.onToggle != null);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: clickable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.checkable ? widget.onToggle : widget.onTap,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            border: widget.last ? null : Border(
                bottom: BorderSide(
                    color: K.line.withValues(alpha: 0.85), width: 0.7)),
          ),
          child: Row(children: [
            if (widget.checkable)
              Container(width: 9, height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.checked
                        ? K.installed : Colors.transparent,
                    border: Border.all(
                        color: widget.checked ? K.installed : K.fg3,
                        width: 1.5),
                  ))
            else
              Container(width: 7, height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.transparent,
                    border: Border.all(color: widget.color, width: 1.5),
                  )),
            const SizedBox(width: 12),
            Expanded(child: Text(widget.name,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: KT.ui.copyWith(
                    fontSize: 15, fontWeight: FontWeight.w500,
                    decoration: _hover && clickable && !widget.checkable
                        ? TextDecoration.underline : TextDecoration.none,
                    decorationColor: K.fg3))),
            const SizedBox(width: 10),
            SizedBox(width: 62, child: Text(
                widget.sizeLabel ?? '${widget.sizeMb} MB',
                textAlign: TextAlign.right,
                style: KT.ui.copyWith(
                    fontSize: 13, color: K.fg2))),
            SizedBox(width: 58, child: Text(
                widget.status,
                textAlign: TextAlign.right,
                style: KT.ui.copyWith(
                    fontSize: 13.5, fontWeight: FontWeight.w600,
                    color: widget.color))),
          ]),
        ),
      ),
    );
  }
}

/// 弹层右上角 × 关闭钮：hover 墨色
class AboutCloseX extends StatefulWidget {
  final VoidCallback onTap;
  const AboutCloseX({super.key, required this.onTap});
  @override
  State<AboutCloseX> createState() => _AboutCloseXState();
}

class _AboutCloseXState extends State<AboutCloseX> {
  var _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(Icons.close, size: 17,
              color: _hover ? K.ink : K.fg3),
        ),
      ),
    );
  }
}

/// 弹层链接行：标签 + URL，hover 下划，点击系统浏览器打开
class AboutLinkRow extends StatefulWidget {
  final String label, url;
  final VoidCallback onTap;
  const AboutLinkRow(this.label, this.url, {super.key,
      required this.onTap});
  @override
  State<AboutLinkRow> createState() => _AboutLinkRowState();
}

class _AboutLinkRowState extends State<AboutLinkRow> {
  var _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            SizedBox(width: 56, child: Text(widget.label,
                style: KT.ui.copyWith(fontSize: 13,
                    fontWeight: FontWeight.w600))),
            Expanded(child: Text(widget.url,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: KT.ui.copyWith(fontSize: 12.5,
                    color: _hover ? K.ink : K.fg2,
                    decoration: _hover
                        ? TextDecoration.underline : TextDecoration.none,
                    decorationColor: K.missing))),
            Icon(Icons.arrow_outward, size: 13,
                color: _hover ? K.ink : K.fg3),
          ]),
        ),
      ),
    );
  }
}

/// 无边框窗的窗口控制钮：46×32 极简细线 icon。
/// hover：min/max/restore 淡墨底加深图标；close 红底白字。
enum WinBtnKind { min, max, restore, close }

class WinCaptionButton extends StatefulWidget {
  final WinBtnKind kind;
  final VoidCallback onTap;
  const WinCaptionButton(this.kind, {super.key, required this.onTap});
  @override
  State<WinCaptionButton> createState() => _WinCaptionButtonState();
}

class _WinCaptionButtonState extends State<WinCaptionButton> {
  var _hover = false;
  @override
  Widget build(BuildContext context) {
    final isClose = widget.kind == WinBtnKind.close;
    final bg = _hover
        ? (isClose ? const Color(0xFFC42B1C)
                   : K.ink.withValues(alpha: 0.08))
        : Colors.transparent;
    final fg = isClose && _hover ? const Color(0xFFFDFBF5) : K.ink;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 46, height: 32, color: bg,
          child: CustomPaint(
              painter: _CaptionIconPainter(widget.kind, fg, bg)),
        ),
      ),
    );
  }
}

/// 发丝级细线 icon：— / ▢ / 叠方框 / ✕，1px 描边
class _CaptionIconPainter extends CustomPainter {
  final WinBtnKind kind;
  final Color fg, bg;
  const _CaptionIconPainter(this.kind, this.fg, this.bg);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = fg
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final c = size.center(Offset.zero);
    switch (kind) {
      case WinBtnKind.min:
        canvas.drawLine(Offset(c.dx - 4.5, c.dy),
            Offset(c.dx + 4.5, c.dy), p);
      case WinBtnKind.max:
        canvas.drawRect(
            Rect.fromCenter(center: c, width: 9.5, height: 9.5), p);
      case WinBtnKind.restore:
        // 后方窗框右上偏：先画完整方框，再用底色盖前方方框区域画出前景
        final rear = Rect.fromCenter(
            center: c + const Offset(1.5, -1.5), width: 8.5, height: 8.5);
        final front = Rect.fromCenter(
            center: c + const Offset(-1.5, 1.5), width: 8.5, height: 8.5);
        canvas.drawRect(rear, p);
        canvas.drawRect(front, Paint()..color = bg);
        canvas.drawRect(front, p);
      case WinBtnKind.close:
        canvas.drawLine(Offset(c.dx - 4, c.dy - 4),
            Offset(c.dx + 4, c.dy + 4), p);
        canvas.drawLine(Offset(c.dx - 4, c.dy + 4),
            Offset(c.dx + 4, c.dy - 4), p);
    }
  }

  @override
  bool shouldRepaint(_CaptionIconPainter old) =>
      old.kind != kind || old.fg != fg || old.bg != bg;
}

/// 呼吸脉动：透明度 0.55↔1.0、1.2s 周期往返——给扫描中的「当前项名」
/// 一点活感。系统「关闭动画」时静止呈现。
class Pulse extends StatefulWidget {
  final Widget child;
  const Pulse({super.key, required this.child});
  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200));
  @override
  void initState() {
    super.initState();
    _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return widget.child;
    }
    return FadeTransition(
      opacity: CurvedAnimation(parent: _c, curve: Curves.easeInOut)
          .drive(Tween(begin: 0.55, end: 1.0)),
      child: widget.child,
    );
  }
}

/// 进度条：3px，完成段深金 / 未完成段浅灰——明暗分明
class HairlineProgress extends StatelessWidget {
  final double frac;
  final Color color;
  const HairlineProgress({super.key, required this.frac,
      this.color = K.gold});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(1.5),
        child: SizedBox(height: 3, child: Stack(children: [
          Container(color: const Color(0xFFC0B9A8)),
          FractionallySizedBox(
            widthFactor: frac.clamp(0.0, 1.0),
            child: AnimatedContainer(
                duration: const Duration(milliseconds: 260), color: color),
          ),
        ])),
      );
}
