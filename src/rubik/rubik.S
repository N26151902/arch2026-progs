# rubik_solve_asm(a0 = state, a1 = out, a2 = cap) -> a0, RV32I only.
# Same algorithm as rubik.c (meet in the middle), no recursion.
#
# Saved registers:
#   s0-s5  masks for the quarter turns
#   s6     depth - 1 (search), solved P (descent)
#   s7     current depth / scratch
#   s8     near table, s9 ori table, s11 far table
#   s10    write pointer into the move path
# Table lookups are called through t6, so they need no stack.

    # stack frame layout
    .equ    FRAME, 256
    .equ    OUT, 52
    .equ    CAP, 56
    .equ    PATH, 64
    .equ    LEAFP, 80
    .equ    LEAFO, 84
    .equ    ROOTP, 88
    .equ    ROOTO, 92
    .equ    NP, 96                  # per-depth arrays (5 words each)
    .equ    NO, 116
    .equ    CP, 136
    .equ    CO, 156
    .equ    FC, 176
    .equ    TN, 196
    .equ    PF, 216
    .equ    OBASE, 236              # ori tables of R, B, D
    .equ    SRA, 248
    .equ    LEAFR, 252

    # offsets of the B and D quarter-turn ori tables
    .equ    ORI_B, 4374
    .equ    ORI_D, 8748
    .equ    SOLVED_P, 0x1AC688      # slot i holds cubie i

    # quarter turns as bit shuffles of P (3 bits per slot)
    .macro  QR x
    srli    t3, \x, 3
    andi    t3, t3, 7
    srli    t4, \x, 9
    andi    t4, t4, 0x38
    or      t3, t3, t4
    andi    t4, \x, 7
    slli    t4, t4, 9
    or      t3, t3, t4
    slli    t4, \x, 3
    and     t4, t4, s1
    or      t3, t3, t4
    and     \x, \x, s0
    or      \x, \x, t3
    .endm

    .macro  QB x
    srli    t3, \x, 3
    and     t3, t3, s2
    slli    t4, \x, 9
    and     t4, t4, s3
    andi    \x, \x, 0x1FF
    or      \x, \x, t3
    or      \x, \x, t4
    .endm

    .macro  QD x
    srli    t3, \x, 3
    andi    t3, t3, 0x38
    srli    t4, \x, 9
    andi    t4, t4, 0x1C0
    or      t3, t3, t4
    slli    t4, \x, 9
    and     t4, t4, s1
    or      t3, t3, t4
    slli    t4, \x, 3
    and     t4, t4, s5
    or      t3, t3, t4
    and     \x, \x, s4
    or      \x, \x, t3
    .endm

    # oc = table[oc]
    .macro  ORI oc, base
    slli    t3, \oc, 1
    add     t3, t3, \base
    lhu     \oc, 0(t3)
    .endm

    # key = ((P & 0x3FFFF) << 10) | oc
    .macro  KEY dst, p, oc
    slli    \dst, \p, 14
    srli    \dst, \dst, 4
    or      \dst, \dst, \oc
    .endm

    # quarter turn of face f (0 R, 1 B, 2 D)
    .macro  QUARTER f, x, l
    beqz    \f, .Lq_r\l
    addi    t3, \f, -1
    beqz    t3, .Lq_b\l
    QD      \x
    j       .Lq_end\l
.Lq_r\l:
    QR      \x
    j       .Lq_end\l
.Lq_b\l:
    QB      \x
.Lq_end\l:
    .endm

    # unrolled binary search step
    .macro  STEP off
    lw      t1, \off(t0)
    bgeu    t1, a5, 1f
    addi    t0, t0, \off
1:
    .endm

    .macro  STEP_FAR off            # offset too big for an immediate
    li      t2, \off
    add     t2, t0, t2
    lw      t1, 0(t2)
    bgeu    t1, a5, 1f
    mv      t0, t2
1:
    .endm

    .text

    .align  2
# near_find: a0 = key -> a0 = distance mod 3, or -1
near_find:
    slli    a5, a0, 2               # entries are (key << 2) | residue
    mv      t0, s8
    STEP_FAR 24448
    STEP_FAR 12224
    STEP_FAR 6112
    STEP_FAR 3056
    STEP    1528
    STEP    764
    STEP    380
    STEP    192
    STEP    96
    STEP    48
    STEP    24
    STEP    12
    STEP    4
    STEP    4
    lw      t1, 0(t0)
    bgeu    t1, a5, 1f
    lw      t1, 4(t0)
