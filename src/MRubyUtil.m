//
//  MRubyUtil.m
//  MRuby
//
//  Created by yoshida on 2014/01/08.
//  Copyright (c) 2014年 yoshida. All rights reserved.
//

#import "MRubyUtil.h"
#import "MRubyBlockInfo.h"

@implementation MRubyUtil

+ (void)mrbInit:(mrb_state *)mrb
{
    // GC.disable
    mrb_funcall(mrb, mrb_obj_value(mrb_class_get(mrb, "GC")), "disable", 0);
    
    // define ObjcBridgeProc class
    mrb_init_objc_bridge_proc(mrb);
}

+ (void)mrb:(mrb_state *)mrb setArgv:(NSArray *)args
{
    if (!args) {
        args = @[];
    }
    mrb_define_global_const(mrb, "ARGV", [MRubyUtil mrb:mrb objc2mrb:args]);
}


#pragma mark eval

+ (mrb_value)mrb:(mrb_state *)mrb eval:(NSString *)code
{
    return [self mrb:mrb eval:code filename:NULL];
}

+ (mrb_value)mrb:(mrb_state *)mrb eval:(NSString *)code filename:(const char *)filename
{
    if (!filename) {
        filename = "-e";
    }
    mrbc_context *c = mrbc_context_new(mrb);
    mrbc_filename(mrb, c, filename);
    mrb_gv_set(mrb, mrb_intern_lit(mrb, "$0"), mrb_str_new_cstr(mrb, filename));
    
    mrb_value val = mrb_load_string_cxt(mrb, [code UTF8String], c);
    mrbc_context_free(mrb, c);
    
    [self mrbRaiseUncaughtException:mrb];
    
    return val;
}

+ (void)mrbRaiseUncaughtException:(mrb_state *)mrb
{
    if (mrb->exc) {
        // Uncaught Exception
        NSException *exception = (NSException*)[self mrb:mrb mrb2objc:mrb_obj_value(mrb->exc)];
        mrb->exc = 0;
        [exception raise];
    }
}


#pragma mark convert

// see also: https://github.com/mattn/go-mruby/blob/master/mruby.go

