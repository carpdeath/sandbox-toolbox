#ifndef MIGRATION_BONUS_H
#define MIGRATION_BONUS_H
#include <stdint.h>
typedef struct {
    uintptr_t region, calendar;
    int month, amount;
} MigrationBonus;
static int migration_queue(MigrationBonus *b, uintptr_t region, uintptr_t calendar, int now, int amount) {
    if (amount != 1 && amount != 5)
        return 0;
    if (b->region != region || b->calendar != calendar || b->month != now + 1)
        *b = (MigrationBonus){region, calendar, now + 1, 0};
    if (b->amount > 100 - amount)
        return 0;
    b->amount += amount;
    return b->amount;
}
static int migration_slot(const MigrationBonus *b, int n, uintptr_t region, uintptr_t calendar, int now) {
    for (int i = 0; i < n; i++)
        if (b[i].region == region && b[i].calendar == calendar && b[i].month == now + 1 && b[i].amount)
            return i;
    for (int i = 0; i < n; i++)
        if (!b[i].amount || b[i].month < now)
            return i;
    return -1;
}
static int migration_extra(const MigrationBonus *b, uintptr_t region, uintptr_t calendar, int now) {
    return b->region == region && b->calendar == calendar && b->month == now ? b->amount : 0;
}
#endif
