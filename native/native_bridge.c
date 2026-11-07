#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "migration_bonus.h"
#include "damage_scale.h"
#include "damage_stub.h"
#include "sig_match.h"
#include "signatures.h"

static HMODULE self;

BOOL WINAPI DllMain(HINSTANCE h, DWORD why, LPVOID p) {
    (void)p;
    if (why == DLL_PROCESS_ATTACH)
        self = h;
    return TRUE;
}

static FILE *open_beside(const char *name, const char *mode) {
    char path[MAX_PATH];
    DWORD len = GetModuleFileNameA(self, path, MAX_PATH);
    char *slash = len ? strrchr(path, '\\') : NULL;
    if (!slash || (size_t)(slash + 1 - path) + strlen(name) >= MAX_PATH)
        return NULL;
    strcpy(slash + 1, name);
    return fopen(path, mode);
}

static int fail(FILE *result, const char *message) {
    if (message)
        fputs(message, result);
    fclose(result);
    return 0;
}

static int readable(uintptr_t p, size_t n) {
    MEMORY_BASIC_INFORMATION m;
    if (!p || !VirtualQuery((void *)p, &m, sizeof(m)))
        return 0;
    return m.State == MEM_COMMIT && !(m.Protect & (PAGE_NOACCESS | PAGE_GUARD)) && p + n >= p &&
           p + n <= (uintptr_t)m.BaseAddress + m.RegionSize;
}

static unsigned char *game_image(void) {
    return (unsigned char *)GetModuleHandleW(NULL);
}

static uintptr_t sig_values[SIG_COUNT];
static signed char sig_state[SIG_COUNT];

static int text_section(const unsigned char **base, size_t *size) {
    unsigned char *image = game_image();
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(image + ((IMAGE_DOS_HEADER *)image)->e_lfanew);
    IMAGE_SECTION_HEADER *sec = IMAGE_FIRST_SECTION(nt);
    for (int i = 0; i < nt->FileHeader.NumberOfSections; i++)
        if (!memcmp(sec[i].Name, ".text", 6)) {
            *base = image + sec[i].VirtualAddress;
            *size = sec[i].Misc.VirtualSize;
            return 1;
        }
    return 0;
}

/* CODE: the matched address. FIELD: the struct offset encoded at match + at. 0 when not found exactly once. */
static uintptr_t sig(int id) {
    if (sig_state[id])
        return sig_state[id] > 0 ? sig_values[id] : 0;
    sig_state[id] = -1;
    const Signature *s = &signatures[id];
    const unsigned char *base, *found = NULL;
    size_t size;
    Pattern p;
    if (!sig_parse(s->pattern, &p) || !text_section(&base, &size) || sig_find(base, size, &p, &found) != 1)
        return 0;
    if (s->kind == FIELD) {
        int32_t disp;
        memcpy(&disp, found + s->at, 4);
        if (disp <= 0)
            return 0;
        sig_values[id] = (uintptr_t)disp;
    } else {
        sig_values[id] = (uintptr_t)(found + s->at);
    }
    sig_state[id] = 1;
    return sig_values[id];
}

static int sigs(const int *ids, int n) {
    for (int i = 0; i < n; i++)
        if (!sig(ids[i]))
            return 0;
    return 1;
}

static void pin_self(void *any_function) {
    HMODULE pinned;
    GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN, (LPCSTR)any_function,
                       &pinned);
}

#define ABS_JUMP_SIZE 14

static void write_abs_jump(unsigned char *code, uintptr_t target) {
    code[0] = 0xff;
    code[1] = 0x25;
    memset(code + 2, 0, 4);
    memcpy(code + 6, &target, 8);
}

#define MIGRATION_PROLOGUE_SIZE 15
#define TRAMPOLINE_SIZE (MIGRATION_PROLOGUE_SIZE + ABS_JUMP_SIZE)

#define MAX_BONUSES 32

typedef int (*MonthlyRate)(void *);
static MonthlyRate original_rate;
static MigrationBonus bonuses[MAX_BONUSES];
static SRWLOCK bonus_lock = SRWLOCK_INIT;

static uintptr_t region_game_state, game_state_calendar;

static uintptr_t calendar_for(uintptr_t region) {
    if (!readable(region, region_game_state + 8))
        return 0;
    uintptr_t state = *(uintptr_t *)(region + region_game_state);
    if (!readable(state, game_state_calendar + 8))
        return 0;
    uintptr_t calendar = *(uintptr_t *)(state + game_state_calendar);
    return readable(calendar, CALENDAR_MONTH + 4) ? calendar : 0;
}

