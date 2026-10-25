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
function Entry([int]$Second){return [pscustomobject]@{utc=(Stamp $Second);category='launcher-stage';stage='launcher-entry';elapsedMs=0}}
function Handoff([int]$Second){return [pscustomobject]@{utc=(Stamp $Second);category='handoff-complete';success=1;replayExisting=1;wallpaperCommitConfirmed=0;wallpaperPlaybackRequiresObserver=0}}
function Route([int]$Second,[string]$Decision,[string]$Reason,[string]$HostState,[int]$Activations=0){return Convert-FixLogEvent ((Stamp $Second)+' warm-start decision='+$Decision+' reason='+$Reason+' elapsedMs=100 activationCount='+$Activations+' hostState='+$HostState) 'output/handoff-latest.log'}
function Report($Launcher,$HostEvents=@()){return [pscustomobject]@{logs=@([pscustomobject]@{log='output/handoff-latest.log';records=@($Launcher)},[pscustomobject]@{log='output/wallpaper-readiness.log';records=@($HostEvents)})}}
function Playing([int]$Second){return [pscustomobject]@{utc=(Stamp $Second);category='host-phase';phase=39;code=0;generationMatches=1;protocolVersion=2;health='fresh';attached=1;disposed=0;mediaReady=1;playing=1;wallpaperApplied=1;firstFrameConfirmed=1;layoutSupported=1;revealed=1;documentHidden=0;stageVisible=1;commitAccepted=1;actualPhase='visible';hostRunOrdinal=1}}

# Entirely synthetic timeline: fifteen clicks, nine unavailable windows, one
# skip and five replay handoffs. No user timestamps, paths or report content.
$fixture=@()
for($n=1;$n -le 15;$n++){
    $at=($n-1)*20;$fixture+=Entry $at
    if($n -in @(1,2,5,6,7,9,10,11,14)){$fixture+=[pscustomobject]@{utc=(Stamp ($at+1));category='launcher-stage';stage='replay-target-unavailable-no-activation';elapsedMs=25}}
    elseif($n -eq 4){$fixture+=[pscustomobject]@{utc=(Stamp ($at+8));category='animation-skipped'}}
    else{$fixture+=Handoff ($at+9)}
}
$text=Get-CodexDiagnosticAnalysis (Report $fixture) $null
Check ($text.Contains('仅完成动画及窗口交接') -and $text.Contains('没有新建壁纸准备') -and $text.Contains('不能证明既有壁纸正在播放')) 'synthetic fifteen-click replay never claims wallpaper success'
$history=@(Get-CodexStartupHistoryAnalysis (Report $fixture)) -join "`n"
Check (([regex]::Matches($history,'启动尝试 \d+').Count -eq 8) -and $history.Contains('最近 8 次') -and $history.Contains('启动尝试 15')) 'synthetic fifteen-click history remains bounded and latest'
Check (([regex]::Matches($history,'仅完成动画及窗口交接').Count -eq 4) -and ([regex]::Matches($history,'重播未找到合格窗口').Count -eq 4)) 'last eight synthetic attempts retain four replay successes and four refusals'
$current=@((Entry 0),(Handoff 9))
$oldHost=@([pscustomobject]@{utc=(Stamp -10);category='host-phase';phase=20;code=0;hostRunOrdinal=1},(Playing 10))
$text=Get-CodexDiagnosticAnalysis (Report $current $oldHost) $null
Check ($text.Contains('仅完成动画及窗口交接') -and -not $text.Contains('当时确认了首帧') -and -not $text.Contains('历史快照确认过壁纸显示')) 'old continuing host cannot supply replay click playback proof'
$text=Get-CodexDiagnosticAnalysis (Report ($current+@(Entry 20)) $oldHost) $null
Check ($text.Contains('没有可解释的本次运行状态记录')) 'new entry retires previous animation-only current state'

