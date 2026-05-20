#import "TouchInjectManager.h"
#import <objc/runtime.h>

@interface TouchInjectManager ()

@property (nonatomic, strong) UITouch *currentTouch;
@property (nonatomic, strong) UIEvent *currentEvent;
@property (nonatomic, strong) UIWindow *keyWindow;

@end

@implementation TouchInjectManager

+ (instancetype)sharedInstance {
    static TouchInjectManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[TouchInjectManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _keyWindow = [self getKeyWindow];
    }
    return self;
}

- (UIWindow *)getKeyWindow {
    UIWindow *keyWindow = nil;
    
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                keyWindow = scene.windows.firstObject;
                break;
            }
        }
    }
    
    if (!keyWindow) {
        keyWindow = [UIApplication sharedApplication].keyWindow;
    }
    
    if (!keyWindow) {
        keyWindow = [UIApplication sharedApplication].windows.firstObject;
    }
    
    return keyWindow;
}

- (UITouch *)createTouchAtPoint:(CGPoint)point phase:(UITouchPhase)phase {
    Class UITouchClass = NSClassFromString(@"UITouch");
    if (!UITouchClass) {
        NSLog(@"[TouchInjectManager] Failed to get UITouch class");
        return nil;
    }
    
    UITouch *touch = [[UITouchClass alloc] init];
    if (!touch) {
        NSLog(@"[TouchInjectManager] Failed to create UITouch");
        return nil;
    }
    
    // 设置 phase
    [self setValue:@(phase) forKey:@"_phase" onObject:touch];
    
    // 设置 timestamp
    NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];
    [self setValue:@(timestamp) forKey:@"_timestamp" onObject:touch];
    
    // 设置 tapCount
    [self setValue:@(1) forKey:@"_tapCount" onObject:touch];
    
    // 设置 locationInWindow
    [self setValue:[NSValue valueWithCGPoint:point] forKey:@"_locationInWindow" onObject:touch];
    [self setValue:[NSValue valueWithCGPoint:point] forKey:@"_previousLocationInWindow" onObject:touch];
    
    // 设置 window
    [self setValue:_keyWindow forKey:@"_window" onObject:touch];
    
    // 设置 view（通过 hitTest 获取）
    UIView *hitView = [_keyWindow hitTest:point withEvent:nil];
    if (hitView) {
        [self setValue:hitView forKey:@"_view" onObject:touch];
    }
    
    return touch;
}

- (UIEvent *)createEventWithTouch:(UITouch *)touch {
    Class UIEventClass = NSClassFromString(@"UIEvent");
    if (!UIEventClass) {
        NSLog(@"[TouchInjectManager] Failed to get UIEvent class");
        return nil;
    }
    
    UIEvent *event = [[UIEventClass alloc] init];
    if (!event) {
        NSLog(@"[TouchInjectManager] Failed to create UIEvent");
        return nil;
    }
    
    // 设置 type
    [self setValue:@(UIEventTypeTouches) forKey:@"_type" onObject:event];
    
    // 设置 subtype
    [self setValue:@(UIEventSubtypeNone) forKey:@"_subtype" onObject:event];
    
    // 设置 timestamp
    NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];
    [self setValue:@(timestamp) forKey:@"_timestamp" onObject:event];
    
    // 设置 touches
    NSSet *touches = touch ? [NSSet setWithObject:touch] : [NSSet set];
    [self setValue:touches forKey:@"_touches" onObject:event];
    
    // 设置 window
    [self setValue:_keyWindow forKey:@"_window" onObject:event];
    
    return event;
}

- (void)sendEvent:(UIEvent *)event {
    if (!event) {
        NSLog(@"[TouchInjectManager] Cannot send nil event");
        return;
    }
    
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) {
        NSLog(@"[TouchInjectManager] Failed to get sharedApplication");
        return;
    }
    
    // 调用 UIApplication 的 sendEvent: 方法
    SEL sendEventSel = @selector(sendEvent:);
    if ([app respondsToSelector:sendEventSel]) {
        NSMethodSignature *signature = [app methodSignatureForSelector:sendEventSel];
        if (signature) {
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setSelector:sendEventSel];
            [invocation setTarget:app];
            void *eventPtr = (__bridge void *)event;
            [invocation setArgument:&eventPtr atIndex:2];
            [invocation invoke];
            NSLog(@"[TouchInjectManager] Sent event to UIApplication");
        }
    }
}

- (void)setValue:(id)value forKey:(NSString *)key onObject:(id)object {
    if (!object || !key) return;
    
    SEL setter = NSSelectorFromString([NSString stringWithFormat:@"set%@:", [key substringFromIndex:1]]);
    if ([object respondsToSelector:setter]) {
        NSMethodSignature *signature = [object methodSignatureForSelector:setter];
        if (signature) {
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setSelector:setter];
            [invocation setTarget:object];
            if (value) {
                [invocation setArgument:&value atIndex:2];
            }
            [invocation invoke];
        }
    } else {
        // 尝试使用 KVC
        @try {
            [object setValue:value forKey:key];
        } @catch (NSException *exception) {
            NSLog(@"[TouchInjectManager] Failed to set value for key %@: %@", key, exception);
        }
    }
}

