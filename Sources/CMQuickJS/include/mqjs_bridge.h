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

#endif /* MQJS_BRIDGE_H */
