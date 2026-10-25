# Codex 龙娘启动动画与动态壁纸 · 社区 R16

**当前完整包为用户测试通过的 R16，按验收 ZIP 原字节发布。** 原发布页和下载直链保持不变；文件名中的 `r5` 用于保留原地址，实际程序版本为 **34.16.0.0**。

[下载完整 Windows x64 包](https://github.com/HanwenZhang-George/codex-startup-animation/releases/download/community-v34-r5/CodexDragon-V34-Portable-Windows-x64-r5.zip) · [固定发布页](https://github.com/HanwenZhang-George/codex-startup-animation/releases/tag/community-v34-r5) · [故障排查与反馈教程](TROUBLESHOOTING.md) · [验证记录](VERIFICATION.txt)

> 请下载上述完整包。GitHub 的 **Code → Download ZIP** 和 **Source code (zip)** 是源码下载，不是包含全部视频的可运行包。

## 第一次使用

1. 完整解压到新的本地文件夹，例如 `D:\CodexDragon-R16`。不要在 ZIP 内运行，不要混入旧版文件。
2. 确认当前用户安装的官方 Microsoft Store Codex 能正常打开并登录。
3. 保存工作，正常完整退出 Codex。仅关闭窗口但仍留在后台，可能不算退出。
4. 双击最外层 **`Launch.exe`**。通常无需管理员权限，不必先安装或运行开发测试。
5. 检查启动动画、流泪与波纹交接，以及进入 Codex 后的壁纸、输入框透明度、点击与输入。

首次壁纸固定使用常态视频；以后每次出现按 **75% 常态 / 25% 粒子视频**选择，两次出现之间保留 **10–15 秒随机间隔**。人物暂时离开属于正常设计；25% 不表示每四次必有一次粒子视频。

**ESC 或动画上的 × 都可跳过动画，继续准备 Codex 和壁纸。** 跳过不代表客户端已立即就绪；传输、布局或解码问题仍可能影响显示。等待明显异常时先收集报告，不必等几分钟或反复重启。

由同一份包启动后，再点同一个 `Launch.exe` 可回到已有窗口并重播动画，保留该份包的壁纸会话。普通官方入口启动的 Codex 没有本包的私有壁纸连接，不能安全地事后补接；遇到提示时保存工作、完整退出再重试，不需要强制结束进程。

## 本次修复与包内容

- **R16：修复提前关闭动画导致无壁纸。** 动画、转场上的 × 和普通窗口关闭统一使用跳过流程，不再在清理时误发停用壁纸指令。保留晚到的准备请求，区分预览、系统退出和真实失败。
- **R15：完善重复启动和后台进程处理。** 不再把后台进程当成已经可以重播的主窗口；核验同目录壁纸会话。自动唤起有次数和时间上限，普通客户端没有壁纸会话时明确提示完整退出后重试。
- **R14：扩展官方注册安装路径兼容并补齐入口图标。** 支持经过校验的本地目录联接，继续检查注册身份、签名、路径与真实进程；`Launch.exe` 保留官方图标。
- **诊断：更清楚地区分关闭来源、当前启动与旧记录、暂未就绪与终态布局失败。** 旧播放成功和退出码零都不能单独证明本次运行正常。

R13 的慢响应查询、隐藏窗口恢复及更早的透明布局、最小化恢复、自动版本识别和内存暂停/恢复继续保留。普通官方版本与安装路径更新无需手改版本或哈希；身份、框架、协议或页面结构的大改仍可能需要适配，**不承诺任意未来更新都免维护**。

完整包有四个程序组件、源码、完整性清单和轻量诊断，包含全部 **46 项媒体/字体/图像素材，其中 6 个 MP4**。原素材未重新编码或降低分辨率、画质、帧率，原有透明度参数、概率及出现间隔保持不变。**不含 CC Switch**，不需要视频生成 API Key。

## 环境与兼容范围

- Windows 10/11 **x64**、.NET Framework **4.8+**、系统 Windows PowerShell **5.1**。
- 当前用户安装的官方 Microsoft Store Codex x64；壁纸支持已核验的 **Electron 私有 CDP 管道**。
- 正常 Windows 媒体组件和视频解码能力；Windows N 版需要相应媒体组件。
- 本包解压到本地可写 NTFS 文件夹，不使用网络共享、目录链接或不完整副本。官方登记安装根的受支持目录联接由身份校验单独处理。

尚未实现 Tauri/Wry/WebView2 壁纸传输。不要关闭身份校验、公开调试端口或反复管理员运行来绕过兼容错误。已知的一次独立终态布局超时尚不能归因于提前关闭，R16 没有将所有“无壁纸”都宣布为已修复；如仍失败请保留报告。

## 出问题时：一键生成报告

1. 出现问题后，到**实际运行这份程序的目录**，打开 `Diagnostics`。
2. 双击 **`One-Click-Diagnostics.cmd`**。不用先退出 Codex，不用再次启动或等待壁纸。
3. 成功后打开 `Diagnostics\Reports`：**`latest-analysis.txt`** 是中文分析；把 **`latest-report.zip`** 发给维护者。
4. 准备重试启动时先另存本次 ZIP；工具只保留最新一份。最好在故障出现后、再次关闭或启动前收集。

一键诊断默认核对**全部正式文件 SHA-256**，然后收集有界的允许日志摘要和数值环境证据；文件核验失败也会尽量生成报告。它不启动、关闭或等待应用，不联网、不安装依赖、不做 GPU/整机压力测试。完整哈希会读取视频，慢磁盘或安全软件可能延长耗时。需要停止可按 Ctrl+C 或关闭诊断窗口。

只想核对文件可运行 `Diagnostics\Check-All-Files.cmd`，一般反馈直接运行一键诊断即可。工具未完成时，旧 ZIP 不代表本次结果，请提供错误窗口截图。测试顺序、快速模式和反馈模板见 [详细教程](TROUBLESHOOTING.md)。

反馈任选一种方式：

- [GitHub Issue](https://github.com/HanwenZhang-George/codex-startup-animation/issues/new)：附 `latest-report.zip` 与故障现象。
- 邮件 [hanwen.3.zhang@kcl.ac.uk](mailto:hanwen.3.zhang@kcl.ac.uk) 或 [zhanghw0511@gmail.com](mailto:zhanghw0511@gmail.com)。

不要发送整个安装目录、原始日志、API Key、私钥、账号配置、浏览器 Cookie 或聊天记录。GitHub Issue 是公开的；截图和文字也请先检查私人信息。

## 可选：绑定原来的官方桌面图标

先确认便携运行正常，正常退出 Codex，再双击 **`Install-and-Bind.cmd`**。它将独立副本安装到 `%LOCALAPPDATA%\Programs\CodexDragonPublic`，尝试绑定当前用户桌面唯一可信的官方快捷方式，保留原名称和图标，不修改官方程序。

安装目录已存在、快捷方式不唯一或不支持时，工具会停止或保留原入口并提示。安装后在**安装目录**的 `Diagnostics` 收集报告。需要还原时运行安装目录中的 `Uninstall.ps1`，不要直接删除仍被快捷方式引用的目录。详细操作见 [安装与还原](TROUBLESHOOTING.md#可选安装后的报告位置与还原)。

## 下载核验

发布使用用户确认通过的 R16 ZIP 原字节，未再次编译、打包或修改包内诊断。包内 `test`、候选版、“尚未发布”等文字保留原样以保持哈希，当前发布状态以本页和发布页为准。

```text
公开文件名：CodexDragon-V34-Portable-Windows-x64-r5.zip
实际内容：V34-r16
程序文件版本：34.16.0.0
发布清单版本：34.4-reliability-r16-test
文件字节数：369681871
SHA-256：23243E01A53A80C7B73E5A970160D46556B7A0D727FB7991E5693EAA4268C3FF
```

附件直链也保持不变：[校验文件](https://github.com/HanwenZhang-George/codex-startup-animation/releases/download/community-v34-r5/CodexDragon-V34-Portable-Windows-x64-r5.zip.sha256)、[反馈教程](https://github.com/HanwenZhang-George/codex-startup-animation/releases/download/community-v34-r5/TROUBLESHOOTING.md)、[验证记录](https://github.com/HanwenZhang-George/codex-startup-animation/releases/download/community-v34-r5/VERIFICATION.txt)。

核验覆盖 199 项清单文件、200 项 ZIP 成员、128 份源码和全部原素材。提前关闭、晚到准备、重复启动、生命周期、慢响应、资源恢复和诊断回归通过；具体证据及限制见 [VERIFICATION.txt](VERIFICATION.txt)。用户反馈与隔离测试不代表已覆盖所有硬件、驱动和未来版本。

[分支贡献与 Pull Request 教程](CONTRIBUTING.md)。此版本不是 OpenAI 官方发行版。上游：[mytjxs/codex-startup-animation](https://github.com/mytjxs/codex-startup-animation)；社区修改与打包：HanwenZhang-George。保留上游归属与字体许可，不为第三方代码或媒体自行新增授权。

---
## 上游 v1.0.0 历史说明（仅保留原文）

以下为原作者早期版本的记录，**不是当前 R16 的下载或使用教程**。旧入口、旧文件名和旧校验值只适用于历史版本；当前使用以上社区 R16 下载链接。

<details>
<summary>展开上游历史原文</summary>

# codex启动动画

Windows Codex 龙娘启动动画安装包。横向 **16:9、2560 × 1440、60 帧/秒、8 秒**，从发光线条勾勒人物到龙娘显现、缓缓睁眼，随后打开 Codex 桌面应用。

标题为 **Chatgpt**，欢迎语为 **欢迎主人回家 / WELCOME HOME, MASTER**。

## 下载

[下载 v1.0.0 完整安装包](https://github.com/mytjxs/codex-startup-animation/releases/download/v1.0.0/codex-startup-animation-v1.0.0-win-x64.zip) · [版本下载页](https://github.com/mytjxs/codex-startup-animation/releases/tag/v1.0.0)

## 使用

1. 下载 ZIP，完整解压到固定文件夹。
2. 双击 `Start-Codex-Dragon.exe`，播放启动动画后进入 Codex。
3. 为该 EXE 创建桌面快捷方式，以后从此入口打开。
4. 只想查看动画时，双击 `Preview-Dragon.cmd`。

安装包解压即用，无需安装 Python、Node.js 或 FFmpeg。需要 Windows 10/11、.NET Framework 4.x，以及已安装的 Codex 桌面应用。保留 EXE 同目录的配置、素材和视频文件夹。

按 Esc、Enter 或空格可以跳过动画；点击关闭按钮取消本次启动。

如需调整目标应用，修改 `launcher.config.xml`。默认应用标识为 `OpenAI.Codex_2p2nqsd0c76g0!App`；本机标识不同可修改 `appUserModelId`，或填写 `executablePath`。

此启动器提供额外启动入口。从 Codex 原有图标打开时仍直接进入应用。

## 包内容与校验

完整安装包保持原样，内部包含启动器、配置、视频、角色素材、说明及源码。详细说明在压缩包中的 `README.md`。

仓库单独提供使用说明与校验信息。下载页中的 `SHA256SUMS.txt` 用于核对 ZIP 文件。

安装包 SHA-256：

```text
682928d2e6ce85bfb3d83acadb4e85da9efe4948a593a63e4dc2e605a08ff524
```

## 社区交流

社区交流：[LINUX DO](https://linux.do/)

</details>
