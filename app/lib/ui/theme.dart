// 视觉体系：「精密仪器控制台」——石墨底 + 信号橙主行动 + 宋体展示 + mono 数据
// 与网站同品牌家族（同一信号橙/宋体），但界面语言独立：刻度、仪表、扫描线。

import 'package:flutter/material.dart';

class K {
  // 底色（暖石墨，不泛蓝）
  static const bg = Color(0xFF0C0C0B);
  static const panel = Color(0xFF141412);
  static const surface = Color(0xFF1B1B18);
  static const line = Color(0xFF272724);
  static const lineStrong = Color(0xFF3A3933);

  // 文字
  static const fg = Color(0xFFEDEBE3);
  static const fg2 = Color(0xFFABA89E);
  static const fg3 = Color(0xFF8B887D);

  // 信号橙：只给主 CTA / 当前态 / 焦点
  static const accent = Color(0xFFFF6B2C);
  static const accentHi = Color(0xFFFF8448);
  static const onAccent = Color(0xFF140A04);

  // 语义色
  static const ok = Color(0xFF4CC38A);
  static const warn = Color(0xFFE9B44C);
  static const bad = Color(0xFFF2555A);
  static const unknown = Color(0xFF8A8880);
}

class KT {
  // 宋体展示（字体文件后续打到 assets；先用系统宋体栈兜底）
  static const serif = TextStyle(
    fontFamily: 'NotoSerifSC', fontFamilyFallback: ['SimSun', 'NSimSun', 'STSong'],
    color: K.fg, fontWeight: FontWeight.w900, height: 1.05, letterSpacing: -1.5,
  );
  static const body = TextStyle(
    fontFamilyFallback: ['Microsoft YaHei UI', 'PingFang SC', 'Noto Sans SC'],
    color: K.fg, fontSize: 13.5, height: 1.7,
  );
  static const mono = TextStyle(
    fontFamily: 'Consolas', fontFamilyFallback: ['JetBrains Mono', 'Courier New'],
    color: K.fg3, fontSize: 11, letterSpacing: 0.8, height: 1.5,
  );
}

ThemeData kitTheme() => ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: K.bg,
      fontFamily: 'Microsoft YaHei UI',
      colorScheme: const ColorScheme.dark(
        primary: K.accent, surface: K.panel, error: K.bad,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );
