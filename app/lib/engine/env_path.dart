// 进程启动时的 PATH 是快照——安装中途新装的 dotnet/java 会写进注册表
// Path，但不会出现在本进程环境块里（子进程继承父进程环境）→
// 「装完验证」找不到命令误报失败。
// 解法：每次拉起子进程前从注册表重建权威 PATH：
//   HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment\Path
//   + HKCU\Environment\Path
// （RegGetValue 不抑制展开 → REG_EXPAND_SZ 的 %SystemRoot% 等已就地展开），
// 末尾再拼进程自带 PATH 兜底，整体小写去重。
import 'dart:io';
import 'package:win32_registry/win32_registry.dart';

class EnvPath {
  static String? _read(RegistryHive hive, String keyPath) {
    RegistryKey? key;
    try {
      key = Registry.openPath(hive, path: keyPath);
      // expandPaths: true → REG_EXPAND_SZ 就地展开，REG_SZ 原样返回
      return key.getStringValue('Path', expandPaths: true);
    } catch (_) {
      return null; // 键/值不存在 → 忽略该段
    } finally {
      key?.close();
    }
  }

  /// 重建后的完整 PATH：系统 Path → 用户 Path → 进程当前 PATH（兜底），
  /// 按序拼接、忽略大小写去重。
  static String rebuild() {
    final env = Platform.environment;
    final curKey = env.keys.firstWhere(
        (k) => k.toLowerCase() == 'path', orElse: () => 'PATH');
    final parts = <String?>[
      _read(RegistryHive.localMachine,
          r'SYSTEM\CurrentControlSet\Control\Session Manager\Environment'),
      _read(RegistryHive.currentUser, 'Environment'),
      env[curKey],
    ];
    final seen = <String>{};
    final out = <String>[];
    for (final chunk in parts) {
      if (chunk == null) continue;
      for (final p in chunk.split(';')) {
        final t = p.trim();
        if (t.isNotEmpty && seen.add(t.toLowerCase())) out.add(t);
      }
    }
    return out.join(';');
  }

  /// 直接喂给 Process.run(environment:) 的完整环境：拷贝当前环境并
  /// 原位替换 Path 键（保留原键名大小写，避免 env 块出现两个 PATH）。
  static Map<String, String> environment() {
    final env = Map<String, String>.of(Platform.environment);
    final key = env.keys.firstWhere(
        (k) => k.toLowerCase() == 'path', orElse: () => 'PATH');
    env[key] = rebuild();
    return env;
  }
}
