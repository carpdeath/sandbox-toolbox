#ifndef DAMAGE_SCALE_H
#define DAMAGE_SCALE_H
#include <limits.h>
#include <stdlib.h>
#define DAMAGE_MAX_SQUADS 512
typedef struct {
    float mult;
    int count;
    int ids[DAMAGE_MAX_SQUADS];
} DamageScale;
static inline float damage_adjust(float before, float after, float mult) {
    if (!(after < before))
        return after;
    return before - (before - after) * mult;
}
static inline int damage_is_player(const DamageScale *s, int squad) {
    for (int i = 0; i < s->count; i++)
        if (s->ids[i] == squad)
            return 1;
    return 0;
}
static inline int damage_parse(const char *text, DamageScale *out) {
    char *end;
    DamageScale s;
    s.count = 0;
    double mult = strtod(text, &end);
    if (end == text || !(mult >= 0.0 && mult <= 2.0))
        return 0;
    text = end;
    long n = strtol(text, &end, 10);
    if (end == text || n < 0 || n > DAMAGE_MAX_SQUADS)
        return 0;
    for (long i = 0; i < n; i++) {
        text = end;
        long id = strtol(text, &end, 10);
        if (end == text || id < INT_MIN || id > INT_MAX)
            return 0;
        s.ids[s.count++] = (int)id;
    }
    s.mult = (float)mult;
    *out = s;
    return 1;
}
#endif
