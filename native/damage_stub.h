#ifndef DAMAGE_STUB_H
#define DAMAGE_STUB_H
#include <stdint.h>
#include <string.h>
#define DAMAGE_STUB_BODY(name, reg)                                                                                    \
    ".globl " name "\n" name ":\n"                                                                                     \
    "push rax\npush rcx\npush rdx\npush r8\npush r9\npush r10\npush r11\n"                                             \
    "sub rsp,112\n"                                                                                                    \
    "movdqu [rsp+32],xmm1\nmovdqu [rsp+48],xmm2\nmovdqu [rsp+64],xmm3\nmovdqu [rsp+80],xmm4\nmovdqu [rsp+96],xmm5\n"   \
    "mov rcx," reg "\nmovaps xmm1,xmm0\ncall damage_adjust_health\n"                                                   \
    "movdqu xmm1,[rsp+32]\nmovdqu xmm2,[rsp+48]\nmovdqu xmm3,[rsp+64]\nmovdqu xmm4,[rsp+80]\nmovdqu xmm5,[rsp+96]\n"   \
    "add rsp,112\n"                                                                                                    \
    "pop r11\npop r10\npop r9\npop r8\npop rdx\npop rcx\npop rax\nret\n"
__asm__(".text\n.intel_syntax noprefix\n" DAMAGE_STUB_BODY("damage_stub_rsi", "rsi")
            DAMAGE_STUB_BODY("damage_stub_r14", "r14") ".att_syntax prefix\n");
extern void damage_stub_rsi(void);
extern void damage_stub_r14(void);
float damage_adjust_health(unsigned long long unit, float next);
#define DAMAGE_THUNK_SIZE 64
static inline void damage_build_thunk(unsigned char *t, const unsigned char *site, const unsigned char *orig,
                                      unsigned len, void (*stub)(void)) {
    int32_t slot = 6 + (int32_t)len + 5, disp = slot - 6,
            back = (int32_t)((intptr_t)(site + len) - (intptr_t)(t + 6 + len + 5));
    uintptr_t target = (uintptr_t)stub;
    t[0] = 0xff;
    t[1] = 0x15;
    memcpy(t + 2, &disp, 4);
    memcpy(t + 6, orig, len);
    t[6 + len] = 0xe9;
    memcpy(t + 7 + len, &back, 4);
    memcpy(t + slot, &target, 8);
}
static inline void damage_patch_site(unsigned char *site, const unsigned char *t, unsigned len) {
    int32_t rel = (int32_t)((intptr_t)t - (intptr_t)(site + 5));
    site[0] = 0xe9;
    memcpy(site + 1, &rel, 4);
    for (unsigned k = 5; k < len; k++)
        site[k] = 0x90;
}
#endif
