# 玩机装机工具（Wanji Kit）

Windows 游戏运行环境一键检测与安装工具。Flutter Windows 桌面应用，奶油雕塑风格单窗口 UI。

## 功能现状

- **检测**：26 项运行库组件（VC++ 2005–2022 x86/x64、.NET Framework 3.5/4.8、.NET Desktop Runtime 6/8/9、DirectX Jun 2010、DirectPlay、XNA 4.0、OpenAL、PhysX、WebView2、Java 21、UE4 前置组件等）。注册表 / 文件 / 命令 / WinSxS 四类规则，全部只读，约 10–30 秒。
- **安装**：点「安装 N 项」→ 弹一次 UAC 自我提权重启（`--install=` 续装）→ winget 优先 → 微软官方直链兜底 → 装完逐项重扫验证。失败项在完成屏计入「部分未过」。
- **手动项**：无自动渠道的组件（DirectPlay / Media Feature Pack / OpenAL / PhysX / .NET 3.5 / UE4 前置）在结果清单标「需手动」，点击行用系统协议处理程序打开官方指引页。
- **日志**：JSONL 写 `%APPDATA%\WanjiKit\logs\<时间戳>.log`（装了什么 / 来源 / 退出码）。完成屏「打开日志」打开日志目录。
- **目录热更**：exe 同级放 `catalog/runtimes.json` 优先于内置 asset 加载，改组件不用重编。

## 运行要求

- Windows 10 / 11 x64（真·无边框窗：顶部 chrome 行即标题栏，可拖拽、双击最大化、边缘缩放）
- winget 可选：没有 winget 时自动走官方直链；装运行库需要管理员（届时会弹 UAC）

## 构建

```bash
# 环境：Flutter SDK（F:\flutter）+ VS Build Tools（C++ 负载）
cd app
flutter pub get
flutter analyze                  # 当前零 issue
flutter run -d windows           # 调试运行
flutter build windows --release  # 产出 → app\build\windows\x64\runner\Release\
```

## 分发须知

- **整目录分发**：`wanji_kit.exe` + `flutter_windows.dll` + `data\`（含 catalog、雕塑图、字体）三者缺一不可，单独拷贝 exe **跑不起来**。发布产物见 `dist\wanji-kit-v0.2.1-windows-x64.zip`，解压即整目录
- **SmartScreen 提示属正常**：exe 未做代码签名，首次运行可能弹「Windows 已保护你的电脑」→ 更多信息 → 仍要运行
- `catalog\runtimes.json` 放 exe 同级可热更组件，不用重编

## 调试参数

```
wanji_kit.exe --autoscan       # 启动后自动开扫（真实检测）
wanji_kit.exe --demo-report    # 假数据直进结果屏（视觉自查）
wanji_kit.exe --demo-install   # 假数据走完整安装动画，不写系统
wanji_kit.exe --install=a,b,c  # 提权续装（内部由 UAC 重启调用）
```

## 目录结构

```
catalog/runtimes.json     组件目录——新增组件 = 加一条 JSON，不写代码
app/lib/engine/           catalog / detect / install / elevate / log 引擎
app/lib/ui/               雕塑舞台(sculpt) + 轨道粒子模型(orb) + HUD
app/windows/runner/       Win32 宿主：无边框（NCCALCSIZE 裁框 + NCHITTEST 拖拽/缩放 + wanji/window 通道）、最小 890x560、图标
scripts/winshot.py        PrintWindow 截图工具
docs/                     产品规划
```

## 已知限制

- 端到端真实安装未在开发机上跑过全流程（需 UAC 确认 + 真装组件）；winget/直链/重扫逻辑为代码审查 + 演示模式验证
- 手动项只给官方指引页跳转，不代办系统操作（如 DirectPlay 走 `ms-settings:optionalfeatures`）
- 检测是存在性判断：能验"装没装"，不验运行库内部是否损坏
- winget 静默安装受 winget 源可用性影响；下载兜底仅覆盖 catalog 中配了 `download` 的组件
- 窗口最小 890×560，更小的屏幕/分屏下排版不换响应式布局

## 路线图

- v0.1：扫描 + 报告 + 一键装齐 + 日志
- v0.2.1（当前）：无边框窗 + 双语 + 修复模式 + 32 项目录 + 系统优化项
- v0.3：按游戏检查（吃玩机索引站数据）、catalog 在线热更
- v0.3：离线包、自动更新、CLI（`wanji-kit scan --json`）

详见 `docs/产品规划.md`。
