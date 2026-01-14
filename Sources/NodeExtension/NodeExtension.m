//
//  Bridge.m
//  Bridge
//
//  Copyright (c) 2021 Changbeom Ahn
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import <Foundation/Foundation.h>
@import node_api;
@import NodeBridge;

#define NAPI_CALL(env, call)                                      \
  do {                                                            \
    napi_status status = (call);                                  \
    if (status != napi_ok) {                                      \
      const napi_extended_error_info* error_info = NULL;          \
      napi_get_last_error_info((env), &error_info);               \
      bool is_pending;                                            \
      napi_is_exception_pending((env), &is_pending);              \
      if (!is_pending) {                                          \
        const char* message = (error_info->error_message == NULL) \
            ? "empty error message"                               \
            : error_info->error_message;                          \
        napi_throw_error((env), NULL, message);                   \
        return NULL;                                              \
      }                                                           \
    }                                                             \
  } while(0)

static napi_value callback(napi_env env, napi_callback_info info) {
    return [Addon callbackWithEnv:env info:info];
}

static void CallJs(napi_env env, napi_value js_cb, void* context, void *data) {
    napi_status status;
    
    napi_value value;
    NSError *error;
    [Addon convertWithData:data result:&value env:env error:&error];
    
    napi_value cb;
    status = napi_create_function(env, "cb", NAPI_AUTO_LENGTH, callback, nil, &cb);
    assert(status == napi_ok);
    
    napi_value undefined;
    status = napi_get_undefined(env, &undefined);
    assert(status == napi_ok);
    
    napi_value argv[] = {value, cb};
    status = napi_call_function(env, undefined, js_cb, 2, argv, nil);
    assert(status == napi_ok);
}

static napi_value
DoSomethingUseful(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value js_cb;
    napi_status status;
    
    status = napi_get_cb_info(env, info, &argc, &js_cb, nil, nil);
    assert(status == napi_ok);
    
    napi_value work_name;
    status = napi_create_string_utf8(env, "work", NAPI_AUTO_LENGTH, &work_name);
    assert(status == napi_ok);
    
    napi_threadsafe_function tsfn;
    status = napi_create_threadsafe_function(env, js_cb, nil, work_name, 0, 1, nil, nil, nil, CallJs, &tsfn);
    assert(status == napi_ok);
    
    Addon.tsfn = tsfn;
    
    return NULL;
}

static napi_value Notify(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_status status = napi_get_cb_info(env, info, &argc, args, NULL, NULL);
    
    if (status != napi_ok) {
        napi_throw_error(env, NULL, "Failed to parse arguments");
        return NULL;
    }
    
    if (argc < 1) {
        napi_throw_error(env, NULL, "Expected one argument");
        return NULL;
    }
    
    napi_valuetype valuetype;
    status = napi_typeof(env, args[0], &valuetype);
    
    if (valuetype != napi_object) {
        napi_throw_type_error(env, NULL, "Argument must be an object");
        return NULL;
    }
    
    // Retrieve global.JSON.stringify
    napi_value global;
    status = napi_get_global(env, &global);
    if (status != napi_ok) return NULL;
    
    napi_value json_object;
    status = napi_get_named_property(env, global, "JSON", &json_object);
    if (status != napi_ok) return NULL;
    
    napi_value stringify_fn;
    status = napi_get_named_property(env, json_object, "stringify", &stringify_fn);
    if (status != napi_ok) return NULL;
    
    // Call JSON.stringify(args[0])
    napi_value json_string_val;
    status = napi_call_function(env, json_object, stringify_fn, 1, &args[0], &json_string_val);
    
    if (status != napi_ok) {
        napi_throw_error(env, NULL, "JSON.stringify failed");
        return NULL;
    }
    
    // Get C string
    size_t str_len;
    status = napi_get_value_string_utf8(env, json_string_val, NULL, 0, &str_len);
    if (status != napi_ok) return NULL;
    
    char *str = (char *)malloc(str_len + 1);
    if (str == NULL) {
        napi_throw_error(env, NULL, "Memory allocation failed");
        return NULL;
    }
    
    status = napi_get_value_string_utf8(env, json_string_val, str, str_len + 1, &str_len);
    if (status != napi_ok) {
        free(str);
        return NULL;
    }
    
    // Convert to NSDictionary
    NSString *jsonString = [NSString stringWithUTF8String:str];
    free(str);
    
    if (jsonString) {
        NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
        NSError *error = nil;
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
        
        if (dict) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:@"JSNotify"
                                                                    object:nil
                                                                  userInfo:dict];
            });
        } else {
            NSLog(@"[NodeExtension] Failed to parse JSON data: %@", error);
        }
    }
    
    return NULL;
}

napi_value create_addon(napi_env env, napi_value exports) {
  napi_value on;
  NAPI_CALL(env, napi_create_function(env,
                                      "on",
                                      NAPI_AUTO_LENGTH,
                                      DoSomethingUseful,
                                      NULL,
                                      &on));

  NAPI_CALL(env, napi_set_named_property(env,
                                         exports,
                                         "on",
                                         on));

  napi_value notify;
  NAPI_CALL(env, napi_create_function(env,
                                      "notify",
                                      NAPI_AUTO_LENGTH,
                                      Notify,
                                      NULL,
                                      &notify));

  NAPI_CALL(env, napi_set_named_property(env,
                                         exports,
                                         "notify",
                                         notify));

  return exports;
}

#define NODE_GYP_MODULE_NAME SwiftBridge

NAPI_MODULE_INIT() {
    return create_addon(env, exports);
}
