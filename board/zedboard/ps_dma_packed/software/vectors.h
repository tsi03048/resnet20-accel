/* Generated from frozen E2-B; Golden scores are PS-side checks only. */
#ifndef PS_DMA_VECTORS_H
#define PS_DMA_VECTORS_H
#include <stdint.h>
#define ACCEL_BASE 0x43c00000u
#define DMA_BASE 0x40400000u
#define RX_BASE 0x02200000u
#define REPORT_BASE 0x03000000u
struct packet { uint32_t address, bytes; };
static const struct packet input_packets[2] = {
    {0x02000000u,3084u},
    {0x02004000u,3084u},
};
static const struct packet constants[4] = {
    {0x02010000u,268348u},
    {0x02120000u,2804u},
    {0x02124000u,2804u},
    {0x02128000u,2804u},
};
static const int32_t expected_scores[2][10] = {
    {-381997,-36909,46541,1586887,-259757,306431,35286,-351394,-276301,-666530},
    {375818,759555,-571137,-422553,-786112,-518376,-400169,-532279,2082934,15190},
};
static const uint32_t expected_prediction[2]={3u,8u};
#endif
