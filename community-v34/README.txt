Codex Dragon — community startup animation and dynamic wallpaper
Portable V34-r9 memory policy candidate for Windows 10/11 x64

STATUS
This candidate corrects a second memory gate in wallpaper preparation. A Windows
low-physical-memory notification or a low RAM reading no longer disables playback
when the current process still has sufficient available commit. Critical commit
below 512 MiB suspends the decoder; recovery requires at least 1 GiB of available
commit for 30 continuous seconds. It resumes the same file/document attachment,
without repeating installation or making the launcher wait for that recovery.
This is a conservative headroom policy, not a guarantee against every allocation
failure. Startup process caps, signed-client checks and file hashes remain intact.
No original media, resolution, frame rate, appearance interval or opacity changed.

This directory is a publication candidate, not a statement that a GitHub release
has already been published. No upstream project-code license was found; this
candidate does not invent a license for upstream code or media. The contributor
has requested submission of the customization and generated media for review;
the maintainer still needs to clarify distribution terms. This is not an official
OpenAI product.

GET THE COMPLETE PACKAGE
Download the complete CodexDragon ZIP from this repository's Releases section.
The complete package includes all videos, high-resolution character assets,
font, source, executables, installation scripts and an integrity manifest.
GitHub's green "Code > Download ZIP" contains source only. It is not a ready-to-run
wallpaper distribution. Large media is kept out of ordinary Git history.
Nothing is re-encoded or downloaded during installation. No API key is required
for the pre-generated videos. Both wallpaper clips are included in the user ZIP.

REQUIREMENTS
- Windows 10/11 x64, .NET Framework 4.8 or later, Windows PowerShell 5.1.
- The current user's official Microsoft Store Codex x64 application.
  The host currently supports the verified Electron application with its private
  CDP pipe. Similar DOM markup does not imply Tauri/Wry/WebView2 transport support.
- Normal Windows media components. Windows N editions need Microsoft's Media
  Feature Pack. GPU drivers must support the video's playback format; no promise
  is made that every driver/hardware combination can sustain 144 fps.
- A local writable NTFS folder, not a network share or a linked/junction folder.
  Extract the ZIP completely before opening any EXE. Do not run inside the ZIP.
- Sign in to Codex normally using the official app. This package never needs or
  contains the author's account, API key, cookies, browser profile or proxy data.

INSTALL AND USE
1. Extract the entire release ZIP to a new local folder. Do not mix versions.
2. Open Windows PowerShell (powershell.exe), change to that extracted folder and
   run: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
   This installs into %LOCALAPPDATA%\Programs\CodexDragonPublic. It never replaces
   an existing destination. Use -Destination "D:\Apps\CodexDragonPublic" for a new
   folder. No administrator rights are needed for a user-owned location.
   Optional: add -CreateDesktopShortcut to create a NEW community shortcut.
   Alternatively double-click Install-and-Bind.cmd to install and bind the
   unique verified official Codex shortcut on the current user's desktop.
   These two shortcut options are mutually exclusive. Normal launches need no UAC.
3. Save your work and normally exit the official Codex app for first integration.
4. Open Launch.exe in the installed folder. The entry is a windowless WinExe;
   no console is intentionally created. If preparation fails, a concise error
   explains the problem instead of leaving an unresponsive launch request.
5. Open WallpaperControls.exe to pause/resume, inspect, or disable the wallpaper.
   Launch.exe --preview previews the startup without starting or controlling Codex.

You may also use Launch.exe from the fully extracted release without installation.
Keep the complete folder together and writable. Install.ps1 is useful for owning
an isolated copy and providing a narrowly scoped uninstall operation.

OFFICIAL ICON AND WARM STARTS
The public package does not patch the official Codex executable, add a registry
hook, install a service or change startup tasks. Launch.exe is the portable entry.
Optional -BindOfficialDesktopShortcut (Install-and-Bind.cmd) backs up and binds
the unique verified current-user official desktop shortcut to the installed
Launch.exe. The original name and icon are preserved. Public-desktop, ambiguous,
unsupported or modified links are left alone. This is per-user installation,
with no automatic elevation or run-as-administrator flag for everyday use.
Use the installed Uninstall.ps1 to restore the verified original shortcut before
removing the installation. Never delete the installed directory while its shortcut
is bound. If ownership checks fail, preserve the files and resolve the conflict.
If Codex is already running, Launch.exe replays the existing-start flow. A running
Codex that was started without the wallpaper host cannot safely gain the host
after the fact: exit it normally and launch through Launch.exe next time.
ESC skips the startup animation; the original host flow retains the wallpaper.
The r7 replay path requests only read/query and synchronization process rights,
while retaining process-generation, registered-package and executable checks.
It records fixed diagnostic stages when discovery or attestation is rejected.
One tested ACL failure is corrected; the remote machine must still validate the
actual repeated-click behavior. No claim is made that all warm starts are fixed.

