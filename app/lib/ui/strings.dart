// 界面文案字典：zh / en 双语。S.of('key') 取词，S.fmt 带参。
// catalog 里的组件名/why 是数据，不走这里。
// 纯 Dart 无 flutter 依赖——引擎层（install.dart）和独立脚本都能引用。
class S {
  S._();

  static String lang = 'zh'; // 'zh' | 'en'
  static bool get isEn => lang == 'en';

  /// 语言变更钩子（main.dart 注册 → 重建根部件刷新窗口标题）
  static void Function(String lang)? onLangChange;

  static void setLang(String l) {
    if (l == lang) return;
    lang = l;
    onLangChange?.call(l);
  }

  /// 启动时加载的语言：直接赋值 + 手动触发一次钩子
  static void applyLoaded(String l) {
    lang = l;
    onLangChange?.call(l);
  }

  static void toggle() => setLang(isEn ? 'zh' : 'en');

  static String of(String key) =>
      _t[lang]?[key] ?? _t['zh']?[key] ?? key;

  /// {name} 占位替换：S.fmt('installN', {'n': 4})
  static String fmt(String key, Map<String, Object> args) {
    var s = of(key);
    for (final e in args.entries) {
      s = s.replaceAll('{${e.key}}', '${e.value}');
    }
    return s;
  }

