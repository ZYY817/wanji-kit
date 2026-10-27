// ORB 生命体模型：粒子弹簧权重系统。
// 每个粒子的位置不是关键帧，而是几组弹簧权重（spread/ring/front/dust/fly）
// 在解算后的基础坐标之间插值——状态切换 = 改目标值，天然连续、可打断。
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../engine/catalog.dart';
import 'noise.dart';

enum OrbPhase { idle, scanning, result, installing, complete }

enum PStatus { pending, checking, installed, missing, outdated, absorbed }

/// 可自动安装 = 有 winget 或官方直链或命令渠道；仅 manual 链接的组件需手动处理
extension ComponentInstallX on Component {
  bool get autoInstall =>
      install.winget != null || install.download != null ||
      install.command != null;

  /// 该单项安装是否需要管理员权限：运行库统一要（winget/msiexec 写系统区），
  /// 设置项看 command.elevated（HKLM 写入要、HKCU/powercfg 不要）
  bool get requiresAdmin =>
      isSetting ? (install.command?.elevated ?? false) : true;
}

/// 一维弹簧（欠阻尼 → 形变带回弹）
class Spr {
  double x, v = 0, target;
  final double k, d;
  Spr({this.k = 80, this.d = 8, this.x = 0}) : target = x;
  void tick(double dt) {
    v += (target - x) * k * dt;
    v *= math.exp(-d * dt);
    x += v * dt;
  }
}

class OrbParticle {
  final int index;
  final Component? component;
  final double seed;
  OrbParticle(this.index, this.component) : seed = index * 13.73;

  PStatus status = PStatus.pending;
  double flash = 0;          // 落定瞬间的点亮脉冲（衰减）
  double delay = 0;          // 形变错峰计时
  double frontDelay = 0;     // 前弹错峰（ring 先收拢，front 后弹出）
  double tw = 0;             // 星尘闪烁相位

  // 弹簧权重
  final spread = Spr(k: 72, d: 6.8);   // 0=融在球面 → 1=在轨道上
  final ring = Spr(k: 55, d: 9.5);     // 0=轨道     → 1=收拢成环
  final front = Spr(k: 40, d: 8.0);    // 0=在环上   → 1=弹到前方
  final dust = Spr(k: 24, d: 7.0);     // 0=实体     → 1=退为背景星尘
  final scale = Spr(k: 60, d: 9.0, x: 1);

  // 安装飞行（贝塞尔，非弹簧——要可控时长）
  bool flying = false;
  double flyT = 0;
  Offset flyFrom = Offset.zero, flyCtrl = Offset.zero;
  final List<Offset> trail = [];

  bool get fixable =>
      status == PStatus.missing || status == PStatus.outdated;
}

class Ripple {
  double born; final double maxR, alpha;
  Ripple(this.born, {this.maxR = 190, this.alpha = 0.55});
}

class OrbModel extends ChangeNotifier {
  OrbModel({required this.vsync}) {
    _ticker = vsync.createTicker(_tick)..start();
  }

  final TickerProvider vsync;
  late final Ticker _ticker;
  final noise = SimplexNoise(7);
  final rng = math.Random(23);

  // —— 时间 ——
  double t = 0;
  double _last = 0;
  double phaseStart = 0;

  // —— 状态 ——
  OrbPhase phase = OrbPhase.idle;
  List<OrbParticle> particles = [];
  int doneCount = 0;
  String currentLabel = '';
  int okCount = 0, failCount = 0;
  bool allInstalled = false;

  // —— 核心球体弹簧 ——
  final coreScale = Spr(k: 50, d: 8.2, x: 1);   // 球体大小
  final noiseAmp = Spr(k: 30, d: 6.0, x: 1);    // 液态扰动强度
  final bloom = Spr(k: 40, d: 7.0);             // 亮度（吸收纳秒）
  final mirror = Spr(k: 26, d: 7.0);            // 0=液态 → 1=完美镜面

  // —— 鼠标 ——
  Offset pointer = Offset.zero;  // 场景坐标（px）
  double hoverAmt = 0, hoverTarget = 0;

  // —— 系统降级 ——
  bool reduceMotion = false;   // MediaQuery.disableAnimations → 关漂浮/漂移
  void setPaused(bool p) => p ? _ticker.stop() : _ticker.start();

