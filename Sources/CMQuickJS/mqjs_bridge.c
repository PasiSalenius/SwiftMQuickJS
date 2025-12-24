/*
 * Bridge functions for SwiftMQuickJS
 * Implements missing functions referenced in generated stdlib
 */

#include <stdio.h>
#include <sys/time.h>
#include "mquickjs_priv.h"

/* Forward declarations for functions referenced in mqjs_stdlib.h */
JSValue js_swift_trampoline(JSContext *ctx, JSValue *this_val, int argc, JSValue *argv, JSValue params);

#include "mqjs_stdlib.h"

/* Helper functions to access C macros and constants from Swift */
JSValue mqjs_get_undefined(void) {
    return JS_UNDEFINED;
}

JSValue mqjs_get_null(void) {
    return JS_NULL;
}

JSValue mqjs_get_true(void) {
    return JS_TRUE;
}

JSValue mqjs_get_false(void) {
    return JS_FALSE;
}

/* Helper to get the standard library definition */
const JSSTDLibraryDef *mqjs_get_stdlib(void) {
    return &js_stdlib;
}

/* Eval flags */
int32_t mqjs_eval_flag_retval(void) {
    return JS_EVAL_RETVAL;
}

int32_t mqjs_eval_flag_repl(void) {
    return JS_EVAL_REPL;
}

int32_t mqjs_eval_flag_strip_col(void) {
    return JS_EVAL_STRIP_COL;
}

int32_t mqjs_eval_flag_json(void) {
    return JS_EVAL_JSON;
}

/* Date.now() - returns current time in milliseconds since epoch */
JSValue js_date_now(JSContext *ctx, JSValue *this_val,
                    int argc, JSValue *argv)
{
    struct timeval tv;
    double d;

    gettimeofday(&tv, NULL);
    d = (double)tv.tv_sec * 1000.0 + (double)tv.tv_usec / 1000.0;

    return JS_NewFloat64(ctx, d);
}

/* print() - simple console output */
JSValue js_print(JSContext *ctx, JSValue *this_val,
                 int argc, JSValue *argv)
{
    JSCStringBuf buf;
    const char *str;
    int i;

    for (i = 0; i < argc; i++) {
        if (i != 0)
            putchar(' ');
        str = JS_ToCString(ctx, argv[i], &buf);
        if (str) {
            fputs(str, stdout);
        }
    }
    putchar('\n');
    fflush(stdout);

    return JS_UNDEFINED;
}

/* load() - not supported, return undefined */
JSValue js_load(JSContext *ctx, JSValue *this_val,
                int argc, JSValue *argv)
{
    return JS_ThrowReferenceError(ctx, "load() not supported");
}

/* setTimeout() - not supported in embedded mode */
JSValue js_setTimeout(JSContext *ctx, JSValue *this_val,
                      int argc, JSValue *argv)
{
    return JS_ThrowReferenceError(ctx, "setTimeout() not supported");
}

/* clearTimeout() - not supported in embedded mode */
JSValue js_clearTimeout(JSContext *ctx, JSValue *this_val,
                        int argc, JSValue *argv)
{
    return JS_ThrowReferenceError(ctx, "clearTimeout() not supported");
}

/* gc() - manually trigger garbage collection */
JSValue js_gc(JSContext *ctx, JSValue *this_val,
              int argc, JSValue *argv)
{
    JS_GC(ctx);
    return JS_UNDEFINED;
}

/* performance.now() - returns high-resolution time */
JSValue js_performance_now(JSContext *ctx, JSValue *this_val,
                           int argc, JSValue *argv)
{
    struct timeval tv;
    double d;

    gettimeofday(&tv, NULL);
    d = (double)tv.tv_sec * 1000.0 + (double)tv.tv_usec / 1000.0;

    return JS_NewFloat64(ctx, d);
}

/* Swift function trampoline - NOT YET IMPLEMENTED */
/* Placeholder for future native function binding support */
JSValue js_swift_trampoline(JSContext *ctx, JSValue *this_val,
                            int argc, JSValue *argv, JSValue params)
{
    return JS_ThrowReferenceError(ctx, "Native function binding not yet implemented");
}

/* Helper to get the Swift trampoline function index */
int32_t mqjs_get_swift_trampoline_index(void) {
    /* The trampoline is at index 147 in c_function_table */
    return 147;
}
