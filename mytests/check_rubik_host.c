/* Checks rubik_solve on every state against BFS distances (host only).
 *
 *   cc -O2 -I. -o build/check_rubik mytests/check_rubik_host.c \
 *       src/rubik/rubik.c src/rubik/rubik_tab.c
 *   build/check_rubik
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "src/rubik/rubik.h"

enum { CUBIES = 7, NSTATES = 3674160, NORI = 729 };

static const uint8_t source[3][CUBIES] = {
    {1, 4, 2, 0, 3, 5, 6},
    {0, 1, 2, 4, 5, 6, 3},
    {0, 2, 5, 3, 1, 4, 6},
};
static const uint8_t twist[3][CUBIES] = {
    {1, 2, 0, 2, 1, 0, 0},
    {0, 0, 0, 1, 2, 1, 2},
    {0, 0, 0, 0, 0, 0, 0},
};

struct cube {
    uint8_t p[CUBIES], o[CUBIES];
};

static struct cube turn(struct cube c, int move)
{
    int face = move / 3, turns = move % 3 + 1;
    for (int t = 0; t < turns; t++) {
        struct cube n;
        for (int i = 0; i < CUBIES; i++) {
            int from = source[face][i];
            n.p[i] = c.p[from];
            n.o[i] = (uint8_t) ((c.o[from] + twist[face][i]) % 3);
        }
        c = n;
    }
    return c;
}

static const int fact[8] = {1, 1, 2, 6, 24, 120, 720, 5040};

static int index_of(const struct cube *c)
{
    int r = 0;
    for (int i = 0; i < CUBIES; i++) {
        int smaller = 0;
        for (int j = i + 1; j < CUBIES; j++)
            smaller += c->p[j] < c->p[i];
        r += smaller * fact[CUBIES - 1 - i];
    }
    int oc = 0;
    for (int i = CUBIES - 2; i >= 0; i--)
        oc = oc * 3 + c->o[i];
    return r * NORI + oc;
}

static struct cube cube_of(int idx)
{
    struct cube c;
    int r = idx / NORI, oc = idx % NORI, used[CUBIES] = {0}, sum = 0;
    for (int i = 0; i < CUBIES; i++) {
        int f = fact[CUBIES - 1 - i], k = r / f;
        r %= f;
        for (int v = 0; v < CUBIES; v++) {
            if (!used[v] && k-- == 0) {
                c.p[i] = (uint8_t) v;
                used[v] = 1;
                break;
            }
        }
    }
    for (int i = 0; i < CUBIES - 1; i++) {
        c.o[i] = (uint8_t) (oc % 3);
        sum += c.o[i];
        oc /= 3;
    }
    c.o[CUBIES - 1] = (uint8_t) ((3 - sum % 3) % 3);
    return c;
}

static const char *const names[9] = {"R",  "R2", "R'", "B", "B2",
                                     "B'", "D",  "D2", "D'"};

static int8_t dist[NSTATES];
static int queue[NSTATES];

int main(void)
{
    memset(dist, -1, sizeof dist);
    struct cube solved;
    for (int i = 0; i < CUBIES; i++) {
        solved.p[i] = (uint8_t) i;
        solved.o[i] = 0;
    }
    int head = 0, tail = 0;
    queue[tail++] = index_of(&solved);
    dist[queue[0]] = 0;
    while (head < tail) {
        int s = queue[head++];
        struct cube c = cube_of(s);
        for (int m = 0; m < 9; m++) {
            struct cube n = turn(c, m);
            int t = index_of(&n);
            if (dist[t] < 0) {
                dist[t] = (int8_t) (dist[s] + 1);
                queue[tail++] = t;
            }
        }
    }

    long bad = 0;
    for (int s = 0; s < NSTATES; s++) {
        struct cube c = cube_of(s);
        char state[15], out[64];
        for (int i = 0; i < CUBIES; i++) {
            state[i] = (char) ('1' + c.p[i]);
            state[i + CUBIES] = (char) ('1' + c.o[i]);
        }
        state[14] = '\0';
        int n = rubik_solve(state, out, sizeof out);
        int count = 0;
        char *t = out;
        while (*t) {
            char *e = t;
            while (*e && *e != ' ')
                e++;
            int m;
            for (m = 0; m < 9; m++) {
                if ((size_t) (e - t) == strlen(names[m]) &&
                    !strncmp(t, names[m], (size_t) (e - t)))
                    break;
            }
            if (m == 9)
                break;
            c = turn(c, m);
            count++;
            t = *e ? e + 1 : e;
        }
        int ok =
            n == dist[s] && count == n && index_of(&c) == index_of(&solved);
        if (!ok && bad++ < 10)
            printf("FAIL %s: returned %d, distance %d, text \"%s\"\n", state, n,
                   dist[s], out);
    }
    printf("%s: %ld of %d states wrong\n", bad ? "FAIL" : "PASS", bad, NSTATES);
    return bad != 0;
}
