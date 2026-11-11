# Codex Dragon for Mac

Mac 原生启动器与 Codex 内动态壁纸。保留 R16 的原版视频、常态／粒子轮换、10–15 秒间隔、26% 人物透明度与输入框玻璃效果；新增 Mac 菜单栏控制。采用 AppKit、AVFoundation 和官方客户端内置的签名运行组件，无需另装 Python、Node、FFmpeg 或申请辅助功能权限。

## 使用

1. 首次使用前保存工作，使用 Cmd+Q **完整退出 Codex／ChatGPT**，然后打开 `Codex Dragon.app`。
2. 启动动画与流泪片段播放后进入 Codex，准备完成的动态壁纸开始显示。
3. Esc、空格、回车或画面右上角的“跳过”跳过动画，壁纸仍继续准备。
4. 菜单栏 **龍** 提供重播、暂停、继续、恢复原界面和退出。恢复后可再次“启用／继续壁纸”。
5. 双击 `Preview.command` 仅预览动画，不启动或连接 Codex。
6. 可把此应用拖入 Dock。再次打开同一启动器会重播动画并复用已有壁纸会话；官方图标仍直接进入应用。

如果 Codex 已从普通入口运行，启动器仍播放动画并回到已有窗口，菜单栏提示完整退出后重开，以便建立壁纸连接；不会强行结束会话。默认静音。遵循系统“减弱动态效果”跳过启动动画；显式预览仍播放。

首轮固定常态视频，以后每轮独立按 75% 常态／25% 粒子选择，两轮之间随机等待 10–15 秒。窗口隐藏或内存压力期间暂停解码；用户暂停通过“继续壁纸”恢复。人物暂时不出现属于间隔设计。

## 兼容与实现

### ChatGPT 图标入口与启动回退

可选安装 `~/Applications/ChatGPT.app` 作为同名图标入口，使用官方图标，身份为 `local.codex-dragon.chatgpt-entry`。只有显式运行绑定脚本才会修改 Dock；普通安装不添加桌面快捷方式或更改 Dock。官方程序保持原安装位置，不修改其文件或注册协议。

该入口独立于动画启动器。启动器不存在、无法运行或提前退出时直接打开官方应用；五秒内未观察到官方进程时也会尝试普通启动。配置损坏自动使用默认设置；视频缺失或播放失败直接进入应用；壁纸准备不会无限阻塞应用交接。正常动画仍需要播放时间，可随时跳过。

绑定：`./macos/scripts/build-entry.sh && ./macos/scripts/bind-chatgpt-dock.sh`。构建脚本自动寻找 Codex.app / ChatGPT.app，也可传入安装路径。还原 Dock：`./macos/scripts/bind-chatgpt-dock.sh --restore`。还原只处理本入口，并保留之后对其他 Dock 图标的修改。升级动画启动器可用 `./macos/scripts/install.sh --update`，旧版先备份后替换。点击运行中的官方应用图标或直接打开原版应用，仍直接进入官方应用。

macOS 13+，包含 Apple Silicon 与 Intel 两种架构。本机验证是 Apple Silicon、macOS 26.6.2；Intel 仅交叉编译，没有实机验收。

通过 `com.openai.codex` 识别官方客户端，包括保留该身份的 `ChatGPT.app`。壁纸需要安装包中的签名运行组件 `Contents/Resources/cua_node/bin/node`；校验 OpenAI Team ID `2DC432GLL2` 后才使用。缺失组件、登录页或未知布局时保留原界面。当前 Mac 157 客户端的独立组件哈希类名已适配，也兼容上游旧式类名；未来大改可能需要更新。

通过 Chromium 私有双向管道连接自己启动的客户端，**不开放调试端口**，不修改官方 `.app`、`app.asar` 或签名。仅上传打包视频并设置主题样式，不读取聊天文本或账户资料。退出启动器时移除样式并保留 Codex；轻量管道助手继续排空连接，直到 Codex 退出，避免断开管道导致官方应用退出。

Mac 转场使用原版流泪视频与原生波纹淡出；Windows 的 WPF 窗口交接由 Mac 原生窗口与 Launch Services 替代。Windows EXE、Store 快捷方式绑定、诊断脚本不在 Mac 上运行。

## 从源码构建

需要 Apple Command Line Tools（Swift 与 Python 3）：

```sh
xcode-select --install
./macos/scripts/build.sh
./macos/scripts/test.sh
./macos/scripts/install.sh
./macos/scripts/package.sh
```

首次下载约 370 MB 的 R16 发布包，只提取六段原版视频，不运行 Windows 程序。发布包和所有视频分别校验 SHA-256；不重新编码、降分辨率或帧率。已有发布包可执行 `./macos/scripts/build.sh /path/to/release.zip`。成品运行不需要构建工具或联网下载素材。

构建产物：`macos/dist/Codex Dragon.app`；安装位置：`~/Applications/Codex Dragon.app`；分享包：`macos/dist/Codex-Dragon-macOS-universal.zip`。安装脚本遇到已有应用时停止。退出启动器后移除该应用即可卸载。构建使用本机临时签名，没有 Apple Developer ID 公证；发到其他 Mac 时需由接收者按系统提示允许打开。

## 配置与检查

默认无需配置。可将 `config.example.json` 复制到 `~/Library/Application Support/Codex Dragon/config.json`：`applicationPath` 指定安装位置，`muted` 控制静音，`respectReducedMotion` 控制减弱动态效果，`wallpaperEnabled` 控制壁纸。

```sh
"$HOME/Applications/Codex Dragon.app/Contents/MacOS/CodexDragon" --diagnose
```

诊断验证目标与签名运行组件，读取视频轨道并实际解码一帧，不连接或关闭 Codex。开发验证可附加 `--test-report /tmp/codex-dragon-test.log`，仅记录播放与交接事件。壁纸状态只输出固定的布局、媒体枚举和数值，不输出 DOM、标题或聊天。

开发回归另需 `cd macos && npm ci`。回到仓库根后运行 `./macos/scripts/test-renderer.sh`，使用本机 Chrome 的隔离离线实例。`node macos/tests/pipe-smoke.mjs /path/to/Codex.app/Contents/MacOS/Codex --wallpaper` 使用单独的临时用户目录测试官方客户端，不关闭原会话；测试期间出现隔离窗口，结束后关闭测试实例。

无需安装官方客户端的检查：构建后运行 `./macos/scripts/test.sh --offline`，只验证原生 bundle、双架构与媒体解码。`python3 macos/tests/dock-binding.py` 使用临时应用元数据与专用偏好域，检查绑定和还原，不修改真实 Dock。GitHub Actions 运行这些检查及旧式／新版 Mac 类名的离线渲染回归。`--diagnose-media` 也可单独验证视频而不查询客户端或用户配置。

## 归属

来源：mytjxs/codex-startup-animation；R16 社区代码、素材与发布：HanwenZhang-George/codex-startup-animation。Mac 原生启动器、管道适配与新版类名兼容是本地新增实现。Mac 渲染器基于 `community-v34/renderer.js`，保留媒体行为与无障碍样式。保留原作者归属，不为上游代码与媒体另行声明授权。本项目不是 OpenAI 官方发行版。
