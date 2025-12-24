/*
 * Bridge functions for SwiftMQuickJS
 */

#ifndef MQJS_BRIDGE_H
#define MQJS_BRIDGE_H

#include "mquickjs.h"

/* Helper functions to access C macros and constants from Swift */
JSValue mqjs_get_undefined(void);
JSValue mqjs_get_null(void);
JSValue mqjs_get_true(void);
JSValue mqjs_get_false(void);
const JSSTDLibraryDef *mqjs_get_stdlib(void);

/* Eval flags */
int32_t mqjs_eval_flag_retval(void);
int32_t mqjs_eval_flag_repl(void);
int32_t mqjs_eval_flag_strip_col(void);
int32_t mqjs_eval_flag_json(void);

/* Declare functions referenced by mqjs_stdlib but not in mquickjs_priv.h */
JSValue js_date_now(JSContext *ctx, JSValue *this_val, int argc, JSValue *argv);
JSValue js_print(JSContext *ctx, JSValue *this_val, int argc, JSValue *argv);

/* Swift function trampoline */
JSValue js_swift_trampoline(JSContext *ctx, JSValue *this_val, int argc, JSValue *argv, JSValue params);
int32_t mqjs_get_swift_trampoline_index(void);

/* Native function binding support */

/* Callback type for Swift to handle native function calls */
typedef JSValue (*MQJSNativeCallback)(void *opaque, int32_t function_id,
                                       int argc, JSValue *argv, JSValue this_val);

/* Set the native callback handler (called once from Swift during init) */
void mqjs_set_native_callback(MQJSNativeCallback callback);

/* Create a native function bound to a Swift closure */
JSValue mqjs_new_native_function(JSContext *ctx, int32_t function_id);

/* Context opaque pointer accessors */
void mqjs_set_context_opaque(JSContext *ctx, void *opaque);
void *mqjs_get_context_opaque(JSContext *ctx);

/* Helper to get JS_EXCEPTION value (macro not accessible from Swift) */
JSValue mqjs_get_exception(void);

/* Helper to throw an internal error (macro not accessible from Swift) */
JSValue mqjs_throw_internal_error(JSContext *ctx, const char *message);

/* Set the prototype of an object */
int mqjs_set_prototype(JSContext *ctx, JSValue obj, JSValue proto);

#endif /* MQJS_BRIDGE_H */
