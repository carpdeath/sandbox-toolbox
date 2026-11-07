#include <windows.h>
#include <wincrypt.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>
#include "migration_bonus.h"
#include "damage_scale.h"
#include "damage_stub.h"

static HMODULE self;

BOOL WINAPI DllMain(HINSTANCE h, DWORD why, LPVOID p) {
    (void)p;
    if (why == DLL_PROCESS_ATTACH)
        self = h;
    return TRUE;
}

static const unsigned char SUPPORTED_SHA256[32] = {
    0x56, 0x04, 0x51, 0xdf, 0x38, 0xcd, 0x91, 0x13, 0x40, 0x26, 0xc2, 0x5b, 0x69, 0x53, 0x94, 0x49,
    0xc5, 0x70, 0xf3, 0x16, 0x3e, 0x33, 0xbc, 0x8c, 0x45, 0xb4, 0xdc, 0x20, 0xb6, 0x95, 0x2c, 0xee,
};

enum { BUILD_UNREADABLE = -1, BUILD_OTHER = 0, BUILD_SUPPORTED = 1 };

static int game_build(void) {
    static int cached;
    if (cached)
        return cached;
    cached = BUILD_UNREADABLE;

    wchar_t path[MAX_PATH];
    GetModuleFileNameW(NULL, path, MAX_PATH);
    FILE *f = _wfopen(path, L"rb");
    if (!f)
        return cached;

    HCRYPTPROV provider = 0;
    HCRYPTHASH hash = 0;
    if (CryptAcquireContextA(&provider, NULL, NULL, PROV_RSA_AES, CRYPT_VERIFYCONTEXT) &&
        CryptCreateHash(provider, CALG_SHA_256, 0, 0, &hash)) {
        static unsigned char buf[65536];
        unsigned char digest[32];
        DWORD length = sizeof(digest);
        size_t n;
        int ok = 1;
        while (ok && (n = fread(buf, 1, sizeof(buf), f)))
            ok = CryptHashData(hash, buf, (DWORD)n, 0);
        if (ok && !ferror(f)) {
            int match = CryptGetHashParam(hash, HP_HASHVAL, digest, &length, 0) &&
                        !memcmp(digest, SUPPORTED_SHA256, sizeof(digest));
            cached = match ? BUILD_SUPPORTED : BUILD_OTHER;
        }
    }
    fclose(f);
    if (hash)
        CryptDestroyHash(hash);
    if (provider)
        CryptReleaseContext(provider, 0);
    return cached;
}

