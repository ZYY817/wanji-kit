// 共用件：标题栏 / 网格底 / 按钮 / 状态点 / 计数数字
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'theme.dart';

/// 发丝网格 + 四角对位标记背景
class Backdrop extends StatelessWidget {
  const Backdrop({super.key});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _BackdropPainter());
}

class _BackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = K.line.withValues(alpha: 0.28)
      ..strokeWidth = 0.5;
    const step = 56.0;
    for (var x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    // 四角 L 形对位标记
    final mark = Paint()
      ..color = K.lineStrong
      ..strokeWidth = 1;
    const m = 14.0, l = 10.0;
    void corner(Offset o, double dx, double dy) {
      canvas.drawLine(o, o + Offset(l * dx, 0), mark);
      canvas.drawLine(o, o + Offset(0, l * dy), mark);
    }
    corner(const Offset(m, m), 1, 1);
    corner(Offset(size.width - m, m), -1, 1);
    corner(Offset(m, size.height - m), 1, -1);
    corner(Offset(size.width - m, size.height - m), -1, -1);
  }

  @override
  bool shouldRepaint(_) => false;
}

/// 无边框标题栏：左 logo + 右 min/close
class KitTitleBar extends StatelessWidget {
  const KitTitleBar({super.key});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          const SizedBox(width: 14),
          Container(width: 8, height: 8, color: K.accent),
          const SizedBox(width: 8),
          const Text('WANJI KIT', style: TextStyle(
              fontFamily: 'Consolas', fontSize: 10.5, letterSpacing: 3, color: K.fg2)),
          Expanded(child: DragToMoveArea(child: const SizedBox.expand())),
          _WinBtn(icon: Icons.remove, onTap: () => windowManager.minimize()),
          _WinBtn(icon: Icons.close, onTap: () => windowManager.close(), danger: true),
        ],
      ),
    );
  }
}

class _WinBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;
  const _WinBtn({required this.icon, required this.onTap, this.danger = false});
  @override
  State<_WinBtn> createState() => _WinBtnState();
}

class _WinBtnState extends State<_WinBtn> {
  var _hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 44, height: 40,
            color: _hover
                ? (widget.danger ? K.bad : K.surface)
                : Colors.transparent,
            child: Icon(widget.icon, size: 15, color: K.fg2),
          ),
        ),
      );
}

/// 主按钮（橙实色=唯一获取类行动）/ 描边按钮
class KitButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool outline;
  final IconData? icon;
  const KitButton(this.label, {super.key, this.onTap, this.outline = false, this.icon});
  @override
  State<KitButton> createState() => _KitButtonState();
}

class _KitButtonState extends State<KitButton> {
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          decoration: BoxDecoration(
            color: widget.outline
                ? (_hover && enabled ? K.surface : Colors.transparent)
                : enabled
                    ? (_hover ? K.accentHi : K.accent)
                    : K.surface,
            border: Border.all(
                color: widget.outline
                    ? (_hover ? K.lineStrong : K.line)
                    : Colors.transparent,
                width: 1),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.label,
                style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.5,
                  color: widget.outline
                      ? (enabled ? K.fg : K.fg3)
                      : (enabled ? K.onAccent : K.fg3),
                )),
            if (widget.icon != null) ...[
              const SizedBox(width: 8),
              Icon(widget.icon, size: 15,
                  color: widget.outline ? K.fg : K.onAccent),
            ],
          ]),
        ),
      ),
    );
  }
}

/// 状态点：✓ ok / ✗ bad / ! warn / ? unknown / · scanning
class StatusDot extends StatelessWidget {
  final Color color;
  final String symbol;
  final bool pulse;
  const StatusDot(this.color, this.symbol, {super.key, this.pulse = false});
  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 22, height: 22,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(2),
      ),
      alignment: Alignment.center,
      child: Text(symbol, style: TextStyle(
          color: color, fontSize: 12, fontWeight: FontWeight.w800, height: 1)),
    );
    if (!pulse) return dot;
    return _Pulse(child: dot);
  }
}

class _Pulse extends StatefulWidget {
  final Widget child;
  const _Pulse({required this.child});
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(_c), child: widget.child);
}

/// 计数数字（滚动动画）
class CountUp extends StatelessWidget {
  final int value;
  final TextStyle style;
  const CountUp(this.value, {super.key, required this.style});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.toDouble()),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) =>
            Text(v.round().toString().padLeft(2, '0'), style: style),
      );
}
