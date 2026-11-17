#include "bf16.h"

/* bf16 = upper 16 bits of a float (1 sign, 8 exponent, 7 fraction).
 * Integer operations only.
 */

#define BF16_EXP_BIAS 127
#define BF16_QNAN 0x7FC0u
#define BF16_INF 0x7F80u

/* round to nearest even: add 0x7FFF + bit 16, keep the top half */
uint16_t bf16_from_f32(uint32_t f32bits)
{
    if (((f32bits >> 23) & 0xFFu) == 0xFFu)
        return (uint16_t) (f32bits >> 16);
    f32bits += 0x7FFFu + ((f32bits >> 16) & 1u);
    return (uint16_t) (f32bits >> 16);
}

/* 8x8 shift-and-add multiply */
static uint32_t mul8(uint32_t x, uint32_t y)
{
    uint32_t p = 0;
    while (y) {
        if (y & 1u)
            p += x;
        x <<= 1;
        y >>= 1;
    }
    return p;
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint32_t sign_a = (uint32_t) (a >> 15), sign_b = (uint32_t) (b >> 15);
    int32_t exp_a = (a >> 7) & 0xFF, exp_b = (b >> 7) & 0xFF;
    uint32_t mant_a = a & 0x7Fu, mant_b = b & 0x7Fu;
    uint32_t sign = (sign_a ^ sign_b) << 15;

    /* special values; a is checked before b */
    if (exp_a == 0xFF) {
        if (mant_a)
            return a;
        if (!exp_b && !mant_b)
            return BF16_QNAN;
        return (uint16_t) (sign | BF16_INF);
    }
    if (exp_b == 0xFF) {
        if (mant_b)
            return b;
        if (!exp_a && !mant_a)
            return BF16_QNAN;
        return (uint16_t) (sign | BF16_INF);
    }
    if ((!exp_a && !mant_a) || (!exp_b && !mant_b))
        return (uint16_t) sign;

    /* normalize denormals */
    int32_t exp_adjust = 0;
    if (!exp_a) {
        while (!(mant_a & 0x80u)) {
            mant_a <<= 1;
            exp_adjust--;
        }
        exp_a = 1;
    } else {
        mant_a |= 0x80u;
    }
    if (!exp_b) {
        while (!(mant_b & 0x80u)) {
            mant_b <<= 1;
            exp_adjust--;
        }
        exp_b = 1;
    } else {
        mant_b |= 0x80u;
    }

    /* product in [1, 4); fraction is truncated */
    uint32_t prod = mul8(mant_a, mant_b);
    int32_t exp = exp_a + exp_b - BF16_EXP_BIAS + exp_adjust;
    uint32_t frac;
    if (prod & 0x8000u) {
        frac = (prod >> 8) & 0x7Fu;
        exp++;
    } else {
        frac = (prod >> 7) & 0x7Fu;
    }

    if (exp >= 0xFF)
        return (uint16_t) (sign | BF16_INF);
    if (exp <= 0) {
        if (exp < -6)
            return (uint16_t) sign;
        frac >>= 1 - exp;
        exp = 0;
    }
    return (uint16_t) (sign | ((uint32_t) exp << 7) | frac);
}

/* digit-by-digit integer square root, no multiply */
static uint32_t isqrt16(uint32_t n)
{
    uint32_t root = 0, bit = 1u << 14;
    while (bit) {
        if (n >= root + bit) {
            n -= root + bit;
            root = (root >> 1) + bit;
        } else {
            root >>= 1;
        }
        bit >>= 2;
    }
    return root;
}

uint16_t bf16_sqrt(uint16_t a)
{
    uint32_t sign = (uint32_t) (a >> 15);
    int32_t exp = (a >> 7) & 0xFF;
    uint32_t mant = a & 0x7Fu;

    if (exp == 0xFF) {
        if (mant)
            return a;
        if (sign)
            return BF16_QNAN;
        return a;
    }
    if (!exp && !mant)
        return 0;
    if (sign)
        return BF16_QNAN;
    if (!exp)
        return 0;

    int32_t e = exp - BF16_EXP_BIAS;
    uint32_t m = 0x80u | mant;
    int32_t new_exp;
    if (e & 1) { /* odd exponent: double m */
        m <<= 1;
        new_exp = ((e - 1) >> 1) + BF16_EXP_BIAS;
    } else {
        new_exp = (e >> 1) + BF16_EXP_BIAS;
    }

    /* largest r with r * r / 128 <= m */
    uint32_t r = isqrt16(((m + 1u) << 7) - 1u);
    return (uint16_t) (((uint32_t) new_exp << 7) | (r & 0x7Fu));
}
