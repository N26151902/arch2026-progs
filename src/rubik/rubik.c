#include "rubik.h"
#include "rubik_tab.h"

/* Optimal 2x2x2 solver, meet in the middle.
 *
 * near table: states within 5 moves (+ distance mod 3)
 * far table:  states at distance 11
 *
 * - in near: walk down the table
 * - distance 6..10: iterative deepening, check only leaves against near;
 *   the first hit is at depth D - 5
 * - in far: one move out of far (distance 10), then search depth 5
 *
 * P: 3 bits per slot; oc: orientations in base 3.
 */

#define MAXLEN 11
#define SOLVED_P 0x001AC688u /* slot i holds cubie i */

/* src_shift[m][i] = 3 * source slot of slot i for move m */
static const uint8_t src_shift[9][7] = {
    {3, 12, 6, 0, 9, 15, 18}, /* R  {1,4,2,0,3,5,6} */
    {12, 9, 6, 3, 0, 15, 18}, /* R2 {4,3,2,1,0,5,6} */
    {9, 0, 6, 12, 3, 15, 18}, /* R' {3,0,2,4,1,5,6} */
    {0, 3, 6, 12, 15, 18, 9}, /* B  {0,1,2,4,5,6,3} */
    {0, 3, 6, 15, 18, 9, 12}, /* B2 {0,1,2,5,6,3,4} */
    {0, 3, 6, 18, 9, 12, 15}, /* B' {0,1,2,6,3,4,5} */
    {0, 6, 15, 9, 3, 12, 18}, /* D  {0,2,5,3,1,4,6} */
    {0, 15, 12, 9, 6, 3, 18}, /* D2 {0,5,4,3,2,1,6} */
    {0, 12, 3, 9, 15, 6, 18}, /* D' {0,4,1,3,5,2,6} */
};

static const char move_text[9][2] = {
    {'R', 0},    {'R', '2'}, {'R', '\''}, {'B', 0},    {'B', '2'},
    {'B', '\''}, {'D', 0},   {'D', '2'},  {'D', '\''},
};

static uint32_t perm_move(uint32_t p, int m)
{
    uint32_t n = 0;
    for (int i = 0; i < 7; i++)
        n |= ((p >> src_shift[m][i]) & 7u) << (3 * i);
    return n;
}

static uint32_t key_of(uint32_t p, uint32_t oc)
{
    return ((p & 0x3FFFFu) << 10) | oc;
}

/* returns distance mod 3, or -1 if not in the table */
static int near_lookup(uint32_t key)
{
    uint32_t lo = 0, hi = RUBIK_NNEAR, want = key << 2;
    while (lo < hi) {
        uint32_t mid = (lo + hi) >> 1;
        uint32_t e = rubik_near[mid];
        if ((e >> 2) == key)
            return (int) (e & 3u);
        if (e < want)
            lo = mid + 1;
        else
            hi = mid;
    }
    return -1;
}

static int far_lookup(uint32_t key)
{
    uint32_t lo = 0, hi = RUBIK_NFAR;
    while (lo < hi) {
        uint32_t mid = (lo + hi) >> 1;
        uint32_t e = rubik_far[mid];
        if (e == key)
            return 1;
        if (e < key)
            lo = mid + 1;
        else
            hi = mid;
    }
    return 0;
}

struct search {
    uint8_t path[MAXLEN];
    uint32_t p, oc; /* leaf where the search stopped */
};

/* try all sequences of `depth` moves; never turn the same face twice */
static int dfs(struct search *s,
               uint32_t p,
               uint32_t oc,
               int depth,
               int pos,
               int last_face)
{
    if (depth == 0) {
        if (near_lookup(key_of(p, oc)) < 0)
            return 0;
        s->p = p;
        s->oc = oc;
        return 1;
    }
    for (int m = 0; m < 9; m++) {
        int face = m < 3 ? 0 : m < 6 ? 1 : 2;
        if (face == last_face)
            continue;
        s->path[pos] = (uint8_t) m;
        if (dfs(s, perm_move(p, m), rubik_ori_move[m][oc], depth - 1, pos + 1,
                face))
            return 1;
    }
    return 0;
}

/* follow the neighbor whose residue is one lower until solved */
static int descend(uint8_t *path, int pos, uint32_t p, uint32_t oc)
{
    int r = near_lookup(key_of(p, oc));
    while (p != SOLVED_P || oc != 0) {
        int want = r == 0 ? 2 : r - 1;
        for (int m = 0; m < 9; m++) {
            uint32_t np = perm_move(p, m), noc = rubik_ori_move[m][oc];
            if (near_lookup(key_of(np, noc)) == want) {
                path[pos++] = (uint8_t) m;
                p = np;
                oc = noc;
                r = want;
                break;
            }
        }
    }
    return pos;
}

/* parse the 14-character state; -1 if invalid */
static int parse(const char *s, uint32_t *p, uint32_t *oc)
{
    uint32_t seen = 0, perm = 0, ori = 0, sum = 0;
    for (int i = 0; i < 7; i++) {
        uint32_t c = (uint32_t) (unsigned char) s[i] - '1';
        if (c > 6 || (seen & (1u << c)))
            return -1;
        seen |= 1u << c;
        perm |= c << (3 * i);
    }
    uint32_t pow3 = 1;
    for (int i = 7; i < 14; i++) {
        uint32_t c = (uint32_t) (unsigned char) s[i] - '1';
        if (c > 2)
            return -1;
        sum += c;
        if (i < 13) {
            ori += (c & 1u ? pow3 : 0) + (c & 2u ? pow3 << 1 : 0);
            pow3 = pow3 + (pow3 << 1);
        }
    }
    if (s[14] != '\0')
        return -1;
    if (sum != 0 && sum != 3 && sum != 6 && sum != 9 && sum != 12)
        return -1;
    *p = perm;
    *oc = ori;
    return 0;
}

int rubik_solve(const char *state, char *out, size_t cap)
{
    uint32_t p, oc;
    if (parse(state, &p, &oc) < 0)
        return -1;

    struct search s;
    int len;
    if (near_lookup(key_of(p, oc)) >= 0) {
        len = descend(s.path, 0, p, oc);
    } else if (far_lookup(key_of(p, oc))) {
        /* distance 11: step to a neighbor outside far (distance 10) */
        int m = 0;
        uint32_t np, noc;
        for (;; m++) {
            np = perm_move(p, m);
            noc = rubik_ori_move[m][oc];
            if (!far_lookup(key_of(np, noc)))
                break;
        }
        s.path[0] = (uint8_t) m;
        int face = m < 3 ? 0 : m < 6 ? 1 : 2;
        dfs(&s, np, noc, 5, 1, face);
        len = descend(s.path, 6, s.p, s.oc);
    } else {
        int k = 1;
        while (!dfs(&s, p, oc, k, 0, -1))
            k++;
        len = descend(s.path, k, s.p, s.oc);
    }

    /* write the move names */
    size_t need = len ? (size_t) len - 1 : 0;
    for (int i = 0; i < len; i++)
        need += move_text[s.path[i]][1] ? 2 : 1;
    if (cap < need + 1) {
        if (cap)
            out[0] = '\0';
        return -2;
    }
    char *w = out;
    for (int i = 0; i < len; i++) {
        if (i)
            *w++ = ' ';
        *w++ = move_text[s.path[i]][0];
        if (move_text[s.path[i]][1])
            *w++ = move_text[s.path[i]][1];
    }
    *w = '\0';
    return len;
}
