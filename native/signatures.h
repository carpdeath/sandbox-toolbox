#ifndef SIGNATURES_H
#define SIGNATURES_H
/* Byte patterns located in the game's .text at runtime, so a patch that only moves code needs no rebuild.
   "??" is a wildcard. Each pattern must match exactly once.
   CODE:  the address is the match itself.
   FIELD: the struct offset is the int32 displacement read at match + at. */
typedef enum { CODE, FIELD } SigKind;
typedef struct {
    SigKind kind;
    int at;
    const char *pattern;
} Signature;

enum {
    SIG_MIGRATION_RATE,
    SIG_FINISH_CONSTRUCTION,
    SIG_DAMAGE_R14,
    SIG_DAMAGE_RSI_A,
    SIG_DAMAGE_RSI_B,
    SIG_REGION_GAME_STATE,
    SIG_GAME_STATE_CALENDAR,
    SIG_BUILDING_CONSTRUCTED,
    SIG_UNIT_SQUAD,
    SIG_FERTILITY_GRID,
    SIG_FERTILITY_LIMITS,
    SIG_REGION_CONTAINS,
    SIG_COUNT
};

// clang-format off
static const Signature signatures[SIG_COUNT] = {
    /* region monthly migration rate (hooked) */
    [SIG_MIGRATION_RATE] = {CODE, 0, "48 89 5C 24 10 48 89 74 24 18 48 89 7C 24 20 55 48 8D 6C 24 A9 48 81 EC F0 00 00 00 48 8B 05 ?? ?? ?? ?? 48 33 C4 48 89 45 47 48 8D 55 F7 33 DB E8 ?? ?? ?? ?? 44 8B 5D 1F"},
    /* building finishConstruction */
    [SIG_FINISH_CONSTRUCTION] = {CODE, 0, "48 8B C4 48 89 58 10 48 89 70 18 48 89 78 20 55 41 54 41 55 41 56 41 57 48 8D A8 08 FE FF FF 48 81 EC D0 02 00 00 44 0F 29 48 98 48 8B 05 ?? ?? ?? ?? 48 33 C4"},
    /* movss [unit+health], xmm0 stores; the wildcarded disp32 is the health offset */
    [SIG_DAMAGE_R14] = {CODE, 0, "F3 41 0F 11 86 ?? ?? ?? ?? E9 ?? ?? ?? ?? B3 01 41 BC 01 00 00 00 EB ??"},
    [SIG_DAMAGE_RSI_A] = {CODE, 0, "F3 0F 11 86 ?? ?? ?? ?? 80 7C 24 72 12 0F 85 ?? ?? ?? ?? 80 BE DD 08 00 00 03 0F 87 ?? ?? ?? ??"},
    [SIG_DAMAGE_RSI_B] = {CODE, 0, "F3 0F 11 86 ?? ?? ?? ?? E9 ?? ?? ?? ?? 0F 5A CF 41 B8 01 00 00 00 48 8D 8D 88 00 00 00"},
    /* mov rcx, [region+game_state] before the day getter */
    [SIG_REGION_GAME_STATE] = {FIELD, 3, "48 8B 89 ?? ?? ?? ?? E8 ?? ?? ?? ?? 48 63 C8 49 2B 8D F0 02 00 00 48 81 F9 6D 01 00 00 0F 8D ?? ?? ?? ??"},
    /* month getter: [state+calendar]->month; the month offset (0x170) is what identifies it, so it stays literal */
    [SIG_GAME_STATE_CALENDAR] = {FIELD, 3, "48 8B 81 ?? ?? ?? ?? 48 85 C0 74 ?? 8B 80 70 01 00 00 C3 C3 CC CC"},
    /* finishConstruction: mov byte [building+constructed], 1 */
    [SIG_BUILDING_CONSTRUCTED] = {FIELD, 2, "C6 86 ?? ?? ?? ?? 01 66 44 89 AE A1 03 00 00 44 88 AE A3 03 00 00 44 88 AE 00 07 00 00 44 39 AE C4 14 00 00"},
    /* damage function: mov edx, [unit+squad] */
    [SIG_UNIT_SQUAD] = {FIELD, 2, "8B 96 ?? ?? ?? ?? 48 8B 88 D0 02 00 00 E8 ?? ?? ?? ?? 48 85 C0 74 ?? 49 8B 8F 18 03 00 00 8B 96 B8 02 00 00 48 8B 89 D0 02 00 00 E8 ?? ?? ?? ??"},
    /* fertility clamp: limits, then grid */
    [SIG_FERTILITY_GRID] = {FIELD, 13, "48 8B 83 ?? ?? ?? ?? 48 03 FF 48 8B 8B ?? ?? ?? ?? 48 83 C6 04 F3 0F 10 04 F8 F3 0F 5D 04 F9"},
    [SIG_FERTILITY_LIMITS] = {FIELD, 3, "48 8B 83 ?? ?? ?? ?? 48 03 FF 48 8B 8B ?? ?? ?? ?? 48 83 C6 04 F3 0F 10 04 F8 F3 0F 5D 04 F9"},
    /* region contains point */
    [SIG_REGION_CONTAINS] = {CODE, 0, "48 83 EC 28 48 8B 81 ?? ?? ?? ?? 4C 8B C2 48 85 C0 74 ?? 8B 40 08 C1 E8 1E F6 D0 A8 01 74 ?? F2 0F 10 02 66 0F 2F 81"},
};
// clang-format on

#define CALENDAR_MONTH 0x170
#endif