static int build_ok(FILE *result, const char *feature) {
    int build = game_build();
    if (build == BUILD_SUPPORTED)
        return 1;
    fprintf(result,
            build == BUILD_OTHER ? "Unsupported game executable; %s disabled."
                                 : "Could not read the game executable; %s disabled.",
            feature);
    return 0;
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

#define MIGRATION_RATE_RVA 0x4c3ff10
#define MIGRATION_PROLOGUE_SIZE 15
#define TRAMPOLINE_SIZE (MIGRATION_PROLOGUE_SIZE + ABS_JUMP_SIZE)

#define REGION_GAME_STATE 0x318
#define GAME_STATE_CALENDAR 0x2c8
#define CALENDAR_MONTH 0x170

#define MAX_BONUSES 32

typedef int (*MonthlyRate)(void *);
static MonthlyRate original_rate;
static MigrationBonus bonuses[MAX_BONUSES];
static SRWLOCK bonus_lock = SRWLOCK_INIT;

static uintptr_t calendar_for(uintptr_t region) {
    if (!readable(region, REGION_GAME_STATE + 8))
        return 0;
    uintptr_t state = *(uintptr_t *)(region + REGION_GAME_STATE);
    if (!readable(state, GAME_STATE_CALENDAR + 8))
        return 0;
    uintptr_t calendar = *(uintptr_t *)(state + GAME_STATE_CALENDAR);
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
    static const unsigned char expected[MIGRATION_PROLOGUE_SIZE] = {
        0x48, 0x89, 0x5c, 0x24, 0x10, 0x48, 0x89, 0x74, 0x24, 0x18, 0x48, 0x89, 0x7c, 0x24, 0x20,
    };
    unsigned char *target = game_image() + MIGRATION_RATE_RVA;
    if (memcmp(target, expected, MIGRATION_PROLOGUE_SIZE))
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
    if (!build_ok(out, "People"))
        return fail(out, NULL);
    uintptr_t calendar = calendar_for((uintptr_t)region);
    if (parsed != 2 || !calendar || (amount != 1 && amount != 5))
        return fail(out, "Invalid settlement or migration amount.");
    if (!install_rate_hook())
        return fail(out, "Migration hook could not be installed.");

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

#define UNIT_HEALTH 0x2e8
#define UNIT_SQUAD 0x2b8
#define DAMAGE_SITES 3
#define THUNK_PAGE_SIZE 4096

typedef struct {
    uintptr_t rva;
    unsigned len;
    unsigned char bytes[9];
    void (*stub)(void);
} DamageSite;

static const DamageSite damage_sites[DAMAGE_SITES] = {
    {0x4dabf81, 9, {0xf3, 0x41, 0x0f, 0x11, 0x86, 0xe8, 0x02, 0x00, 0x00}, damage_stub_r14},
    {0x4dac0a4, 8, {0xf3, 0x0f, 0x11, 0x86, 0xe8, 0x02, 0x00, 0x00}, damage_stub_rsi},
    {0x4dac3f5, 8, {0xf3, 0x0f, 0x11, 0x86, 0xe8, 0x02, 0x00, 0x00}, damage_stub_rsi},
};

static DamageScale damage_scale = {.mult = 1.0f};
static SRWLOCK damage_lock = SRWLOCK_INIT;
static volatile LONG damage_seen, damage_mine;
static int damage_hooked;

float damage_adjust_health(unsigned long long unit, float next) {
    float mult = *(volatile float *)&damage_scale.mult;
    if (mult == 1.0f || !readable((uintptr_t)unit, UNIT_HEALTH + 4))
        return next;
    InterlockedIncrement(&damage_seen);
    AcquireSRWLockShared(&damage_lock);
    int player = damage_is_player(&damage_scale, *(int *)((uintptr_t)unit + UNIT_SQUAD));
    ReleaseSRWLockShared(&damage_lock);
    if (!player)
        return next;
    InterlockedIncrement(&damage_mine);
    return damage_adjust(*(float *)((uintptr_t)unit + UNIT_HEALTH), next, mult);
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
    unsigned char *image = game_image();
    for (int i = 0; i < DAMAGE_SITES; i++)
        if (memcmp(image + damage_sites[i].rva, damage_sites[i].bytes, damage_sites[i].len))
            return 0;

    unsigned char *page = alloc_near(image);
    if (!page)
        return 0;
    for (int i = 0; i < DAMAGE_SITES; i++) {
        const DamageSite *s = &damage_sites[i];
        damage_build_thunk(page + i * DAMAGE_THUNK_SIZE, image + s->rva, s->bytes, s->len, s->stub);
    }
    DWORD old;
    if (!VirtualProtect(page, THUNK_PAGE_SIZE, PAGE_EXECUTE_READ, &old)) {
        VirtualFree(page, 0, MEM_RELEASE);
        return 0;
    }
    FlushInstructionCache(GetCurrentProcess(), page, THUNK_PAGE_SIZE);

    DWORD olds[DAMAGE_SITES];
    for (int i = 0; i < DAMAGE_SITES; i++) {
        if (!VirtualProtect(image + damage_sites[i].rva, damage_sites[i].len, PAGE_EXECUTE_READWRITE, &olds[i])) {
            for (int j = 0; j < i; j++) {
                DWORD unused;
                VirtualProtect(image + damage_sites[j].rva, damage_sites[j].len, olds[j], &unused);
            }
            return 0;
        }
    }
    for (int i = 0; i < DAMAGE_SITES; i++) {
        const DamageSite *s = &damage_sites[i];
        unsigned char *site = image + s->rva;
        damage_patch_site(site, page + i * DAMAGE_THUNK_SIZE, s->len);
        FlushInstructionCache(GetCurrentProcess(), site, s->len);
    }
    for (int i = DAMAGE_SITES - 1; i >= 0; i--) {
        DWORD unused;
        VirtualProtect(image + damage_sites[i].rva, damage_sites[i].len, olds[i], &unused);
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
    if (!build_ok(out, "damage scaling"))
        return fail(out, NULL);
    DamageScale next;
    if (!damage_parse(text, &next))
        return fail(out, "Invalid damage request.");
    if (next.mult != 1.0f && !install_damage_hook())
        return fail(out, "Damage hook could not be installed.");

    AcquireSRWLockExclusive(&damage_lock);
    damage_scale = next;
    ReleaseSRWLockExclusive(&damage_lock);
    fprintf(out, "OK %.2f %d %ld %ld", next.mult, next.count, (long)damage_seen, (long)damage_mine);
    fclose(out);
    return 0;
}

#define FINISH_CONSTRUCTION_RVA 0x4d0b370
#define BUILDING_CONSTRUCTED 0x3c1
#define MAX_FINISHED_PER_CALL 256

typedef void (*FinishConstruction)(void *);

static FinishConstruction finish_construction_fn(void) {
    static const unsigned char expected[16] = {0x48, 0x8b, 0xc4, 0x48, 0x89, 0x58, 0x10, 0x48,
                                               0x89, 0x70, 0x18, 0x48, 0x89, 0x78, 0x20, 0x55};
    unsigned char *target = game_image() + FINISH_CONSTRUCTION_RVA;
    return memcmp(target, expected, sizeof(expected)) ? NULL : (FinishConstruction)target;
}

static int is_constructed(uintptr_t building) {
    if (!building || !readable(building, BUILDING_CONSTRUCTED + 1))
        return -1;
    return *(volatile unsigned char *)(building + BUILDING_CONSTRUCTED) != 0;
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
    if (!build_ok(out, "instant construction")) {
        fclose(in);
        return fail(out, NULL);
    }
    FinishConstruction finish = finish_construction_fn();
    if (!finish) {
        fclose(in);
        return fail(out, "finishConstruction not found in this executable.");
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
