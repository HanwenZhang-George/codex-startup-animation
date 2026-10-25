[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$WorkRoot)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSVersion.Major -ne 5){throw 'Requires Windows PowerShell 5.1'}
$source=Split-Path -Parent $PSScriptRoot
. (Join-Path $source 'packaging/CompatibilityProbe.ps1')
if(Test-Path -LiteralPath $WorkRoot){throw 'Fresh isolated output required'}
[void][IO.Directory]::CreateDirectory($WorkRoot)
$checks=0
function Check([bool]$Value,[string]$Name){if(-not $Value){throw ('FAIL '+$Name)};$script:checks++;Write-Output ('PASS '+$Name)}
function Save([string]$Path,[string]$Value){[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));[IO.File]::WriteAllText($Path,$Value,[Text.UTF8Encoding]::new($false))}
$fixture=Join-Path $WorkRoot 'package'
$packageName='OpenAI.Codex_26.1021.3705.0_x64__2p2nqsd0c76g0'
Save (Join-Path $fixture 'app/ChatGPT.exe') 'fixture only; never execute'
Save (Join-Path $fixture 'app/resources/app.asar') 'fixture only'
Save (Join-Path $fixture 'AppxManifest.xml') '<Package><Applications><Application Id="App" Executable="app\ChatGPT.exe"/></Applications></Package>'
$dll=Join-Path $WorkRoot 'Launch.exe'
$csc=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
& $csc /nologo /target:library /platform:x64 /warnaserror+ ('/out:'+$dll) (Join-Path $source 'src/OfficialIdentity.cs')
if($LASTEXITCODE -ne 0){throw 'Fixture assembly compilation failed'}
$record=@{files=@(@{path='Launch.exe';bytes=([IO.FileInfo]::new($dll)).Length;sha256=(Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash})}
$manifest=Join-Path $WorkRoot 'release-manifest.json'
Save $manifest ($record|ConvertTo-Json -Depth 4)
$resolver=Get-CodexProbeResolver $WorkRoot
Check ($null -ne $resolver) 'load matching assembly bytes without invoking entry point'
$direct=Read-CodexRegisteredProbePackage $packageName $fixture ([Diagnostics.Stopwatch]::StartNew()) 3000 $null
Check ($direct.rootPathReason -ceq 'ok' -and $direct.rootPathKind -ceq 'direct' -and $direct.runtimeEvidence -ceq 'electron-evidence') 'ordinary path has no assembly dependency'
$extended=Read-CodexRegisteredProbePackage $packageName ('\\?\'+$fixture) ([Diagnostics.Stopwatch]::StartNew()) 3000 $resolver
Check ($extended.readState -ceq 'ok' -and $extended.rootPathKind -ceq 'direct' -and $extended.runtimeEvidence -ceq 'electron-evidence') 'extended local DOS path uses runtime normalization'
$link=Join-Path $WorkRoot 'registered-alias'
[void](New-Item -ItemType Junction -Path $link -Target $fixture)
Check ((Get-CodexProbePathReason $link) -ceq 'reparse') 'strict generic path guard remains in place'
$legacy=Read-CodexProbePackage $packageName $link ([Diagnostics.Stopwatch]::StartNew()) 3000
Check ($legacy.readState -ceq 'blocked-root') 'unregistered arbitrary links still rejected'
$resolved=Read-CodexRegisteredProbePackage $packageName $link ([Diagnostics.Stopwatch]::StartNew()) 3000 $resolver
Check ($resolved.readState -ceq 'ok' -and $resolved.rootPathReason -ceq 'ok' -and $resolved.rootPathKind -ceq 'registered-alias' -and $resolved.runtimeEvidence -ceq 'electron-evidence') 'registered alias uses shared production resolver'
$noResolver=Read-CodexRegisteredProbePackage $packageName $link ([Diagnostics.Stopwatch]::StartNew()) 3000 $null
Check ($noResolver.readState -ceq 'blocked-root' -and $noResolver.rootPathReason -ceq 'reparse') 'missing resolver never grants trust'
$expired=Read-CodexRegisteredProbePackage $packageName $link ([Diagnostics.Stopwatch]::StartNew()) 0 $resolver
Check ($expired.readState -ceq 'blocked-root' -and $expired.rootPathReason -ceq 'reparse') 'expired budget never resolves aliases'
foreach($path in @('\\server\PRIVATE','\\?\UNC\server\PRIVATE','\\?\GLOBALROOT\Device\PRIVATE','C:\PRIVATE:stream','C:\PRIVATE\..\Windows')){
    $blocked=Read-CodexRegisteredProbePackage $packageName $path ([Diagnostics.Stopwatch]::StartNew()) 3000 $resolver
    Check ($blocked.readState -ceq 'blocked-root' -and $blocked.rootPathReason -ceq 'invalid-path') 'invalid roots rejected before resolver'
}
$missing=Read-CodexRegisteredProbePackage $packageName (Join-Path $WorkRoot 'missing') ([Diagnostics.Stopwatch]::StartNew()) 3000 $resolver
Check ($missing.rootPathReason -ceq 'missing' -and $missing.readState -ceq 'blocked-root') 'missing path has explicit bounded reason'
$json=@($direct,$resolved,$noResolver,$expired,$missing)|ConvertTo-Json -Depth 8
Check (-not $json.Contains($WorkRoot) -and $json -notmatch 'PRIVATE|apiKey|OpenAI\.Codex_|[A-Z]:\\|Exception') 'projection exports no paths or arbitrary exception body'
$record.files[0].sha256='0'*64;Save $manifest ($record|ConvertTo-Json -Depth 4)
Check ($null -eq (Get-CodexProbeResolver $WorkRoot)) 'hash mismatch rejects assembly before loading'
$record.files[0].sha256=(Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
$record.files+= $record.files[0];Save $manifest ($record|ConvertTo-Json -Depth 4)
Check ($null -eq (Get-CodexProbeResolver $WorkRoot)) 'duplicate executable record rejected'
Save $manifest '{PRIVATE'
Check ($null -eq (Get-CodexProbeResolver $WorkRoot)) 'malformed manifest does not load resolver'
[IO.File]::WriteAllText((Join-Path $WorkRoot 'results.json'),(@{passed=$true;checks=$checks;realApplicationsStarted=$false;networkUsed=$false}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
Write-Output ('ALL PASS: '+$checks+' registered path diagnostic checks')