$line=(Stamp 1)+' warm-start decision=activate reason=no-window elapsedMs=250 activationCount=1 hostState=unchecked'
$event=Convert-FixLogEvent $line 'output/handoff-latest.log'
Check ($null -ne $event -and $event.category -ceq 'warm-start' -and $event.decision -ceq 'activate' -and $event.reason -ceq 'no-window' -and $event.elapsedMs -eq 250 -and $event.activationCount -eq 1 -and $event.hostState -ceq 'unchecked') 'fixed warm-start route fields retained'
foreach($source in @('diagnostics/portable-launch.log','output/wallpaper-readiness.log','output/wallpaper-readiness.log.1','output/launcher-error.txt')){Check ($null -eq (Convert-FixLogEvent $line $source)) ('warm route source restricted '+$source)}
$private=Convert-FixLogEvent ($line+' path=PRIVATE_PATH token=PRIVATE_TOKEN pid=432123 account=PRIVATE_ACCOUNT') 'output/handoff-latest.log'
Check (($private|ConvertTo-Json -Compress) -notmatch 'PRIVATE|432123|path|token|pid|account') 'warm route drops private extras'
$bad=Convert-FixLogEvent ($line+' decision=PRIVATE reason=PRIVATE elapsedMs=PRIVATE activationCount=PRIVATE hostState=PRIVATE') 'output/handoff-latest.log'
Check ($bad.decision -ceq 'unknown' -and $bad.reason -ceq 'unknown' -and $bad.elapsedMs -eq -1 -and $bad.activationCount -eq -1 -and $bad.hostState -ceq 'unknown') 'duplicate fields cannot establish a route'
$bad=Convert-FixLogEvent ((Stamp 1)+' warm-start decision=PRIVATE reason=PRIVATE elapsedMs=31536000001 activationCount=2 hostState=PRIVATE') 'output/handoff-latest.log'
Check ($bad.decision -ceq 'unknown' -and $bad.reason -ceq 'unknown' -and $bad.elapsedMs -eq -1 -and $bad.activationCount -eq -1 -and $bad.hostState -ceq 'unknown') 'unknown and out-of-range fields stay unknown'
foreach($reason in @('no-running','existing-window','window-recovered','no-window','activation-timeout','activation-failed','window-timeout','observation-timeout','identity-unavailable','target-ended','host-unavailable','manual-retry-running','manual-retry-cold','user-cancelled','animation-only')){Check ((Route 1 'unavailable' $reason 'unchecked').reason -ceq $reason) ('route reason enum '+$reason)}
foreach($hostState in @('unchecked','unavailable','unverified','managed','disabled','paused','faulted','animation-only')){Check ((Route 1 'replay' 'existing-window' $hostState).hostState -ceq $hostState) ('host state enum '+$hostState)}

