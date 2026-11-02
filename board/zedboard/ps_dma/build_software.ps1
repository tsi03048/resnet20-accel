param([string]$Gcc='C:/Xilinx/2025.1/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe')
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$out=Join-Path $root 'build/ps_dma_software';New-Item -ItemType Directory -Path $out -Force | Out-Null
$source=Join-Path $PSScriptRoot 'software'
if(!(Test-Path -LiteralPath $Gcc)){throw "ARM compiler not found: $Gcc"}
$stage=Join-Path $env:TEMP ('r20sw_'+[guid]::NewGuid().ToString('N').Substring(0,6))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Copy-Item -LiteralPath "$source/start.S","$source/main.c","$source/link.ld","$source/vectors.h" -Destination $stage
Push-Location -LiteralPath $stage
try {
    & $Gcc -mcpu=cortex-a9 -marm -mfloat-abi=soft -O2 -Wall -Wextra -Werror -ffreestanding -fno-builtin -fno-unwind-tables -fno-asynchronous-unwind-tables -nostdlib '-Wl,--build-id=none' '-Wl,-Map,app.map' -T link.ld start.S main.c -o app.elf -lgcc
    if($LASTEXITCODE -ne 0){throw 'ARM software compilation failed.'}
    Copy-Item -LiteralPath app.elf,app.map -Destination $out
} finally {Pop-Location}
& $Gcc --version | Select-Object -First 1 | Set-Content (Join-Path $out 'compiler.txt')
$hashes=[ordered]@{}
foreach($name in @('start.S','main.c','link.ld','vectors.h')){$hashes['board/zedboard/ps_dma/software/'+$name]=(Get-FileHash -LiteralPath (Join-Path $source $name) -Algorithm SHA256).Hash.ToLower()}
[ordered]@{status='ARM_ELF_BUILT';executed_on_board=$false;compiler=(Get-Content (Join-Path $out 'compiler.txt'));elf_sha256=(Get-FileHash -LiteralPath (Join-Path $out 'app.elf') -Algorithm SHA256).Hash.ToLower();source_sha256=$hashes} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $root 'results/ps_dma_software_build.json') -Encoding utf8
Get-FileHash -LiteralPath (Join-Path $out 'app.elf') -Algorithm SHA256
Write-Output 'ARM_ELF_BUILT (not executed on board)'
