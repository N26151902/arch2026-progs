#include "fixed.h"

/* a + b with gates: xor = sum, and << 1 = carry; repeat until no carry */
uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    int passes = 0;
    while (b != 0) {
        uint32_t carry = (a & b) << 1;
        a ^= b;
        b = carry;
        passes++;
    }
    *n = passes;
    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

/* floor((a + b) / 2) without overflow: a + b = 2(a & b) + (a ^ b) */
uint32_t op3(uint32_t a, uint32_t b)
{
    return (a & b) + ((a ^ b) >> 1);
}

/* Q11.20: (a * b + 2^19) >> 20. 64-bit product from 16-bit halves, so only
 * 32-bit multiplies are used; then fix the high word for negative inputs.
 */
int32_t q_mul(int32_t a, int32_t b)
{
    uint32_t ua = (uint32_t) a, ub = (uint32_t) b;
    uint32_t al = ua & 0xFFFFu, ah = ua >> 16;
    uint32_t bl = ub & 0xFFFFu, bh = ub >> 16;

    uint32_t ll = al * bl, lh = al * bh, hl = ah * bl, hh = ah * bh;
    uint32_t mid = (ll >> 16) + (lh & 0xFFFFu) + (hl & 0xFFFFu);
    uint32_t lo = (mid << 16) | (ll & 0xFFFFu);
    uint32_t hi = hh + (lh >> 16) + (hl >> 16) + (mid >> 16);

    /* signed = unsigned - 2^32 * (other operand) */
    if (a < 0)
        hi -= ub;
    if (b < 0)
        hi -= ua;

    uint64_t p = (((uint64_t) hi << 32) | lo) + (1u << (Q - 1));
    return (int32_t) (uint32_t) (p >> Q);
}