static int current_month(uintptr_t calendar) {
    return *(int *)(calendar + CALENDAR_MONTH);
}

static int monthly_rate(void *region) {
    int base = original_rate(region), extra = 0;
    uintptr_t calendar = calendar_for((uintptr_t)region);
    if (calendar) {
        int month = current_month(calendar);
        AcquireSRWLockShared(&bonus_lock);
        for (int i = 0; i < MAX_BONUSES; i++)
            extra += migration_extra(&bonuses[i], (uintptr_t)region, calendar, month);
        ReleaseSRWLockShared(&bonus_lock);
    }
    return base + extra;
}

static int install_rate_hook(void) {
    if (original_rate)
        return 1;
    /* the signature pins the first 15 bytes to three whole register saves, which the trampoline relocates */
    unsigned char *target = (unsigned char *)sig(SIG_MIGRATION_RATE);
    if (!target)
        return 0;

    unsigned char *trampoline = VirtualAlloc(NULL, TRAMPOLINE_SIZE, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!trampoline)
        return 0;
    memcpy(trampoline, target, MIGRATION_PROLOGUE_SIZE);
    write_abs_jump(trampoline + MIGRATION_PROLOGUE_SIZE, (uintptr_t)target + MIGRATION_PROLOGUE_SIZE);
    DWORD old;
    if (!VirtualProtect(trampoline, TRAMPOLINE_SIZE, PAGE_EXECUTE_READ, &old)) {
        VirtualFree(trampoline, 0, MEM_RELEASE);
        return 0;
    }
    FlushInstructionCache(GetCurrentProcess(), trampoline, TRAMPOLINE_SIZE);

    if (!VirtualProtect(target, MIGRATION_PROLOGUE_SIZE, PAGE_EXECUTE_READWRITE, &old)) {
        VirtualFree(trampoline, 0, MEM_RELEASE);
        return 0;
    }
    original_rate = (MonthlyRate)trampoline;
    unsigned char patch[MIGRATION_PROLOGUE_SIZE];
    write_abs_jump(patch, (uintptr_t)monthly_rate);
    patch[ABS_JUMP_SIZE] = 0x90;
    memcpy(target, patch, MIGRATION_PROLOGUE_SIZE);
    FlushInstructionCache(GetCurrentProcess(), target, MIGRATION_PROLOGUE_SIZE);
    DWORD unused;
    VirtualProtect(target, MIGRATION_PROLOGUE_SIZE, old, &unused);

    pin_self(monthly_rate);
    return 1;
}

__declspec(dllexport) int queue_migration(void *lua) {
    (void)lua;
    FILE *in = open_beside("people-request.txt", "r");
    if (!in)
        return 0;
    unsigned long long region = 0;
    int amount = 0;
    int parsed = fscanf(in, "%llx %d", &region, &amount);
    fclose(in);

    FILE *out = open_beside("people-result.txt", "w");
    if (!out)
        return 0;
    static const int needed[] = {SIG_REGION_GAME_STATE, SIG_GAME_STATE_CALENDAR};
    if (!sigs(needed, 2))
        return fail(out, "Migration data not found in this game version.");
    region_game_state = sig(SIG_REGION_GAME_STATE);
    game_state_calendar = sig(SIG_GAME_STATE_CALENDAR);
    uintptr_t calendar = calendar_for((uintptr_t)region);
    if (parsed != 2 || !calendar || (amount != 1 && amount != 5))
        return fail(out, "Invalid settlement or migration amount.");
    if (!install_rate_hook())
        return fail(out, "Migration hook not found in this game version or could not be installed.");

    int now = current_month(calendar);
    AcquireSRWLockExclusive(&bonus_lock);
    int slot = migration_slot(bonuses, MAX_BONUSES, (uintptr_t)region, calendar, now);
    int total = slot < 0 ? 0 : migration_queue(&bonuses[slot], (uintptr_t)region, calendar, now, amount);
    ReleaseSRWLockExclusive(&bonus_lock);

    if (total)
        fprintf(out, "OK %d", total);
    else if (slot < 0)
        fputs("Too many pending migration bonuses; wait for next month.", out);
    else
        fputs("Cannot queue more migration (limit 100 per region/month).", out);
    fclose(out);
    return 0;
}

#define DAMAGE_SITES 3
#define THUNK_PAGE_SIZE 4096

