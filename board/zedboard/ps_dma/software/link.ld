ENTRY(_start)
MEMORY { DDR (rwx) : ORIGIN = 0x00100000, LENGTH = 0x00100000 }
SECTIONS {
    .text : { KEEP(*(.text.start)) *(.text*) *(.rodata*) } > DDR
    .data : { *(.data*) } > DDR
    .bss (NOLOAD) : { . = ALIGN(4); __bss_start = .; *(.bss*) *(COMMON) . = ALIGN(4); __bss_end = .; } > DDR
    __stack_top = ORIGIN(DDR) + LENGTH(DDR) - 16;
    ASSERT(__bss_end < __stack_top - 0x10000, "Application overlaps reserved stack")
}
