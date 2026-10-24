# 玩机装机工具（Wanji Kit）

Windows 游戏运行环境一键检测与安装工具。**只装官方源、每步可验证、单文件 exe、零依赖**。

- 检测：VC++ 2005–2022（x86+x64）、.NET Framework 4.8、.NET 8 桌面运行时、DirectX June 2010 旧组件、XNA 4.0、OpenAL、PhysX
- 安装：winget 优先 → 微软官方直链兜底 → 手动链接；装完自动重扫验证
- 日志：`%APPDATA%\WanjiKit\logs\`（装了什么 / 从哪下的 / 退出码，全留痕）
- 权限：扫描不需要管理员；仅在「一键装齐」时弹一次 UAC

## 开发

```bash
# 环境：Flutter SDK（F:\flutter）+ VS Build Tools（C++ 负载）
cd app
flutter pub get
flutter analyze
flutter run -d windows      # 调试运行
flutter build windows       # 产出 exe → build\windows\x64\runner\Release\
```

## 架构（数据驱动）

```
catalog/runtimes.json   运行库目录——新增组件 = 加一条 JSON，不写代码
app/lib/engine/         检测 / 安装 / 提权 / 日志引擎
app/lib/ui/             界面（石墨 + 信号橙 + 宋体 + mono，自有视觉体系）
```

外挂 `catalog/runtimes.json` 放在 exe 同级 `catalog/` 下即可热更新组件目录，免重编。

## 路线图

- v0.1（当前）：扫描 + 报告 + 一键装齐 + 日志
- v0.2：按游戏检查（吃玩机索引站数据）、修复模式、catalog 在线热更
- v0.3：离线包、自动更新、CLI（`wanji-kit scan --json`）

详见 `docs/产品规划.md`。
