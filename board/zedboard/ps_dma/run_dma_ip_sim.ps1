param([string]$VivadoPath='C:/Xilinx/2025.1/Vivado/bin/vivado.bat')
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$stage=Join-Path $env:TEMP ('r20dma_'+[guid]::NewGuid().ToString('N').Substring(0,6))
$destination=Join-Path $root ('build/dma_ip_runs/dma_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path "$stage/board/zedboard/ps_dma","$stage/tb/ps_dma_v1",$destination -Force | Out-Null
$hashes=[ordered]@{}
foreach($p in @('board/zedboard/ps_dma/sim_dma_ip.tcl','tb/ps_dma_v1/tb_dma_ip.sv')){
    Copy-Item -LiteralPath (Join-Path $root $p) -Destination (Join-Path $stage $p)
    $hashes[$p]=(Get-FileHash -LiteralPath (Join-Path $root $p) -Algorithm SHA256).Hash.ToLower()
}
[ordered]@{started_at=(Get-Date).ToString('o');stage=$stage;scope='Real DMA IP with AXI DDR/PS BFMs, loopback only';source_sha256=$hashes} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $destination 'launch_manifest.json') -Encoding utf8
Push-Location $stage
try {& $VivadoPath -mode batch -nojournal -log vivado.log -source board/zedboard/ps_dma/sim_dma_ip.tcl;$code=$LASTEXITCODE}
finally {
    Pop-Location
    Copy-Item -LiteralPath (Join-Path $stage 'vivado.log') -Destination $destination
    $sim=Join-Path $stage 'build/dma_ip_sim/project/dma_ip_sim.sim/sim_1/behav/xsim'
    foreach($p in @('simulate.log','xsim.log','xvlog.log','elaborate.log')){if(Test-Path (Join-Path $sim $p)){Copy-Item -LiteralPath (Join-Path $sim $p) -Destination $destination}}
}
if($code -ne 0 -or !(Select-String -LiteralPath (Join-Path $destination 'vivado.log') -Pattern '^DMA_IP_PASS ' -Quiet)){throw "Actual DMA IP simulation did not pass: $destination"}
Write-Output "DMA_IP_SIMULATION_PASS: $destination"
