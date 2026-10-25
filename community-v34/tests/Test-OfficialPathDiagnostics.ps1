[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$WorkRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -ne 5){throw 'Requires Windows PowerShell 5.1'}
$source=Split-Path -Parent $PSScriptRoot
. (Join-Path $source 'packaging/DiagnosticReport.Common.ps1')
. (Join-Path $source 'packaging/DiagnosticAnalysis.ps1')
if(Test-Path -LiteralPath $WorkRoot){throw 'Fresh isolated output required'}
[void][IO.Directory]::CreateDirectory($WorkRoot)
$checks=0
function Check([bool]$Value,[string]$Name){if(-not $Value){throw ('FAIL '+$Name)};$script:checks++;Write-Output ('PASS '+$Name)}
function Parse([string]$Body,[string]$Time='2026-10-25T10:00:00Z',[string]$Log='diagnostics/portable-launch.log'){return Convert-FixLogEvent ($Time+' '+$Body) $Log}
function Detail([string]$Time='2026-10-25T10:00:00Z',[string]$Reason='path-metadata-unavailable',[string]$Mode='launch'){return Parse ('PUBLIC_IDENTITY_DETAIL reason='+$Reason+' mode='+$Mode) $Time}
function Failure([string]$Time='2026-10-25T10:00:01Z',[string]$Code='PUBLIC_OFFICIAL_IDENTITY_REJECTED'){return Parse $Code $Time}
function Report($Records,$OtherLogs=@()){return [pscustomobject]@{logs=@([pscustomobject]@{log='diagnostics/portable-launch.log';records=@($Records)})+@($OtherLogs)}}
function Explain($Records,$OtherLogs=@()){return (Get-CodexPublicEntryEvidence (Report $Records $OtherLogs)).lines -join "`n"}
function NoPrivate($Value){return (($Value|ConvertTo-Json -Depth 12 -Compress) -notmatch 'PRIVATE|SECRET|C:\\\\Users|packageFullName|"pid"|"trace"')}
$reasons=@('registration','path-missing','path-invalid','path-access-denied','path-reparse','path-metadata-unavailable','manifest','signature','process','unknown')
foreach($reason in $reasons){foreach($mode in @('launch','check','configure')){
    $event=Detail -Reason $reason -Mode $mode
    Check ($null -ne $event -and $event.category -ceq 'public-identity-detail' -and $event.reason -ceq $reason -and $event.mode -ceq $mode) ('strict detail projection: '+$reason+'/'+$mode)
    Check ($null -eq (Get-CodexAnalysisEvent $event)) 'identity detail never counts as playback evidence'
}}
foreach($body in @(
    'PUBLIC_IDENTITY_DETAIL reason=path-reparse mode=launch PRIVATE',
    'PUBLIC_IDENTITY_DETAIL reason=path-reparse reason=signature mode=launch',
    'PUBLIC_IDENTITY_DETAIL reason=path-reparse mode=launch mode=check',
    'PUBLIC_IDENTITY_DETAIL reason=PRIVATE mode=launch',
    'PUBLIC_IDENTITY_DETAIL reason=path-reparse mode=preview',
    'PUBLIC_IDENTITY_DETAIL reason=path-reparse mode=Launch',
    'PUBLIC_IDENTITY_DETAIL mode=launch reason=path-reparse',
    'PUBLIC_IDENTITY_DETAIL reason=path-reparse mode=launch ',
    ' PUBLIC_IDENTITY_DETAIL reason=path-reparse mode=launch',
    ('PUBLIC_IDENTITY_DETAIL reason=path-reparse mode=launch'+"`n"+'PRIVATE'),
    ('PUBLIC_IDENTITY_DETAIL reason=path-reparse mode=launch '+('x'*4096))
)){
    Check ($null -eq (Parse $body)) 'unrecognized detail payload is never copied into report'
}
Check ($null -eq (Parse 'PUBLIC_IDENTITY_DETAIL reason=path-reparse mode=launch' -Log 'output/handoff-latest.log')) 'detail from wrong log is rejected'
Check ($null -eq (Parse 'PUBLIC_IDENTITY_DETAIL reason=path-reparse mode=launch' -Time '2026-99-25T10:00:00Z')) 'invalid date never projected'
$good=Detail;$failure=Failure
foreach($code in @('PUBLIC_OFFICIAL_IDENTITY_REJECTED','PUBLIC_OFFICIAL_DISCOVERY_FAILED')){
    foreach($mode in @('launch','check','configure')){
        $text=Explain @((Detail -Mode $mode),(Failure -Code $code))
        Check ($text.Contains('身份细项：path-metadata-unavailable；操作模式：'+$mode) -and -not $text.Contains('没有运行模式标记')) ('bounded identity attribution: '+$code+'/'+$mode)
        Check ($text.Contains('不代表原有客户端或壁纸已关闭') -and $text.Contains('元数据')) 'attribution is limited to rejected entry and observed reason'
    }
}
foreach($reason in $reasons){$text=Explain @((Detail -Reason $reason),$failure);Check ($text.Contains('身份细项：'+$reason) -and (NoPrivate $text)) ('fixed safe reason explanation: '+$reason)}
Check ((Explain @($failure)).Contains('没有运行模式标记')) 'R13 legacy identity failure retains original interpretation'
Check ((Explain @($good,(Failure -Code 'PUBLIC_LAUNCH_FAILED'))).Contains('没有运行模式标记')) 'detail is never attached to unrelated failure type'
Check ((Explain @((Detail '2026-10-25T09:59:59Z'),$failure)).Contains('身份细项：')) 'two-second boundary is inclusive'
Check ((Explain @((Detail '2026-10-25T09:59:58.9999999Z'),$failure)).Contains('没有运行模式标记')) 'older detail is not joined across attempts'
Check ((Explain @((Detail '2026-10-25T10:00:02Z'),$failure)).Contains('没有运行模式标记')) 'future detail is not joined to failure'
Check ((Explain @((Detail '2026-10-25T10:00:01Z'),$failure)).Contains('身份细项：')) 'equal timestamp uses strict same-source record order'
Check ((Explain @($failure,$good)).Contains('没有运行模式标记')) 'reversed record order is not guessed'
foreach($interloper in @((Parse 'PUBLIC_ENTRY_BUSY' '2026-10-25T10:00:00.5Z'),(Parse 'PUBLIC_CHILD_EXIT_0' '2026-10-25T10:00:00.5Z'),(Failure '2026-10-25T10:00:00.5Z'))){
    Check ((Explain @($good,$interloper,$failure)).Contains('没有运行模式标记')) 'another public operation between detail and failure prevents association'
}
Check ((Explain @($good,$good,$failure)).Contains('没有运行模式标记')) 'identical duplicate detail is not attributed to one attempt'
Check ((Explain @((Detail -Reason 'manifest'),$good,$failure)).Contains('没有运行模式标记')) 'conflicting adjacent detail is not arbitrarily selected'
Check ((Explain @($good,$failure,$failure)).Contains('没有运行模式标记')) 'duplicate latest failure does not invent a unique detail pairing'
$bad=[pscustomobject]@{utc='2026-10-25T10:00:00Z';category='public-identity-detail';reason='SECRET';mode='launch'}
Check ((Explain @($bad,$failure)).Contains('没有运行模式标记') -and (NoPrivate (Explain @($bad,$failure)))) 'untrusted report detail reason is not echoed'
$bad.reason='path-reparse';$bad.mode='SECRET'
Check ((Explain @($bad,$failure)).Contains('没有运行模式标记') -and (NoPrivate (Explain @($bad,$failure)))) 'untrusted report detail mode is not echoed'
$bad.mode='launch';$bad.utc='PRIVATE'
Check ((Explain @($bad,$failure)).Contains('没有运行模式标记') -and (NoPrivate (Explain @($bad,$failure)))) 'untimed detail cannot be attributed'
foreach($boundary in @(
    [pscustomobject]@{log='output/handoff-latest.log';records=@([pscustomobject]@{utc='2026-10-25T10:00:00.5Z';category='launcher-stage';stage='launcher-entry'})},
    [pscustomobject]@{log='output/wallpaper-readiness.log';records=@([pscustomobject]@{utc='2026-10-25T10:00:00.5Z';category='host-phase';phase=20;code=0})},
    [pscustomobject]@{log='output/wallpaper-readiness.log.1';records=@([pscustomobject]@{utc='2026-10-25T10:00:00Z';category='host-phase';phase=20;code=0})}
)){
    Check ((Explain @($good,$failure) @($boundary)).Contains('没有运行模式标记')) 'launcher or host boundary prevents crossing identity association'
}
$duplicate=[pscustomobject]@{log='diagnostics/portable-launch.log';records=@($good,$failure)}
Check ((Explain @($good,$failure) @($duplicate)).Contains('先后关系无法确认')) 'duplicate public sources retain ambiguity'
$foreign=[pscustomobject]@{log='output/handoff-latest.log';records=@($good)}
Check ((Explain @($failure) @($foreign)).Contains('没有运行模式标记')) 'detail from another source cannot explain public failure'
$next=[pscustomobject]@{log='output/handoff-latest.log';records=@([pscustomobject]@{utc='2026-10-25T10:00:02Z';category='launcher-stage';stage='launcher-entry'})}
$result=Get-CodexPublicEntryEvidence (Report @($good,$failure) @($next))
Check (-not $result.suppressPlaybackProof -and $result.lines.Count -eq 0) 'newer launcher boundary retires old identity failure and its detail'
$result=Get-CodexPublicEntryEvidence (Report @($good,$failure))
Check ($result.suppressPlaybackProof -and (NoPrivate $result)) 'attributed failure still suppresses unrelated playback proof'
Check ((Explain @($good,$failure,(Detail '2026-10-25T10:00:04Z' 'manifest'),(Failure '2026-10-25T10:00:05Z'))).Contains('身份细项：manifest')) 'latest attempt receives only its own detail'
$text=Get-CodexDiagnosticAnalysis (Report @($good,$failure)) $null
Check ($text.Contains('身份细项：') -and $text.Contains('没有可解释的本次运行状态记录') -and $text.Length -lt 16384 -and (NoPrivate $text)) 'full analysis retains absence of runtime evidence and bounded private-free detail'
function PathExplanation($Packages){return (Get-CodexOfficialAdaptationAnalysis ([pscustomobject]@{compatibility=[pscustomobject]@{packages=@($Packages)}})) -join "`n"}
$reasonMessages=@{'missing'='未找到';'invalid-path'='本地路径格式';'unsupported-drive'='驱动器类型';'reparse'='重解析路径';'access-denied'='元数据被拒绝';'metadata-unavailable'='元数据不可用'}
foreach($reason in $reasonMessages.Keys){
    $package=[pscustomobject]@{readState='blocked-root';rootPathReason=$reason;rootPathKind='unknown';installPath='C:\Users\PRIVATE';token='SECRET'}
    $text=PathExplanation @($package)
    Check ($text.Contains('采集时') -and $text.Contains($reasonMessages[$reason]) -and (NoPrivate $text)) ('path probe projects fixed explanation without runtime causation: '+$reason)
}
$legacy=[pscustomobject]@{readState='blocked-root'}
$text=PathExplanation @($legacy)
Check ($text.Contains('缺少可确认的细项') -and $text.Contains('不能据此归因于权限、显卡、素材缺失或客户端框架变化')) 'R13 blocked-root remains an unclassified observation'
$alias=[pscustomobject]@{readState='ok';rootPathReason='ok';rootPathKind='registered-alias'}
$text=PathExplanation @($alias)
Check ($text.Contains('目录别名') -and $text.Contains('不代表官方签名、实际进程或壁纸接入已通过验证')) 'registered alias probe is metadata evidence only'
$alias.rootPathReason='access-denied';$alias.readState='blocked-root'
Check (-not (PathExplanation @($alias)).Contains('目录别名')) 'failed metadata cannot confirm registered alias compatibility'
$alias.rootPathReason='ok';$alias.rootPathKind='direct';$alias.readState='ok'
Check ([string]::IsNullOrEmpty((PathExplanation @($alias)))) 'ordinary metadata success does not add playback or trust claim'
foreach($value in @('PRIVATE',1,$null)){
    $badPackage=[pscustomobject]@{readState='blocked-root';rootPathReason=$value;rootPathKind='SECRET'}
    $text=PathExplanation @($badPackage)
    Check ($text.Contains('缺少可确认的细项') -and (NoPrivate $text)) 'untrusted package reason and kind are not echoed or coerced'
}
$alias.rootPathKind='registered-alias';$many=@();for($i=0;$i -lt 33;$i++){$many+= $alias}
Check ([string]::IsNullOrEmpty((PathExplanation $many))) 'oversized compatibility records are not analysed'
$text=PathExplanation @($alias,$alias)
Check ([regex]::Matches($text,'目录别名').Count -eq 1) 'repeated package metadata cannot multiply claims'
$logDirectory=Join-Path $WorkRoot 'diagnostics';[void][IO.Directory]::CreateDirectory($logDirectory)
$logPath=Join-Path $logDirectory 'portable-launch.log'
$logText=@('PRIVATE C:\Users\PRIVATE apiKey=SECRET','2026-10-25T10:00:00Z PUBLIC_IDENTITY_DETAIL reason=path-metadata-unavailable mode=launch','2026-10-25T10:00:01Z PUBLIC_OFFICIAL_IDENTITY_REJECTED') -join "`r`n"
[IO.File]::WriteAllText($logPath,$logText,[Text.UTF8Encoding]::new($true))
$before=(Get-FileHash -LiteralPath $logPath -Algorithm SHA256).Hash
$tail=Read-FixLogTail $WorkRoot 'diagnostics/portable-launch.log'
Check ($tail.status -ceq 'read' -and $tail.records.Count -eq 2 -and $tail.unrecognizedLineCount -eq 1 -and (NoPrivate $tail)) 'bounded log reader keeps fixed identity detail and drops raw private line'
$roundTrip=([pscustomobject]@{logs=@($tail)}|ConvertTo-Json -Depth 8)|ConvertFrom-Json
$text=(Get-CodexPublicEntryEvidence $roundTrip).lines -join "`n"
Check ($text.Contains('身份细项：path-metadata-unavailable；操作模式：launch') -and (NoPrivate $text)) 'strict detail survives JSON report round trip'
Check ($before -ceq (Get-FileHash -LiteralPath $logPath -Algorithm SHA256).Hash) 'report reading leaves input log unchanged'
[IO.File]::WriteAllText((Join-Path $WorkRoot 'results.json'),(@{passed=$true;checks=$checks;applicationStarted=$false;gpuStress=$false}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
Write-Output ('ALL PASS: '+$checks+' official path diagnostic checks')
