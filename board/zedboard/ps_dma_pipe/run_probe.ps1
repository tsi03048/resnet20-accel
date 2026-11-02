param([string]$VivadoPath='C:/Xilinx/2025.1/Vivado/bin/vivado.bat',[string]$Python='python')
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$stage=Join-Path $env:TEMP ('r20probe_'+[guid]::NewGuid().ToString('N').Substring(0,6))
$out=Join-Path $root ('build/pipe_probe_runs/probe_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $stage,$out -Force | Out-Null
$paths=@('rtl/full_e2b_v1/argmax10.sv','tb/ps_dma_v3/tb_pipe_probe.sv','tools/pipe_probe_vectors.py','board/zedboard/ps_dma_pipe/sim_probe.tcl','board/zedboard/ps_dma_pipe/run_probe.ps1')
$paths+=@(Get-ChildItem (Join-Path $root 'rtl/full_e2b_fpga_v3') -File | ForEach-Object {'rtl/full_e2b_fpga_v3/'+$_.Name})
$paths+=@(Get-ChildItem (Join-Path $root 'reference/pipe_probe') -File | ForEach-Object {'reference/pipe_probe/'+$_.Name})
$hashes=[ordered]@{}
foreach($p in $paths){$dst=Join-Path $stage $p;New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null;Copy-Item -LiteralPath (Join-Path $root $p) -Destination $dst;$sha=(Get-FileHash -LiteralPath (Join-Path $root $p) -Algorithm SHA256).Hash.ToLower();if((Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash.ToLower() -ne $sha){throw "Staging mismatch: $p"};$hashes[$p]=$sha}
[ordered]@{stage=$stage;scope='Synthetic four Stem pixels, per-MAC signed arithmetic and CE stalls; no physical board';source_sha256=$hashes} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $out 'launch_manifest.json') -Encoding utf8
Push-Location $stage
try {& $VivadoPath -mode batch -nojournal -log vivado.log -source board/zedboard/ps_dma_pipe/sim_probe.tcl;$code=$LASTEXITCODE}
finally {
    Pop-Location
    Copy-Item -LiteralPath (Join-Path $stage 'vivado.log') -Destination $out
    $sim=Join-Path $stage 'build/pipe_probe/project/pipe_probe.sim/sim_1/behav/xsim'
    foreach($name in @('simulate.log','xvlog.log','elaborate.log')){if(Test-Path (Join-Path $sim $name)){Copy-Item -LiteralPath (Join-Path $sim $name) -Destination $out}}
    if(Test-Path (Join-Path $stage 'results/pipe_probe/mac.csv')){Copy-Item -LiteralPath (Join-Path $stage 'results/pipe_probe/mac.csv') -Destination $out}
    foreach($p in $paths){$dst=Join-Path $out ('source_snapshot/'+$p);New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null;Copy-Item -LiteralPath (Join-Path $stage $p) -Destination $dst}
}
if($code -ne 0 -or !(Select-String -LiteralPath (Join-Path $out 'vivado.log') -Pattern '^PIPE_PROBE_PASS pixels=4 macs=108' -Quiet) -or (Select-String -LiteralPath (Join-Path $out 'vivado.log') -Pattern '^Fatal:' -Quiet)){throw "Pipe probe did not pass: $out"}
Push-Location $root
try {& $Python -m tools.pipe_probe_vectors --trace (Join-Path $out 'mac.csv') --output (Join-Path $out 'validation.json');if($LASTEXITCODE -ne 0){throw 'Independent MAC CSV comparison failed.'}} finally {Pop-Location}
Write-Output "PIPE_PROBE_PASS: $out"
