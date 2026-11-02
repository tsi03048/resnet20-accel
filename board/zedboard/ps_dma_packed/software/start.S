.syntax unified
.cpu cortex-a9
.arm
.global _start
.section .text.start,"ax"
_start:
    cpsid if
    /* JTAG entry is reset/initialized first. Run MMU, L1 D/I cache disabled. */
    dsb sy
    mrc p15,0,r0,c1,c0,0
    bic r0,r0,#1
    bic r0,r0,#4
    bic r0,r0,#0x1000
    mcr p15,0,r0,c1,c0,0
    isb
    ldr sp,=__stack_top
    ldr r0,=__bss_start
    ldr r1,=__bss_end
    mov r2,#0
1:  cmp r0,r1
    strlo r2,[r0],#4
    blo 1b
    bl main
2:  dsb sy
    wfi
    b 2b
