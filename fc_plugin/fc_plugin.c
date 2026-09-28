/* bpf_conformance plugin for Femto-Container (rBPF successor).
 * Usage: fc_plugin [<hex memory>] ; program hex on stdin; prints r0 hex. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "femtocontainer/femtocontainer.h"

// same as rbpf_plugin, a dummy helper function call with id 5
static uint32_t helper_unwind(f12r_t *fc, uint64_t *regs) { (void)fc; return (uint32_t)regs[1]; }
f12r_call_t f12r_get_external_call(uint32_t num) { return num == 5 ? helper_unwind : NULL; }

static size_t decode_hex(const char *s, uint8_t *out, size_t cap) {
    size_t n = 0;
    while (*s) {
        while (*s && isspace((unsigned char)*s)) s++;
        if (!*s) break;
        char *end; unsigned long v = strtoul(s, &end, 16);
        if (end == s || n >= cap) { fprintf(stderr, "bad hex\n"); exit(1); }
        out[n++] = (uint8_t)v; s = end;
    }
    return n;
}

static uint8_t stack[FC_STACK_SIZE] __attribute__((aligned(8)));
static uint8_t mem[1 << 16] __attribute__((aligned(8)));
static uint8_t app[sizeof(f12r_header_t) + (1 << 20)] __attribute__((aligned(8)));
static char buf[1 << 22];

int main(int argc, char **argv) {
    size_t mem_len = 0;
    if (argc > 1 && strncmp(argv[1], "--", 2) != 0) mem_len = decode_hex(argv[1], mem, sizeof mem);
    size_t n = fread(buf, 1, sizeof buf - 1, stdin); buf[n] = 0;
    f12r_header_t *h = (f12r_header_t *)app;
    uint8_t *text = app + sizeof *h;
    /* prepend `mov r2, mem_len` (suite expects r2 = mem length) */
    uint8_t pre[8] = {0xb7, 0x02, 0, 0};
    int32_t l = (int32_t)mem_len; memcpy(pre + 4, &l, 4);
    memcpy(text, pre, 8);
    size_t plen = decode_hex(buf, text + 8, sizeof app - sizeof *h - 8);
    memset(h, 0, sizeof *h);
    h->magic = RBPF_MAGIC_NO; h->text_len = (uint32_t)(plen + 8);

    f12r_t fc = { .application = app, .application_len = sizeof *h + plen + 8,
                  .stack = stack, .stack_size = sizeof stack };
    f12r_setup(&fc);
    int64_t res = 0;
    int rc = f12r_execute_ctx(&fc, mem, mem_len, &res);
    if (rc != FC_OK) { fprintf(stderr, "femto-container error %d\n", rc); return 1; }
    printf("%llx\n", (unsigned long long)res);
    return 0;
}
