## V34-r5 社区修复版：完整启动动画与动态壁纸

**请下载 r5；旧 r2 已撤回，避免继续遇到跨电脑启动失败和 59% 长时间等待。**

[下载完整 Windows x64 包](https://github.com/HanwenZhang-George/codex-startup-animation/releases/download/community-v34-r5/CodexDragon-V34-Portable-Windows-x64-r5.zip) · [发布说明与 SHA-256](https://github.com/HanwenZhang-George/codex-startup-animation/releases/tag/community-v34-r5) · [验证记录](VERIFICATION.txt)

完整解压到新目录，保存工作并正常退出已运行的 Codex，然后双击最外层 **Launch.exe**。不用先运行安装脚本。**Code → Download ZIP / Source code ZIP 只有源码，不是完整可运行包。**

完整包包含全部 46 项原始素材、其中 6 个 MP4、两种动态壁纸、流泪转场、字体、源码和四个程序，不包含 CC Switch。素材质量和原有动画效果未降低。需要 Windows 10/11 x64、.NET Framework 4.8、Windows PowerShell 5.1、正常媒体组件，以及本机已安装并登录的官方 Microsoft Store Codex x64。

本次公开包与另一台电脑上用户确认可用的 r5 测试 ZIP **字节完全一致**，仅对外文件名去掉 `-test`。为保留原包哈希，包内候选版/等待测试字样未重写；当前发布状态以本页面和 Release 说明为准。`community-v34/` 保留包内源码原字节，实际验证范围和兼容性限制见 [VERIFICATION.txt](VERIFICATION.txt)。

首次使用常态壁纸，之后 75% 常态 / 25% 粒子视频，两次出现间隔 10–15 秒。该社区包通过 Launch.exe 启动，不替换官方图标，不带作者账号、API Key 或私人配置，也不是 OpenAI 官方发行版。贡献者：HanwenZhang-George；保留原项目及字体来源，不为上游代码和媒体新增授权。

遇到问题可在解压目录运行 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Collect-DiagnosticReport.ps1"`。它只收集固定字段的脱敏报告，不启动、关闭或等待应用。请勿上传账号配置或整个运行目录。

---

以下保留原项目 v1.0.0 的历史说明；上面的 r5 链接是此社区版本的当前下载入口。

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
