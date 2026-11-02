/* Freestanding Cortex-A9 polling example: no OS, BSP, IRQ or SD-card dependency.
 * Startup runs with MMU/cache disabled. Cache-enabled applications must add
 * clean/flush before MM2S and invalidate after S2MM (HP0 is not coherent).
 */
#include <stdint.h>
#include "vectors.h"
static volatile uint32_t *const report=(volatile uint32_t *)REPORT_BASE;
static inline void barrier(void){__asm__ volatile("dsb sy":::"memory");}
static inline uint32_t rd(uint32_t a){return *(volatile uint32_t *)(uintptr_t)a;}
static inline void wr(uint32_t a,uint32_t v){*(volatile uint32_t *)(uintptr_t)a=v;barrier();}
static uint64_t ticks(void){
    uint32_t hi,lo,again;
    do {hi=rd(0xf8f00204u);lo=rd(0xf8f00200u);again=rd(0xf8f00204u);}while(hi!=again);
    return ((uint64_t)hi<<32)|lo;
}
static int expired(uint64_t start){return ticks()-start>60000000000ull;}
static int fail(uint32_t code){
    report[2]=code;report[4]=rd(DMA_BASE+4);report[5]=rd(DMA_BASE+0x34);
    report[6]=rd(ACCEL_BASE+8);report[7]=rd(ACCEL_BASE+0x10);barrier();report[1]=0x80000000u|code;barrier();return -1;
}
static int dma_reset(void){
    uint64_t t=ticks();wr(DMA_BASE,4);
    while(rd(DMA_BASE)&4u) if(expired(t)) return fail(0x10);
    wr(DMA_BASE+4,0x7000);wr(DMA_BASE+0x34,0x7000);
    wr(DMA_BASE,1);wr(DMA_BASE+0x30,1);return 0;
}
static int dma_wait(uint32_t channel){
    uint64_t t=ticks();uint32_t s;
    for(;;){s=rd(DMA_BASE+channel+4);
        if(s&0x770u) return fail(0x20u+channel);
        if((s&0x1002u)==0x1002u) break;
        if(expired(t)) return fail(0x30u+channel);
    }
    wr(DMA_BASE+channel+4,0x7000);return 0;
}
static int send(struct packet p){
    wr(DMA_BASE+4,0x7000);wr(DMA_BASE+0x18,p.address);
    barrier();wr(DMA_BASE+0x28,p.bytes); /* Length is the final DMA doorbell write. */
    if(dma_wait(0)) return -1;
    if(rd(ACCEL_BASE+0x10)) return fail(0x40);
    return 0;
}
static int launch(uint32_t sample,uint32_t tag){
    wr(ACCEL_BASE+0x0c,tag);wr(ACCEL_BASE+4,1);
    for(uint32_t i=0;i<16;i++) wr(RX_BASE+i*4,0xa5a5a5a5);
    wr(DMA_BASE+0x34,0x7000);wr(DMA_BASE+0x48,RX_BASE);wr(DMA_BASE+0x58,64); /* Arm S2MM first. */
    if(send(input_packets[sample])) return -1;
    for(uint32_t i=0;i<4;i++) if(send(constants[i])) return -1;
    if((rd(ACCEL_BASE+8)&0x45u)!=5u || rd(ACCEL_BASE+0x14)!=273502u) return fail(0x41);
    wr(ACCEL_BASE+4,2);return 0;
}
static int complete(uint32_t job,uint32_t sample,uint32_t tag){
    if(dma_wait(0x30)) return -1;
    barrier();
    if(rd(RX_BASE)!=0x52323052u || rd(RX_BASE+4)!=tag || rd(RX_BASE+8)!=0 || rd(RX_BASE+12)!=expected_prediction[sample]) return fail(0x50);
    for(uint32_t i=0;i<10;i++) if((int32_t)rd(RX_BASE+16+i*4)!=expected_scores[sample][i]) return fail(0x51u+i);
    if((rd(ACCEL_BASE+8)&0x78u)!=0x20u || rd(ACCEL_BASE+0x18)!=16u) return fail(0x60);
    for(uint32_t i=0;i<16;i++) report[8+job*16+i]=rd(RX_BASE+i*4);
    barrier();report[3]=job+1;barrier();return 0;
}
int main(void){
    for(uint32_t i=0;i<128;i++) report[i]=0;
    report[0]=0x52325053u;report[1]=1;barrier();
    wr(0xf8f00208u,1); /* Global timer, prescaler=0, interrupt disabled. */
    if(rd(ACCEL_BASE)!=0x52323031u) return fail(1);
    if(dma_reset()) return -1;
    wr(ACCEL_BASE+4,4);
    const uint32_t order[3]={0,1,0};
    for(uint32_t job=0;job<3;job++){
        uint32_t tag=0xc9000000u+job;report[2]=0x100u+job;
        if(launch(order[job],tag) || complete(job,order[job],tag)) return -1;
    }
    /* Abort a real compute job, reset both DMA and accelerator, then reload. */
    report[2]=0x200;
    if(launch(0,0xca000000u)) return -1;
    uint64_t t=ticks();while(!(rd(ACCEL_BASE+8)&8u)) if(expired(t)) return fail(0x70);
    if(dma_reset()) return -1;
    wr(ACCEL_BASE+4,4);
    if(rd(ACCEL_BASE+8)!=0 || rd(ACCEL_BASE+0x14)!=0 || rd(ACCEL_BASE+0x18)!=0) return fail(0x71);
    if(launch(1,0xc9000003u) || complete(3,1,0xc9000003u)) return -1;
    report[2]=0;barrier();report[1]=2;barrier();return 0;
}