/* each site is a movss [reg+health], xmm0 of len bytes whose last 4 are the health offset */
typedef struct {
    int sig;
    unsigned len;
    void (*stub)(void);
} DamageSite;

static const DamageSite damage_sites[DAMAGE_SITES] = {
    {SIG_DAMAGE_R14, 9, damage_stub_r14},
    {SIG_DAMAGE_RSI_A, 8, damage_stub_rsi},
    {SIG_DAMAGE_RSI_B, 8, damage_stub_rsi},
};

static uintptr_t unit_health, unit_squad;

static DamageScale damage_scale = {.mult = 1.0f};
static SRWLOCK damage_lock = SRWLOCK_INIT;
static volatile LONG damage_seen, damage_mine;
static int damage_hooked;

float damage_adjust_health(unsigned long long unit, float next) {
    float mult = *(volatile float *)&damage_scale.mult;
    if (mult == 1.0f || !readable((uintptr_t)unit, unit_health + 4) || !readable((uintptr_t)unit, unit_squad + 4))
        return next;
    InterlockedIncrement(&damage_seen);
    AcquireSRWLockShared(&damage_lock);
    int player = damage_is_player(&damage_scale, *(int *)((uintptr_t)unit + unit_squad));
    ReleaseSRWLockShared(&damage_lock);
    if (!player)
        return next;
    InterlockedIncrement(&damage_mine);
    return damage_adjust(*(float *)((uintptr_t)unit + unit_health), next, mult);
}

