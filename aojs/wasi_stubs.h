#ifndef WASI_STUBS_H
#define WASI_STUBS_H
#include <stddef.h>
 
// Floating-point environment stubs (WASI doesn't support fenv.h)
#define FE_DOWNWARD 0x400
#define FE_UPWARD 0x800
#define FE_TOWARDZERO 0xC00
static inline int fesetround(int r) { (void)r; return 0; }
static inline int fegetround(void) { return 0; }
 
// Memory introspection stub (not available in WASI)
static inline size_t malloc_usable_size(void *p) { (void)p; return 0; }
 
#endif