  static const _t = <String, Map<String, String>>{
    'zh': {
      'appTitle': '运行库体检 · ZYY817',
      // —— 待机 ——
      'idleTitle': '运行库体检',
      'idleSub': '检查游戏运行环境',
      'idleCta': '开始检测',
      'idleHint': '只读检测 · 不修改系统 · 约 10 秒',
      'about': '关于作者',
      // —— 扫描 ——
      'scanning': '检测中',
      // —— 底部元信息 ——
      'metaItems': '{n} 项组件 · {phase}',
      'phaseIdle': '待机',
      'phaseScan': '检测中',
      'phaseResult': '体检报告',
      'phaseInstall': '安装中',
      'phaseDone': '完毕',
      // —— 结果 ——
      'resultAllPass': '全项通过',
      'resultAllPassSub': '运行库一件不缺 · 无需安装',
      'resultPre': '待补',
      'resultPost': '项',
      'fixableInfo': '可装 {n} 项 · 共约 {mb} MB',
      'needAdmin': '需管理员',
      'allManual': '均需手动处理',
      'secRuntimes': '运行库',
      'secSettings': '系统优化',
      'rowMissing': '缺失',
      'rowOutdated': '过旧',
      'rowManual': '需手动',
      'rowOff': '待优化',
      'rowOptimized': '已优化',
      'colToggle': '开关',
      'recOn': '建议开启',
      'recOff': '建议关闭',
      'recSwitch': '建议切换',
      'ctaInstallN': '安装 {n} 项',
      'ctaOptN': '优化 {m} 项',
      'ctaInstallOpt': '安装 {n} 项 · 优化 {m} 项',
      'ctaNone': '组已取消 · 无可装项',
      'fixableN': '可装 {n} 项',
      'manualNote': '另 {n} 项需手动处理 · 点击清单打开指引',
      'rescan': '重新检测',
      'exit': '退出',
      'openLog': '打开日志',
      'repair': '修复重装',
      // —— 修复模式 ——
      'repairTitle': '修复模式',
      'repairHint': '勾选要重装的已装项',
      'repairCta': '重装 {n} 项',
      'repairBack': '返回',
      'rowInstalled': '已装',
      // —— 安装 ——
      'installing': '正在装齐',
      'queueSeed': '装齐队列 {n} 项',
      // —— 完成 ——
      'donePartial': '部分未过',
      'doneAll': '装机完毕',
      'doneOk': '本次装齐 {ok} / {total} 项 · 日志已留存',
      'doneNone': '运行库一件不缺',
      'failDl': '官方下载',
      // —— 加载失败 ——
      'loadFail': '组件目录加载失败',
      // —— 安装引擎细节 ——
      'evDownloading': '下载官方安装包…',
      'evDlPct': '下载官方安装包… {pct}%',
      'evInstalling': '静默安装…',
      'evVerifying': '安装后重扫…',
      'evWingetExit': 'winget 退出码 {code}',
      'evPkgExit': '安装器退出码 {code}',
      'evCmdExit': '命令退出码 {code}',
      'evNoChannel': '无自动安装渠道',
      'evDlFail': '下载失败',
      'evVerifyFail': '安装器返回成功但验证未通过',
      'evInterrupted': '安装中断：{err}',
      'uacCancel': '提权已取消，可稍后重试',
      // —— 关于 ——
      'aboutTitle': '关于作者',
      'aboutBioZh': '用 AI 创造，让想法真正产生价值。',
      'aboutBioEn': 'Creating with AI. Turning ideas into useful products, '
          'tools, and content for real-world impact.',
    },
    'en': {
      'appTitle': 'Runtime Check · ZYY817',
      // —— idle ——
      'idleTitle': 'Runtime Check',
      'idleSub': 'Game runtime health check',
      'idleCta': 'Start Scan',
      'idleHint': 'Read-only · changes nothing · ~10 s',
      'about': 'About',
      // —— scanning ——
      'scanning': 'Scanning',
      // —— bottom meta ——
      'metaItems': '{n} items · {phase}',
      'phaseIdle': 'idle',
      'phaseScan': 'scanning',
      'phaseResult': 'report',
      'phaseInstall': 'installing',
      'phaseDone': 'done',
      // —— result ——
      'resultAllPass': 'All clear',
      'resultAllPassSub': 'Every runtime in place · nothing to install',
      'resultPre': 'Fix',
      'resultPost': 'items',
      'fixableInfo': '{n} auto-fixable · ~{mb} MB',
      'needAdmin': 'admin required',
      'allManual': 'Manual steps only',
      'secRuntimes': 'RUNTIMES',
      'secSettings': 'OPTIMIZATION',
      'rowMissing': 'Missing',
      'rowOutdated': 'Outdated',
      'rowManual': 'Manual',
      'rowOff': 'Pending',
      'rowOptimized': 'Optimized',
      'colToggle': 'Toggle',
      'recOn': 'Enable',
      'recOff': 'Disable',
      'recSwitch': 'Switch',
      'ctaInstallN': 'Install {n}',
      'ctaOptN': 'Optimize {m}',
      'ctaInstallOpt': 'Install {n} · Optimize {m}',
      'ctaNone': 'Nothing selected',
      'fixableN': '{n} auto-fixable',
      'manualNote': '{n} more need manual steps · click a row for guide',
      'rescan': 'Rescan',
      'exit': 'Exit',
      'openLog': 'Open logs',
      'repair': 'Repair',
      // —— repair mode ——
      'repairTitle': 'Repair mode',
      'repairHint': 'Pick installed items to reinstall',
      'repairCta': 'Reinstall {n}',
      'repairBack': 'Back',
      'rowInstalled': 'OK',
      // —— installing ——
      'installing': 'Installing',
      'queueSeed': 'Queued {n} items',
      // —— done ——
      'donePartial': 'Some failed',
      'doneAll': 'All done',
      'doneOk': '{ok} of {total} fixed · logs saved',
      'doneNone': 'Nothing missing',
      'failDl': 'Official download',
      // —— load fail ——
      'loadFail': 'Catalog failed to load',
      // —— install engine details ——
      'evDownloading': 'Downloading installer…',
      'evDlPct': 'Downloading installer… {pct}%',
      'evInstalling': 'Silent install…',
      'evVerifying': 'Re-checking…',
      'evWingetExit': 'winget exit {code}',
      'evPkgExit': 'installer exit {code}',
      'evCmdExit': 'command exit {code}',
      'evNoChannel': 'no auto-install channel',
      'evDlFail': 'download failed',
      'evVerifyFail': 'installer ok but verify failed',
      'evInterrupted': 'interrupted: {err}',
      'uacCancel': 'Elevation cancelled — try again anytime',
      // —— about ——
      'aboutTitle': 'About',
      'aboutBioZh': '用 AI 创造，让想法真正产生价值。',
      'aboutBioEn': 'Creating with AI. Turning ideas into useful products, '
          'tools, and content for real-world impact.',
    },
  };
}
