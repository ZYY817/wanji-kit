// 权限：启动不弹 UAC（扫描只读注册表）；点「一键装齐」时才自我 runas 提权一次。
// 用 PowerShell Start-Process -Verb RunAs——比手写 ShellExecute FFI 稳。
import 'dart:io';

class Elevation {
  /// 当前是否管理员（net session 在无权限时退出码非 0）
  static Future<bool> get isAdmin async {
    try {
      final r = await Process.run('net', ['session'], runInShell: true);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// 以管理员身份重启自身，携带要安装的组件 id；用户同意 UAC 后当前进程退出。
  /// 用户取消 UAC / powershell 拉起失败 → 返回 false，留在原界面。
  static Future<bool> relaunchElevated(List<String> componentIds) async {
    final exe = Platform.resolvedExecutable;
    final params = '--elevated --install=${componentIds.join(',')}';
    try {
      final r = await Process.run('powershell', [
        '-NoProfile', '-Command',
        "Start-Process -FilePath '$exe' -ArgumentList '$params' -Verb RunAs",
      ], runInShell: true);
      if (r.exitCode == 0) {
        exit(0);
      }
    } catch (_) {
      // powershell 不存在/被策略拦 → 按「提权失败」处理，不静默吞掉
    }
    return false; // 用户点了「否」或拉起失败
  }
}
