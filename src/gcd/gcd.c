#include "gcd.h"

/* Binary GCD (Stein): shifts and subtractions only. */
uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    if (a == 0)
        return b;
    if (b == 0)
        return a;

    /* common factors of two = trailing zeros of a | b */
    unsigned shift = 0;
    uint32_t both = a | b;
    while ((both & 1u) == 0) {
        both >>= 1;
        shift++;
    }

    while ((a & 1u) == 0)
        a >>= 1;
    while ((b & 1u) == 0)
        b >>= 1;

    /* a, b odd: replace the larger by the (even) difference */
    for (;;) {
        uint32_t diff = b - a;
        if (b < a) {
            diff = a - b;
            a = b;
        }
        if (diff == 0)
            break;
        do
            diff >>= 1;
        while ((diff & 1u) == 0);
        b = diff;
    }
    return a << shift;
}
