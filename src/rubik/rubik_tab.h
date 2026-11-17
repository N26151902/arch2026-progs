#pragma once

#include <stdint.h>

/* Tables from mytests/gen_rubik.c (the assembly has its own copy).
 * near: (key << 2) | distance mod 3, sorted; far: keys at distance 11;
 * ori_move[m][oc]: orientation after move m.
 */
#define RUBIK_NNEAR 12224
#define RUBIK_NFAR 2644
#define RUBIK_NORI 729

extern const uint32_t rubik_near[RUBIK_NNEAR];
extern const uint32_t rubik_far[RUBIK_NFAR];
extern const uint16_t rubik_ori_move[9][RUBIK_NORI];