foreach($case in @(@('cold','no-running','unchecked',0,'冷启动'),@('replay','existing-window','managed',0,'同目录'),@('activate','no-window','unchecked',1,'激活一次'),@('needs-exit','host-unavailable','unavailable',1,'没有通过验证的同目录壁纸会话'),@('cancelled','user-cancelled','unavailable',0,'取消'),@('unavailable','window-timeout','unchecked',1,'期限内未获得合格窗口'))){
    $text=Get-CodexDiagnosticAnalysis (Report @((Entry 0),(Route 1 $case[0] $case[1] $case[2] $case[3]))) $null
    Check ($text.Contains($case[4]) -and -not $text.Contains('当时确认了首帧')) ('current route meaning '+$case[0])
}
foreach($state in @('disabled','paused','faulted')){
    $text=Get-CodexDiagnosticAnalysis (Report @((Entry 0),(Route 1 'replay' 'existing-window' $state),(Handoff 9))) $null
    Check ($text.Contains('保留') -and $text.Contains('仅完成动画及窗口交接') -and -not $text.Contains('当时确认了首帧')) ('existing host state retained without playback claim '+$state)
}
$text=Get-CodexDiagnosticAnalysis (Report @((Entry 0),(Route 1 'activate' 'no-window' 'unchecked' 1),(Route 2 'needs-exit' 'host-unavailable' 'unavailable' 1),(Route 3 'cold' 'manual-retry-cold' 'unavailable' 1))) $null
Check ($text.Contains('冷启动') -and -not $text.Contains('没有通过验证的同目录壁纸会话')) 'latest route supersedes intermediate needs-exit decision'
$text=Get-CodexDiagnosticAnalysis (Report @((Entry 0),(Route 1 'needs-exit' 'host-unavailable' 'unavailable' 1)) $oldHost) $null
Check ($text.Contains('没有通过验证的同目录壁纸会话') -and -not $text.Contains('当时确认了首帧')) 'continuing old host cannot override current unhosted route'
$text=Get-CodexDiagnosticAnalysis (Report @((Entry 0),(Route 1 'replay' 'existing-window' 'managed'),(Entry 20))) $null
Check (-not $text.Contains('本次启动路由') -and $text.Contains('没有可解释的本次运行状态记录')) 'latest entry retires previous route'
$text=Get-CodexDiagnosticAnalysis (Report @((Entry 0),(Route 1 'replay' 'existing-window' 'managed'),(Route 1 'cold' 'no-running' 'unchecked'))) $null
Check ($text.Contains('路由记录冲突') -and -not $text.Contains('本次启动路由：冷启动')) 'same-time different routes stay ambiguous'
$same=Route 1 'replay' 'existing-window' 'managed'
$text=Get-CodexDiagnosticAnalysis (Report @((Entry 0),$same,$same)) $null
Check ($text.Contains('本次启动路由：重播现有窗口') -and -not $text.Contains('路由记录冲突')) 'identical duplicate route does not manufacture conflict'
$text=Get-CodexDiagnosticAnalysis (Report @((Entry 0),$bad)) $null
Check ($text.Contains('路由字段不完整') -and $text -notmatch 'PRIVATE|432123') 'malformed latest route remains unknown without private text'
foreach($case in @(@('cold','animation-only','unchecked',0),@('activate','no-window','unchecked',0),@('cancelled','no-running','unavailable',0),@('needs-exit','existing-window','managed',0))){
    $text=Get-CodexDiagnosticAnalysis (Report @((Entry 0),(Route 1 $case[0] $case[1] $case[2] $case[3]))) $null
    Check ($text.Contains('路由字段相互矛盾') -and -not $text.Contains('当时确认了首帧')) ('inconsistent route fields cannot establish state '+$case[0])
}
$malformedTime=Route 1 'replay' 'existing-window' 'managed';$malformedTime.utc='2026-01-01T12:00:99Z PRIVATE'
$text=Get-CodexDiagnosticAnalysis (Report @((Entry 0),$malformedTime)) $null
Check (-not $text.Contains('本次启动路由') -and $text -notmatch 'PRIVATE') 'malformed route time cannot establish current attempt'
Check (-not (Get-CodexDiagnosticAnalysis (Report @((Route 1 'replay' 'existing-window' 'managed'))) $null).Contains('本次启动路由')) 'route without entry has no current-attempt association'
$reverse=@((Route 3 'cold' 'manual-retry-cold' 'unavailable' 1),(Route 1 'needs-exit' 'host-unavailable' 'unavailable' 1),(Entry 0))
$text=Get-CodexDiagnosticAnalysis (Report $reverse) $null
Check ($text.Contains('本次启动路由：冷启动') -and -not $text.Contains('没有通过验证的同目录壁纸会话')) 'route chronology uses UTC rather than record enumeration order'
$wrong=Report @((Entry 0)) @((Route 1 'needs-exit' 'host-unavailable' 'unavailable'))
Check (-not (Get-CodexDiagnosticAnalysis $wrong $null).Contains('没有通过验证的同目录壁纸会话')) 'host stream cannot inject a route into analysis'
$duplicate=Report @((Entry 0),(Route 1 'replay' 'existing-window' 'managed'))
$duplicate.logs+= [pscustomobject]@{log='output/handoff-latest.log';records=@((Entry 0),(Route 1 'cold' 'no-running' 'unchecked'))}
Check (-not (Get-CodexDiagnosticAnalysis $duplicate $null).Contains('本次启动路由')) 'duplicate authoritative streams do not establish route'
$large=Report @((Entry 0),(Route 1 'replay' 'existing-window' 'managed'))
$large.logs[0].records=@(1..513|ForEach-Object {Route 1 'replay' 'existing-window' 'managed'})
Check (-not (Get-CodexDiagnosticAnalysis $large $null).Contains('本次启动路由')) 'overlarge stream cannot establish route'
$text=Get-CodexDiagnosticAnalysis (Report @((Entry 0),(Route 1 'cold' 'no-running' 'unchecked')) @([pscustomobject]@{utc=(Stamp 2);category='host-phase';phase=20;code=0},(Playing 10))) $null
Check ($text.Contains('冷启动') -and $text.Contains('当时确认了首帧')) 'cold route does not suppress later new-host playback evidence'
$waiting=Report @((Entry 0),(Route 1 'needs-exit' 'host-unavailable' 'unavailable' 0))
$waiting.logs+=[pscustomobject]@{log='diagnostics/portable-launch.log';records=@([pscustomobject]@{utc=(Stamp 121);category='public-entry';publicCode='PUBLIC_CHILD_TIMEOUT'})}
$text=Get-CodexDiagnosticAnalysis $waiting $null
Check ($text.Contains('没有通过验证的同目录壁纸会话') -and $text.Contains('PUBLIC_CHILD_TIMEOUT') -and $text.Contains('达到 120 秒') -and $text.Contains('不关闭子程序') -and $text.Contains('重试/取消') -and $text.Contains('不能仅凭该码认定壁纸故障') -and -not $text.Contains('壁纸宿主报告故障')) 'parent wait timeout during Retry Cancel remains user-wait evidence rather than wallpaper failure'
[IO.File]::WriteAllText((Join-Path $WorkRoot 'results.json'),(@{passed=$true;checks=$checks}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
Write-Output ('ALL PASS: warm-start diagnostics '+$checks)