  // —— 低功耗：静稳相位（待机/结果/完成）落定后降拍 ~30fps ——
  // 扫描/安装相位保持满帧。ticker 仍按 vsync 走，但累积 dt 到阈值才
  // 解算+重绘——动画时长不变，只牺牲帧率，视觉几乎无损。
  static const _calmDelay = 3.5;   // 相位稳定多少秒后进入低频
  static const _lowStep = 1 / 30;  // 低频节拍（秒/帧）
  double _accum = 0;
  bool get _calm => phase == OrbPhase.idle ||
      phase == OrbPhase.result || phase == OrbPhase.complete;

  // —— 事件 ——
  final List<Ripple> ripples = [];
  double shock = -1;             // 完成冲击波 0..1，-1 休眠
  VoidCallback? onInstallVisualDone;

  static const orbitSpeed = 0.85;      // rad/s
  double get orbitAng => t * orbitSpeed;

  void _tick(Duration elapsed) {
    final now = elapsed.inMicroseconds / 1e6;
    var dt = now - _last;
    _last = now;
    if (dt <= 0 || dt > 0.05) dt = 0.016;
    // 静稳相位降拍：dt 照积，攒够一拍才解算——相位切换后的入场
    // 形变（前 _calmDelay 秒）与扫描/安装全程仍是满帧
    if (_calm && t - phaseStart > _calmDelay) {
      _accum += dt;
      if (_accum < _lowStep) return;
      dt = _accum;
      _accum = 0;
    } else {
      _accum = 0;
    }
    t += dt;
    _step(dt);
    notifyListeners();
  }

  void _step(double dt) {
    coreScale.tick(dt);
    noiseAmp.tick(dt);
    bloom.tick(dt);
    mirror.tick(dt);
    hoverAmt += (hoverTarget - hoverAmt) * math.min(1, dt * 10);
    if (shock >= 0) {
      shock += dt / 1.15;
      if (shock > 1) shock = -1;
    }
    for (final p in particles) {
      if (p.delay > 0) {
        p.delay -= dt;
      } else {
        p.spread.tick(dt);
        p.ring.tick(dt);
        p.dust.tick(dt);
        p.scale.tick(dt);
      }
      if (p.frontDelay > 0) {
        p.frontDelay -= dt;
      } else {
        p.front.tick(dt);
      }
      if (p.flash > 0) p.flash = math.max(0, p.flash - dt * 2.2);
      p.tw += dt;
      if (p.flying) {
        p.flyT += dt / 0.82;
        if (p.flyT >= 1) _absorb(p);
      }
    }
    ripples.removeWhere((r) => t - r.born > 1.4);
  }

  // ═══════════════ 相位编排 ═══════════════

  void build(int n, List<Component> comps) {
    particles = [
      for (var i = 0; i < n; i++)
        OrbParticle(i, i < comps.length ? comps[i] : null),
    ];
  }

  void _setPhase(OrbPhase p) {
    phase = p;
    phaseStart = t;
  }

  /// 待机 → 扫描：球体炸散成卫星
  void toScan() {
    _setPhase(OrbPhase.scanning);
    doneCount = 0;
    okCount = 0;
    failCount = 0;
    absorbed = 0;
    installedIds.clear();
    coreScale.target = 0.34;
    noiseAmp.target = 1.7;
    mirror.target = 0;
    bloom.target = 0;
    for (final p in particles) {
      p.status = PStatus.pending;
      p.flying = false;
      p.flyT = 0;
      p.trail.clear();
      p.delay = p.index * 0.045;
      p.spread.target = 1;
      p.ring.target = 0;
      p.front.target = 0;
      p.dust.target = 0;
      p.scale.target = 1;
    }
    ripples.add(Ripple(t, maxR: 240, alpha: 0.35));
  }

  void markChecking(int i) {
    if (i >= 0 && i < particles.length) {
      particles[i].status = PStatus.checking;
    }
  }

  void markResult(CheckResult r) {
    final p = particles.firstWhere((e) => e.component?.id == r.component.id,
        orElse: () => particles.first);
    p.status = switch (r.status) {
      CheckStatus.installed => PStatus.installed,
      CheckStatus.missing => PStatus.missing,
      CheckStatus.outdated => PStatus.outdated,
      CheckStatus.unknown => PStatus.pending,
    };
    p.flash = 1;
    doneCount++;
  }

