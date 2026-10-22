# Codex 龙娘启动动画与动态壁纸 · 社区 R9 修复版

**当前完整下载包已更新为 R9，用户已在另一台电脑完成本地实测并确认通过。** 原发布页与下载链接保持不变；链接和对外文件名中的 `r5` 是为保留原下载地址，**不代表包内仍是旧 R5 程序**。

[下载完整 Windows x64 包](https://github.com/HanwenZhang-George/codex-startup-animation/releases/download/community-v34-r5/CodexDragon-V34-Portable-Windows-x64-r5.zip) · [原发布页](https://github.com/HanwenZhang-George/codex-startup-animation/releases/tag/community-v34-r5) · [故障排查与反馈教程](TROUBLESHOOTING.md) · [验证记录](VERIFICATION.txt)

> 请下载上面的完整包。GitHub 的 **Code → Download ZIP** 和 **Source code (zip)** 只有仓库源码，不是含视频素材的完整可运行包。

## 第一次使用：无需安装脚本

1. 下载完整 ZIP，**完整解压到一个新的本地文件夹**，例如 `D:\CodexDragon-R9`。不要在 ZIP 内打开程序，也不要把新旧版本文件混在一起。
2. 确认这台电脑已安装官方 Microsoft Store Codex，并能通过官方入口正常打开和登录。
3. 保存工作，正常完整退出已运行的 Codex。只关闭窗口后仍留在后台的实例，可能尚未退出。
4. 在刚解压的文件夹中找到最外层 **`Launch.exe`**，双击运行。**无需管理员权限**，不必先运行 `Install.ps1`。
5. 检查启动画面、流泪与波纹交接，以及进入 Codex 后的壁纸、输入框透明度和正常点击/输入。

首次壁纸固定使用常态视频；之后每次出现按 **75% 常态 / 25% 粒子视频**选择，两次出现之间保留 **10–15 秒随机间隔**。人物离开后的短暂空白是正常设计，25% 也不表示每四次必有一次粒子视频。

如果启动等待明显异常，**按 ESC 跳过即可，不必等几分钟**。随后按下方步骤收集报告。ESC 跳过启动动画并保留壁纸请求；若确有资源或兼容性问题，仍需报告判断壁纸是否能恢复。

便携模式必须从这个包的 `Launch.exe` 启动。已经从官方入口打开、没有附带壁纸宿主的 Codex，不能安全地事后补上宿主；请正常退出后再从本包启动。

## 包含哪些内容

- 完整启动动画、流泪转场、常态循环视频与粒子壁纸。
- 全部 **46 项素材，其中 6 个 MP4**，以及字体、源码、程序和完整性清单。
- 常驻的轻量诊断工具，可生成中文分析和小型分享报告。
- 可选独立安装与官方桌面快捷方式绑定工具。

**不包含 CC Switch**，也不包含作者的账号、API Key、聊天记录、浏览器配置或代理设置。视频已在包内，不需要视频生成服务账号或 API Key。素材没有重新编码，画质、帧率、透明度和原有出现间隔未降低。

## R9 修复了什么

此前在部分电脑上，Windows 的低物理内存信号会触发壁纸准备阶段的终态停用：启动动画有了，壁纸却一直不出现。R9 不再把这个信号单独当作停用依据。

- 改为检查当前进程可用的提交内存余量；低于 **512 MiB** 时暂停解码，恢复至至少 **1 GiB** 并连续稳定 **30 秒**后尝试恢复同一壁纸会话。
- 暂停期间保留文件与会话，不反复注入，也不让启动画面等完这段恢复时间。只有壁纸宿主察觉压力时，也会请求释放启动动画，避免继续卡在 59%。
- 原有启动器自身资源保护、文件完整性和客户端身份校验继续保留。
- 诊断明确区分旧版永久停用、当前保护暂停、恢复请求和实际播放证据；不会把“已请求恢复”写成“已正常播放”。

这是针对已定位问题的修复，不是对所有硬件、驱动和未来 Codex 版本的兼容保证。可用提交内存也不等于空闲物理内存。

## 环境与兼容范围

- Windows 10/11 **x64**、.NET Framework **4.8 或更高版本**、系统自带的 **Windows PowerShell 5.1**。
- 当前用户安装的官方 Microsoft Store Codex x64；当前壁纸接入支持已核验的 **Electron 私有 CDP 管道**。
- 正常的 Windows 媒体组件和视频解码能力；Windows N 版还需要相应媒体组件。
- 本地可写的 NTFS 文件夹。不要使用网络盘、目录链接或不完整的解压副本。

**尚未实现 Tauri/Wry/WebView2 客户端的壁纸传输适配**。仅看到 WebView2 文件或类似界面，不能据此认定客户端是什么运行时。遇到差异请提交报告，不要关闭身份校验或开启公开调试端口。

## 出问题时：一键生成可发送的报告

1. 到**实际运行这份程序的目录**，打开 `Diagnostics` 文件夹。
2. 双击 **`One-Click-Diagnostics.cmd`**。
3. 成功后打开其中的 `Reports` 文件夹：
   - **`latest-analysis.txt`**：先看中文分析。
   - **`latest-report.zip`**：把这个 ZIP 发给维护者即可。
4. 怀疑文件缺失或解压不全时，可先双击 `Diagnostics\Check-All-Files.cmd`；完成后再运行 `One-Click-Diagnostics.cmd`，把核验摘要纳入报告。

诊断读取已有的有限日志、允许的兼容性信息和素材存在性/大小，**不启动、不关闭、不等待应用，不联网，也不做 GPU 或整机压力测试**。通常是几秒级的本地读取，实际耗时取决于磁盘等环境；完整哈希校验会读取全部文件。快速报告的“素材存在”不等于哈希或解码验证。

报告只保留最新一份，不堆积历史 ZIP。窗口若显示工具未完成，已有 ZIP 可能是上次结果，请发错误窗口截图，不要把旧报告当成新报告。完整路径说明、可复制的反馈模板和常见问题见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)。

