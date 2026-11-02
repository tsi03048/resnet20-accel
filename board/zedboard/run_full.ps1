param(
    [ValidateSet('synth','route')][string]$Action='synth',
    [ValidateSet('baseline','flat','fpga','fpga2')][string]$Variant='fpga2',
    [string]$VivadoPath='C:/Xilinx/2025.1/Vivado/bin/vivado.bat',
    [string]$StageBase=$env:TEMP
)
$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$runName='run_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'_'+[guid]::NewGuid().ToString('N').Substring(0,6)
$stage=Join-Path $StageBase ('resnet20_zedboard_'+$runName)
if($stage -match '[^\x00-\x7F]'){throw 'Choose an ASCII-only StageBase path; Vivado Windows cannot reliably read this project path.'}
if(!(Test-Path -LiteralPath $VivadoPath)){throw "Vivado not found: $VivadoPath"}
$destination=Join-Path $projectRoot ('build/zedboard_full_runs/'+$runName)
New-Item -ItemType Directory -Path $stage,$destination -Force | Out-Null
$paths=@('rtl/full_e2b_v1/full_model.sv','rtl/full_e2b_v1/full_graph.svh','rtl/full_e2b_v1/requant_full.sv','rtl/full_e2b_v1/argmax10.sv','board/zedboard/full_core.xdc','board/zedboard/build_full.tcl')
if($Variant -eq 'flat'){$paths+=@('rtl/full_e2b_flat_v1/full_model.sv','rtl/full_e2b_flat_v1/manifest.json')}
if($Variant -eq 'fpga'){$paths+=@('rtl/full_e2b_fpga_v1/full_model.sv','rtl/full_e2b_fpga_v1/manifest.json','rtl/full_e2b_fpga_v1/feature_ram.sv')}
if($Variant -eq 'fpga2'){$paths+=@(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'rtl/full_e2b_fpga_v2') -File | ForEach-Object {'rtl/full_e2b_fpga_v2/'+$_.Name})}
$hashes=[ordered]@{}
foreach($relative in $paths){
    $source=Join-Path $projectRoot $relative
    $target=Join-Path $stage $relative
    New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $target
    $originalHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLower()
    if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLower() -ne $originalHash){throw "Staging hash mismatch: $relative"}
    $hashes[$relative]=$originalHash
}
$manifest=[ordered]@{started_at=(Get-Date).ToString('o');action=$Action;variant=$Variant;vivado=$VivadoPath;stage=$stage;destination=$destination;top=$(if($Variant -eq 'fpga2'){'full_model_timed'}else{'full_model'});part='xc7z020clg484-1';mode='out_of_context';source_sha256=$hashes}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $destination 'launch_manifest.json') -Encoding utf8
Write-Output "Running Vivado in ASCII stage: $stage"
$toolExit=1
Push-Location -LiteralPath $stage
try {
    & $VivadoPath -mode batch -nojournal -log vivado.log -source board/zedboard/build_full.tcl -tclargs $Action $Variant
    $toolExit=$LASTEXITCODE
} finally {
    Pop-Location
    foreach($relative in $paths){
        $saved=Join-Path $destination ('source_snapshot/'+$relative)
        New-Item -ItemType Directory -Path (Split-Path $saved) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $stage $relative) -Destination $saved
    }
    if(Test-Path -LiteralPath (Join-Path $stage 'vivado.log')){Copy-Item -LiteralPath (Join-Path $stage 'vivado.log') -Destination $destination}
    $generated=Join-Path $stage 'build/zedboard_full'
    if(Test-Path -LiteralPath $generated){Copy-Item -LiteralPath $generated -Destination (Join-Path $destination 'output') -Recurse}
}
$statusPath=Join-Path $destination 'output/reports/status.txt'
Write-Output "Reports copied to: $destination"
if($toolExit -ne 0 -or !(Test-Path -LiteralPath $statusPath) -or !(Select-String -LiteralPath $statusPath -Pattern '^status=COMPLETE$' -Quiet)){
    throw "Vivado did not complete the requested $Action run. Inspect $destination/vivado.log and output/reports/status.txt."
}
Write-Output 'VIVADO_RUN_COMPLETE (review resource fit and timing separately)'
