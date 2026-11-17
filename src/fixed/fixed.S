# op1/op2/op3/q_mul in RV32I. All leaf functions, no stack frame.

    .text

# op1_asm(a0 = a, a1 = b, a2 = &n) -> a0
# Loop unrolled twice; t1 = pass count.

    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    li      t1, 0
    beqz    a1, .Lop1_done
.Lop1_loop:
    and     t0, a0, a1
    xor     a0, a0, a1
    slli    a1, t0, 1
    beqz    a1, .Lop1_odd
    and     t0, a0, a1
    xor     a0, a0, a1
    slli    a1, t0, 1
    addi    t1, t1, 2
    bnez    a1, .Lop1_loop
.Lop1_done:
    sw      t1, 0(a2)
    ret
.Lop1_odd:
    addi    t1, t1, 1
    sw      t1, 0(a2)
    ret
    .size   op1_asm, .-op1_asm

    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    sub     a0, a0, a1
    ret
    .size   op2_asm, .-op2_asm

# (a & b) + ((a ^ b) >> 1)

    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    and     t0, a0, a1
    xor     a0, a0, a1
    srli    a0, a0, 1
    add     a0, a0, t0
    ret
    .size   op3_asm, .-op3_asm

# q_mul_asm(a0 = a, a1 = b) -> a0
# Shift-and-add over the smaller operand, 64-bit result in t1:t0.
# t2 = m >> 1, t3 = 31 - i, t4 = multiplier, t5 = m << i.

    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    mv      a4, a0                  # save a, b for the sign fix
    mv      a5, a1
    bgeu    a1, a0, 1f              # multiplier = smaller one
    mv      a0, a1
    mv      a1, a4
1:  li      t0, 0
    li      t1, 0
    beqz    a0, .Lq_signs
    mv      t4, a0
    mv      t5, a1
    srli    t2, a1, 1
    li      t3, 31
.Lq_loop:
    andi    t6, t4, 1
    beqz    t6, .Lq_skip
    add     t0, t0, t5
    sltu    t6, t0, t5              # carry
    srl     a3, t2, t3              # high part, avoids shift by 32
    add     t1, t1, a3
    add     t1, t1, t6
.Lq_skip:
    slli    t5, t5, 1
    addi    t3, t3, -1
    srli    t4, t4, 1
    bnez    t4, .Lq_loop

.Lq_signs:
    srai    t6, a4, 31              # a < 0: hi -= b
    and     t6, t6, a5
    sub     t1, t1, t6
    srai    t6, a5, 31              # b < 0: hi -= a
    and     t6, t6, a4
    sub     t1, t1, t6

    lui     t6, 0x80                # + 2^19
    add     t0, t0, t6
    sltu    t6, t0, t6
    add     t1, t1, t6
    slli    t1, t1, 12              # (hi:lo) >> 20
    srli    t0, t0, 20
    or      a0, t1, t0
    ret
    .size   q_mul_asm, .-q_mul_asm