RESOURCE PROTECTION
When startup resource protection trips, r8 releases the optional animation and
retains the wallpaper reveal request, including for a late bridge session. This
is not a successful animated handoff and does not override an earlier disable.
The original thresholds and independent wallpaper-host protection remain in
force. Persistent resource pressure can still prevent playback. Diagnostics
distinguish the request to continue from proof of actual video playback.
Launch.exe normally runs without administrator privileges; no UAC prompt is
expected. Elevation is not a substitute for diagnosing an unavailable wallpaper.

WHAT IS PRESERVED
- Original startup artwork, living blinks, tear/impact transition and typography.
- The normal wallpaper appears first on each hosted app start.
- Thereafter each new appearance draws 75% normal / 25% particle video.
- The existing random 10–15 second gaps and transparent readable interface.
- Existing bounded failure handling, visibility pause/recovery and resource guards.
- All video pixels/frame rates remain the delivered originals.

PORTABILITY AND UPDATES
Launch.exe discovers the registered official Store package on the target PC,
verifies its OpenAI signature and writes local media paths plus the executable
hash to wallpaper-host-config.json. It rechecks registration on subsequent starts
so this package contains no fixed username, drive, workspace or official version.
A currently running registered package is preferred for the warm-start flow.
This does not prove future Codex layouts are compatible. If a future update
changes the DOM or transport, the wallpaper may decline to attach. Use the official
app normally and report the failure; do not disable signature/path checks.
The original source was developed against Codex 26.1007.9446.0. The r6 audit also
found Electron runtime files in registered Codex 26.1016.6573.0; this inventory
does not prove every version/distribution uses Electron. Fresh builds and
isolated configuration tests do not replace tests on a genuinely separate PC.

FAILURE AND PRIVACY BOUNDARIES
The wallpaper uses Codex's existing renderer and a private local debugging pipe.
It does not listen on a public TCP debugging port, replace TLS settings, read
account files, upload logs or send data to a new service. The official Codex app
continues its own normal network/account behavior.
Wallpaper and Codex still share some renderer/GPU/process failure boundaries.
A hard host crash/forced termination can affect the hosted client; do not kill
WallpaperHost.exe while using Codex. "Perfect isolation" or days-long stability
on every machine is not claimed. Save work before a normal restart or upgrade.
Local diagnostics may contain process/window details and locally generated paths.
Do not upload an entire installed folder, output folder, config, or process dump
as a bug report. Collect-DiagnosticReport.ps1 exports only bounded allowlisted
fields, numeric versions, known file marker presence and six fixed media roles.
It never exports raw paths, titles, messages, account files or process command
lines. Compatibility markers are evidence, not a transport-support guarantee.
The quick report checks media sizes only; use the independent local test helper
or Test-PublicPackage.ps1 for full SHA-256 verification. No tool waits for playback.
The permanent Diagnostics folder provides One-Click-Diagnostics.cmd, with fixed
Reports/latest-report.zip and Reports/latest-analysis.txt outputs. It overwrites
only these latest report outputs instead of accumulating archives. Its default
mode reads bounded records and runs no GPU test, application launch, install or
network operation. Check-All-Files.cmd is an optional full hash verification.
Only the report ZIP should be shared; generated Reports are excluded from release.

VERIFY / REBUILD
The release-manifest.json inventory covers the full package and all media.
From the source tree, run:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-PublicPackage.ps1 -ReleaseRoot "D:\Downloads\CodexDragon"
Build offline from these sources using the complete media tree:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build.ps1 -MediaRoot "D:\Downloads\CodexDragon" -OutputDirectory "D:\Build\CodexDragon-new"
Use a new output path. No former local installation, old V27/V33 receipt, cached
SDK or author's workspace is used. Windows' installed .NET compiler is required.
The build is reproducible from declared inputs, but binary byte determinism is
not claimed for the legacy framework compiler. Successful compilation verifies
framework metadata and then hashes the complete output closure.
Source-only clones need the corresponding complete release/media bundle; the
build stops on missing/corrupt media instead of silently creating a broken ZIP.
Source-only licensing text is not permission to redistribute every media asset.

UNINSTALL / UPGRADE
Close this installed launcher, wallpaper controls and normally exit the Codex it
hosts. Run powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1
inside the installed folder. It removes only manifest-owned files whose bytes
still match, and its own unchanged optional shortcut. Modified files and logs are
retained. -RemoveGeneratedConfiguration also removes the local host configuration.
It will not kill clients, modify the official app or recursively erase unknown
files. For an upgrade, extract/install into a NEW folder first, then retire the
old public install after normally closing it. Your existing custom installation
is never overwritten or automatically migrated.

ATTRIBUTION
Upstream: https://github.com/mytjxs/codex-startup-animation
Customization and release packaging: HanwenZhang-George (GitHub).
See SOURCE-PROVENANCE.txt in source/ and FONT-LICENSE.txt. Project-code and media
licenses are not silently replaced by the public packaging work.