1:  xor     t2, t1, a5
    srli    t2, t2, 2
    bnez    t2, 2f
    andi    a0, t1, 3
    jr      t6
2:  li      a0, -1
    jr      t6

    .align  2
# far_find: a0 = key -> a0 = 1 if at distance 11
far_find:
    mv      a5, a0
    mv      t0, s11
    STEP_FAR 5288
    STEP_FAR 2644
    STEP    1320
    STEP    660
    STEP    332
    STEP    164
    STEP    84
    STEP    40
    STEP    20
    STEP    12
    STEP    4
    STEP    4
    lw      t1, 0(t0)
    bgeu    t1, a5, 1f
    lw      t1, 4(t0)
1:  xor     t1, t1, a5
    seqz    a0, t1
    jr      t6

    # turn, look up, stop on a hit
    .macro  LEAF_TURN q, move
    \q      a1
    ORI     a2, a7
    KEY     a0, a1, a2
    jal     t6, near_find
    bltz    a0, 1f
    li      t5, \move
    j       .Lle_hit
1:
    .endm

    .align  2
# leaf_expand: look up all children of (a3, a4); a6 = last face
leaf_expand:
    beqz    a6, .Lle_b
    mv      a1, a3
    mv      a2, a4
    mv      a7, s9
    LEAF_TURN QR, 0
    LEAF_TURN QR, 1
    LEAF_TURN QR, 2
.Lle_b:
    addi    t5, a6, -1
    beqz    t5, .Lle_d
    mv      a1, a3
    mv      a2, a4
    lw      a7, OBASE+4(sp)
    LEAF_TURN QB, 3
    LEAF_TURN QB, 4
    LEAF_TURN QB, 5
.Lle_d:
    addi    t5, a6, -2
    beqz    t5, .Lle_none
    mv      a1, a3
    mv      a2, a4
    lw      a7, OBASE+8(sp)
    LEAF_TURN QD, 6
    LEAF_TURN QD, 7
    LEAF_TURN QD, 8
.Lle_none:
    li      a0, 0
    ret
.Lle_hit:                           # save the move and the leaf
    add     t0, s10, s6
    sb      t5, 0(t0)
    sw      a1, LEAFP(sp)
    sw      a2, LEAFO(sp)
    sw      a0, LEAFR(sp)
    li      a0, 1
    ret

    .align  2
# search: all sequences of s6 + 1 moves from (a3, a4), no recursion
search:
    sw      ra, SRA(sp)
    bnez    s6, 1f
    jal     ra, leaf_expand
    lw      ra, SRA(sp)
    ret
1:  li      s7, 0
    sw      a3, NP(sp)
    sw      a4, NO(sp)
    sw      a6, PF(sp)
    li      t0, -1
    sw      t0, FC(sp)
    li      t0, 3
    sw      t0, TN(sp)
.Ls_next:                           # next child at depth s7
    slli    t6, s7, 2
    add     t6, sp, t6
    lw      t0, TN(t6)
    lw      t1, FC(t6)
    addi    t2, t0, -3
    bnez    t2, .Ls_same_face
    addi    t1, t1, 1
    lw      t2, PF(t6)
    bne     t1, t2, 2f
    addi    t1, t1, 1
2:  addi    t2, t1, -3
    bgez    t2, .Ls_up              # all faces done
    sw      t1, FC(t6)
    li      t0, 0
    lw      a1, NP(t6)
    lw      a2, NO(t6)
    j       .Ls_turn
.Ls_same_face:
    lw      a1, CP(t6)
    lw      a2, CO(t6)
.Ls_turn:
    addi    t0, t0, 1
    sw      t0, TN(t6)
    slli    t2, t1, 2
    add     t2, sp, t2
    lw      a7, OBASE(t2)
    ORI     a2, a7
    QUARTER t1, a1, s
    sw      a1, CP(t6)
    sw      a2, CO(t6)
    slli    t2, t1, 1
    add     t2, t2, t1
    add     t2, t2, t0
    addi    t2, t2, -1
    add     t3, s10, s7
    sb      t2, 0(t3)
    addi    t2, s7, 1
    bne     t2, s6, .Ls_down
    mv      a3, a1
    mv      a4, a2
    mv      a6, t1
    jal     ra, leaf_expand
    beqz    a0, .Ls_next
    lw      ra, SRA(sp)
    ret
