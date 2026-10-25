[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$WorkRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$tools=Join-Path (Split-Path -Parent $PSScriptRoot) 'packaging'
. (Join-Path $tools 'DiagnosticReport.Common.ps1')
. (Join-Path $tools 'DiagnosticAnalysis.ps1')
if($PSVersionTable.PSVersion.Major -ne 5){throw 'Requires Windows PowerShell 5.1'}
[void][IO.Directory]::CreateDirectory($WorkRoot)
$script:checks=0
function Check([bool]$Value,[string]$Name){if(-not $Value){throw ('FAIL '+$Name)};$script:checks++}
function Stamp([int]$Second){return ([datetime]::new(2026,1,1,12,0,0,[DateTimeKind]::Utc)).AddSeconds($Second).ToString('o')}
function Entry([int]$Second){return [pscustomobject]@{utc=(Stamp $Second);category='launcher-stage';stage='launcher-entry'}}
function Skip([int]$Second,[string]$Source='movie-button',[string]$Intent='reveal',[string]$Activation='True'){return Convert-FixLogEvent ((Stamp $Second)+' animation-skip source='+$Source+' wallpaperIntent='+$Intent+' activationRequested='+$Activation) 'output/handoff-latest.log'}
function Phase([int]$Second,[int]$Phase,[int]$Code=0,[int]$Run=1){return [pscustomobject]@{utc=(Stamp $Second);category='host-phase';phase=$Phase;code=$Code;hostRunOrdinal=$Run}}
function Layout([int]$Second){$r=Phase $Second 38;$r|Add-Member sourcePhase 6;$r|Add-Member layoutSupported 0;$r|Add-Member layoutReason 'main-count';return $r}
function Report($Launcher,$HostEvents=@()){return [pscustomobject]@{logs=@([pscustomobject]@{log='output/handoff-latest.log';records=@($Launcher)},[pscustomobject]@{log='output/wallpaper-readiness.log';records=@($HostEvents)})}}
$sample=Skip 2
Check ($null -ne $sample -and $sample.category -ceq 'animation-skip' -and $sample.source -ceq 'movie-button' -and $sample.wallpaperIntent -ceq 'reveal' -and $sample.activationRequested -eq 1) 'fixed dismissal fields retained'
foreach($source in @('keyboard','movie-button','pulse-button','window-close','resource-protection','compatibility-fallback')){Check ((Skip 2 $source).source -ceq $source) ('source enum '+$source)}
foreach($intent in @('reveal','disabled','preserve','none')){Check ((Skip 2 'keyboard' $intent).wallpaperIntent -ceq $intent) ('intent enum '+$intent)}
$line=(Stamp 2)+' animation-skip source=window-close wallpaperIntent=reveal activationRequested=True'
$private=Convert-FixLogEvent ($line+' title=PRIVATE_TITLE key=PRIVATE_KEY path=PRIVATE_PATH token=PRIVATE_TOKEN pid=432123') 'output/handoff-latest.log'
Check (($private|ConvertTo-Json -Compress) -notmatch 'PRIVATE|432123|title|path|token|pid') 'private extra fields dropped'
foreach($source in @('diagnostics/portable-launch.log','output/wallpaper-readiness.log','output/launcher-error.txt')){Check ($null -eq (Convert-FixLogEvent $line $source)) ('wrong source rejected '+$source)}
foreach($tail in @(' source=PRIVATE wallpaperIntent=PRIVATE activationRequested=PRIVATE',' source=window-close wallpaperIntent=reveal activationRequested=True')){
    $bad=Convert-FixLogEvent ($line+$tail) 'output/handoff-latest.log'
    Check ($bad.source -ceq 'unknown' -and $bad.wallpaperIntent -ceq 'unknown' -and $bad.activationRequested -eq -1) 'duplicate fields unknown'
}
$bad=Skip 2 'PRIVATE_SOURCE' 'PRIVATE_INTENT' 'true'
Check ($bad.source -ceq 'unknown' -and $bad.wallpaperIntent -ceq 'unknown' -and $bad.activationRequested -eq -1) 'unknown and malformed fields unknown'
$current=@((Entry 0),(Skip 3),[pscustomobject]@{utc=(Stamp 4);category='launcher-cleanup-complete'})
$hostEvents=@((Phase 1 20),(Layout 2),(Phase 5 13),(Phase 6 15 202))
$text=Get-CodexDiagnosticAnalysis (Report $current $hostEvents) $null
Check ($text.Contains('动画按钮') -and $text.Contains('保留壁纸显示意图') -and $text.Contains('不是壁纸播放成功') -and -not $text.Contains('当时确认了首帧')) 'dismissal intent is not playback proof'
Check ($text.Contains('准备中的布局采样尚未就绪') -and -not $text.Contains('最新有效记录：页面布局未满足')) 'interrupted preparation is not terminal layout failure'
$legacy=@((Entry 0),[pscustomobject]@{utc=(Stamp 4);category='launcher-cleanup-complete'})
$text=Get-CodexDiagnosticAnalysis (Report $legacy $hostEvents) $null
Check ($text.Contains('准备阶段提前清理') -and $text.Contains('没有记录关闭来源') -and -not $text.Contains('用户点击')) 'legacy cleanup evidence is cautious'
$text=Get-CodexDiagnosticAnalysis (Report $current @((Phase 1 20),(Layout 2),(Phase 15 6 166),(Phase 16 15 166))) $null
Check ($text.Contains('最新有效记录：页面布局未满足') -and -not $text.Contains('准备阶段提前清理')) 'actual HOST166 survives dismissal intent'
$old=@((Phase -20 20 0 2),(Phase -7 6 166 2),(Phase -6 15 166 2))
$text=Get-CodexDiagnosticAnalysis (Report $current ($old+$hostEvents)) $null
Check ($text.Contains('较早宿主记录') -and $text.Contains('166') -and $text.Contains('准备中的布局采样尚未就绪')) 'old timeout separated from latest incomplete preparation'
$text=Get-CodexDiagnosticAnalysis (Report @((Entry 0),(Skip 3),(Entry 10))) $null
Check (-not $text.Contains('本次动画提前结束')) 'new entry retires old dismissal'
$text=Get-CodexDiagnosticAnalysis (Report @((Skip 3))) $null
Check (-not $text.Contains('本次动画提前结束')) 'no entry cannot associate dismissal'
$text=Get-CodexDiagnosticAnalysis (Report @((Entry 0),$bad)) $null
Check ($text.Contains('动画结束记录字段不完整') -and $text -notmatch 'PRIVATE') 'malformed current dismissal safe'
$text=Get-CodexDiagnosticAnalysis (Report @((Entry 0),(Skip 3),(Skip 3 'window-close'))) $null
Check ($text.Contains('动画结束记录冲突') -and -not $text.Contains('本次动画提前结束')) 'same-time conflict unknown'
$text=Get-CodexDiagnosticAnalysis (Report @((Entry 0),(Skip 3),(Skip 3))) $null
Check ($text.Contains('本次动画提前结束') -and -not $text.Contains('记录冲突')) 'identical duplicate harmless'
foreach($case in @(@('disabled','保留已有禁用状态'),@('preserve','保留现有壁纸会话状态'),@('none','未请求壁纸显示'))){
    $text=Get-CodexDiagnosticAnalysis (Report @((Entry 0),(Skip 3 'keyboard' $case[0] 'False'))) $null
    Check ($text.Contains($case[1]) -and -not $text.Contains('当时确认了首帧')) ('state preserved '+$case[0])
}
$text=Get-CodexDiagnosticAnalysis (Report @((Entry 0),(Skip 3 'resource-protection'))) $null
Check ($text.Contains('资源保护') -and -not $text.Contains('用户提前结束')) 'resource event not called user input'
$text=Get-CodexDiagnosticAnalysis (Report @((Entry 0),(Skip 3 'compatibility-fallback'))) $null
Check ($text.Contains('兼容路径回退') -and -not $text.Contains('用户提前结束')) 'compatibility fallback not called user input'
$wrong=Report @((Entry 0)) @((Skip 3))
Check (-not (Get-CodexDiagnosticAnalysis $wrong $null).Contains('本次动画提前结束')) 'host stream cannot inject dismissal'
$duplicate=Report $current $hostEvents;$duplicate.logs+= [pscustomobject]@{log='output/handoff-latest.log';records=$current}
Check (-not (Get-CodexDiagnosticAnalysis $duplicate $null).Contains('本次动画提前结束')) 'duplicate authoritative streams rejected'
$oldPollution=@((Phase -10 20),(Layout 2),(Phase 5 13),(Phase 6 15 202))
Check (-not (Get-CodexDiagnosticAnalysis (Report $legacy $oldPollution) $null).Contains('准备阶段提前清理')) 'old host cannot establish current cleanup association'
$late=@((Phase 1 20),(Layout 2),(Phase 5 13),(Phase 6 15 202),(Phase 7 7))
Check (-not (Get-CodexDiagnosticAnalysis (Report $legacy $late) $null).Contains('准备阶段提前清理')) 'later preparation evidence prevents incomplete-cleanup inference'
$badTime=Skip 3;$badTime.utc='2026-01-01T12:00:99Z PRIVATE'
Check (-not (Get-CodexDiagnosticAnalysis (Report @((Entry 0),$badTime)) $null).Contains('本次动画提前结束')) 'invalid time cannot establish dismissal'
$large=Report @((Entry 0),(Skip 3));$large.logs[0].records=@(1..513|ForEach-Object {Skip 3})
Check (-not (Get-CodexDiagnosticAnalysis $large $null).Contains('本次动画提前结束')) 'bounded stream enforced'
$playing=Phase 7 39
foreach($name in @('generationMatches','attached','mediaReady','wallpaperApplied','firstFrameConfirmed','layoutSupported','revealed','stageVisible','commitAccepted','playing')){$playing|Add-Member $name 1}
$playing|Add-Member protocolVersion 2;$playing|Add-Member health 'fresh';$playing|Add-Member disposed 0;$playing|Add-Member documentHidden 0;$playing|Add-Member actualPhase 'visible'
$text=Get-CodexDiagnosticAnalysis (Report $current @((Phase 1 20),(Layout 2),$playing)) $null
Check ($text.Contains('当时确认了首帧') -and $text.Contains('保留壁纸显示意图')) 'late actual playback after dismissal is independently recognized'
$text=Get-CodexDiagnosticAnalysis (Report $current @((Phase -10 20),$playing)) $null
Check (-not $text.Contains('当时确认了首帧') -and $text.Contains('未把旧宿主播放')) 'old continuing host playback cannot confirm new dismissal'
[IO.File]::WriteAllText((Join-Path $WorkRoot 'results.json'),(@{passed=$true;checks=$checks}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
Write-Output ('ALL PASS: early dismissal diagnostics '+$checks)