- (void)tapAtPoint:(CGPoint)point {
    NSLog(@"[TouchInjectManager] tapAtPoint: (%.2f, %.2f)", point.x, point.y);
    
    // 触发 touch down
    [self touchDown:point];
    
    // 短暂延迟
    [NSThread sleepForTimeInterval:0.05];
    
    // 触发 touch up
    [self touchUp:point];
}

- (void)longPressAtPoint:(CGPoint)point duration:(NSTimeInterval)duration {
    NSLog(@"[TouchInjectManager] longPressAtPoint: (%.2f, %.2f) duration: %.2f", point.x, point.y, duration);
    
    // 触发 touch down
    [self touchDown:point];
    
    // 持续时间
    [NSThread sleepForTimeInterval:duration];
    
    // 触发 touch up
    [self touchUp:point];
}

- (void)swipeFrom:(CGPoint)startPoint to:(CGPoint)endPoint duration:(NSTimeInterval)duration {
    NSLog(@"[TouchInjectManager] swipeFrom: (%.2f, %.2f) to: (%.2f, %.2f) duration: %.2f", 
          startPoint.x, startPoint.y, endPoint.x, endPoint.y, duration);
    
    // 触发 touch down
    [self touchDown:startPoint];
    
    // 计算移动步数
    const NSInteger steps = 20;
    const NSTimeInterval stepDuration = duration / steps;
    
    // 触发 touch move
    for (NSInteger i = 1; i <= steps; i++) {
        CGFloat progress = (CGFloat)i / steps;
        CGPoint currentPoint = CGPointMake(
            startPoint.x + (endPoint.x - startPoint.x) * progress,
            startPoint.y + (endPoint.y - startPoint.y) * progress
        );
        [self touchMove:currentPoint];
        [NSThread sleepForTimeInterval:stepDuration];
    }
    
    // 触发 touch up
    [self touchUp:endPoint];
}

- (void)touchDown:(CGPoint)point {
    NSLog(@"[TouchInjectManager] touchDown: (%.2f, %.2f)", point.x, point.y);
    
    _currentTouch = [self createTouchAtPoint:point phase:UITouchPhaseBegan];
    _currentEvent = [self createEventWithTouch:_currentTouch];
    
    if (_currentEvent) {
        [self sendEvent:_currentEvent];
    }
}

- (void)touchMove:(CGPoint)point {
    NSLog(@"[TouchInjectManager] touchMove: (%.2f, %.2f)", point.x, point.y);
    
    if (!_currentTouch) {
        NSLog(@"[TouchInjectManager] No current touch, creating new one");
        _currentTouch = [self createTouchAtPoint:point phase:UITouchPhaseMoved];
    } else {
        // 更新现有 touch 的 phase 和 location
        [self setValue:@(UITouchPhaseMoved) forKey:@"_phase" onObject:_currentTouch];
        [self setValue:[NSValue valueWithCGPoint:point] forKey:@"_previousLocationInWindow" onObject:_currentTouch];
        [self setValue:[NSValue valueWithCGPoint:point] forKey:@"_locationInWindow" onObject:_currentTouch];
        
        // 更新 timestamp
        NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];
        [self setValue:@(timestamp) forKey:@"_timestamp" onObject:_currentTouch];
    }
    
    _currentEvent = [self createEventWithTouch:_currentTouch];
    
    if (_currentEvent) {
        [self sendEvent:_currentEvent];
    }
}

- (void)touchUp:(CGPoint)point {
    NSLog(@"[TouchInjectManager] touchUp: (%.2f, %.2f)", point.x, point.y);
    
    if (!_currentTouch) {
        NSLog(@"[TouchInjectManager] No current touch, creating new one");
        _currentTouch = [self createTouchAtPoint:point phase:UITouchPhaseEnded];
    } else {
        // 更新现有 touch 的 phase 和 location
        [self setValue:@(UITouchPhaseEnded) forKey:@"_phase" onObject:_currentTouch];
        [self setValue:[NSValue valueWithCGPoint:point] forKey:@"_previousLocationInWindow" onObject:_currentTouch];
        [self setValue:[NSValue valueWithCGPoint:point] forKey:@"_locationInWindow" onObject:_currentTouch];
        
        // 更新 timestamp
        NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];
        [self setValue:@(timestamp) forKey:@"_timestamp" onObject:_currentTouch];
    }
    
    _currentEvent = [self createEventWithTouch:_currentTouch];
    
    if (_currentEvent) {
        [self sendEvent:_currentEvent];
    }
    
    // 清理
    _currentTouch = nil;
    _currentEvent = nil;
}

@end
