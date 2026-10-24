// 应用骨架：无边框窗 + 自定义标题栏 + 发丝网格底 + 五屏状态机
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../engine/catalog.dart';
import 'theme.dart';
import 'screens/boot.dart';
import 'screens/scan.dart';
import 'screens/result.dart';
import 'screens/install.dart';
import 'screens/done.dart';
import 'widgets.dart';

enum KitScreen { boot, scan, result, install, done }

class KitApp extends StatefulWidget {
  final List<String> presetInstall; // --install=ids（提权重启带过来的）
  const KitApp({super.key, this.presetInstall = const []});

  @override
  State<KitApp> createState() => _KitAppState();
}

class _KitAppState extends State<KitApp> {
  KitScreen _screen = KitScreen.boot;
  Catalog? _catalog;
  List<CheckResult> _results = [];
  List<Component> _toInstall = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _catalog = await Catalog.load();
    setState(() {});
    if (widget.presetInstall.isNotEmpty) {
      // 提权重启直接进安装
      _toInstall = _catalog!.components
          .where((c) => widget.presetInstall.contains(c.id))
          .toList();
      setState(() => _screen = KitScreen.install);
    }
  }

  void _go(KitScreen s) => setState(() => _screen = s);

  void _onScanned(List<CheckResult> r) {
    _results = r;
    _go(KitScreen.result);
  }

  void _onConfirmInstall(List<Component> items) {
    _toInstall = items;
    _go(KitScreen.install);
  }

  @override
  Widget build(BuildContext context) {
    final cat = _catalog;
    return Scaffold(
      backgroundColor: K.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: Backdrop()),
          Column(
            children: [
              const KitTitleBar(),
              Expanded(
                child: cat == null
                    ? const Center(child: Text('加载组件目录…', style: KT.mono))
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 420),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: _screen == KitScreen.boot
                            ? BootScreen(
                                key: const ValueKey('boot'),
                                catalog: cat,
                                onStart: () => _go(KitScreen.scan),
                              )
                            : _screen == KitScreen.scan
                                ? ScanScreen(
                                    key: const ValueKey('scan'),
                                    catalog: cat,
                                    onDone: _onScanned,
                                  )
                                : _screen == KitScreen.result
                                    ? ResultScreen(
                                        key: const ValueKey('result'),
                                        results: _results,
                                        onInstall: _onConfirmInstall,
                                        onRescan: () => _go(KitScreen.scan),
                                      )
                                    : _screen == KitScreen.install
                                        ? InstallScreen(
                                            key: const ValueKey('install'),
                                            items: _toInstall,
                                            onDone: () => _go(KitScreen.done),
                                          )
                                        : DoneScreen(
                                            key: const ValueKey('done'),
                                            onRescan: () => _go(KitScreen.scan),
                                            onClose: () => windowManager.close(),
                                          ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