  /// 扫描 → 结果：收拢成环，缺失弹出，已装退为星尘
  void toResult() {
    _setPhase(OrbPhase.result);
    coreScale.target = 0.42;
    noiseAmp.target = 1.1;
    final fix = particles.where((p) => p.fixable).toList();
    allInstalled = fix.isEmpty;
    var j = 0;
    for (final p in particles) {
      p.delay = 0.12 + p.index * 0.03;
      p.spread.target = 1;   // demo/直入路径没有扫描，先保证粒子显形
      p.ring.target = 1;
      if (p.fixable) {
        p.front.target = 1;      // 弹到前方
        p.scale.target = 1.75;
        p.frontDelay = 0.35 + j++ * 0.09;
      } else {
        p.dust.target = 1;       // 退为背景星尘
        p.scale.target = 0.32;
      }
    }
    ripples.add(Ripple(t, maxR: 200, alpha: 0.3));
  }

  /// 结果 → 安装：修复项逐一飞回核心
  void toInstalling(List<String> queue) {
    _setPhase(OrbPhase.installing);
    installQueue = List.of(queue);
    installedIds.clear();
    coreScale.target = 0.5;
    noiseAmp.target = 1.4;
  }

  List<String> installQueue = [];
  final Set<String> installedIds = {};

  /// 某项开始安装 → 粒子点火飞回
  void launch(String id) {
    final p = particles.firstWhere((e) => e.component?.id == id,
        orElse: () => particles.first);
    if (p.flying) return;
    p.flying = true;
    p.flyT = 0;
    p.flyFrom = lastPos[p.index] ?? Offset.zero;
    final mid = (p.flyFrom) / 2;
    final dir = (Offset.zero - p.flyFrom);
    final perp = Offset(-dir.dy, dir.dx) / (dir.distance + 0.001);
    p.flyCtrl = mid + perp * (dir.distance * 0.35) * (p.index.isEven ? 1 : -1);
    p.flash = 1;
  }

  int absorbed = 0;

  void markInstalled(String id, bool ok) {
    if (ok) {
      installedIds.add(id);
      okCount++;
    } else {
      failCount++;
      eject(id);
    }
    bloom.target = (0.25 + installedIds.length * 0.12).clamp(0.0, 1.0);
  }

  /// 安装失败：粒子被吐回前方队列位
  void eject(String id) {
    final p = particles.firstWhere((e) => e.component?.id == id,
        orElse: () => particles.first);
    if (p.status == PStatus.absorbed) {
      p.status = PStatus.missing;
      p.flying = false;
      p.flyT = 0;
      absorbed--;
      p.flash = 1;
      ripples.add(Ripple(t, maxR: 90, alpha: 0.4));
    }
  }

  /// 安装/结果 → 完成：全部归位，凝为镜面，冲击波
  void toComplete() {
    _setPhase(OrbPhase.complete);
    coreScale.target = 1.04;
    noiseAmp.target = 1;
    mirror.target = 1;
    shock = 0;
    ripples.add(Ripple(t, maxR: 300, alpha: 0.5));
    for (final p in particles) {
      if (p.flying) continue;
      p.delay = p.index * 0.02;
      p.front.target = 0;
      p.dust.target = 0;
      p.ring.target = 0;
      p.spread.target = 0;   // 全部融回球体
      p.scale.target = 1;
    }
    // 4s 后恢复呼吸
    Future.delayed(const Duration(seconds: 4), () {
      if (phase == OrbPhase.complete) {
        mirror.target = 0;
        bloom.target = 0;
        coreScale.target = 1;
      }
    });
  }

  /// 回到待机（重新检测前的收缩由 toScan 负责）
  void reset() {
    _setPhase(OrbPhase.idle);
    coreScale.target = 1;
    noiseAmp.target = 1;
    mirror.target = 0;
    bloom.target = 0;
    doneCount = 0;
    for (final p in particles) {
      p.status = PStatus.pending;
      p.flying = false;
      p.spread.target = 0;
      p.ring.target = 0;
      p.front.target = 0;
      p.dust.target = 0;
      p.scale.target = 1;
      p.delay = 0;
      p.trail.clear();
    }
  }

  void _absorb(OrbParticle p) {
    p.flying = false;
    p.status = PStatus.absorbed;
    p.trail.clear();
    absorbed++;
    ripples.add(Ripple(t, maxR: 130 + absorbed * 14, alpha: 0.65));
    bloom.target = (0.3 + absorbed * 0.14).clamp(0.0, 1.0);
    // 吞食冲击：球体果冻式晃动
    noiseAmp.v += 2.6;
    coreScale.v += 0.55;
  }

  // 粒子最新解算位置（ painter 每帧回填，launch() 用作 flyFrom ）
  final Map<int, Offset> lastPos = {};

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}


