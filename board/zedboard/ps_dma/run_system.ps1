param([string]$VivadoPath='C:/Xilinx/2025.1/Vivado/bin/vivado.bat',[string]$StageBase=$env:TEMP)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$name='ps_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'_'+[guid]::NewGuid().ToString('N').Substring(0,6)
$stage=Join-Path $StageBase ('r20p_'+[guid]::NewGuid().ToString('N').Substring(0,6))
if($stage -match '[^\x00-\x7F]'){throw 'Use an ASCII-only StageBase.'}
if(!(Test-Path -LiteralPath $VivadoPath)){throw "Vivado not found: $VivadoPath"}
$destination=Join-Path $root ('build/zedboard_ps_runs/'+$name)
New-Item -ItemType Directory -Path $stage,$destination -Force | Out-Null
$paths=@('board/zedboard/ps_dma/build_system.tcl','board/zedboard/ps_dma/run_system.ps1','rtl/ps_dma_v1/resnet20_axi.sv','rtl/ps_dma_v1/resnet20_axi_bd.v','rtl/full_e2b_v1/argmax10.sv')
foreach($file in @('full_model.sv','feature_ram.sv','sync_bram.sv','weight_bram.sv','mul_serial.sv','rne_serial.sv','control_rom.svh')){$paths+='rtl/full_e2b_fpga_v2/'+$file}
$paths+=@(Get-ChildItem -LiteralPath (Join-Path $root 'third_party/avnet_bdf') -Recurse -File | ForEach-Object {$_.FullName.Substring($root.Length+1).Replace('\','/')})
$hashes=[ordered]@{}
foreach($p in $paths){
    $src=Join-Path $root $p;$dst=Join-Path $stage $p
    New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null
    Copy-Item -LiteralPath $src -Destination $dst
    $hash=(Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash.ToLower()
    if((Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash.ToLower() -ne $hash){throw "Staging mismatch: $p"}
    $hashes[$p]=$hash
}
[ordered]@{started_at=(Get-Date).ToString('o');vivado=$VivadoPath;stage=$stage;destination=$destination;top='system_wrapper';part='xc7z020clg484-1';mode='complete_system';source_sha256=$hashes} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $destination 'launch_manifest.json') -Encoding utf8
Write-Output "PS system stage: $stage"
$code=1
Push-Location -LiteralPath $stage
try {& $VivadoPath -mode batch -nojournal -log vivado.log -source board/zedboard/ps_dma/build_system.tcl;$code=$LASTEXITCODE}
finally {
    Pop-Location
    foreach($p in $paths){$dst=Join-Path $destination ('source_snapshot/'+$p);New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null;Copy-Item -LiteralPath (Join-Path $stage $p) -Destination $dst}
    if(Test-Path (Join-Path $stage 'vivado.log')){Copy-Item -LiteralPath (Join-Path $stage 'vivado.log') -Destination $destination}
    $built=Join-Path $stage 'build/zedboard_ps'
    $output=Join-Path $destination 'output';New-Item -ItemType Directory -Path $output -Force | Out-Null
    if(Test-Path (Join-Path $built 'reports')){Copy-Item -LiteralPath (Join-Path $built 'reports') -Destination $output -Recurse}
    foreach($p in @('system.bit','system.xsa','system_post_route.dcp','system_export.tcl')){if(Test-Path (Join-Path $built $p)){Copy-Item -LiteralPath (Join-Path $built $p) -Destination $output}}
    $init=Get-ChildItem -LiteralPath $built -Recurse -Filter ps7_init.tcl -ErrorAction SilentlyContinue | Select-Object -First 1
    if($init){Copy-Item -LiteralPath $init.FullName -Destination (Join-Path $output 'ps7_init.tcl')}
}
Write-Output "PS system result: $destination"
if($code -ne 0 -or !(Test-Path (Join-Path $output 'reports/status.txt')) -or !(Select-String -LiteralPath (Join-Path $output 'reports/status.txt') -Pattern '^status=COMPLETE$' -Quiet)){throw 'System build did not complete. Inspect the saved log and status.'}
Write-Output 'PS_SYSTEM_BUILD_COMPLETE (review routed timing/resources separately; board execution not performed)'