.Ls_down:                           # go one level deeper
    mv      s7, t2
    addi    t6, t6, 4
    sw      a1, NP(t6)
    sw      a2, NO(t6)
    sw      t1, PF(t6)
    li      t0, -1
    sw      t0, FC(t6)
    li      t0, 3
    sw      t0, TN(t6)
    j       .Ls_next
.Ls_up:                             # back up one level
    addi    s7, s7, -1
    bgez    s7, .Ls_next
    li      a0, 0
    lw      ra, SRA(sp)
    ret

    .globl  rubik_solve_asm
    .type   rubik_solve_asm, @function
    .align  2
rubik_solve_asm:
    addi    sp, sp, -FRAME
    sw      ra, 0(sp)
    sw      s0, 4(sp)
    sw      s1, 8(sp)
    sw      s2, 12(sp)
    sw      s3, 16(sp)
    sw      s4, 20(sp)
    sw      s5, 24(sp)
    sw      s6, 28(sp)
    sw      s7, 32(sp)
    sw      s8, 36(sp)
    sw      s9, 40(sp)
    sw      s10, 44(sp)
    sw      s11, 48(sp)
    sw      a1, OUT(sp)
    # parse: P from the 7 cubies, oc from 6 orientations
    sw      a2, CAP(sp)

    li      a3, 0
    li      t1, 0
    li      t2, 0
.Lp_perm:
    lbu     t3, 0(a0)
    addi    t3, t3, -49
    li      t4, 7
    bgeu    t3, t4, .Linvalid       # out of range
    li      t4, 1
    sll     t4, t4, t3
    and     t5, t2, t4
    bnez    t5, .Linvalid           # repeated cubie
    or      t2, t2, t4
    sll     t3, t3, t1
    or      a3, a3, t3
    addi    a0, a0, 1
    addi    t1, t1, 3
    li      t4, 21
    bne     t1, t4, .Lp_perm

    li      a4, 0
    li      t1, 1
    li      t2, 0
    li      t0, 7
.Lp_ori:
    lbu     t3, 0(a0)
    addi    t3, t3, -49
    li      t4, 3
    bgeu    t3, t4, .Linvalid
    add     t2, t2, t3
    addi    t0, t0, -1
    beqz    t0, .Lp_end             # last orientation is implied
    beqz    t3, 1f
    add     a4, a4, t1
    addi    t3, t3, -1
    beqz    t3, 1f
    add     a4, a4, t1
1:  slli    t4, t1, 1
    add     t1, t1, t4
    addi    a0, a0, 1
    j       .Lp_ori
.Lp_end:
    lbu     t3, 1(a0)
    bnez    t3, .Linvalid           # longer than 14
    li      t4, 3
2:  bltu    t2, t4, 3f
    addi    t2, t2, -3
    j       2b
3:  bnez    t2, .Linvalid           # sum not a multiple of 3

    # constants
    li      s0, 0xFFFF81C0
    li      s1, 0x7000
    li      s2, 0x3FE00
    li      s3, 0x1C0000
    li      s4, 0xFFFC0E07
    li      s5, 0x38000
    la      s8, rubik_asm_near
    la      s9, rubik_asm_ori_move
    la      s11, rubik_asm_far
    sw      s9, OBASE(sp)
    li      t0, ORI_B
    add     t0, s9, t0
    sw      t0, OBASE+4(sp)
    li      t0, ORI_D
    add     t0, s9, t0
    sw      t0, OBASE+8(sp)
    addi    s10, sp, PATH

    KEY     a0, a3, a4
    jal     t6, near_find
    bltz    a0, .Lnot_near          # within 5 moves?
    mv      a6, a0
    j       .Ldescend

.Lnot_near:
    sw      a3, ROOTP(sp)
    sw      a4, ROOTO(sp)
    KEY     a0, a3, a4
    jal     t6, far_find
    beqz    a0, .Lsearch            # distance 11?

    li      s7, 0
# distance 11: find a neighbor not in far (distance 10)
.Lf_face:
    lw      a1, ROOTP(sp)
    lw      a2, ROOTO(sp)
    slli    t0, s7, 2
    add     t0, sp, t0
    lw      a7, OBASE(t0)
    li      t5, 0
.Lf_turn:
    addi    t5, t5, 1
    ORI     a2, a7
    QUARTER s7, a1, f
    KEY     a0, a1, a2
    jal     t6, far_find
    beqz    a0, .Lf_found
    addi    t0, t5, -3
    bnez    t0, .Lf_turn
    addi    s7, s7, 1
    j       .Lf_face
