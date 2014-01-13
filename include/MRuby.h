//
//  MRuby.h
//  MRuby
//
//  Created by yoshida on 2014/01/07.
//  Copyright (c) 2014年 yoshida. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MRubyValue.h"
#import "MRubyUtil.h"

@interface MRuby : NSObject {
    mrb_state *mrb;
    NSString *filename;
    NSMutableArray *loadPath;
}

// exec
- (void)setArgv:(NSArray *)argv;
- (MRubyValue *)require:(NSString *)filePath;
- (MRubyValue *)exec:(NSString *)filePath withArgs:(NSArray *)args;

// eval
- (MRubyValue *)eval:(NSString *)code;

// convert
- (MRubyValue *)value:(NSObject *)object;

@property (nonatomic, assign, readonly) mrb_state *mrb;
@property (nonatomic, copy, readwrite) NSString *filename;
@property (nonatomic, strong, readonly) NSMutableArray *loadPath;

+ (id)mruby;

@end