**反馈任选一种方式：**

- [在本仓库新建 GitHub Issue](https://github.com/HanwenZhang-George/codex-startup-animation/issues/new)，附上 `latest-report.zip` 和故障现象。
- 邮件发送到 [hanwen.3.zhang@kcl.ac.uk](mailto:hanwen.3.zhang@kcl.ac.uk) 或 [zhanghw0511@gmail.com](mailto:zhanghw0511@gmail.com)，任选一个即可。

不要发送整个安装包、原始日志、私钥、API Key、账号配置、聊天记录或整个 `.codex` 目录。截图也请先遮住私人内容。

## 可选：从原来的官方桌面图标启动

先按上面的便携步骤确认工作正常，再正常退出 Codex，双击包内 **`Install-and-Bind.cmd`**。它会安装独立副本，并尝试绑定当前用户桌面唯一可信的官方 Codex 快捷方式，保留原名称和图标；不修改官方 Codex 可执行文件。

默认安装位置是 `%LOCALAPPDATA%\Programs\CodexDragonPublic`。若安装目录已存在、快捷方式不唯一或类型不支持，工具会停止或保留原入口并提示；不要为绕过检查而删除不明文件。安装后请使用**安装目录里的 `Diagnostics`**，不要收集旧解压目录的报告。

需要撤销绑定时，使用安装目录中的 `Uninstall.ps1` 还原原快捷方式，再移除安装；不要直接删除仍被快捷方式引用的目录。详细操作见 [故障排查教程](TROUBLESHOOTING.md#可选安装后的报告位置与还原)。

## 下载核验与验证边界

本次公开 ZIP 与用户实测通过的 R9 测试 ZIP **字节完全一致，没有重打包**。包内 `test`、候选版或“尚未发布”等文字保留原样以保持哈希；当前发布状态以本页和原发布页为准。

```text
公开文件名：CodexDragon-V34-Portable-Windows-x64-r5.zip
实际内容版本：V34-r9
文件字节数：369184032
SHA-256：9BC3C666A2803B4853378CC984EDDF54FEBF0FEB68D5ABE1E2B5742199D8B3A5
```

除用户跨电脑实测外，本次完成 16 套隔离测试、155 项发布清单文件与 156 项 ZIP 文件核对；46 项素材及其中 6 个视频哈希保持不变。隔离测试不等于穷尽所有系统和显卡组合，文件哈希通过也不证明每台电脑都能顺畅解码。更多范围见 [VERIFICATION.txt](VERIFICATION.txt)。

[参与贡献：Fork、分支与 Pull Request 操作说明](CONTRIBUTING.md)。使用问题请提交 Issue；代码修改通过 PR 审查后合并。

此社区版本不是 OpenAI 官方发行版。贡献者：HanwenZhang-George。保留原项目和字体来源，不为上游代码或媒体自行新增授权。

---

## 上游 v1.0.0 历史说明（仅保留原文）

以下为原作者早期版本的记录，**不是当前 R9 的下载或使用教程**。旧入口、旧文件名和旧校验值只适用于历史版本；当前使用以上社区 R9 下载链接。

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
