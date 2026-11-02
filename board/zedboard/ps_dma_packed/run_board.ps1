param([Parameter(Mandatory=$true)][string]$RunDirectory,[string]$Xsdb='C:/Xilinx/2025.1/Vitis/bin/xsdb.bat',[string]$Python='python')
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$run=(Resolve-Path -LiteralPath $RunDirectory).Path
$stage=Join-Path $env:TEMP ('r20board_'+[guid]::NewGuid().ToString('N').Substring(0,6))
$output=Join-Path $root ('results/board_ps_dma_packed_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path "$stage/inputs",$output -Force | Out-Null
Push-Location $root
try {
    & $Python -m tools.ps_dma_packed_vectors
    if($LASTEXITCODE -ne 0){throw 'Generate/verify packets before board execution.'}
    foreach($name in @('system.bit','ps7_init.tcl')){Copy-Item -LiteralPath (Join-Path $run ('output/'+$name)) -Destination $stage}
    Copy-Item -LiteralPath (Join-Path $root 'build/ps_dma_packed_software/app.elf') -Destination $stage
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'run_board.tcl') -Destination $stage
    Get-ChildItem -LiteralPath (Join-Path $root 'reference/ps_dma_packed') -File | Where-Object {$_.Extension -in @('.bin','.tcl','.json')} | Copy-Item -Destination "$stage/inputs"
    $hashes=[ordered]@{}
    Get-ChildItem -LiteralPath $stage -Recurse -File | ForEach-Object {$hashes[$_.FullName.Substring($stage.Length+1).Replace('\','/')]=(Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()}
    [ordered]@{started_at=(Get-Date).ToString('o');scope='Actual connected board execution attempt';system_run=$run;bundle_sha256=$hashes} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $output 'launch_manifest.json') -Encoding utf8
    Push-Location $stage
    try {& $Xsdb run_board.tcl $stage 2>&1 | Tee-Object -FilePath (Join-Path $output 'xsdb.log');$code=$LASTEXITCODE} finally {Pop-Location}
    if(Test-Path "$stage/board_report.words"){Copy-Item -LiteralPath "$stage/board_report.words" -Destination $output}
    if($code -ne 0){throw 'Board execution failed; inspect the saved XSDB log/report.'}
    & $Python -m tools.ps_dma_packed_board_report --words (Join-Path $output 'board_report.words') --output (Join-Path $output 'validated.json')
    if($LASTEXITCODE -ne 0){throw 'Board report comparison failed.'}
} finally {Pop-Location}
Write-Output "BOARD_REPORT_VALIDATED: $output"
