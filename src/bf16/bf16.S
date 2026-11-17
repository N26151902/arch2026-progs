# bf16_from_f32, bf16_mul, bf16_sqrt in RV32I. Leaf functions, no stack frame.

    .text

    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
# bf16_from_f32_asm(a0 = float bits) -> a0
bf16_from_f32_asm:
    slli    t0, a0, 1
    lui     t1, 0xFF000
    bgeu    t0, t1, .Lf32_special   # Inf / NaN
    srli    t2, a0, 16
    andi    t2, t2, 1               # bit 16
    lui     t1, 8
    addi    t1, t1, -1              # 0x7FFF
    add     a0, a0, t2
    add     a0, a0, t1
.Lf32_special:
    srli    a0, a0, 16
    ret
    .size   bf16_from_f32_asm, .-bf16_from_f32_asm

    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2
# bf16_mul_asm(a0 = a, a1 = b) -> a0
# t0/t1 exponents, t2/t3 significands, a2 exponent, a3 product, t6 sign
bf16_mul_asm:
    xor     t6, a0, a1
    lui     t5, 8
    and     t6, t6, t5              # sign
    srli    t0, a0, 7
    andi    t0, t0, 0xFF
    srli    t1, a1, 7
    andi    t1, t1, 0xFF
    li      t5, 0xFF
    beq     t0, t5, .Lmul_a_special
    beq     t1, t5, .Lmul_b_special
    slli    t5, a0, 17              # a == 0?
    beqz    t5, .Lmul_zero
    slli    t5, a1, 17              # b == 0?
    beqz    t5, .Lmul_zero

    andi    t2, a0, 0x7F
    andi    t3, a1, 0x7F
    add     a2, t0, t1
    beqz    t0, .Lmul_a_denormal
    ori     t2, t2, 0x80
.Lmul_a_ready:
    beqz    t1, .Lmul_b_denormal
    ori     t3, t3, 0x80
.Lmul_b_ready:

    # 8x8 product, unrolled (bit 7 is always set)
    slli    a3, t2, 7
    andi    t4, t3, 0x40
    beqz    t4, 1f
    slli    t5, t2, 6
    add     a3, a3, t5
1:  andi    t4, t3, 0x20
    beqz    t4, 1f
    slli    t5, t2, 5
    add     a3, a3, t5
1:  andi    t4, t3, 0x10
    beqz    t4, 1f
    slli    t5, t2, 4
    add     a3, a3, t5
1:  andi    t4, t3, 0x08
    beqz    t4, 1f
    slli    t5, t2, 3
    add     a3, a3, t5
1:  andi    t4, t3, 0x04
    beqz    t4, 1f
    slli    t5, t2, 2
    add     a3, a3, t5
1:  andi    t4, t3, 0x02
    beqz    t4, 1f
    slli    t5, t2, 1
    add     a3, a3, t5
1:  andi    t4, t3, 0x01
    beqz    t4, 1f
    add     a3, a3, t2
1:
    addi    a2, a2, -127
    srli    t4, a3, 15              # product >= 2: shift one more
    beqz    t4, 1f
    srli    a3, a3, 1
    addi    a2, a2, 1
1:  srli    a3, a3, 7
    andi    a3, a3, 0x7F            # truncate
    li      t5, 0xFF
    bge     a2, t5, .Lmul_inf
    blez    a2, .Lmul_small
    slli    a2, a2, 7
    or      a0, t6, a2
    or      a0, a0, a3
    ret

.Lmul_small:                        # denormal result
    li      t5, -6
    blt     a2, t5, .Lmul_zero
    li      t5, 1
    sub     t5, t5, a2
    srl     a3, a3, t5
    or      a0, t6, a3
    ret

.Lmul_a_denormal:                   # normalize a
    addi    a2, a2, 1
1:  andi    t4, t2, 0x80
    bnez    t4, .Lmul_a_ready
    slli    t2, t2, 1
    addi    a2, a2, -1
    j       1b

.Lmul_b_denormal:                   # normalize b
    addi    a2, a2, 1
1:  andi    t4, t3, 0x80
    bnez    t4, .Lmul_b_ready
    slli    t3, t3, 1
    addi    a2, a2, -1
    j       1b

.Lmul_a_special:                    # a is Inf or NaN
    andi    t4, a0, 0x7F
    bnez    t4, .Lmul_ret
    slli    t5, a1, 17
    beqz    t5, .Lmul_nan
    j       .Lmul_inf

.Lmul_b_special:                    # b is Inf or NaN
    andi    t4, a1, 0x7F
    bnez    t4, .Lmul_ret_b
    slli    t5, a0, 17
    beqz    t5, .Lmul_nan
.Lmul_inf:
    li      t5, 0x7F80
    or      a0, t6, t5
.Lmul_ret:
    ret
.Lmul_ret_b:
    mv      a0, a1
    ret
.Lmul_nan:
    li      a0, 0x7FC0
    ret
.Lmul_zero:
    mv      a0, t6
    ret
    .size   bf16_mul_asm, .-bf16_mul_asm

    # one step of the digit-by-digit root
    .macro  ROOT_STEP bit
    addi    t2, a2, \bit
    srli    a2, a2, 1
    bltu    t3, t2, 1f
    sub     t3, t3, t2
    addi    a2, a2, \bit
1:
    .endm

    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2
# bf16_sqrt_asm(a0 = a) -> a0
# r = isqrt(128 * (m + 1) - 1), unrolled; t3 = n, a2 = root, a3 = exponent
bf16_sqrt_asm:
    srli    t0, a0, 7
    andi    t0, t0, 0xFF
    li      t1, 0xFF
    beq     t0, t1, .Lsqrt_special
    slli    t2, a0, 17
    beqz    t2, .Lsqrt_zero         # +0 / -0
    srli    t2, a0, 15
    bnez    t2, .Lsqrt_nan          # negative
    beqz    t0, .Lsqrt_zero         # denormal

    andi    t3, a0, 0x7F
    ori     t3, t3, 0x80
    andi    t1, t0, 1
    srli    a3, t0, 1
    add     a3, a3, t1
    addi    a3, a3, 63              # result exponent
    bnez    t1, 1f
    slli    t3, t3, 1               # even field: double m
1:  addi    t3, t3, 1
    slli    t3, t3, 7
    addi    t3, t3, -1              # n = 128 * (m + 1) - 1

    lui     a2, 4                   # first step folded in
    sub     t3, t3, a2
    lui     t5, 1
    add     t2, a2, t5
    srli    a2, a2, 1
    bltu    t3, t2, 1f
    sub     t3, t3, t2
    add     a2, a2, t5
1:  ROOT_STEP 1024
    ROOT_STEP 256
    ROOT_STEP 64
    ROOT_STEP 16
    ROOT_STEP 4
    ROOT_STEP 1

    andi    a2, a2, 0x7F            # drop leading one
    slli    a3, a3, 7
    or      a0, a3, a2
    ret

.Lsqrt_special:                     # NaN, +Inf unchanged; -Inf -> NaN
    li      t1, 0xFF80
    bne     a0, t1, .Lsqrt_ret
.Lsqrt_nan:
    li      a0, 0x7FC0
.Lsqrt_ret:
    ret
.Lsqrt_zero:
    li      a0, 0
    ret
    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
