# gcd_u32_asm(a0 = a, a1 = b) -> a0, binary GCD, RV32I only.
# t0 bit test, t2 a | b, t3 shift count. No stack frame.

    .text

    .globl  gcd_u32_asm
    .type   gcd_u32_asm, @function
    .align  2
gcd_u32_asm:
    beqz    a0, .Lret_b
    beqz    a1, .Lret_a
    or      t2, a0, a1
    andi    t0, t2, 1
    li      t3, 0
    beqz    t0, .Lshared            # both even
.Lstrip_a:
    andi    t0, a0, 1
    beqz    t0, .La_even
.Lstrip_b:
    andi    t0, a1, 1
    beqz    t0, .Lb_even

    # Two copies of the loop: A reduces a1, B reduces a0.
    # Switching copies replaces a register swap.
    bgeu    a1, a0, .LA_sub
    sub     a0, a0, a1
    j       .LB_shift

.LA_sub:                            # loop A: a1 >= a0
    sub     a1, a1, a0
    beqz    a1, .Ldone_a
.LA_shift:
    srli    a1, a1, 1
    andi    t0, a1, 1
    beqz    t0, .LA_shift
.LA:
    bgeu    a1, a0, .LA_sub
    sub     a0, a0, a1              # go to B
    j       .LB_shift

.LB_sub:                            # loop B: a0 >= a1
    sub     a0, a0, a1
    beqz    a0, .Ldone_b
.LB_shift:
    srli    a0, a0, 1
    andi    t0, a0, 1
    beqz    t0, .LB_shift
    bgeu    a0, a1, .LB_sub
    sub     a1, a1, a0              # go to A
    j       .LA_shift

.Ldone_b:
    sll     a0, a1, t3
    ret
.Ldone_a:
    sll     a0, a0, t3
.Lret_a:
    ret

.Lret_b:
    mv      a0, a1
    ret

.Lshared:                           # count common twos
    srli    t2, t2, 1
    addi    t3, t3, 1
    andi    t0, t2, 1
    beqz    t0, .Lshared
    j       .Lstrip_a

.La_even:
    srli    a0, a0, 1
    andi    t0, a0, 1
    beqz    t0, .La_even
    j       .Lstrip_b

.Lb_even:
    srli    a1, a1, 1
    andi    t0, a1, 1
    beqz    t0, .Lb_even
    j       .LA
    .size   gcd_u32_asm, .-gcd_u32_asm
