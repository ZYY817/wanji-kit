// 状态机：奶油空间 + 悬浮雕塑。相位切换不切页——
// 待机(珠子静卧轨道) → 扫描(光沿轨道流过逐节点落定) → 结果(缺失珠前移+清单)
// → 安装(缺失珠飞回雕塑) → 完成(雕塑归稳+一圈柔光)。
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show LogicalKeyboardKey, KeyDownEvent, MethodChannel;
import 'package:path/path.dart' as p;
import '../engine/catalog.dart';
import '../engine/detect.dart';
import '../engine/elevate.dart';
import '../engine/install.dart';
import '../engine/log.dart';
import 'theme.dart';
import 'hud.dart';
import 'strings.dart';
import 'orb/orb_model.dart';
import 'sculpt/sculpt_stage.dart';

/// 无边框窗控制通道「wanji/window」→ 原生层 ShowWindow / WM_CLOSE。
/// 调用失败静默忽略（调试期原生侧未编译新通道时界面照常可用）。
class Win {
  static const _ch = MethodChannel('wanji/window');
  static Future<void> _call(String m, [Object? args]) async {
    try {
      await _ch.invokeMethod(m, args);
    } catch (_) {/* 原生侧缺失时按无操作处理 */}
  }

  static Future<void> minimize() => _call('minimize');
  static Future<void> toggleMaximize() => _call('toggleMaximize');
  static Future<void> close() => _call('close');
  static Future<void> setCaptionExclusion(double leftDip) =>
      _call('setCaptionExclusion', leftDip);

  static Future<bool> isMaximized() async {
    try {
      return await _ch.invokeMethod<bool>('isMaximized') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 原生→Dart 反向回调：窗口最小化/还原。Windows 引擎在最小化时
  /// 只发 inactive（不发 hidden），动画停表必须靠这条原生通道。
  static void initWindowState(void Function(bool minimized) onMin) {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'windowState') {
        onMin(call.arguments == 'minimized');
      }
    });
  }
}

class KitApp extends StatefulWidget {
  final List<String> presetInstall;
  final bool autoScan, demoReport, demoInstall, about;
  final bool repair, exclSettings; // 截图调试态：直入修复模式 / 优化组取消勾选
  const KitApp({super.key, this.presetInstall = const [],
      this.autoScan = false, this.demoReport = false,
      this.demoInstall = false, this.about = false,
      this.repair = false, this.exclSettings = false});

  @override
  State<KitApp> createState() => _KitAppState();
}

class _KitAppState extends State<KitApp> with TickerProviderStateMixin {
  late final OrbModel orb = OrbModel(vsync: this);
  late final AppLifecycleListener _lifecycle;
  Catalog? _catalog;
  final List<CheckResult> _results = [];
  List<Component> _queue = [];
  String _current = '';
  String _detail = '';
  String? _loadError;
  bool _installing = false;
  bool? _admin;
  bool _aboutOpen = false;
  bool _compsOpen = false;   // 组件清单弹层（与 about 同体系遮罩，互斥）
  // 修复模式：结果相位内的轻量子态（不新增页面/相位）
  bool _repairMode = false;
  final Set<String> _repairSel = {};
  // 组级勾选：整组取消参与「一键」（清单仍列出状态）
  bool _incRt = true, _incSt = true;
  // 安装失败项：完成屏展示官方下载兜底链接
  final Set<String> _failIds = {};
  // 无边框窗：顶条控件群 key（上报排除区左缘）+ 最大化图标态
  final GlobalKey _controlsKey = GlobalKey();
  bool _maximized = false;
  double _lastExcl = -1;
  // 停表判定：原生最小化信号 | 生命周期进入 hidden/paused/detached
  bool _minimized = false;
  AppLifecycleState? _lcState;

  void _updatePause() {
    final lcHidden = _lcState != null &&
        _lcState != AppLifecycleState.resumed &&
        _lcState != AppLifecycleState.inactive;
    orb.setPaused(_minimized || lcHidden);
  }

