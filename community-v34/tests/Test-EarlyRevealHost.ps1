[CmdletBinding()]
param([string]$SourceRoot,[Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$testDirectory=Split-Path -Parent $PSCommandPath
if([string]::IsNullOrWhiteSpace($SourceRoot)){$SourceRoot=Split-Path -Parent $testDirectory}
$sourceFull=[IO.Path]::GetFullPath($SourceRoot).TrimEnd('\','/')
$outputFull=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\','/')
if($outputFull -eq $sourceFull -or $outputFull.StartsWith($sourceFull+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Test artifacts must remain outside source project'}
$files=@(Get-ChildItem -LiteralPath (Join-Path $sourceFull 'wallpaper-host-src') -Filter '*.cs' | ForEach-Object FullName)
if($files.Count -ne 5){throw 'Expected five host source files'}
$files+=Join-Path $sourceFull 'src\OfficialIdentity.cs'
[void][IO.Directory]::CreateDirectory($outputFull)
$fixtureDirectory=Join-Path $outputFull ('fixture-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixtureDirectory)
$assembly=Join-Path $fixtureDirectory 'EarlyRevealHostTests.exe'
$framework=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$metadata=Join-Path $sourceFull 'build-inputs\RuntimeMetadata.cs'
$manifest=Join-Path $sourceFull 'build-inputs\Runtime.manifest'
& (Join-Path $framework 'csc.exe') /nologo /target:exe /platform:x64 /warn:4 /warnaserror+ /main:CodexDragonWallpaper.EarlyRevealHostTests /r:System.Web.Extensions.dll ('/win32manifest:'+$manifest) ('/out:'+$assembly) @files $metadata (Join-Path $testDirectory 'EarlyRevealHostTests.cs')
if($LASTEXITCODE -ne 0){throw 'Early reveal host compilation failed'}
$result=@(& $assembly $fixtureDirectory);$code=$LASTEXITCODE
[IO.File]::WriteAllText((Join-Path $outputFull 'results.json'),($result -join [Environment]::NewLine),[Text.UTF8Encoding]::new($false))
$hashes=@(foreach($file in $files){[pscustomobject]@{file=$file.Substring($sourceFull.Length+1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash}})
[IO.File]::WriteAllText((Join-Path $outputFull 'source-hashes.json'),($hashes|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
$result
exit $code