+ (mrb_value)mrb:(mrb_state *)mrb objc2mrb:(NSObject *)o
{
    if (!o) {
        return mrb_nil_value();
    } else if ([o isKindOfClass:[MRubyValue class]]) {
        return [(MRubyValue *)o toMRb];
    } else if ([o isKindOfClass:[NSNumber class]]) {
        switch (CFNumberGetType((CFNumberRef)o)) {
            case kCFNumberSInt8Type:
            case kCFNumberCharType:
                return mrb_fixnum_value((mrb_int)[(NSNumber*)o charValue]);
                break;
            case kCFNumberSInt16Type:
            case kCFNumberShortType:
                return mrb_fixnum_value((mrb_int)[(NSNumber*)o shortValue]);
                break;
            case kCFNumberSInt32Type:
            case kCFNumberIntType:
                return mrb_fixnum_value((mrb_int)[(NSNumber*)o intValue]);
                break;
            case kCFNumberLongType:
                return mrb_fixnum_value((mrb_int)[(NSNumber*)o longValue]);
                break;
            case kCFNumberSInt64Type:
            case kCFNumberLongLongType:
                return mrb_fixnum_value((mrb_int)[(NSNumber*)o longLongValue]);
                break;
            case kCFNumberFloat32Type:
            case kCFNumberFloatType:
                return mrb_float_value(mrb, (mrb_float)[(NSNumber*)o floatValue]);
                break;
            case kCFNumberFloat64Type:
            case kCFNumberDoubleType:
                return mrb_float_value(mrb, (mrb_float)[(NSNumber*)o doubleValue]);
                break;
            default:
                NSLog(@"Unsupported CFNumberType: %d", (int)CFNumberGetType((CFNumberRef)o));
                break;
        }
    } else if ([o isKindOfClass:[NSString class]]) {
        return mrb_str_new(mrb, [(NSString*)o UTF8String], [(NSString*)o lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
    } else if ([o isKindOfClass:[NSArray class]]) {
        mrb_value ary = mrb_ary_new_capa(mrb, (mrb_int)[(NSArray*)o count]);
        for (int i=0; i<[(NSArray*)o count]; i++) {
            mrb_ary_push(mrb, ary, [self mrb:mrb objc2mrb:[(NSArray*)o objectAtIndex:i]]);
        }
        return ary;
    } else if ([o isKindOfClass:[NSDictionary class]]) {
        mrb_value hash = mrb_hash_new_capa(mrb, (mrb_int)[(NSDictionary*)o count]);
        for (id key in [(NSDictionary*)o keyEnumerator]) {
            mrb_hash_set(mrb, hash, [self mrb:mrb objc2mrb:key], [self mrb:mrb objc2mrb:[(NSDictionary*)o objectForKey:key]]);
        }
        return hash;
    } else {
        NSLog(@"Unsupported Class: %@", [o class]);
    }
    return mrb_nil_value();
}

+ (NSObject *)mrb:(mrb_state *)mrb mrb2objc:(mrb_value)o
{
    return [self mrb:mrb mrb2objc:o useNSNull:FALSE];
}

+ (NSObject *)mrb:(mrb_state *)mrb mrb2objc:(mrb_value)o useNSNull:(BOOL)useNSNull
{
    NSObject *ret = nil;
    if (!mrb_nil_p(o)) {
        switch (mrb_type(o)) {
            case MRB_TT_FALSE:
                ret = [NSNumber numberWithBool:FALSE];
                break;
            case MRB_TT_TRUE:
                ret = [NSNumber numberWithBool:TRUE];
                break;
            case MRB_TT_FIXNUM:
                ret = [NSNumber numberWithInt:mrb_fixnum(o)];
                break;
            case MRB_TT_SYMBOL:
                ret = [NSString stringWithCString:mrb_string_value_ptr(mrb, mrb_funcall(mrb, o, "to_s", 0)) encoding:NSUTF8StringEncoding];
                break;
            case MRB_TT_FLOAT:
                ret = [NSNumber numberWithDouble:(mrb_float)mrb_float(o)];
                break;
            case MRB_TT_PROC:
                break;
            case MRB_TT_ARRAY:{
                NSMutableArray *ary = [NSMutableArray arrayWithCapacity:RARRAY_LEN(o)];
                for (int i=0; i<RARRAY_LEN(o); i++) {
                    NSObject *obj = [self mrb:mrb mrb2objc:mrb_ary_ref(mrb, o, i) useNSNull:TRUE];
                    [ary setObject:obj atIndexedSubscript:i];
                }
                ret = ary;
                break;
            }
            case MRB_TT_HASH:{
                mrb_value keys = mrb_hash_keys(mrb, o);
                NSMutableDictionary *hash = [NSMutableDictionary dictionaryWithCapacity:RARRAY_LEN(keys)];
                for (int i=0; i<RARRAY_LEN(keys); i++) {
                    mrb_value key = mrb_ary_entry(keys, i);
                    mrb_value val = mrb_hash_get(mrb, o, key);
                    
                    id<NSCopying> key2 = (id<NSCopying>)[self mrb:mrb mrb2objc:key useNSNull:TRUE];
                    NSObject *val2 = [self mrb:mrb mrb2objc:val useNSNull:TRUE];
                    
                    [hash setObject:val2 forKey:key2];
                }
                ret = hash;
                break;
            }
            case MRB_TT_STRING:{
                char str[RSTRING_LEN(o)+1];
                memcpy(str, RSTRING_PTR(o), RSTRING_LEN(o));
                str[RSTRING_LEN(o)] = 0;
                ret = [NSString stringWithCString:str encoding:NSUTF8StringEncoding];
                break;
            }
            case MRB_TT_RANGE:{
                // NOTICE: force convert to unsigned integer
                mrb_value begin = mrb_funcall(mrb, mrb_funcall(mrb, o, "begin", 0), "to_i", 0);
                mrb_value end = mrb_funcall(mrb, mrb_funcall(mrb, o, "end", 0), "to_i", 0);
                
                NSUInteger loc = [(NSNumber*)[self mrb:mrb mrb2objc:begin] unsignedIntegerValue];
                NSUInteger len = [(NSNumber*)[self mrb:mrb mrb2objc:end] unsignedIntegerValue] - loc;
                
                ret = [NSValue valueWithRange:NSMakeRange(loc, len)];
                break;
            }
            case MRB_TT_OBJECT:{
                if (mrb_obj_is_kind_of(mrb, o, mrb->eException_class)) {
                    // Exception class
                    NSArray *backtrace = (NSArray *)[self mrb:mrb mrb2objc:mrb_get_backtrace(mrb, o)];
                    NSString *message = (NSString *)[self mrb:mrb mrb2objc:mrb_funcall(mrb, o, "message", 0)];
                    NSString *className = (NSString *)[self mrb:mrb mrb2objc:mrb_funcall(mrb, mrb_funcall(mrb, o, "class", 0), "to_s", 0)];
                    
                    NSDictionary *userInfo = @{
                                               @"className": className,
                                               @"message": message,
                                               @"backtrace": backtrace,
                                               };
                    ret = [NSException exceptionWithName:className reason:message userInfo:userInfo];
                } else {
                    // Unsupported class
                    NSLog(@"Unsupported class: %@", (NSString *)[self mrb:mrb mrb2objc:mrb_funcall(mrb, mrb_funcall(mrb, o, "class", 0), "to_s", 0)]);
                }
                break;
            }
            default:
                NSLog(@"Unsupported mrb_vtype: %d", mrb_type(o));
                break;
        }
        
        if (!ret) {
            // force convert string
            //ret = (NSString *)[self mrb:mrb mrb2objc:mrb_funcall(mrb, o, "inspect", 0)];
        }
    }
    
    if (!ret && useNSNull) {
        ret = [NSNull null];
    }
    return ret;
}

@end


#pragma mark objc_bridge_proc

void mrb_init_objc_bridge_proc(mrb_state *mrb)
{
    struct RClass *objcBridgeProcClass = mrb_define_class(mrb, "ObjcBridgeProc", mrb_class_get(mrb, "Proc"));
    
    mrb_define_method(mrb, objcBridgeProcClass, "initialize", mrb_objc_bridge_proc_initialize, MRB_ARGS_NONE());
    mrb_define_method(mrb, objcBridgeProcClass, "call", mrb_objc_bridge_proc_call, MRB_ARGS_ANY());
}

mrb_value mrb_objc_bridge_proc_initialize(mrb_state *mrb, mrb_value self)
{
    return self;
}

mrb_value mrb_objc_bridge_proc_call(mrb_state *mrb, mrb_value self)
{
    mrb_value argv;
    MRubyBlockInfo *info = [MRubyBlockInfo get];
    
    if (info.block) {
        // args
        mrb_get_args(mrb, "o", &argv);
        MRubyValue *args = [[MRubyValue alloc] initWithValue:argv withMRuby:info.mruby];
        
        // yield
        NSObject *ret = info.block(args);
        return [MRubyUtil mrb:mrb objc2mrb:ret];
    }
    return mrb_nil_value();
}

