param([string]$VivadoPath='C:/Xilinx/2025.1/Vivado/bin/vivado.bat')
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$stage=Join-Path $env:TEMP ('r20reset_'+[guid]::NewGuid().ToString('N').Substring(0,6))
$out=Join-Path $root ('build/timing_reset_runs/reset_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $stage,$out -Force | Out-Null
$paths=@('rtl/full_e2b_v1/argmax10.sv','rtl/ps_dma_v3/resnet20_axi_packed.sv','tb/ps_dma_timing/tb_timing_reset.sv','board/zedboard/ps_dma_timing/sim_packed_reset.tcl','board/zedboard/ps_dma_timing/run_packed_reset.ps1')
foreach($name in @('full_model.sv','feature_ram.sv','sync_bram.sv','weight_bram.sv','mul_serial.sv','rne_serial.sv','control_rom.svh')){$paths+='rtl/full_e2b_fpga_v3/'+$name}
$hashes=[ordered]@{}
foreach($p in $paths){
    $target=Join-Path $stage $p;New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $root $p) -Destination $target
    $digest=(Get-FileHash -LiteralPath (Join-Path $root $p) -Algorithm SHA256).Hash.ToLower()
    if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLower() -ne $digest){throw "Staging mismatch: $p"}
    $hashes[$p]=$digest
}
[ordered]@{stage=$stage;scope='Unpacker lane Reset RTL test; synthetic input pattern; no physical board';source_sha256=$hashes} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $out 'launch_manifest.json') -Encoding utf8
Push-Location $stage
try {& $VivadoPath -mode batch -nojournal -log vivado.log -source board/zedboard/ps_dma_timing/sim_packed_reset.tcl;$code=$LASTEXITCODE}
finally {
    Pop-Location
    Copy-Item -LiteralPath (Join-Path $stage 'vivado.log') -Destination $out
    $sim=Join-Path $stage 'build/packed_reset/project/packed_reset.sim/sim_1/behav/xsim'
    foreach($name in @('simulate.log','xvlog.log','elaborate.log')){if(Test-Path (Join-Path $sim $name)){Copy-Item -LiteralPath (Join-Path $sim $name) -Destination $out}}
    foreach($p in $paths){$target=Join-Path $out ('source_snapshot/'+$p);New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null;Copy-Item -LiteralPath (Join-Path $stage $p) -Destination $target}
}
if($code -ne 0 -or !(Select-String -LiteralPath (Join-Path $out 'vivado.log') -Pattern '^PACKED_RESET_PASS hard_reset_lanes=4 soft_reset_collision=1' -Quiet) -or (Select-String -LiteralPath (Join-Path $out 'vivado.log') -Pattern '^Fatal:' -Quiet)){throw "Packed Reset test did not pass: $out"}
Write-Output "PACKED_RESET_SIMULATION_PASS: $out"
