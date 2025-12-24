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

/* ============================================================================
 * Native Function Binding Support
 * ============================================================================ */

/*
 * Callback type for Swift to handle native function calls.
 *
 * Parameters:
 *   - opaque: The context opaque pointer (Swift context reference)
 *   - function_id: The ID of the registered Swift function
 *   - argc: Number of arguments
 *   - argv: Array of JSValue arguments
 *
 * Returns: JSValue result (or JS_EXCEPTION on error)
 */
typedef JSValue (*MQJSNativeCallback)(void *opaque, int32_t function_id,
                                       int argc, JSValue *argv);

/* Global callback - set by Swift during context initialization */
static MQJSNativeCallback g_native_callback = NULL;

/* Set the native callback handler (called from Swift) */
void mqjs_set_native_callback(MQJSNativeCallback callback) {
    g_native_callback = callback;
}

/* Get function ID from params object */
static int32_t get_function_id_from_params(JSContext *ctx, JSValue params) {
    /* params is a JS number containing the function ID */
    int32_t func_id = 0;
    JS_ToInt32(ctx, &func_id, params);
    return func_id;
}

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

/*
 * Swift function trampoline - called when JavaScript invokes a native function.
 *
 * This function extracts the function ID from params, retrieves the context
 * opaque pointer, and calls the Swift callback handler.
 */
JSValue js_swift_trampoline(JSContext *ctx, JSValue *this_val,
                            int argc, JSValue *argv, JSValue params)
{
    if (!g_native_callback) {
        return JS_ThrowInternalError(ctx, "Native callback not initialized");
    }

    /* Get the function ID from params */
    int32_t func_id = get_function_id_from_params(ctx, params);

    /* Get the Swift context reference from context opaque */
    void *opaque = JS_GetContextOpaque(ctx);

    /* Call Swift handler */
    return g_native_callback(opaque, func_id, argc, argv);
}

/* Helper to get the Swift trampoline function index */
int32_t mqjs_get_swift_trampoline_index(void) {
    /* The trampoline is at index 147 in c_function_table */
    return 147;
}

/* Create a native function bound to a Swift closure */
JSValue mqjs_new_native_function(JSContext *ctx, int32_t function_id) {
    /* Create params value containing the function ID */
    JSValue params = JS_NewInt32(ctx, function_id);

    /* Create the C function with params */
    int32_t trampoline_idx = mqjs_get_swift_trampoline_index();
    return JS_NewCFunctionParams(ctx, trampoline_idx, params);
}

/* Get context opaque pointer */
void *mqjs_get_context_opaque(JSContext *ctx) {
    return JS_GetContextOpaque(ctx);
}

/* Set context opaque pointer */
void mqjs_set_context_opaque(JSContext *ctx, void *opaque) {
    JS_SetContextOpaque(ctx, opaque);
}

/* Helper to get JS_EXCEPTION value (macro not accessible from Swift) */
JSValue mqjs_get_exception(void) {
    return JS_EXCEPTION;
}

/* Helper to throw an internal error (macro not accessible from Swift) */
JSValue mqjs_throw_internal_error(JSContext *ctx, const char *message) {
    return JS_ThrowInternalError(ctx, "%s", message);
}
