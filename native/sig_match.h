#ifndef SIG_MATCH_H
#define SIG_MATCH_H
#include <stddef.h>
#include <string.h>
#define SIG_MAX_LEN 128
typedef struct {
    unsigned char bytes[SIG_MAX_LEN], wild[SIG_MAX_LEN];
    int len, anchor;
} Pattern;
static inline int sig_hex(char c) {
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    return -1;
}
static inline int sig_parse(const char *s, Pattern *p) {
    p->len = 0;
    p->anchor = -1;
    while (*s) {
        if (*s == ' ') {
            s++;
            continue;
        }
        if (p->len == SIG_MAX_LEN || !s[1])
            return 0;
        int wild = s[0] == '?' && s[1] == '?', hi = sig_hex(s[0]), lo = sig_hex(s[1]);
        if (!wild && (hi < 0 || lo < 0))
            return 0;
        p->wild[p->len] = (unsigned char)wild;
        p->bytes[p->len] = wild ? 0 : (unsigned char)(hi << 4 | lo);
        if (!wild && p->anchor < 0)
            p->anchor = p->len;
        p->len++;
        s += 2;
    }
    return p->anchor >= 0;
}
/* Counts matches up to 2 and stores the first in *found. */
static inline int sig_find(const unsigned char *base, size_t size, const Pattern *p, const unsigned char **found) {
    int hits = 0;
    if ((size_t)p->len > size)
        return 0;
    const unsigned char *at = base + p->anchor, *end = base + size - p->len + p->anchor + 1;
    while (at < end && (at = memchr(at, p->bytes[p->anchor], (size_t)(end - at)))) {
        const unsigned char *start = at - p->anchor;
        int k = 0;
        while (k < p->len && (p->wild[k] || start[k] == p->bytes[k]))
            k++;
        if (k == p->len) {
            if (!hits++)
                *found = start;
            if (hits == 2)
                break;
        }
        at++;
    }
    return hits;
}
#endif