static unsigned char *alloc_near(unsigned char *image) {
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(image + ((IMAGE_DOS_HEADER *)image)->e_lfanew);
    uintptr_t base = (uintptr_t)image, end = base + nt->OptionalHeader.SizeOfImage;
    const uintptr_t granularity = 0x10000, reach = 0x70000000;
    for (uintptr_t at = (end + granularity - 1) & ~(granularity - 1); at < base + reach; at += granularity) {
        unsigned char *p = VirtualAlloc((void *)at, THUNK_PAGE_SIZE, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
        if (p)
            return p;
    }
    return NULL;
}

static int install_damage_hook(void) {
    if (damage_hooked)
        return 1;
    unsigned char *sites[DAMAGE_SITES];
    int32_t health = 0;
    for (int i = 0; i < DAMAGE_SITES; i++) {
        int32_t disp;
        if (!(sites[i] = (unsigned char *)sig(damage_sites[i].sig)))
            return 0;
        memcpy(&disp, sites[i] + damage_sites[i].len - 4, 4);
        if (disp <= 0 || (i && disp != health))
            return 0;
        health = disp;
    }
    if (!(unit_squad = sig(SIG_UNIT_SQUAD)))
        return 0;
    unit_health = (uintptr_t)health;

    unsigned char *page = alloc_near(game_image());
    if (!page)
        return 0;
    for (int i = 0; i < DAMAGE_SITES; i++)
        damage_build_thunk(page + i * DAMAGE_THUNK_SIZE, sites[i], sites[i], damage_sites[i].len, damage_sites[i].stub);
    DWORD old;
    if (!VirtualProtect(page, THUNK_PAGE_SIZE, PAGE_EXECUTE_READ, &old)) {
        VirtualFree(page, 0, MEM_RELEASE);
        return 0;
    }
    FlushInstructionCache(GetCurrentProcess(), page, THUNK_PAGE_SIZE);

    DWORD olds[DAMAGE_SITES];
    for (int i = 0; i < DAMAGE_SITES; i++) {
        if (!VirtualProtect(sites[i], damage_sites[i].len, PAGE_EXECUTE_READWRITE, &olds[i])) {
            for (int j = 0; j < i; j++) {
                DWORD unused;
                VirtualProtect(sites[j], damage_sites[j].len, olds[j], &unused);
            }
            return 0;
        }
    }
    for (int i = 0; i < DAMAGE_SITES; i++) {
        damage_patch_site(sites[i], page + i * DAMAGE_THUNK_SIZE, damage_sites[i].len);
        FlushInstructionCache(GetCurrentProcess(), sites[i], damage_sites[i].len);
    }
    for (int i = DAMAGE_SITES - 1; i >= 0; i--) {
        DWORD unused;
        VirtualProtect(sites[i], damage_sites[i].len, olds[i], &unused);
    }

    pin_self(damage_adjust_health);
    return damage_hooked = 1;
}

__declspec(dllexport) int set_damage_scale(void *lua) {
    (void)lua;
    FILE *in = open_beside("damage-request.txt", "r");
    if (!in)
        return 0;
    char text[8192];
    size_t n = fread(text, 1, sizeof(text) - 1, in);
    fclose(in);
    text[n] = 0;

    FILE *out = open_beside("damage-result.txt", "w");
    if (!out)
        return 0;
    DamageScale next;
    if (!damage_parse(text, &next))
        return fail(out, "Invalid damage request.");
    if (next.mult != 1.0f && !install_damage_hook())
        return fail(out, "Damage hook not found in this game version or could not be installed.");

    AcquireSRWLockExclusive(&damage_lock);
    damage_scale = next;
    ReleaseSRWLockExclusive(&damage_lock);
    fprintf(out, "OK %.2f %d %ld %ld", next.mult, next.count, (long)damage_seen, (long)damage_mine);
    fclose(out);
    return 0;
}

#define MAX_FINISHED_PER_CALL 256

typedef void (*FinishConstruction)(void *);

static int is_constructed(uintptr_t building) {
    uintptr_t constructed = sig(SIG_BUILDING_CONSTRUCTED);
    if (!building || !constructed || !readable(building, constructed + 1))
        return -1;
    return *(volatile unsigned char *)(building + constructed) != 0;
}

__declspec(dllexport) int finish_construction(void *lua) {
    (void)lua;
    FILE *in = open_beside("finish-request.txt", "r");
    if (!in)
        return 0;
    FILE *out = open_beside("finish-result.txt", "w");
    if (!out) {
        fclose(in);
        return 0;
    }
    FinishConstruction finish = (FinishConstruction)sig(SIG_FINISH_CONSTRUCTION);
    if (!finish || !sig(SIG_BUILDING_CONSTRUCTED)) {
        fclose(in);
        return fail(out, "finishConstruction not found in this game version.");
    }

    unsigned long long address, done[MAX_FINISHED_PER_CALL];
    int finished = 0, built = 0;
    while (fscanf(in, "%llx", &address) == 1) {
        int state = is_constructed((uintptr_t)address);
        if (state < 0)
            continue;
        if (state > 0) {
            built++;
            continue;
        }
        if (finished == MAX_FINISHED_PER_CALL)
            continue;
        finish((void *)(uintptr_t)address);
        done[finished++] = address;
    }
    fclose(in);

    fprintf(out, "OK %d %d", finished, built);
    for (int i = 0; i < finished; i++)
        fprintf(out, " %llx", done[i]);
    fclose(out);
    return 0;
}

#define ENGINE_SCAN_SIZE 0x2000
#define ENGINE_SCAN_START 0x28
#define TARRAY_SIZE 16

static uintptr_t *find_building_array(uintptr_t engine, int count, uintptr_t first, uintptr_t second) {
    static uintptr_t cached;
    for (int i = -1; ENGINE_SCAN_START + i * 8 + TARRAY_SIZE <= ENGINE_SCAN_SIZE; i++) {
        uintptr_t at = i < 0 ? cached : ENGINE_SCAN_START + (uintptr_t)i * 8;
        if (!at)
            continue;
        uintptr_t *items = *(uintptr_t **)(engine + at);
        int num = *(int *)(engine + at + 8);
        if (num == count && readable((uintptr_t)items, 16) && items[0] == first && items[1] == second) {
            cached = at;
            return items;
        }
    }
    return NULL;
}

__declspec(dllexport) int unbuilt_buildings(void *lua) {
    (void)lua;
    FILE *in = open_beside("unbuilt-request.txt", "r");
    if (!in)
        return 0;
    unsigned long long engine = 0, first = 0, second = 0;
    int count = 0;
    int parsed = fscanf(in, "%llx %d %llx %llx", &engine, &count, &first, &second);
    fclose(in);

    FILE *out = open_beside("unbuilt-result.txt", "w");
    if (!out)
        return 0;
    if (parsed != 4 || count < 2 || !readable((uintptr_t)engine, ENGINE_SCAN_SIZE))
        return fail(out, "Invalid building list request.");
    uintptr_t *data = find_building_array((uintptr_t)engine, count, (uintptr_t)first, (uintptr_t)second);
    if (!data || !readable((uintptr_t)data, (size_t)count * 8))
        return fail(out, "Building list not found in the engine actor.");

    fputs("OK", out);
    for (int i = 0; i < count; i++)
        if (is_constructed(data[i]) == 0)
            fprintf(out, " %d", i);
    fclose(out);
    return 0;
}
