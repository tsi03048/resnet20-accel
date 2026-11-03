param([Parameter(Mandatory=$true)][string]$RunDirectory,[string]$VivadoPath='C:/Xilinx/2025.1/Vivado/bin/vivado.bat')
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$run=(Resolve-Path -LiteralPath $RunDirectory).Path
$stage=Join-Path $env:TEMP ('r20dcp_'+[guid]::NewGuid().ToString('N').Substring(0,6))
$out=Join-Path $root ('build/hold_checkpoint_checks/check_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $stage,$out -Force | Out-Null
$inputDcp=Join-Path $run 'output/system_post_route.dcp'
Copy-Item -LiteralPath $inputDcp -Destination (Join-Path $stage 'system.dcp')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'verify_checkpoint.tcl') -Destination $stage
$hashes=[ordered]@{}
foreach($name in @('verify_checkpoint.tcl','run_checkpoint_check.ps1')){$hashes['board/zedboard/ps_dma_hold/'+$name]=(Get-FileHash (Join-Path $PSScriptRoot $name) -Algorithm SHA256).Hash.ToLower();Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $out}
[ordered]@{scope='Reopen delivered routed DCP without modifying timing constraints or hardware';input_dcp_sha256=(Get-FileHash -LiteralPath $inputDcp -Algorithm SHA256).Hash.ToLower();source_sha256=$hashes} | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $out 'launch_manifest.json') -Encoding utf8
Push-Location $stage
try {& $VivadoPath -mode batch -nojournal -log vivado.log -source verify_checkpoint.tcl;$code=$LASTEXITCODE}
finally {Pop-Location;foreach($name in @('vivado.log','clocks.rpt','timing.rpt','check_timing.rpt')){if(Test-Path (Join-Path $stage $name)){Copy-Item -LiteralPath (Join-Path $stage $name) -Destination $out}}}
if($code -ne 0 -or !(Select-String -LiteralPath (Join-Path $out 'vivado.log') -Pattern '^HOLD_CHECKPOINT_REOPEN_COMPLETE' -Quiet)){throw "Checkpoint re-open failed: $out"}
Write-Output "HOLD_CHECKPOINT_REOPEN_COMPLETE: $out"