.Lf_found:
    slli    t0, s7, 1
    add     t0, t0, s7
    add     t0, t0, t5
    addi    t0, t0, -1
    sb      t0, 0(s10)
    addi    s10, s10, 1
    mv      a3, a1
    mv      a4, a2
    mv      a6, s7
    li      s6, 4                   # search depth 5
    jal     ra, search
    addi    s10, s10, 5
    j       .Lleaf

# distance 6..10: iterative deepening
.Lsearch:
    li      s6, 0
.Lk_loop:
    lw      a3, ROOTP(sp)
    lw      a4, ROOTO(sp)
    li      a6, 3
    jal     ra, search
    bnez    a0, 1f
    addi    s6, s6, 1
    j       .Lk_loop
1:  add     s10, s10, s6
    addi    s10, s10, 1
.Lleaf:
    lw      a3, LEAFP(sp)
    lw      a4, LEAFO(sp)
    lw      a6, LEAFR(sp)

# walk down: take the neighbor whose residue is one lower
.Ldescend:
    li      s6, SOLVED_P
.Ld_loop:
    bne     a3, s6, 1f
    beqz    a4, .Ld_done
1:  addi    s7, a6, -1              # wanted residue
    bgez    s7, 2f
    li      s7, 2
2:  li      s11, 0
.Ld_face:
    mv      a1, a3
    mv      a2, a4
    slli    t0, s11, 2
    add     t0, sp, t0
    lw      a7, OBASE(t0)
    li      t5, 0
.Ld_turn:
    addi    t5, t5, 1
    ORI     a2, a7
    QUARTER s11, a1, d
    KEY     a0, a1, a2
    jal     t6, near_find
    beq     a0, s7, .Ld_take
    addi    t0, t5, -3
    bnez    t0, .Ld_turn
    addi    s11, s11, 1
    j       .Ld_face
.Ld_take:
    slli    t0, s11, 1
    add     t0, t0, s11
    add     t0, t0, t5
    addi    t0, t0, -1
    sb      t0, 0(s10)
    addi    s10, s10, 1
    mv      a3, a1
    mv      a4, a2
    mv      a6, s7
    j       .Ld_loop

# write the move names, or -2 if cap is too small
.Ld_done:
    addi    t0, sp, PATH
    sub     s7, s10, t0
    li      t1, 1
    beqz    s7, 2f
    li      t1, 0
    li      t3, 0x1B6
1:  lbu     t2, 0(t0)
    srl     t4, t3, t2
    andi    t4, t4, 1
    add     t1, t1, t4
    addi    t1, t1, 2
    addi    t0, t0, 1
    bne     t0, s10, 1b
2:  lw      t2, OUT(sp)
    lw      t5, CAP(sp)
    bltu    t5, t1, .Lshort

    addi    t0, sp, PATH
    la      t3, move_text
    beq     t0, s10, 4f
    j       3f
5:  li      t4, ' '
    sb      t4, 0(t2)
    addi    t2, t2, 1
3:  lbu     t1, 0(t0)
    slli    t1, t1, 1
    add     t1, t1, t3
    lbu     t4, 0(t1)
    sb      t4, 0(t2)
    addi    t2, t2, 1
    lbu     t4, 1(t1)
    beqz    t4, 6f
    sb      t4, 0(t2)
    addi    t2, t2, 1
6:  addi    t0, t0, 1
    bne     t0, s10, 5b
4:  sb      zero, 0(t2)
    mv      a0, s7
    j       .Lreturn

.Lshort:                            # buffer too small
    beqz    t5, 1f
    sb      zero, 0(t2)
1:  li      a0, -2
    j       .Lreturn

.Linvalid:
    li      a0, -1
.Lreturn:
    lw      ra, 0(sp)
    lw      s0, 4(sp)
    lw      s1, 8(sp)
    lw      s2, 12(sp)
    lw      s3, 16(sp)
    lw      s4, 20(sp)
    lw      s5, 24(sp)
    lw      s6, 28(sp)
    lw      s7, 32(sp)
    lw      s8, 36(sp)
    lw      s9, 40(sp)
    lw      s10, 44(sp)
    lw      s11, 48(sp)
    addi    sp, sp, FRAME
    ret
    .size   rubik_solve_asm, .-rubik_solve_asm

    .section .rodata
move_text:                          # two bytes per move
    .byte   'R', 0, 'R', '2', 'R', '\'', 'B', 0, 'B', '2', 'B', '\''
    .byte   'D', 0, 'D', '2', 'D', '\''
