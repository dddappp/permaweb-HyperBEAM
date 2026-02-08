#include "quickjs.h"
#include <string.h>
#include <stdlib.h>
#include <pthread.h>
 
// Pthread stubs (WASI has no threads)
#define STUB(ret, name, args) ret name args { return 0; }
STUB(int, pthread_mutex_init, (pthread_mutex_t *m, const pthread_mutexattr_t *a))
STUB(int, pthread_mutex_destroy, (pthread_mutex_t *m))
STUB(int, pthread_mutex_lock, (pthread_mutex_t *m))
STUB(int, pthread_mutex_unlock, (pthread_mutex_t *m))
STUB(int, pthread_mutex_trylock, (pthread_mutex_t *m))
STUB(int, pthread_cond_init, (pthread_cond_t *c, const pthread_condattr_t *a))
STUB(int, pthread_cond_destroy, (pthread_cond_t *c))
STUB(int, pthread_cond_signal, (pthread_cond_t *c))
STUB(int, pthread_cond_broadcast, (pthread_cond_t *c))
STUB(int, pthread_cond_wait, (pthread_cond_t *c, pthread_mutex_t *m))
STUB(int, pthread_cond_timedwait, (pthread_cond_t *c, pthread_mutex_t *m, const struct timespec *t))
 
// Global QuickJS runtime and context
static JSRuntime *rt;
static JSContext *ctx;
 
// Initialize the QuickJS runtime
int qjs_init(void) {
    if (rt) return 0;  // Already initialized
    if (!(rt = JS_NewRuntime())) return -1;
    JS_SetMemoryLimit(rt, 16*1024*1024);   // 16MB memory limit
    JS_SetMaxStackSize(rt, 256*1024);       // 256KB stack limit
    if (!(ctx = JS_NewContext(rt))) return -2;
    return 0;
}
 
// Evaluate JavaScript code and return the result as a string
int qjs_eval(const char *code, int len, char *out, int out_size) {
    if (!ctx) return -1;
    JSValue r = JS_Eval(ctx, code, len, "<eval>", JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(r)) {
        JSValue e = JS_GetException(ctx);
        const char *s = JS_ToCString(ctx, e);
        int n = snprintf(out, out_size, "{\"error\":\"%s\"}", s ? s : "?");
        if (s) JS_FreeCString(ctx, s);
        JS_FreeValue(ctx, e);
        JS_FreeValue(ctx, r);
        return n;
    }
    int n = 0;
    if (!JS_IsUndefined(r)) {
        const char *s = JS_ToCString(ctx, r);
        if (s) { n = snprintf(out, out_size, "%s", s); JS_FreeCString(ctx, s); }
    }
    JS_FreeValue(ctx, r);
    return n;
}
 
// Entry point - initialize runtime when WASM starts
int main(void) { return qjs_init(); }