  @override
  void initState() {
    super.initState();
    // 失焦/最小化 → 停表；回来继续。
    // Windows 最小化只发 inactive——真正的「最小化即停」靠原生
    // WM_SIZE 经 wanji/window 通道上报的 windowState 驱动。
    _lifecycle = AppLifecycleListener(onStateChange: (s) {
      _lcState = s;
      _updatePause();
    });
    Win.initWindowState((min) {
      _minimized = min;
      _updatePause();
    });
    _load();
    // 首帧后上报顶条排除区 + 最大化态（之后由尺寸变化通知触发）
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _syncWindowChrome());
  }

  /// 同步无边框窗状态：顶条控件群左缘（拖拽排除线）+ 最大化图标态。
  /// 窗口尺寸变化（最大化/还原/分屏）后经 SizeChangedLayoutNotification 调用。
  void _syncWindowChrome() {
    final ro = _controlsKey.currentContext?.findRenderObject();
    if (ro is RenderBox && ro.hasSize) {
      final left = ro.localToGlobal(Offset.zero).dx;
      if (left != _lastExcl) {
        _lastExcl = left;
        Win.setCaptionExclusion(left);
      }
    }
    Win.isMaximized().then((m) {
      if (mounted && m != _maximized) setState(() => _maximized = m);
    });
  }

  Future<void> _winToggleMax() async {
    await Win.toggleMaximize();
    final m = await Win.isMaximized();
    if (mounted && m != _maximized) setState(() => _maximized = m);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    orb.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _loadSettings();
    try {
      _catalog = await loadCatalog();
    } catch (e) {
      // catalog 损坏/缺失：停在可读的错误屏，不假装在加载
      if (mounted) setState(() => _loadError = '$e');
      return;
    }
    orb.build(_catalog!.components.length, _catalog!.components);
    _aboutOpen = widget.about; // --about 调试：直接弹出「关于作者」
    if (widget.presetInstall.isNotEmpty) {
      _seedStatuses(widget.presetInstall);
      orb.toResult();
      setState(() {}); // 相位切换后重建面板（无整树帧重建，语义点手动刷新）
      _queue = _catalog!.components
          .where((c) => widget.presetInstall.contains(c.id)).toList();
      Future.delayed(const Duration(milliseconds: 1400),
          () => _startInstall(_queue));
    } else if (widget.demoInstall || widget.demoReport) {
      _results.addAll(_demoResults());
      _applyResults();
      _incSt = !widget.exclSettings;
      orb.toResult();
      if (widget.repair) _enterRepair();
      setState(() {});
      if (widget.demoInstall) {
        Future.delayed(const Duration(milliseconds: 2200), () {
          _queue = _fixable.map((r) => r.component).toList();
          _startInstall(_queue);
        });
      }
    } else {
      setState(() {});
      Elevation.isAdmin.then((a) => mounted ? setState(() => _admin = a) : null);
      if (widget.autoScan) {
        Future.delayed(const Duration(milliseconds: 800), _scan);
      }
    }
  }

  /// 视觉自查假数据：4 可装缺失 + 2 手动缺失(netfx35/OpenAL) + 2 设置项未开 + 1 过旧
  List<CheckResult> _demoResults() {
    const fake = {2: CheckStatus.missing, 5: CheckStatus.missing,
        13: CheckStatus.missing, 23: CheckStatus.missing,
        27: CheckStatus.missing, 29: CheckStatus.missing,
        9: CheckStatus.outdated};
    return [
      for (var i = 0; i < _catalog!.components.length; i++)
        CheckResult(
          component: _catalog!.components[i],
          status: fake[i] ?? CheckStatus.installed,
          installedVersion: fake[i] == null ? '14.44.35211.0' : null,
          evidence: 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes'),
    ];
  }

  void _seedStatuses(List<String> missingIds) {
    for (final p in orb.particles) {
      p.status = missingIds.contains(p.component?.id)
          ? PStatus.missing
          : PStatus.installed;
    }
    orb.doneCount = orb.particles.length;
  }

  void _applyResults() {
    for (final r in _results) {
      final p = orb.particles.firstWhere(
          (e) => e.component?.id == r.component.id,
          orElse: () => orb.particles.first);
      p.status = switch (r.status) {
        CheckStatus.installed => PStatus.installed,
        CheckStatus.missing => PStatus.missing,
        CheckStatus.outdated => PStatus.outdated,
        CheckStatus.unknown => PStatus.pending,
      };
    }
    orb.doneCount = _results.length;
  }

  /// 全部异常项（缺失/过旧），含手动项
  List<CheckResult> get _flagged => _results
      .where((r) => r.status == CheckStatus.missing ||
          r.status == CheckStatus.outdated)
      .toList();

  /// 已装项（修复模式清单来源）
  List<CheckResult> get _installed => _results
      .where((r) => r.status == CheckStatus.installed)
      .toList();

  /// 其中可自动安装的（有 winget / 官方直链 / command 渠道）
  List<CheckResult> get _fixable =>
      _flagged.where((r) => r.component.autoInstall).toList();

  /// 按组勾选过滤后的一键队列
  List<Component> get _queueItems => _fixable
      .where((r) => r.component.isSetting ? _incSt : _incRt)
      .map((r) => r.component).toList();

  /// 仅剩手动指引的（OpenAL/PhysX/DirectPlay 等）
  List<CheckResult> get _manual =>
      _flagged.where((r) => !r.component.autoInstall).toList();

  Future<void> _scan() async {
    if (orb.phase == OrbPhase.scanning) return;
    _results.clear();
    orb.toScan();
    setState(() { _current = ''; _detail = ''; _queue = [];
        _repairMode = false; _repairSel.clear(); _failIds.clear();
        _incRt = true; _incSt = true; });
    await Detector.scan(_catalog!,
        onProgress: (i, _, c) {
          orb.markChecking(i);
          setState(() => _current = c.short);
        },
        onResult: (r) {
          // doneCount 驱动扫描面板大数字——逐项语义刷新
          setState(() {
            _results.add(r);
            orb.markResult(r);
          });
        });
    setState(() => _current = '');
    await Future.delayed(const Duration(milliseconds: 850));
    if (!mounted) return;
    orb.toResult();
    setState(() {});
    Elevation.isAdmin.then((a) => mounted ? setState(() => _admin = a) : null);
  }

  Future<void> _cta() => _runQueue(_queueItems);

  /// 装齐/修复共用入口：按需提权（HKCU 设置项队列可免 UAC），然后走同一安装流
  Future<void> _runQueue(List<Component> items) async {
    if (items.isEmpty || _installing) return;
    if (widget.demoReport || widget.demoInstall) {
      await _startInstall(items); // 视觉自查：假流程，不碰系统
      return;
    }
    if (items.any((c) => c.requiresAdmin)) {
      // _admin 可能还没查完（null）：当场再查一次，别拿 null 当「已提权」
      final admin = _admin ?? await Elevation.isAdmin;
      if (!mounted) return;
      setState(() => _admin = admin);
      if (!admin) {
        final ok = await Elevation.relaunchElevated(
            items.map((c) => c.id).toList());
        // 用户取消 UAC / 拉起失败 → 给出提示留在原位（此前静默无反馈）
        if (!ok && mounted) setState(() => _detail = S.of('uacCancel'));
        return;
      }
    }
    await _startInstall(items);
  }

  Future<void> _startInstall(List<Component> items) async {
    if (_installing) return;
    orb.toInstalling(items.map((c) => c.id).toList());
    setState(() { _installing = true; _queue = items; _detail = '';
        _repairMode = false; _repairSel.clear(); _failIds.clear(); });
    if (widget.demoInstall || widget.demoReport) {
      await _fakeInstall(items);
    } else {
      try {
        final log = await KitLog.open();
        await for (final e in Installer.installAll(items,
            verify: (c) async =>
                (await Detector.check(c)).status == CheckStatus.installed,
            log: log)) {
          if (!mounted) return;
          // okCount/failCount 驱动安装面板计数——与同帧 _detail 一起刷
          setState(() {
            if (e.phase == 'start') orb.launch(e.componentId);
            if (e.phase == 'done') orb.markInstalled(e.componentId, true);
            if (e.phase == 'failed') {
              orb.markInstalled(e.componentId, false);
              _failIds.add(e.componentId);
            }
            if (e.detail.isNotEmpty) _detail = e.detail;
          });
        }
      } catch (e) {
        // 安装流中断（进程/日志/权限异常）：仍落到完成屏，failCount 记未完成的
        if (!mounted) return;
        setState(() => _detail = S.fmt('evInterrupted', {'err': e}));
      }
    }
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    orb.toComplete();
    setState(() => _installing = false);
  }

  Future<void> _fakeInstall(List<Component> items) async {
    for (final c in items) {
      orb.launch(c.id);
      for (final ph in [S.of('evDownloading'),
          'winget ${c.install.winget ?? c.id}', S.of('evVerifying')]) {
        if (!mounted) return;
        setState(() => _detail = ph);
        await Future.delayed(const Duration(milliseconds: 620));
      }
      if (!mounted) return;
      setState(() => orb.markInstalled(c.id, true));
      await Future.delayed(const Duration(milliseconds: 350));
    }
  }

  // ═══════════════ 语言设置（%APPDATA%\WanjiKit\settings.json）═══════════════

  Future<void> _loadSettings() async {
    try {
      final f = File(p.join(Platform.environment['APPDATA'] ?? '.',
          'WanjiKit', 'settings.json'));
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString());
        if (j is Map && (j['lang'] == 'zh' || j['lang'] == 'en')) {
          S.applyLoaded(j['lang'] as String);
        }
      }
    } catch (_) {/* 设置损坏时用默认中文 */}
  }

  Future<void> _saveLang() async {
    try {
      final f = File(p.join(Platform.environment['APPDATA'] ?? '.',
          'WanjiKit', 'settings.json'));
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode({'lang': S.lang}));
    } catch (_) {/* 写不进也只是丢持久化 */}
  }

  void _toggleLang() {
    S.toggle();
    _saveLang();
    setState(() {});
  }

  // ═══════════════ 修复模式 ═══════════════

  void _enterRepair() => setState(() {
        _repairMode = true;
        _repairSel.clear();
      });

  void _exitRepair() => setState(() {
        _repairMode = false;
        _repairSel.clear();
      });

  void _toggleRepairItem(Component c) => setState(() {
        _repairSel.contains(c.id)
            ? _repairSel.remove(c.id)
            : _repairSel.add(c.id);
      });

  void _startRepair() {
    final items = [
      for (final c in _catalog!.components)
        if (_repairSel.contains(c.id)) c,
    ];
    _runQueue(items);
  }

  // ═══════════════ UI ═══════════════

  @override
  Widget build(BuildContext context) {
    orb.reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: K.bgTop,
      body: _catalog == null
          ? Center(child: _loadError != null
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(S.of('loadFail'), style: KT.serif.copyWith(
                      fontSize: 18, letterSpacing: 2)),
                  const SizedBox(height: 10),
                  Text(_loadError!, style: KT.uiMeta.copyWith(
                      fontSize: 12, color: K.fg3)),
                ])
              : const SizedBox(width: 120, height: 1,
                  child: LinearProgressIndicator(
                      color: K.gold, backgroundColor: K.line, minHeight: 1)))
          // 不再用 AnimatedBuilder 整树随帧重建：雕塑画层靠 CustomPaint
          // (repaint: orb) 自己重绘，面板只在语义事件点 setState——
          // 静稳相位满树 60fps rebuild 是弱机 CPU 的主要浪费。
          : LayoutBuilder(
              builder: (_, cst) => NotificationListener<
                  SizeChangedLayoutNotification>(
                // 窗口尺寸变化（含系统最大化/还原/分屏）→ 重算顶条排除+图标
                onNotification: (_) {
                  WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _syncWindowChrome());
                  return false;
                },
                child: SizeChangedLayoutNotifier(
                  child: Stack(children: [
                    Positioned.fill(child: SculptStage(model: orb)),
                    _chromeRow(),
                    _panel(cst.maxWidth, cst.maxHeight),
                    _bottomMeta(),
                    if (_aboutOpen) _aboutLayer(),
                    if (_compsOpen) _compsLayer(),
                  ]),
                ),
              ),
            ),
    );
  }

  /// 顶部 in-app chrome —— 无边框窗下整行就是「标题栏」：
  /// 左 品牌字 · 右 系统信息 + 语言胶囊 + 窗口控制钮。
  /// 行区（除控件群）由原生层 WM_NCHITTEST 回 HTCAPTION → 可拖拽/双击最大化。
  Widget _chromeRow() {
    final style = KT.mono.copyWith(
        fontSize: 9.5, letterSpacing: 3.0, color: K.fg3, height: 1);
    return Positioned(top: 0, left: 0, right: 0,
        child: SizedBox(height: 40,   // 与原生 kCaptionHeightDip 对齐
          child: Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Row(children: [
              IgnorePointer(child: Text('RUNTIME CHECK',
                  style: style.copyWith(color: K.fg2))),
              IgnorePointer(child: Text(' · BY ZYY817', style: style)),
              const Spacer(),
              IgnorePointer(child: Text('WINDOWS 10 / 11 · X64',
                  style: style)),
              const SizedBox(width: 14),
              // 控件群：胶囊左缘即原生拖拽排除线（_controlsKey 上报）；
              // 自身尺寸变化（含首次出现）→ 立即上报排除线
              NotificationListener<SizeChangedLayoutNotification>(
                onNotification: (_) {
                  WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _syncWindowChrome());
                  return false;
                },
                child: SizeChangedLayoutNotifier(
                  child: Row(key: _controlsKey,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    _langPill(),
                    const SizedBox(width: 4),
                    WinCaptionButton(WinBtnKind.min,
                        onTap: Win.minimize),
                    WinCaptionButton(
                        _maximized ? WinBtnKind.restore : WinBtnKind.max,
                        onTap: _winToggleMax),
                    WinCaptionButton(WinBtnKind.close, onTap: Win.close),
                  ]),
                ),
              ),
            ]),
          )));
  }

  /// 中 | EN 胶囊：描边圆角 pill，当前语言实心墨底白字，另一浅灰；点击切换
  Widget _langPill() {
    Widget seg(String t, bool on) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 18,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? K.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(t, style: KT.uiMeta.copyWith(
            fontSize: 9.5, height: 1, letterSpacing: 0.6,
            color: on ? K.pearl : K.fg3,
            fontWeight: on ? FontWeight.w700 : FontWeight.w400)));
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _toggleLang,
        child: Container(
          height: 22,
          padding: const EdgeInsets.all(1.6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: K.line, width: 0.9),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            seg('中', !S.isEn),
            Container(width: 0.7, height: 10, color: K.line),
            seg('EN', S.isEn),
          ]),
        ),
      ),
    );
  }

  /// 右下侧操作区：非对称排版的主文字区
  Widget _panel(double w, double h) {
    final panelW = (w * 0.30).clamp(272.0, 372.0);
    final right = w * 0.055;
    // 结果清单最高 → 上移；其余相位中轴对齐
    final top = orb.phase == OrbPhase.result
        ? (h * 0.22).clamp(86.0, 220.0)
        : h * 0.30;
    return Positioned(
      right: right, top: top, width: panelW,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 480),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
                position: Tween(begin: const Offset(0.04, 0), end: Offset.zero)
                    .animate(anim),
                child: child)),
        child: switch (orb.phase) {
          OrbPhase.idle => _idlePanel(key: const ValueKey('idle')),
          OrbPhase.scanning => _scanPanel(key: const ValueKey('scan')),
          OrbPhase.result => _resultPanel(key: const ValueKey('result'), h: h),
          OrbPhase.installing => _installPanel(key: const ValueKey('install')),
          OrbPhase.complete => _completePanel(key: const ValueKey('done')),
        },
      ),
    );
  }

  Widget _bottomMeta() {
    final phaseTag = switch (orb.phase) {
      OrbPhase.idle => S.of('phaseIdle'),
      OrbPhase.scanning => S.of('phaseScan'),
      OrbPhase.result => S.of('phaseResult'),
      OrbPhase.installing => S.of('phaseInstall'),
      OrbPhase.complete => S.of('phaseDone'),
    };
    return Positioned(left: 18, bottom: 4,
        // 同一行同一基线：meta 小字与「组件清单」链接按 alphabetic 基线对齐
        child: Row(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic, children: [
          IgnorePointer(child: Text(
              S.fmt('metaItems', {'n': orb.particles.length, 'phase': phaseTag}),
              style: KT.uiMeta.copyWith(fontSize: 11, letterSpacing: 1,
                  color: K.fg2))),
          // 组件清单入口：与右侧面板链接同一视觉（细字 hover 下划）
          HaloLink(S.of('compList'), onTap: _openComps),
        ]));
  }

  // —— 待机 ——
  Widget _idlePanel({required Key key}) => Column(key: key,
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        EnterAnim(index: 0, child: Text(S.of('idleTitle'),
            style: KT.serif.copyWith(fontSize: 32, letterSpacing: 2))),
        const SizedBox(height: 14),
        EnterAnim(index: 1, child: Text(S.of('idleSub'),
            style: KT.ui.copyWith(fontSize: 14, color: K.fg2,
                letterSpacing: 1))),
        const SizedBox(height: 8),
        // 痛点钩子：一行小字，点题「游戏运行库」定位
        EnterAnim(index: 2, child: Text(S.of('idleHook'),
            style: KT.uiMeta.copyWith(fontSize: 12, color: K.fg3,
                letterSpacing: 0.8))),
        const SizedBox(height: 26),
        EnterAnim(index: 3, child: ArrowCta(S.of('idleCta'), onTap: _scan)),
        const SizedBox(height: 18),
        EnterAnim(index: 4, child: Text(S.of('idleHint'),
            style: KT.uiMeta.copyWith(fontSize: 12, color: K.fg2))),
        const SizedBox(height: 6),
        EnterAnim(index: 5, child: Row(children: [
          HaloLink(S.of('about'), onTap: _openAbout),
        ])),
      ]);

  // —— 扫描中 ——
  Widget _scanPanel({required Key key}) => Column(key: key,
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(S.of('scanning'), style: KT.serif.copyWith(
            fontSize: 30, letterSpacing: 2)),
        const SizedBox(height: 16),
        // 大数字进度：done / total
        Row(crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic, children: [
          Text('${orb.doneCount}', style: KT.serif.copyWith(fontSize: 34)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('/', style: KT.serif.copyWith(
                  fontSize: 20, color: K.fg3))),
          Text('${orb.particles.length}', style: KT.serif.copyWith(
              fontSize: 20, color: K.fg2)),
        ]),
        const SizedBox(height: 10),
        // 当前项名：▸ 点前缀 + 呼吸脉动——扫描中一眼可感「在动」
        SizedBox(height: 22, child: Pulse(child: Text(
            _current.isEmpty ? '' : '▸ $_current',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: KT.ui.copyWith(fontSize: 15, color: K.ink,
                fontWeight: FontWeight.w500)))),
        const SizedBox(height: 10),
        HairlineProgress(frac: orb.particles.isEmpty
            ? 0 : orb.doneCount / orb.particles.length),
      ]);

  /// 清单行状态文案/颜色：手动项中性灰，设置项缺失叫「未开启」
  String _rowStatus(CheckResult r) {
    if (!r.component.autoInstall) return S.of('rowManual');
    if (r.status == CheckStatus.outdated) return S.of('rowOutdated');
    return r.component.isSetting ? S.of('rowOff') : S.of('rowMissing');
  }

  Color _rowColor(CheckResult r) {
    if (!r.component.autoInstall) return K.manualTx;
    return r.status == CheckStatus.missing ? K.missingTx : K.amberTx;
  }

  /// 设置项建议动作标签（catalog rec 字段 → 字典）；无 rec 回落「开关」
  String _recLabel(Component c) => switch (c.rec) {
        'on' => S.of('recOn'),
        'off' => S.of('recOff'),
        'switch' => S.of('recSwitch'),
        _ => S.of('colToggle'),
      };

  /// 「运行库 / 系统优化」段标题：12px fg2；checked!=null 时带组级勾环（整组参与一键）
  Widget _sectionHead(String label,
      {bool first = false, bool? checked, VoidCallback? onToggle}) {
    final head = Row(mainAxisSize: MainAxisSize.min, children: [
      if (checked != null) ...[
        Container(width: 9, height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: checked ? K.installed : Colors.transparent,
              border: Border.all(
                  color: checked ? K.installed : K.fg3, width: 1.5))),
        const SizedBox(width: 8),
      ],
      Text(label, style: KT.uiMeta.copyWith(
          fontSize: 12, letterSpacing: 1.5,
          color: checked == false ? K.fg3 : K.fg2)),
    ]);
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 10, bottom: 2),
      child: onToggle == null
          ? head
          : MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                  onTap: onToggle,
                  child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: head))),
    );
  }

  // —— 结果 ——
  Widget _resultPanel({required Key key, required double h}) {
    final flagged = _flagged;   // 全部异常（含手动项），与节点/清单同源
    final fx = _fixable;        // 可自动安装（含 command 设置项）
    final man = _manual;        // 仅手动指引
    if (_results.isEmpty && _queue.isNotEmpty) {
      return Column(key: key, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Text(S.fmt('queueSeed', {'n': _queue.length}),
            style: KT.ui.copyWith(fontSize: 14, color: K.fg2)),
      ]);
    }
    // 修复模式子态：同一面板换内容，不是新页面（要在 all-clear 分支之前判定）
    if (_repairMode) {
      return KeyedSubtree(key: const ValueKey('repair'),
          child: _repairBody(h: h));
    }
    if (flagged.isEmpty) {
      return Column(key: key, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        EnterAnim(index: 0, child: Text(S.of('resultAllPass'),
            style: KT.serif.copyWith(fontSize: 32, letterSpacing: 2))),
        const SizedBox(height: 12),
        EnterAnim(index: 1, child: Text(S.of('resultAllPassSub'),
            style: KT.ui.copyWith(fontSize: 13.5, color: K.fg2))),
        const SizedBox(height: 24),
        EnterAnim(index: 2, child: Row(children: [
          HaloLink(S.of('rescan'), onTap: _scan),
          if (_installed.isNotEmpty)
            HaloLink(S.of('repair'), onTap: _enterRepair),
          HaloLink(S.of('about'), onTap: _openAbout),
          HaloLink(S.of('exit'), onTap: () => exit(0)),
        ])),
      ]);
    }
    final rt = flagged.where((r) => !r.component.isSetting).toList();
    final st = flagged.where((r) => r.component.isSetting).toList();
    // 组勾选后的一键队列：n=运行库件数 m=优化件数
    final qRt = _incRt ? rt.where((r) => r.component.autoInstall).length : 0;
    final qSt = _incSt ? st.where((r) => r.component.autoInstall).length : 0;
    final totalMb = fx
        .where((r) => r.component.isSetting ? _incSt : _incRt)
        .fold(0, (s, r) => s + r.component.sizeMb);
    final qCount = qRt + qSt;
    final compact = h < 640;
    // 清单高度自适应：行高 44 × 行数 + 段标题，且不溢出面板可用高度
    final panelTop = (h * 0.22).clamp(86.0, 220.0);
    final fixed = (compact ? 196.0 : 218.0) +
        (man.isNotEmpty ? 32.0 : 0.0); // 标题/元信息/CTA/附注/链接
    final avail = h - panelTop - fixed;
    final need = flagged.length * 44.0 +
        (rt.isNotEmpty ? 22.0 : 0) + (st.isNotEmpty ? 26.0 : 0);
    final listH = need.clamp(88.0, avail < 88 ? 88.0 : avail);
    final gapBig = compact ? 14.0 : 22.0;
    return Column(key: key, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      EnterAnim(index: 0, child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic, children: [
        Text(S.of('resultPre'), style: KT.serif.copyWith(
            fontSize: 16, color: K.fg2, letterSpacing: 1.5)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Text('${flagged.length}', style: KT.serif.copyWith(
                fontSize: 34))),
        Text(S.of('resultPost'), style: KT.serif.copyWith(
            fontSize: 16, color: K.fg2, letterSpacing: 1.5)),
      ])),
      const SizedBox(height: 6),
      EnterAnim(index: 1, child: Text(
          fx.isEmpty || qCount == 0
              ? (fx.isEmpty ? S.of('allManual') : S.of('ctaNone'))
              : (totalMb > 0
                  ? S.fmt('fixableInfo', {'n': qCount, 'mb': totalMb})
                  : S.fmt('fixableN', {'n': qCount})) +
                (_admin == false ? ' · ${S.of('needAdmin')}' : ''),
          style: KT.ui.copyWith(fontSize: 13, color: K.fg2))),
      SizedBox(height: compact ? 10 : 14),
      // 真实异常清单：分「运行库 / 系统优化」两段；段头勾环可整组退出一键
      EnterAnim(index: 2, child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: listH),
        child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          if (rt.isNotEmpty) _sectionHead(S.of('secRuntimes'), first: true,
              checked: _incRt,
              onToggle: () => setState(() => _incRt = !_incRt)),
          for (var i = 0; i < rt.length; i++)
            MissRow(rt[i].component.name,
                sizeMb: rt[i].component.sizeMb,
                status: _rowStatus(rt[i]),
                color: _rowColor(rt[i]),
                onTap: !rt[i].component.autoInstall &&
                        rt[i].component.install.manual != null
                    ? () => _openManual(rt[i].component)
                    : null,
                last: i == rt.length - 1),
          if (st.isNotEmpty) _sectionHead(S.of('secSettings'),
              first: rt.isEmpty, checked: _incSt,
              onToggle: () => setState(() => _incSt = !_incSt)),
          for (var i = 0; i < st.length; i++)
            MissRow(st[i].component.name,
                sizeLabel: _recLabel(st[i].component),
                status: _rowStatus(st[i]),
                color: _rowColor(st[i]),
                onTap: !st[i].component.autoInstall &&
                        st[i].component.install.manual != null
                    ? () => _openManual(st[i].component)
                    : null,
                last: i == st.length - 1),
        ])),
      )),
      SizedBox(height: gapBig),
      // 一键 CTA：文案随勾选组动态「安装 N 项 · 优化 M 项」；无可装 → 灰掉
      if (fx.isNotEmpty)
        EnterAnim(index: 3, child: ArrowCta(
            qCount == 0
                ? S.of('ctaNone')
                : qRt > 0 && qSt > 0
                    ? S.fmt('ctaInstallOpt', {'n': qRt, 'm': qSt})
                    : qSt > 0
                        ? S.fmt('ctaOptN', {'m': qSt})
                        : S.fmt('ctaInstallN', {'n': qRt}),
            onTap: qCount == 0 ? null : _cta))
      else
        EnterAnim(index: 3, child: Text(S.of('allManual'),
            style: KT.ui.copyWith(fontSize: 15, letterSpacing: 1,
                fontWeight: FontWeight.w600, color: K.fg2))),
      if (man.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: EnterAnim(index: 4, child: Text(
              S.fmt('manualNote', {'n': man.length}),
              style: KT.ui.copyWith(fontSize: 13, color: K.fg2))),
        ),
      const SizedBox(height: 8),
      EnterAnim(index: 5, child: Row(children: [
        HaloLink(S.of('rescan'), onTap: _scan),
        // 修复入口：只在有已装项时出现
        if (_installed.isNotEmpty)
          HaloLink(S.of('repair'), onTap: _enterRepair),
        HaloLink(S.of('about'), onTap: _openAbout),
        HaloLink(S.of('exit'), onTap: () => exit(0)),
      ])),
      // 轻提示行（如 UAC 取消）：结果屏没有安装面板，借这里露出 _detail
      if (_detail.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 2),
            child: Text(_detail, style: KT.uiMeta.copyWith(
                fontSize: 12, color: K.fg3))),
    ]);
  }

  // —— 修复模式（结果相位内的轻量确认态，复用清单样式）——
  Widget _repairBody({required double h}) {
    final inst = _installed;
    final rt = inst.where((r) => !r.component.isSetting).toList();
    final st = inst.where((r) => r.component.isSetting).toList();
    final sel = _repairSel.length;
    final compact = h < 640;
    final panelTop = (h * 0.22).clamp(86.0, 220.0);
    final avail = h - panelTop - (compact ? 190.0 : 210.0);
    final need = inst.length * 44.0 +
        (rt.isNotEmpty ? 22.0 : 0) + (st.isNotEmpty ? 26.0 : 0);
    final listH = need.clamp(88.0, avail < 88 ? 88.0 : avail);

    Widget row(CheckResult r, bool last) {
      final c = r.component;
      final pickable = c.autoInstall; // 手动项不可勾，点开跳官方指引
      return MissRow(c.name,
          sizeMb: c.sizeMb,
          sizeLabel: c.isSetting ? _recLabel(c) : null,
          status: pickable
              ? (c.isSetting ? S.of('rowOptimized') : S.of('rowInstalled'))
              : S.of('rowManual'),
          color: pickable ? K.installed : K.manualTx,
          checkable: pickable,
          checked: _repairSel.contains(c.id),
          onToggle: pickable ? () => _toggleRepairItem(c) : null,
          onTap: !pickable && c.install.manual != null
              ? () => _openManual(c)
              : null,
          last: last);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(S.of('repairTitle'), style: KT.serif.copyWith(
          fontSize: 30, letterSpacing: 2)),
      const SizedBox(height: 8),
      Text(S.of('repairHint'),
          style: KT.ui.copyWith(fontSize: 13, color: K.fg2)),
      SizedBox(height: compact ? 10 : 14),
      ConstrainedBox(
        constraints: BoxConstraints(maxHeight: listH),
        child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          if (rt.isNotEmpty) _sectionHead(S.of('secRuntimes'), first: true),
          for (var i = 0; i < rt.length; i++) row(rt[i], i == rt.length - 1),
          if (st.isNotEmpty) _sectionHead(S.of('secSettings'),
              first: rt.isEmpty),
          for (var i = 0; i < st.length; i++) row(st[i], i == st.length - 1),
        ])),
      ),
      SizedBox(height: compact ? 14 : 22),
      ArrowCta(S.fmt('repairCta', {'n': sel}),
          onTap: sel == 0 ? null : _startRepair),
      const SizedBox(height: 8),
      Row(children: [
        HaloLink(S.of('repairBack'), onTap: _exitRepair),
      ]),
      if (_detail.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 2),
            child: Text(_detail, style: KT.uiMeta.copyWith(
                fontSize: 12, color: K.fg3))),
    ]);
  }

  // —— 安装中 ——
  Widget _installPanel({required Key key}) {
    final done = orb.okCount + orb.failCount;
    final total = _queue.length;
    return Column(key: key, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      Row(crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic, children: [
        Text(S.of('installing'), style: KT.serif.copyWith(
            fontSize: 30, letterSpacing: 2)),
        const SizedBox(width: 14),
        Text('$done / $total', style: KT.ui.copyWith(
            fontSize: 14, fontWeight: FontWeight.w600, color: K.fg2)),
      ]),
      const SizedBox(height: 14),
      SizedBox(height: 20, child: Text(_detail,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: KT.ui.copyWith(fontSize: 13, color: K.fg2))),
      const SizedBox(height: 12),
      HairlineProgress(frac: total == 0 ? 0 : done / total),
    ]);
  }

  // —— 完成 ——
  Widget _completePanel({required Key key}) {
    final failed = orb.failCount;
    return Column(key: key, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      EnterAnim(index: 0, child: Text(
          failed != 0
              ? S.of('donePartial')
              : (_queue.isNotEmpty ? S.of('doneAll') : S.of('resultAllPass')),
          style: KT.serif.copyWith(fontSize: 32, letterSpacing: 2))),
      const SizedBox(height: 12),
      EnterAnim(index: 1, child: Text(
          _queue.isEmpty
              ? S.of('doneNone')
              : S.fmt('doneOk', {'ok': orb.okCount, 'total': _queue.length}),
          style: KT.ui.copyWith(fontSize: 13.5, color: K.fg2))),
      if (failed != 0) ...[
        const SizedBox(height: 14),
        for (final id in _failIds)
          _failRow(id),
      ],
      const SizedBox(height: 24),
      EnterAnim(index: 2, child: Row(children: [
        HaloLink(S.of('rescan'), onTap: _scan),
        HaloLink(S.of('openLog'), onTap: _openLogDir),
        HaloLink(S.of('about'), onTap: _openAbout),
        HaloLink(S.of('exit'), onTap: () => exit(0)),
      ])),
    ]);
  }

  /// 失败行：组件名 + 官方下载/指引链接（autoInstall 失败也有兜底入口）
  Widget _failRow(String id) {
    final c = _catalog?.components.firstWhere((e) => e.id == id,
        orElse: () => _catalog!.components.first);
    if (c == null) return const SizedBox.shrink();
    final url = c.install.download?.url ?? c.install.manual?.url;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(c.name,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: KT.ui.copyWith(fontSize: 13, color: K.fg2))),
        if (url != null)
          HaloLink(S.of('failDl'), onTap: () => _openUrl(url)),
      ]),
    );
  }

  // ═══════════════ 关于作者 · 遮罩弹层 ═══════════════

  void _openAbout() => setState(() { _aboutOpen = true; _compsOpen = false; });
  void _closeAbout() => setState(() => _aboutOpen = false);

  /// 系统默认浏览器打开链接（与手动指引同一通道）
  void _openUrl(String u) =>
      Process.run('rundll32', ['url.dll,FileProtocolHandler', u],
          runInShell: true);

  /// 米白遮罩：点遮罩 / Esc 关闭；卡片淡入 + 轻微上移，尊重 disableAnimations
  Widget _aboutLayer() {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Focus(
          autofocus: true,
          onKeyEvent: (_, e) {
            if (e is KeyDownEvent &&
                e.logicalKey == LogicalKeyboardKey.escape) {
              _closeAbout();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Stack(children: [
            Positioned.fill(child: GestureDetector(
              onTap: _closeAbout,
              child: Container(
                  color: K.cream.withValues(alpha: 0.74 * v)),
            )),
            Center(child: Transform.translate(
              offset: Offset(0, 10 * (1 - v)),
              child: Opacity(opacity: v, child: _aboutCard()),
            )),
          ]),
        ),
      ),
    );
  }

  Widget _aboutCard() {
    final maxH = MediaQuery.sizeOf(context).height - 64;
    return Container(
      width: 384,
      constraints: BoxConstraints(maxHeight: maxH < 260 ? 260 : maxH),
      padding: const EdgeInsets.fromLTRB(26, 20, 26, 22),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF8F1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: K.line.withValues(alpha: 0.8), width: 0.7),
        boxShadow: [BoxShadow(
            color: K.shadow.withValues(alpha: 0.38),
            blurRadius: 40, offset: const Offset(0, 18))],
      ),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(S.of('aboutTitle'), style: KT.ui.copyWith(
                fontSize: 20, fontWeight: FontWeight.w700,
                letterSpacing: 1)),
            const Spacer(),
            AboutCloseX(onTap: _closeAbout),
          ]),
          const SizedBox(height: 16),
          Text('ZYY817 / Zhiyu（智宇）', style: KT.ui.copyWith(
              fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('APPLIED AI', style: KT.mono.copyWith(
              fontSize: 10.5, letterSpacing: 2.4, color: K.fg3)),
          const SizedBox(height: 16),
          _hairline(),
          const SizedBox(height: 16),
          // 双语名片：主语言在前
          if (S.isEn) ...[
            Text(S.of('aboutBioEn'),
                style: KT.ui.copyWith(fontSize: 13.5,
                    fontWeight: FontWeight.w500, height: 1.5)),
            const SizedBox(height: 8),
            Text(S.of('aboutBioZh'),
                style: KT.uiMeta.copyWith(fontSize: 12, height: 1.55)),
          ] else ...[
            Text(S.of('aboutBioZh'),
                style: KT.ui.copyWith(fontSize: 13.5,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text(S.of('aboutBioEn'),
                style: KT.uiMeta.copyWith(fontSize: 12, height: 1.55)),
          ],
          const SizedBox(height: 16),
          _hairline(),
          const SizedBox(height: 6),
          AboutLinkRow('GitHub', 'https://github.com/ZYY817',
              onTap: () => _openUrl('https://github.com/ZYY817')),
          AboutLinkRow('Bilibili', 'https://space.bilibili.com/41173761',
              onTap: () =>
                  _openUrl('https://space.bilibili.com/41173761')),
        ]),
      ),
    );
  }

  /// 发丝分隔线
  Widget _hairline() => Container(height: 0.7,
      color: K.line.withValues(alpha: 0.85));

  // ═══════════════ 组件清单 · 遮罩弹层（与 about 同体系）═══════════════

  void _openComps() => setState(() { _compsOpen = true; _aboutOpen = false; });
  void _closeComps() => setState(() => _compsOpen = false);

  /// 米白遮罩：点遮罩 / Esc / × 三关；淡入 + 轻微上移，尊重 disableAnimations
  Widget _compsLayer() {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Focus(
          autofocus: true,
          onKeyEvent: (_, e) {
            if (e is KeyDownEvent &&
                e.logicalKey == LogicalKeyboardKey.escape) {
              _closeComps();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Stack(children: [
            Positioned.fill(child: GestureDetector(
              onTap: _closeComps,
              child: Container(
                  color: K.cream.withValues(alpha: 0.74 * v)),
            )),
            Center(child: Transform.translate(
              offset: Offset(0, 10 * (1 - v)),
              child: Opacity(opacity: v, child: _compsCard()),
            )),
          ]),
        ),
      ),
    );
  }

  /// category → 组头文案；catalog 里还有 runtime/windows 两类，给独立组名，
  /// 未识别的新 category 一律归「其他」
  String _catLabel(String cat) => switch (cat) {
        'vcredist' => S.of('catVcredist'),
        'dotnet' => S.of('catDotnet'),
        'directx' => S.of('catDirectx'),
        'middleware' => S.of('catMiddleware'),
        'setting' => S.of('catSetting'),
        'runtime' => S.of('catRuntime'),
        'windows' => S.of('catWindows'),
        _ => S.of('catOther'),
      };

  /// 行内状态字/色（仅扫描后显示）：设置项缺失叫「待优化」，手动项叫「需手动」
  ({String t, Color c}) _compStatus(OrbParticle p) {
    final comp = p.component;
    final manual = comp != null && !comp.autoInstall;
    return switch (p.status) {
      PStatus.installed => (t: S.of('rowInstalled'), c: K.installed),
      PStatus.outdated => manual
          ? (t: S.of('rowManual'), c: K.manualTx)
          : (t: S.of('rowOutdated'), c: K.amberTx),
      PStatus.missing => manual
          ? (t: S.of('rowManual'), c: K.manualTx)
          : (t: comp?.isSetting == true ? S.of('rowOff') : S.of('rowMissing'),
             c: K.missingTx),
      PStatus.checking => (t: S.of('rowChecking'), c: K.amberTx),
      _ => (t: '—', c: K.fg3),
    };
  }

  /// 行首状态点：已装=金珠实心 / 缺失(待优化)=赤陶环 / 过旧=琥珀点 /
  /// 手动缺失=灰环 / 检测中=琥珀环 / 未检=无
  Widget _compDot(OrbParticle p) {
    final manual = p.component != null && !p.component!.autoInstall;
    final style = switch (p.status) {
      PStatus.installed => (fill: K.gold, ring: Colors.transparent),
      PStatus.outdated => (fill: K.amber, ring: Colors.transparent),
      PStatus.missing => (fill: Colors.transparent,
          ring: manual ? K.manualTx : K.missing),
      PStatus.checking => (fill: Colors.transparent, ring: K.amber),
      _ => (fill: Colors.transparent, ring: Colors.transparent),
    };
    return Container(width: 7, height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: style.fill,
          border: style.ring == Colors.transparent
              ? null
              : Border.all(color: style.ring, width: 1.4),
        ));
  }

  Widget _compRow(int i, OrbParticle p, bool scanned) {
    final c = p.component!;
    final st = scanned ? _compStatus(p) : null;
    return SizedBox(height: 31,
      // 三列定宽严格竖直对齐：序号 28 左齐 | 大小 56 右齐 | 渠道 pill 64 定宽居中
      child: Row(children: [
        SizedBox(width: 20, child: scanned
            ? _compDot(p) : null),
        SizedBox(width: 28, child: Text(
            (i + 1).toString().padLeft(2, '0'),
            style: KT.mono.copyWith(fontSize: 9.5, letterSpacing: 0.8))),
        Expanded(child: Text(c.name,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: KT.ui.copyWith(fontSize: 15,
                fontWeight: FontWeight.w500))),
        const SizedBox(width: 8),
        SizedBox(width: 56, child: Text(
            c.sizeMb > 0 ? '${c.sizeMb} MB' : '—',
            textAlign: TextAlign.right,
            style: KT.ui.copyWith(fontSize: 13, color: K.fg2))),
        const SizedBox(width: 10),
        // 渠道标签：winget/download/command 任一即「自动」，仅 manual 为「手动」；
        // 定宽 64 —— EN「MANUAL」12px 不折行，列缘竖直对齐
        SizedBox(width: 64, child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 4, vertical: 1.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: K.fg3.withValues(alpha: 0.55), width: 0.8),
          ),
          child: Text(c.autoInstall ? S.of('chAuto') : S.of('chManual'),
              textAlign: TextAlign.center,
              maxLines: 1, softWrap: false,
              style: KT.uiMeta.copyWith(fontSize: 12, height: 1.15,
                  letterSpacing: 0.8, color: K.fg2)),
        )),
        const SizedBox(width: 8),
        SizedBox(width: 64, child: st == null ? null : Text(st.t,
            textAlign: TextAlign.right,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: KT.ui.copyWith(fontSize: 12,
                fontWeight: FontWeight.w600, color: st.c))),
      ]),
    );
  }

  Widget _compsCard() {
    final size = MediaQuery.sizeOf(context);
    final compact = size.height < 620;
    final cardH = (compact ? 440.0 : 480.0)
        .clamp(260.0, size.height - 40).toDouble();
    final cardW = 588.0.clamp(320.0, size.width - 48).toDouble();
    final comps = _catalog!.components;
    // 扫描过后：行首状态点 + 右端状态字（数据与轨道珠同源 orb.particles）
    final scanned = orb.particles
        .any((p) => p.status != PStatus.pending);
    // 按 catalog 顺序分组（组序 = 类别首次出现序），序号保持目录序 01-32
    final order = <String>[];
    final groups = <String, List<int>>{};
    for (var i = 0; i < comps.length; i++) {
      final cat = comps[i].category;
      groups.putIfAbsent(cat, () {
        order.add(cat);
        return <int>[];
      }).add(i);
    }
    final rows = <Widget>[];
    for (final cat in order) {
      final idxs = groups[cat]!;
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 3),
        child: Row(children: [
          Text(_catLabel(cat), style: KT.uiMeta.copyWith(
              fontSize: 10.5, letterSpacing: 2.0, color: K.fg2,
              fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Expanded(child: _hairline()),
          const SizedBox(width: 8),
          Text('${idxs.length}', style: KT.mono.copyWith(
              fontSize: 9, letterSpacing: 1)),
        ]),
      ));
      for (var k = 0; k < idxs.length; k++) {
        final i = idxs[k];
        rows.add(_compRow(i, orb.particles[i], scanned));
      }
    }
    return Container(
      width: cardW, height: cardH,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF8F1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: K.line.withValues(alpha: 0.8), width: 0.7),
        boxShadow: [BoxShadow(
            color: K.shadow.withValues(alpha: 0.38),
            blurRadius: 40, offset: const Offset(0, 18))],
      ),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(S.of('compTitle'), style: KT.ui.copyWith(
                fontSize: 20, fontWeight: FontWeight.w700,
                letterSpacing: 1)),
            const SizedBox(height: 4),
            // mono 副标：点题「游戏运行库」定位
            Text(S.of('compSub'), style: KT.mono.copyWith(
                fontSize: 9, letterSpacing: 2.2, color: K.fg3)),
          ]),
          const Spacer(),
          AboutCloseX(onTap: _closeComps),
        ]),
        const SizedBox(height: 10),
        _hairline(),
        // 滚动区右侧留 12px——桌面端 Material 自动挂的细滚动条不压内容列
        Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.only(right: 12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: rows))),
        _hairline(),
        Padding(padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Text(S.fmt('compTotal', {'n': comps.length}),
                  style: KT.uiMeta.copyWith(fontSize: 11,
                      letterSpacing: 1, color: K.fg2)),
            ])),
      ]),
    );
  }

  /// 手动项：打开官方指引页（ms-settings / https 均走系统协议）
  void _openManual(Component c) {
    final u = c.install.manual?.url;
    if (u == null) return;
    Process.run('rundll32', ['url.dll,FileProtocolHandler', u],
        runInShell: true);
  }

  void _openLogDir() {
    final dir = p.join(Platform.environment['APPDATA'] ?? '.',
        'WanjiKit', 'logs');
    Directory(dir).createSync(recursive: true);
    Process.run('explorer', [dir], runInShell: true);
  }
}
