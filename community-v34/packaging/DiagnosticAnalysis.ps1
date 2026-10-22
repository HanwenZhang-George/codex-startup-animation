# Pure, bounded analysis of allowlisted observations. Input text is never echoed.
Set-StrictMode -Version Latest
function Get-CodexAnalysisValue($Object,[string]$Name) {
    if($null -eq $Object){return $null}
    if($Object -is [Collections.IDictionary]){if($Object.Contains($Name)){return ,($Object[$Name])};return $null}
    if($Object -is [pscustomobject]){$property=$Object.PSObject.Properties[$Name];if($null -ne $property -and $property.MemberType -eq [Management.Automation.PSMemberTypes]::NoteProperty){return ,($property.Value)}}
    return $null
}
function Get-CodexAnalysisNumber($Object,[string]$Name,[long]$Maximum=2147483647,[long]$Minimum=0) {
    $value=Get-CodexAnalysisValue $Object $Name
    if(($value -is [int] -or $value -is [long]) -and $value -ge $Minimum -and $value -le $Maximum){return [long]$value}
    return -1L
}
function Get-CodexAnalysisEnum($Object,[string]$Name,[string[]]$Allowed) {
    $value=Get-CodexAnalysisValue $Object $Name
    if($value -is [string] -and $value.Length -le 96 -and $value -cin $Allowed){return $value}
    return 'unknown'
}
function Get-CodexAnalysisUtc($Object) {
    $value=Get-CodexAnalysisValue $Object 'utc';$date=[DateTime]::MinValue
    if($value -isnot [string] -or $value.Length -gt 32 -or $value -cnotmatch '\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z\z'){return -1L}
    if([DateTime]::TryParse($value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$date)){return $date.ToUniversalTime().Ticks}
    return -1L
}
function Get-CodexAnalysisEvent($Event) {
    $category=Get-CodexAnalysisEnum $Event 'category' @('host-phase','bridge-diagnostic','launcher-stage')
    if($category -ceq 'launcher-stage'){
        if((Get-CodexAnalysisEnum $Event 'stage' @('replay-target-unavailable-no-activation')) -ceq 'replay-target-unavailable-no-activation'){return 'replay-target-unavailable'}
        return $null
    }
    if($category -ceq 'bridge-diagnostic'){
        $outcome=Get-CodexAnalysisEnum $Event 'outcome' @('wallpaper-unavailable-existing-process','bridge-existing-normal-reuse','bridge-started','bridge-reused','wallpaper-disabled','wallpaper-host-missing','wallpaper-host-start-failed','bridge-unknown-no-second-launch','activation-failed')
        switch($outcome){
            'wallpaper-unavailable-existing-process' {return 'existing-unhosted'}
            'bridge-existing-normal-reuse' {return 'existing-unhosted'}
            'bridge-started' {return 'client-started'}
            'bridge-reused' {return 'client-started'}
            'wallpaper-disabled' {return 'disabled'}
            'wallpaper-host-missing' {return 'host-unavailable'}
            'wallpaper-host-start-failed' {return 'host-unavailable'}
            'bridge-unknown-no-second-launch' {return 'connection-unknown'}
            'activation-failed' {return 'activation-failed'}
        }
        return $null
    }
    if($category -cne 'host-phase'){return $null}
    $phase=Get-CodexAnalysisNumber $Event 'phase' 63
    $code=Get-CodexAnalysisNumber $Event 'code' 65535
    if($phase -eq 43 -and $code -eq 0){
        switch(Get-CodexAnalysisEnum $Event 'pressureState' @('suspended','resume-requested')){
            'suspended'{return 'host-memory-suspended'}
            'resume-requested'{return 'host-memory-resume-requested'}
            default{return 'snapshot-unconfirmed'}
        }
    }
    if((($phase -ge 1 -and $phase -le 13) -or $phase -eq 15) -and (($code -ge 100 -and $code -le 199) -or ($code -ge 61100 -and $code -le 65099))){
        switch($code){166{return 'layout-failed'};168{return 'first-frame-failed'};174{return 'host-memory-failed'};default{return 'host-failed'}}
    }
    if($phase -eq 14 -and $code -eq 1){return 'preparation-timeout'}
    if($phase -notin @(10,38,39)){return $null}
    if($phase -eq 10){$age=Get-CodexAnalysisNumber $Event 'sampleAgeMs' 31536000000;if($age -lt 0 -or $age -gt 1500){return 'snapshot-unconfirmed'}}
    if($phase -ne 10 -and $code -ne 0){return $null}
    $layout=Get-CodexAnalysisNumber $Event 'layoutSupported' 1
    $reason=Get-CodexAnalysisEnum $Event 'layoutReason' @('not-checked','root-missing','main-count','main-token','workspace-shape','shell-shape','composer-ambiguous','ready')
    if($layout -eq 0){if($reason -ceq 'composer-ambiguous'){return 'composer-ambiguous'};return 'layout-failed'}
    $renderer=Get-CodexAnalysisEnum $Event 'rendererCode' @('media-error','play-rejected','first-frame-timeout','reveal-timeout','resume-timeout','playback-stalled','disposed','retired','invalid-file','file-too-large','unsupported-layout')
    if((Get-CodexAnalysisNumber $Event 'videoErrorCode' 4) -ge 1 -or $renderer -ceq 'media-error'){return 'media-error'}
    if($renderer -cin @('play-rejected','first-frame-timeout','reveal-timeout','resume-timeout','playback-stalled')){return 'playback-failed'}
    if($renderer -cin @('disposed','retired')){return 'ended'}
    if((Get-CodexAnalysisNumber $Event 'disposed' 1) -eq 1){return 'ended'}
    if($renderer -cin @('invalid-file','file-too-large')){return 'media-rejected'}
    if((Get-CodexAnalysisNumber $Event 'generationMatches' 1) -eq 1 -and (Get-CodexAnalysisNumber $Event 'protocolVersion' 2) -eq 2 -and (Get-CodexAnalysisEnum $Event 'health' @('fresh')) -ceq 'fresh' -and (Get-CodexAnalysisNumber $Event 'attached' 1) -eq 1 -and (Get-CodexAnalysisNumber $Event 'disposed' 1) -eq 0 -and (Get-CodexAnalysisNumber $Event 'memoryPressure' 1) -eq 1 -and (Get-CodexAnalysisEnum $Event 'actualPhase' @('hibernating')) -ceq 'hibernating' -and (Get-CodexAnalysisNumber $Event 'mediaReady' 1) -eq 0 -and (Get-CodexAnalysisNumber $Event 'playing' 1) -eq 0){return 'renderer-memory-suspended'}
    if((Get-CodexAnalysisNumber $Event 'documentHidden' 1) -eq 1){return 'hidden'}
    if((Get-CodexAnalysisEnum $Event 'actualPhase' @('gap')) -ceq 'gap'){return 'gap'}
    $proof=(Get-CodexAnalysisNumber $Event 'generationMatches' 1) -eq 1 -and (Get-CodexAnalysisNumber $Event 'protocolVersion' 2) -eq 2 -and (Get-CodexAnalysisEnum $Event 'health' @('fresh')) -ceq 'fresh' -and (Get-CodexAnalysisNumber $Event 'attached' 1) -eq 1 -and (Get-CodexAnalysisNumber $Event 'disposed' 1) -eq 0 -and (Get-CodexAnalysisNumber $Event 'mediaReady' 1) -eq 1
    if($proof -and $phase -eq 39 -and (Get-CodexAnalysisNumber $Event 'playing' 1) -eq 1 -and (Get-CodexAnalysisNumber $Event 'wallpaperApplied' 1) -eq 1 -and (Get-CodexAnalysisNumber $Event 'firstFrameConfirmed' 1) -eq 1 -and $layout -eq 1 -and (Get-CodexAnalysisNumber $Event 'revealed' 1) -eq 1 -and (Get-CodexAnalysisNumber $Event 'documentHidden' 1) -eq 0 -and (Get-CodexAnalysisNumber $Event 'stageVisible' 1) -eq 1 -and (Get-CodexAnalysisNumber $Event 'commitAccepted' 1) -eq 1){return 'observed-playing'}
    if($proof -and (Get-CodexAnalysisNumber $Event 'prepared' 1) -eq 1){return 'prepared-only'}
    if($phase -eq 38 -and $layout -eq 1){return 'layout-only'}
    return 'snapshot-unconfirmed'
}
function Get-CodexCompletedStartupAnalysis($Report) {
    # Only a single bounded handoff stream can supply the historical interval.
    # Without correlation IDs, overlapping entries are deliberately not paired.
    $logs=Get-CodexAnalysisValue $Report 'logs'
    if($logs -isnot [array] -or $logs.Count -gt 16){return}
    $handoff=@($logs|Where-Object {(Get-CodexAnalysisEnum $_ 'log' @('output/handoff-latest.log')) -ceq 'output/handoff-latest.log'})
    if($handoff.Count -ne 1){return}
    $records=Get-CodexAnalysisValue $handoff[0] 'records'
    if($records -isnot [array] -or $records.Count -gt 128){return}
    $ordered=[Collections.Generic.List[object]]::new()
    foreach($record in $records){
        $category=Get-CodexAnalysisEnum $record 'category' @('launcher-stage','handoff-complete','startup-resource-sample')
        if($category -ceq 'unknown'){continue}
        $stage=Get-CodexAnalysisEnum $record 'stage' @('launcher-entry','replay-target-unavailable-no-activation')
        if($category -ceq 'launcher-stage' -and $stage -ceq 'unknown'){continue}
        $ticks=Get-CodexAnalysisUtc $record
        if($ticks -lt 0){if($category -cne 'startup-resource-sample'){return};continue}
        $ordered.Add([pscustomobject]@{ticks=$ticks;category=$category;stage=$stage;record=$record})
    }
    $start=-1L;$overlap=$false;$latestStart=-1L;$latestEnd=-1L
    foreach($item in ($ordered|Sort-Object ticks)){
        if($item.category -ceq 'launcher-stage'){
            if($item.stage -ceq 'launcher-entry'){
                if($start -ge 0 -and $start -ne $item.ticks){$overlap=$true}
                if($start -lt 0){$start=$item.ticks}
            }elseif(-not $overlap){$start=-1L}
        }elseif($item.category -ceq 'handoff-complete'){
            if(-not $overlap -and $start -ge 0 -and $item.ticks -gt $start -and ($item.ticks-$start) -le 315360000000000L -and (Get-CodexAnalysisNumber $item.record 'success' 1) -ge 0){$latestStart=$start;$latestEnd=$item.ticks}
            $start=-1L;$overlap=$false
        }
    }
    if($latestStart -lt 0){return}
    $duration=[long][Math]::Floor(($latestEnd-$latestStart)/[double][TimeSpan]::TicksPerMillisecond)
    $lines=[Collections.Generic.List[string]]::new()
    $lines.Add(('最近一次有结束记录的启动：{0} 毫秒（从启动入口到交接结束）；这是历史完整区间，不代表后续点击已成功。' -f $duration))
    $samples=@($ordered|Where-Object {$_.category -ceq 'startup-resource-sample' -and $_.ticks -ge $latestStart -and $_.ticks -le $latestEnd})
    if($samples.Count -eq 0){$lines.Add('该启动区间没有有效时间的资源采样，不能计算阶段资源摘要。');return $lines.ToArray()}
    $privatePeak=-1L;$cpuPeak=-1L;$availableMinimum=-1L;$lowMemorySeen=$false;$lowMemoryUnknown=$false
    foreach($sample in $samples){
        $record=$sample.record
        $private=Get-CodexAnalysisNumber $record 'privateBytes' 281474976710656
        if($private -ge 0){$privatePeak=[Math]::Max($privatePeak,$private)}
        $cpu=Get-CodexAnalysisNumber $record 'cpuPermille' 1000
        if($cpu -ge 0 -and (Get-CodexAnalysisNumber $record 'intervalMs' 31536000000 1) -gt 0){$cpuPeak=[Math]::Max($cpuPeak,$cpu)}
        $available=Get-CodexAnalysisNumber $record 'availablePhysicalBytes' 281474976710656
        if($available -ge 0 -and ($availableMinimum -lt 0 -or $available -lt $availableMinimum)){$availableMinimum=$available}
        $low=Get-CodexAnalysisNumber $record 'lowMemory' 1
        if($low -eq 1){$lowMemorySeen=$true};if($low -lt 0){$lowMemoryUnknown=$true}
    }
    if($privatePeak -ge 0){$lines.Add(('启动器进程私有内存采样峰值：{0} 字节；仅指启动器，不包含客户端或壁纸宿主的合计。' -f $privatePeak))}
    else{$lines.Add('该区间的启动器进程私有内存采样值不可用。')}
    if($cpuPeak -ge 0){$percentage=($cpuPeak/10.0).ToString('0.0',[Globalization.CultureInfo]::InvariantCulture);$lines.Add(('启动器进程 CPU 采样峰值：{0}%（按整机 CPU 总容量归一化，不是所有程序的 CPU 总占用）。' -f $percentage))}
    else{$lines.Add('该区间的启动器进程 CPU 采样值不可用。')}
    if($availableMinimum -ge 0){$lines.Add(('系统可用物理内存采样最低值：{0} 字节。' -f $availableMinimum))}
    else{$lines.Add('该区间的系统可用物理内存采样值不可用。')}
    if($lowMemorySeen){$lines.Add('该区间采样中记录了低内存标志；它本身不证明资源保护已经执行。')}
    elseif($lowMemoryUnknown){$lines.Add('该区间低内存标志记录不完整，不能判定是否出现。')}
    else{$lines.Add('该区间采样中未记录低内存标志；不代表采样间隔内从未出现。')}
    $lines.Add('以上仅汇总该区间的既有采样，未测量 GPU；不能单凭这些采样确定 CPU、GPU 或其他程序是瓶颈。')
    return $lines.ToArray()
}
function Get-CodexResourceProtectionAnalysis($Report) {
    $logs=Get-CodexAnalysisValue $Report 'logs'
    if($logs -isnot [array] -or $logs.Count -gt 16){return}
    $handoff=@($logs|Where-Object {(Get-CodexAnalysisEnum $_ 'log' @('output/handoff-latest.log')) -ceq 'output/handoff-latest.log'})
    if($handoff.Count -ne 1){return}
    $records=Get-CodexAnalysisValue $handoff[0] 'records'
    if($records -isnot [array] -or $records.Count -gt 128){return}
    $events=[Collections.Generic.List[object]]::new();$entryTimes=[Collections.Generic.HashSet[long]]::new();$latest=-1L;$protection=-1L
    foreach($record in $records){
        $ticks=Get-CodexAnalysisUtc $record;if($ticks -lt 0){continue}
        $category=Get-CodexAnalysisEnum $record 'category' @('launcher-stage','handoff-complete','startup-resource-protection','startup-resource-animation-released','replay-diagnostic','replay-native-candidates')
        if($category -ceq 'unknown'){continue}
        $events.Add([pscustomobject]@{ticks=$ticks;category=$category;record=$record});$latest=[Math]::Max($latest,$ticks)
        if($category -ceq 'startup-resource-protection'){$protection=[Math]::Max($protection,$ticks)}
        if($category -ceq 'launcher-stage' -and (Get-CodexAnalysisEnum $record 'stage' @('launcher-entry')) -ceq 'launcher-entry'){[void]$entryTimes.Add($ticks)}
    }
    if($protection -lt 0 -or $entryTimes.Count -eq 0){return}
    $starts=@($entryTimes|Sort-Object);$currentStart=$starts[-1];$previous=$protection -lt $currentStart;$start=$currentStart;$end=$latest;$replay=-1L
    if($previous){
        if($starts.Count -lt 2 -or $currentStart-$protection -gt 3000000000L){return}
        $start=$starts[-2];$end=$currentStart;if($protection -lt $start){return}
        foreach($event in $events){if($event.ticks -ge $currentStart -and $event.category -ceq 'launcher-stage' -and (Get-CodexAnalysisEnum $event.record 'stage' @('replay-target-unavailable-no-activation')) -ceq 'replay-target-unavailable-no-activation'){$replay=[Math]::Max($replay,$event.ticks)}}
        if($replay -lt 0){return}
    }
    foreach($event in $events){if($event.ticks -ge $protection -and $event.category -ceq 'handoff-complete' -and (Get-CodexAnalysisNumber $event.record 'success' 1) -eq 1){return}}
    $cancelled=$false
    foreach($log in $logs){
        if((Get-CodexAnalysisEnum $log 'log' @('output/wallpaper-readiness.log','output/wallpaper-readiness.log.1')) -ceq 'unknown'){continue}
        $hostRecords=Get-CodexAnalysisValue $log 'records';if($hostRecords -isnot [array] -or $hostRecords.Count -gt 128){continue}
        foreach($record in $hostRecords){
            $ticks=Get-CodexAnalysisUtc $record;if($ticks -lt $start -or $ticks -gt $latest -or (Get-CodexAnalysisEnum $record 'category' @('host-phase')) -cne 'host-phase'){continue}
            $phase=Get-CodexAnalysisNumber $record 'phase' 63
            # A newer host breaks the temporal association; reports omit the
            # private process/session identifiers needed to prove continuity.
            if($phase -eq 20 -and $ticks -gt $protection){return}
            if($phase -eq 9 -and $ticks -ge $protection -and $ticks -le $end -and (Get-CodexAnalysisNumber $record 'code' 65535) -eq 172){$cancelled=$true}
        }
    }
    $lines=[Collections.Generic.List[string]]::new()
    if($previous){$lines.Add('前一次启动记录了资源保护，保留日志内未见它完成成功交接；不能让后一次重复点击失败掩盖这段记录。')}
    else{$lines.Add('本次启动记录了资源保护，保留日志内未见它完成成功交接。')}
    $reasons=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$released=$false
    foreach($event in $events){
        if($event.ticks -lt $start -or $event.ticks -gt $end){continue}
        if($event.category -ceq 'startup-resource-animation-released' -and $event.ticks -ge $protection){$released=$true}
        if($event.category -ceq 'startup-resource-protection'){
            $reason=Get-CodexAnalysisEnum $event.record 'resourceReason' @('system-memory-pressure','system-commit-pressure','wallpaper-commit-pressure','startup-private-memory-limit','startup-sustained-cpu-limit','startup-resource-monitor-unavailable')
            if($reason -cne 'unknown'){[void]$reasons.Add($reason)}
        }
    }
    $reasonMessages=@{
        'system-memory-pressure'='保护原因记录：系统内存压力；这不表示启动器自身内存超限，也不能仅凭附近采样推定触发时的精确值。'
        'system-commit-pressure'='保护原因记录：可用提交内存余量不足；不等于物理内存不足。该指标受当前进程可提交上限影响，附近采样不能证明触发时的精确值或由哪个程序造成。'
        'wallpaper-commit-pressure'='保护原因记录：当前壁纸宿主报告提交内存保护暂停，因此启动器释放动画；这不同于启动器自身采样触发。该记录不能证明宿主触发时的精确内存值，也不表示壁纸已经恢复播放。'
        'startup-private-memory-limit'='保护原因记录：启动器私有内存超过保护条件；这不是整个客户端的内存合计。'
        'startup-sustained-cpu-limit'='保护原因记录：启动器持续 CPU 占用超过保护条件；这不证明 GPU 或其他程序是瓶颈。'
        'startup-resource-monitor-unavailable'='保护原因记录：资源监测连续不可用；这不等于已经测到资源超限。'
    }
    if($reasons.Count -eq 1){foreach($reason in $reasons){$lines.Add($reasonMessages[$reason])}}
    elseif($reasons.Count -gt 1){$lines.Add('保护原因记录相互矛盾，不能选其中一条断言具体原因。')}
    else{$lines.Add('报告未保留确切保护原因；不能把附近一次低内存、CPU 或私有内存采样直接当成触发原因。')}
    if($cancelled){$lines.Add('同一时间段的壁纸宿主还记录了阶段 9、错误码 172；不能仅凭这个错误码判断素材缺失。')}
    if($released){$lines.Add('该启动已请求保留壁纸准备并释放启动动画；仍需首帧和播放证据，不能据此认定壁纸已恢复。')}
    if($previous){
        $attest=@($events|Where-Object {$_.ticks -ge $currentStart -and $_.ticks -le $replay -and $_.category -ceq 'replay-diagnostic' -and (Get-CodexAnalysisEnum $_.record 'operation' @('attest')) -ceq 'attest'}|Sort-Object ticks -Descending)
        if($attest.Count -gt 0){
            $attestAt=$attest[0].ticks;$valid=$true
            foreach($item in $attest){if($item.ticks -eq $attestAt -and ((Get-CodexAnalysisNumber $item.record 'phase' 16) -ne 6 -or (Get-CodexAnalysisNumber $item.record 'reason' 32) -ne 0)){$valid=$false}}
            $candidates=@($events|Where-Object {$_.ticks -ge $attestAt -and $_.ticks -le $replay -and $_.category -ceq 'replay-native-candidates' -and (Get-CodexAnalysisNumber $_.record 'phase' 4) -eq 4}|Sort-Object ticks -Descending)
            if($valid -and $candidates.Count -gt 0){
                $count=Get-CodexAnalysisNumber $candidates[0].record 'verifiedWindows' 99999 1;$candidateAt=$candidates[0].ticks
                foreach($item in $candidates){if($item.ticks -eq $candidateAt -and ((Get-CodexAnalysisNumber $item.record 'verifiedWindows' 99999 1) -ne $count -or (Get-CodexAnalysisNumber $item.record 'visible' 99999) -ne 0 -or (Get-CodexAnalysisNumber $item.record 'hidden' 99999) -ne $count -or (Get-CodexAnalysisNumber $item.record 'eligible' 99999) -ne 0)){$valid=$false}}
                if($valid -and $count -gt 0){$lines.Add(('后一次重复启动通过了身份验证，但随后统计显示：已验证 {0} 个窗口，全部隐藏，合格主窗口 0 个。这些不是当前实时状态，也不能据此确定是谁隐藏了窗口。' -f $count))}
            }
        }
    }
    return $lines.ToArray()
}
function Get-CodexDiagnosticAnalysis($Report,$FileCheck) {
    $lines=[Collections.Generic.List[string]]::new()
    $lines.Add('Codex 启动器与壁纸：本地诊断说明')
    $lines.Add('本说明依据文件检查和有限长度的既有日志生成；不是实时运行探测。旧记录不等于当前故障。')
    if((Get-CodexAnalysisEnum $Report 'manifestState' @('valid','invalid-or-missing')) -ceq 'invalid-or-missing'){$lines.Add('发布清单缺失或无效，本次仅生成有限诊断；没有验证全部文件。这不等于应用运行失败，请先确认已经完整解压。')}
    $checkState=Get-CodexAnalysisEnum $FileCheck 'state' @('not-run','same-manifest')
    $failure=Get-CodexAnalysisEnum $FileCheck 'failure' @('unknown','none','platform-check','manifest-check','file-integrity','framework-metadata')
    $passed=Get-CodexAnalysisValue $FileCheck 'passed';$count=Get-CodexAnalysisNumber $FileCheck 'fileCount' 300 1
    if($checkState -ceq 'same-manifest' -and $passed -is [bool] -and $passed -and $failure -ceq 'none' -and $count -ge 1){
        $lines.Add(('文件校验记录：{0} 项通过。它只证明所检文件匹配清单，不证明解码成功、画面流畅或兼容性正常。' -f $count))
    }elseif($passed -is [bool] -and -not $passed -and $failure -cne 'none' -and $failure -cne 'unknown'){
        $messages=@{'platform-check'='文件校验未通过系统或依赖检查。';'manifest-check'='发布清单无法验证。';'file-integrity'='文件完整性校验失败；请从原发布页重新下载并完整解压到新目录，不要覆盖当前正在运行的目录。';'framework-metadata'='程序框架元数据检查失败。'}
        $lines.Add($messages[$failure])
    }else{$lines.Add('没有可确认的完整文件校验记录；素材存在或大小相同不代表哈希、解码已经验证。')}
    $roles=[ordered]@{startup='完整启动视频';intro='入场视频';idle='启动等待视频';finale='流泪转场视频';ambient='常态壁纸视频';particles='粒子壁纸视频'}
    $media=Get-CodexAnalysisValue $Report 'mediaPresence';$mediaCount=0;$mediaIssues=0
    if($media -is [array] -and $media.Count -le 32){
        foreach($role in $roles.Keys){
            $items=@($media|Where-Object {(Get-CodexAnalysisEnum $_ 'role' @('startup','intro','idle','finale','ambient','particles')) -ceq $role})
            if($items.Count -ne 1){continue};$mediaCount++
            $state=Get-CodexAnalysisEnum $items[0] 'state' @('present','missing','unavailable');$size=Get-CodexAnalysisNumber $items[0] 'sizeMatches' 1
            if($state -ceq 'missing'){$lines.Add($roles[$role]+'：文件缺失。');$mediaIssues++}
            elseif($state -ceq 'present' -and $size -eq 0){$lines.Add($roles[$role]+'：大小与清单不符。');$mediaIssues++}
            elseif($state -ne 'present' -or $size -ne 1){$lines.Add($roles[$role]+'：读取或大小检查结果不明确。');$mediaIssues++}
        }
    }
    if($mediaCount -eq 6 -and $mediaIssues -eq 0){$lines.Add('六类视频的存在和大小记录匹配；这一项没有执行视频解码，也不单独证明哈希正确。')}
    elseif($mediaCount -lt 6){$lines.Add('六类视频的检查记录不完整或存在重复项，不能据此认定素材齐全。')}
    if($mediaIssues -gt 0){$lines.Add('素材异常时，请完整重新解压原发布包到新目录；不要只复制单个 EXE。')}
    $compat=Get-CodexAnalysisValue $Report 'compatibility';$release=Get-CodexAnalysisNumber $compat 'dotNetFrameworkRelease' 9999999
    if($release -ge 528040){$lines.Add('检测记录符合 .NET Framework 4.8 的最低 Release 条件；这不验证其他依赖。')}
    elseif($release -ge 0){$lines.Add('检测到的 .NET Framework Release 低于 4.8 最低条件；先通过微软官方渠道安装或修复 4.8，再测试。')}
    else{$lines.Add('.NET Framework 版本记录不可用，不能据此认定已安装或未安装。')}
    $registration=Get-CodexAnalysisEnum $compat 'registrationState' @('ok','capped','unavailable','not-collected')
    if($registration -ceq 'ok' -and (Get-CodexAnalysisNumber $compat 'registeredPackageCount' 32) -eq 0){$lines.Add('未找到当前用户登记的官方 Codex 软件包。当前启动器要求支持的官方 Windows x64 客户端。')}
    $packages=Get-CodexAnalysisValue $compat 'packages';$electron=$false;$webview=$false
    if($packages -is [array] -and $packages.Count -le 32){foreach($item in $packages){$runtime=Get-CodexAnalysisEnum $item 'runtimeEvidence' @('electron-evidence','webview2-evidence','mixed','unknown');if($runtime -cin @('electron-evidence','mixed')){$electron=$true};if($runtime -cin @('webview2-evidence','mixed')){$webview=$true}}}
    if($webview){$lines.Add('发现 WebView2 相关文件线索；不能据此断言客户端采用 Tauri，也不能据此认定壁纸接入已适配。')}
    elseif($electron){$lines.Add('发现 Electron 相关文件线索；文件线索不等于本次通信与壁纸接入成功。')}
    else{$lines.Add('客户端运行时线索不足，暂不能确定框架或壁纸接入兼容性。')}
    $logs=Get-CodexAnalysisValue $Report 'logs';$events=[Collections.Generic.List[object]]::new();$cutoff=-1L
    if($logs -is [array] -and $logs.Count -le 16){foreach($log in $logs){
        $name=Get-CodexAnalysisEnum $log 'log' @('output/wallpaper-readiness.log.1','output/wallpaper-readiness.log','output/handoff-latest.log')
        if($name -ceq 'unknown'){continue};$records=Get-CodexAnalysisValue $log 'records'
        if($records -isnot [array] -or $records.Count -gt 128){continue}
        foreach($entry in $records){
            $ticks=Get-CodexAnalysisUtc $entry;if($ticks -lt 0){continue}
            $cat=Get-CodexAnalysisEnum $entry 'category' @('host-phase','bridge-diagnostic','launcher-stage')
            if(($name -ceq 'output/handoff-latest.log' -and $cat -ceq 'launcher-stage' -and (Get-CodexAnalysisEnum $entry 'stage' @('launcher-entry')) -ceq 'launcher-entry') -or ($name -cne 'output/handoff-latest.log' -and $cat -ceq 'host-phase' -and (Get-CodexAnalysisNumber $entry 'phase' 63) -eq 20)){$cutoff=[Math]::Max($cutoff,$ticks)}
            if(($name -ceq 'output/handoff-latest.log' -and $cat -cin @('bridge-diagnostic','launcher-stage')) -or ($name -cne 'output/handoff-latest.log' -and $cat -ceq 'host-phase')){
                $meaning=Get-CodexAnalysisEvent $entry;if($meaning){$events.Add([pscustomobject]@{ticks=$ticks;meaning=$meaning})}
            }
        }
    }}
    $latest=-1L;$replayFailure=-1L;$meanings=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($event in $events){if($event.ticks -lt $cutoff){continue};if($event.meaning -ceq 'replay-target-unavailable'){$replayFailure=[Math]::Max($replayFailure,$event.ticks)};if($event.ticks -gt $latest){$latest=$event.ticks;$meanings.Clear()};if($event.ticks -eq $latest){[void]$meanings.Add($event.meaning)}}
    # This terminal launcher event describes the current click. A continuing
    # older wallpaper host cannot turn a failed replay into a successful one.
    # A newer launcher/host entry still retires the failure via the cutoff.
    if($replayFailure -ge 0){$meanings.Clear();[void]$meanings.Add('replay-target-unavailable')}
    $state='unknown'
    if($meanings.Count -eq 1){foreach($entry in $meanings){$state=$entry}}
    $messages=@{
        'existing-unhosted'='最新有效记录：复用了已运行的普通客户端，未建立新的壁纸接入。请先保存工作、正常完全退出 Codex，再从本包最外层 Launch.exe 启动一次；不要反复连点。'
        'replay-target-unavailable'='最新启动请求记录：重复启动分支未找到可验证的目标窗口，本次在重播前退出，未播放启动动画，也未再次激活客户端。不能据此认定原有客户端或壁纸已经关闭。请保留当前状态并发送报告，无需继续反复点击或等待。'
        'client-started'='最新有效记录：客户端已启动或复用；这条记录尚不能证明动态壁纸已经播放。'
        'disabled'='最新有效记录：壁纸功能处于禁用路径。'
        'host-unavailable'='最新有效记录：壁纸宿主缺失或未能启动。请检查完整解压情况并发送报告。'
        'connection-unknown'='最新有效记录：壁纸连接状态未确认；程序没有启动第二份客户端。'
        'activation-failed'='最新有效记录：客户端启动失败。'
        'layout-failed'='最新有效记录：页面布局未满足壁纸适配条件；不能仅凭此记录认定视频素材缺失。'
        'composer-ambiguous'='最新有效记录：输入区域布局存在歧义，壁纸按保护规则暂停接入。'
        'first-frame-failed'='最新有效记录：视频或首帧准备没有完成；可能涉及解码、页面或时序，尚不能确定具体原因。'
        'host-memory-failed'='最新有效记录：壁纸宿主因内存保护终止了本次准备（错误码 174），本次壁纸会话已停用。启动器释放动画或保留准备的请求不能撤销这条终态失败；这不证明素材缺失或解码失败。'
        'host-memory-suspended'='最新有效记录：壁纸宿主已请求内存保护暂停，保留会话等待可用提交内存余量恢复；这不属于错误码 174 的终态停用，也不能单凭该请求确认解码资源已经释放。'
        'host-memory-resume-requested'='最新有效记录：壁纸宿主已请求恢复，仍需后续首帧、播放和样式证据；不能把恢复请求视为播放成功。'
        'renderer-memory-suspended'='壁纸渲染器的最新快照仍处于内存保护暂停；这不是永久停用，也不是已恢复播放的证明。快照本身不能确定触发时的提交内存精确值。'
        'preparation-timeout'='最新有效记录：准备超过安全期限，启动器停止等待。无需再次长时间等待。'
        'host-failed'='最新有效记录：壁纸宿主报告故障，需要结合报告中的固定错误码分析。'
        'media-error'='最新有效记录：视频媒体组件报告错误；文件存在不代表目标电脑能够成功解码。'
        'playback-failed'='最新有效记录：播放、首帧或恢复发生异常，需要结合媒体和通信记录分析。'
        'ended'='最新有效记录：壁纸渲染已结束；这也可能发生在正常退出过程中。'
        'media-rejected'='最新有效记录：媒体输入未通过播放器检查。'
        'hidden'='最新有效记录：页面不可见，壁纸可能按节省资源规则暂停；不可见不等于崩溃。'
        'gap'='最新有效记录：处于两次角色出现之间的正常间隔。'
        'observed-playing'='最新有效记录：当时确认了首帧、播放和透明壁纸样式；这不保证采集时仍在播放。'
        'prepared-only'='最新有效记录：媒体已经准备，但这条记录不能证明完成展示。'
        'layout-only'='最新有效记录：页面布局通过检查，但尚不能证明视频已播放。'
        'snapshot-unconfirmed'='没有可解释的本次播放证明：最新状态字段不完整、相互矛盾或属于过期快照，不能继续采用更早的播放成功记录。'
    }
    if($meanings.Count -gt 1){$lines.Add('同一最新时间出现相互不同的状态记录，不能选其中一条断言成功或失败。')}
    elseif($messages.ContainsKey($state)){$lines.Add($messages[$state])}
    else{$lines.Add('没有可解释的本次运行状态记录；日志缺失、过期快照或未知字段均不能证明运行成功或失败。')}
    foreach($line in (Get-CodexCompletedStartupAnalysis $Report)){$lines.Add($line)}
    foreach($line in (Get-CodexResourceProtectionAnalysis $Report)){$lines.Add($line)}
    $lines.Add('这里没有执行显卡、驱动或解码压力测试。累计帧数和丢帧数不是实时 FPS，也不能单独证明卡顿程度。')
    $lines.Add('若画面仍有问题，请发送同目录的 latest-report.zip，并说明是否看到启动动画、流泪转场和壁纸。无需上传原始日志、账号配置或整个运行目录。')
    $lines.Add('诊断不会启动或关闭应用，不会下载依赖，不需要反复重启或长时间等待。')
    $text=$lines -join [Environment]::NewLine
    if($text.Length -gt 16384){return '诊断说明超出安全长度，未输出详细内容。请发送同目录的 latest-report.zip。'}
    return $text
}
