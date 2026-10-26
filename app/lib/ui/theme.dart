// 主题：奶油暖灰空间 × 墨色文字 × 赤陶/琥珀/墨绿状态点 × 金轨道
import 'package:flutter/material.dart';

class K {
  // —— 空间底 ——
  static const bgTop = Color(0xFFEDE9E2);     // 米白（受光）
  static const bgBottom = Color(0xFFD9D5CD);  // 浅暖灰
  static const cream = Color(0xFFF5F1E8);     // 胶囊奶油
  static const warmGlow = Color(0xFFFFF6E4);  // 左上暖光

  // —— 文字 ——
  static const ink = Color(0xFF1A1815);       // 墨色主文字
  static const fg2 = Color(0xFF6B675C);       // 次要
  static const fg3 = Color(0xFF8A8578);       // 元数据 mono

  // —— 线与面 ——
  static const line = Color(0xFFC9C2B3);      // 发丝线
  static const shadow = Color(0xFF8A8272);    // 投影色

  // —— 状态 ——
  static const missing = Color(0xFFC4552B);   // 赤陶橙：缺失（镂空环）
  static const amber = Color(0xFFB98A2E);     // 琥珀：过旧
  static const installed = Color(0xFF2E5B4C); // 墨绿：已装深点
  static const gold = Color(0xFFA8874E);      // 金属轨道 / 珠
  static const pearl = Color(0xFFFDFBF5);     // 珠体高光

  // —— 状态·文字加深版（奶油底上保证 ≥4:1 可读对比，节点仍用上面的亮色）——
  static const missingTx = Color(0xFFA8431F); // 「缺失」文字
  static const amberTx = Color(0xFF8F6A1E);   // 「过旧」文字
  static const manualTx = Color(0xFF57524A);  // 「需手动」文字：独立中性深灰
}

class KT {
  // 展示标题专用：宋体子集（只含 ~340 字，禁止用于组件名/状态等动态文字）
  static const serif = TextStyle(
    fontFamily: 'NotoSerifCJK',
    color: K.ink, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: 1,
  );
  // 功能文字统一走系统 UI 字体（微软雅黑 UI）：清晰、字形一致、无缺字回退
  static const _ui = 'Microsoft YaHei UI';
  static const ui = TextStyle(
    fontFamily: _ui, color: K.ink, fontSize: 13,
    height: 1.45, fontWeight: FontWeight.w400,
  );
  static const uiMeta = TextStyle(
    fontFamily: _ui, color: K.fg3, fontSize: 12,
    height: 1.4, fontWeight: FontWeight.w400,
  );
  static const body = TextStyle(
    fontFamily: _ui,
    color: K.fg2, fontSize: 13, height: 1.6, fontWeight: FontWeight.w400,
  );
  // 仅拉丁/数字的装饰等宽字（顶部 chrome 用）；中文禁用——会逐字回退
  static const mono = TextStyle(
    fontFamily: 'Consolas', color: K.fg3, fontSize: 11,
    letterSpacing: 1.8, height: 1.4,
  );
}

ThemeData kitTheme() => ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: K.bgTop,
      fontFamily: 'Microsoft YaHei UI',
      colorScheme: const ColorScheme.light(primary: K.missing),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );
