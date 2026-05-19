#import "TouchPlayer.h"
#include <objc/runtime.h>

@interface TouchPlayer ()

@property (nonatomic, assign) BOOL isPlaying;
@property (nonatomic, assign) BOOL isPaused;
@property (nonatomic, strong) NSArray<TouchEvent *> *events;
@property (nonatomic, assign) NSUInteger currentIndex;
@property (nonatomic, assign) BOOL infiniteLoop;
@property (nonatomic, strong) dispatch_queue_t playbackQueue;
@property (nonatomic, strong) dispatch_source_t timerSource;
@property (nonatomic, assign) NSTimeInterval startTime;

@end

@implementation TouchPlayer

+ (instancetype)sharedInstance {
    static TouchPlayer *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[TouchPlayer alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _playbackQueue = dispatch_queue_create("com.touchauto.playback", DISPATCH_QUEUE_SERIAL);
        _loopCount = 1;
        _currentLoop = 0;
        _playbackSpeed = 1.0;
        _randomOffset = 0.0;
        _randomDelayRange = 0.0;
        _infiniteLoop = NO;
        _isPlaying = NO;
        _isPaused = NO;
        _waitTimeAfterFinish = 0.0;
    }
    return self;
}

- (void)setEvents:(NSArray<TouchEvent *> *)events {
    [self stop];
    _events = events;
    _currentIndex = 0;
    _currentLoop = 0;
}

- (void)setLoopCount:(NSUInteger)count {
    _loopCount = count;
    _infiniteLoop = (count == 0);
}

- (void)setInfiniteLoop:(BOOL)infinite {
    _infiniteLoop = infinite;
    _loopCount = infinite ? 0 : 1;
}

- (void)play {
    if (_isPlaying) {
        NSLog(@"[TouchPlayer] Already playing");
        return;
    }
    if (!_events || _events.count == 0) {
        NSLog(@"[TouchPlayer] No events to play");
        return;
    }
    
    NSLog(@"[TouchPlayer] Starting playback with %lu events", (unsigned long)_events.count);
    _isPlaying = YES;
    _isPaused = NO;
    _startTime = [[NSDate date] timeIntervalSince1970];
    
    if (_stateChangeBlock) {
        _stateChangeBlock(YES);
    }
    
    [self executeNextEvent];
}

- (void)pause {
    if (!_isPlaying || _isPaused) return;
    
    _isPaused = YES;
    
    if (_timerSource) {
        dispatch_source_cancel(_timerSource);
        _timerSource = nil;
    }
    
    if (_stateChangeBlock) {
        _stateChangeBlock(NO);
    }
}

- (void)stop {
    _isPlaying = NO;
    _isPaused = NO;
    _currentIndex = 0;
    _currentLoop = 0;
    
    if (_timerSource) {
        dispatch_source_cancel(_timerSource);
        _timerSource = nil;
    }
    
    if (_stateChangeBlock) {
        _stateChangeBlock(NO);
    }
    
    if (_completeBlock) {
        _completeBlock();
    }
}

- (void)executeNextEvent {
    if (!_isPlaying || _isPaused) return;
    
    if (_currentIndex >= _events.count) {
        _currentLoop++;
        
        if (_infiniteLoop || _currentLoop < _loopCount) {
            // 播放完成后等待
            if (_waitTimeAfterFinish > 0) {
                NSLog(@"[TouchPlayer] Waiting %f seconds before next loop...", _waitTimeAfterFinish);
                __weak __typeof(self) weakSelf = self;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_waitTimeAfterFinish * NSEC_PER_SEC)), _playbackQueue, ^{
                    __strong __typeof(weakSelf) strongSelf = weakSelf;
                    if (!strongSelf || !strongSelf->_isPlaying || strongSelf->_isPaused) return;
                    strongSelf->_currentIndex = 0;
                    [strongSelf executeNextEvent];
                });
                return;
            }
            _currentIndex = 0;
        } else {
            [self stop];
            return;
        }
    }
    
    TouchEvent *event = _events[_currentIndex];
    
    NSTimeInterval adjustedDelay = event.delay / _playbackSpeed;
    
    if (_randomDelayRange > 0) {
        CGFloat randomFactor = (CGFloat)arc4random_uniform(1000) / 1000.0;
        adjustedDelay += (_randomDelayRange * (randomFactor - 0.5) * 2);
    }
    
    adjustedDelay = MAX(0.001, adjustedDelay);
    
    __weak __typeof(self) weakSelf = self;
    _timerSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _playbackQueue);
    dispatch_source_set_timer(_timerSource, dispatch_time(DISPATCH_TIME_NOW, adjustedDelay * NSEC_PER_SEC), DISPATCH_TIME_FOREVER, 0);
    dispatch_source_set_event_handler(_timerSource, ^{
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf->_isPlaying || strongSelf->_isPaused) return;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!strongSelf->_isPlaying || strongSelf->_isPaused) return;
            
            [strongSelf injectTouchEvent:event];
            
            if (strongSelf->_progressBlock) {
                strongSelf->_progressBlock(strongSelf->_currentIndex, strongSelf->_events.count);
            }
            
            strongSelf->_currentIndex++;
            [strongSelf executeNextEvent];
        });
    });
    dispatch_resume(_timerSource);
}

- (void)injectTouchEvent:(TouchEvent *)event {
    CGPoint location = event.location;
    
    if (_randomOffset > 0) {
        CGFloat offsetX = ((CGFloat)arc4random_uniform(1000) / 1000.0 - 0.5) * _randomOffset * 2;
        CGFloat offsetY = ((CGFloat)arc4random_uniform(1000) / 1000.0 - 0.5) * _randomOffset * 2;
        location.x += offsetX;
        location.y += offsetY;
    }
    
    NSLog(@"[TouchPlayer] Injecting event at (%f, %f), type: %ld", location.x, location.y, (long)event.type);
    
    [self simulateTouchAtLocation:location withType:event.type];
}

- (void)simulateTouchAtLocation:(CGPoint)location withType:(TouchEventType)type {
    UIWindow *keyWindow = [self getKeyWindow];
    if (!keyWindow) {
        NSLog(@"[TouchPlayer] No key window found");
        return;
    }
    
    NSLog(@"[TouchPlayer] Using window: %@, location: (%f, %f)", keyWindow, location.x, location.y);
    
    UITouchPhase phase;
    switch (type) {
        case TouchEventTypeBegan:
            phase = UITouchPhaseBegan;
            break;
        case TouchEventTypeMoved:
            phase = UITouchPhaseMoved;
            break;
        case TouchEventTypeEnded:
            phase = UITouchPhaseEnded;
            break;
        case TouchEventTypeCancelled:
            phase = UITouchPhaseCancelled;
            break;
        default:
            phase = UITouchPhaseBegan;
    }
    
    [self injectPrivateTouchAtLocation:location phase:phase window:keyWindow];
}

- (UIWindow *)getKeyWindow {
    UIWindow *keyWindow = nil;
    
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *scenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in scenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *window in windowScene.windows) {
                    if (window.isKeyWindow) {
                        keyWindow = window;
                        break;
                    }
                }
                if (keyWindow) break;
            }
        }
    }
    
    if (!keyWindow) {
        keyWindow = [UIApplication sharedApplication].keyWindow;
    }
    
    return keyWindow;
}

- (void)injectPrivateTouchAtLocation:(CGPoint)location phase:(UITouchPhase)phase window:(UIWindow *)window {
    NSLog(@"[TouchPlayer] Injecting touch at (%f, %f), phase: %ld, window: %@", 
          location.x, location.y, (long)phase, window);
    
    // 方法1：直接在进程内调用 window 的 sendEvent
    [self tryDirectSendEvent:location phase:phase window:window];
}

- (void)tryDirectSendEvent:(CGPoint)location phase:(UITouchPhase)phase window:(UIWindow *)window {
    NSLog(@"[TouchPlayer] Method 1: Direct sendEvent");
    
    // 创建 UITouch
    UITouch *touch = [[UITouch alloc] init];
    
    // 使用私有API设置触摸属性
    SEL setPhaseSel = NSSelectorFromString(@"setPhase:");
    if ([touch respondsToSelector:setPhaseSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [touch performSelector:setPhaseSel withObject:@(phase)];
#pragma clang diagnostic pop
    }
    
    SEL setWindowSel = NSSelectorFromString(@"setWindow:");
    if ([touch respondsToSelector:setWindowSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [touch performSelector:setWindowSel withObject:window];
#pragma clang diagnostic pop
    }
    
    SEL setTapCountSel = NSSelectorFromString(@"setTapCount:");
    if ([touch respondsToSelector:setTapCountSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [touch performSelector:setTapCountSel withObject:@1];
#pragma clang diagnostic pop
    }
    
    // 设置触摸位置
    SEL setLocationSel = NSSelectorFromString(@"_setLocationInWindow:");
    if ([touch respondsToSelector:setLocationSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [touch performSelector:setLocationSel withObject:[NSValue valueWithCGPoint:location]];
#pragma clang diagnostic pop
    }
    
    // 创建 UIEvent
    UIEvent *event = [[UIEvent alloc] init];
    SEL setWindowEventSel = NSSelectorFromString(@"setWindow:");
    if ([event respondsToSelector:setWindowEventSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [event performSelector:setWindowEventSel withObject:window];
#pragma clang diagnostic pop
    }
    
    // 获取window的sendEvent方法并直接调用
    SEL sendEventSel = @selector(sendEvent:);
    if ([window respondsToSelector:sendEventSel]) {
        NSMethodSignature *sig = [window methodSignatureForSelector:sendEventSel];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
        [invocation setSelector:sendEventSel];
        [invocation setTarget:window];
        [invocation setArgument:&event atIndex:2];
        [invocation invoke];
        
        NSLog(@"[TouchPlayer] Direct sendEvent succeeded");
        return;
    }
    
    // 备用方法：尝试调用内部方法
    [self tryInternalTouchInjection:location phase:phase window:window];
}

- (void)tryInternalTouchInjection:(CGPoint)location phase:(UITouchPhase)phase window:(UIWindow *)window {
    NSLog(@"[TouchPlayer] Method 2: Internal touch injection");
    
    // 查找点击位置下的视图
    UIView *hitView = [window hitTest:location withEvent:nil];
    if (!hitView) {
        NSLog(@"[TouchPlayer] No view found at location");
        return;
    }
    
    NSLog(@"[TouchPlayer] Hit view: %@", hitView);
    
    // 创建触摸对象
    UITouch *touch = [[UITouch alloc] init];
    
    // 使用私有API设置触摸属性
    SEL setPhaseSel = NSSelectorFromString(@"setPhase:");
    if ([touch respondsToSelector:setPhaseSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [touch performSelector:setPhaseSel withObject:@(phase)];
#pragma clang diagnostic pop
    }
    
    SEL setWindowSel = NSSelectorFromString(@"setWindow:");
    if ([touch respondsToSelector:setWindowSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [touch performSelector:setWindowSel withObject:window];
#pragma clang diagnostic pop
    }
    
    SEL setTapCountSel = NSSelectorFromString(@"setTapCount:");
    if ([touch respondsToSelector:setTapCountSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [touch performSelector:setTapCountSel withObject:@1];
#pragma clang diagnostic pop
    }
    
    // 设置触摸位置
    SEL setLocationSel = NSSelectorFromString(@"_setLocationInWindow:");
    if ([touch respondsToSelector:setLocationSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [touch performSelector:setLocationSel withObject:[NSValue valueWithCGPoint:location]];
#pragma clang diagnostic pop
    }
    
    // 创建事件
    UIEvent *event = [[UIEvent alloc] init];
    SEL setWindowEventSel = NSSelectorFromString(@"setWindow:");
    if ([event respondsToSelector:setWindowEventSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [event performSelector:setWindowEventSel withObject:window];
#pragma clang diagnostic pop
    }
    
    // 使用 NSSet 而不是 NSArray
    NSSet *touches = [NSSet setWithObject:touch];
    
    if (phase == UITouchPhaseBegan) {
        if ([hitView respondsToSelector:@selector(touchesBegan:withEvent:)]) {
            [hitView touchesBegan:touches withEvent:event];
            NSLog(@"[TouchPlayer] Called touchesBegan:");
        }
    } else if (phase == UITouchPhaseMoved) {
        if ([hitView respondsToSelector:@selector(touchesMoved:withEvent:)]) {
            [hitView touchesMoved:touches withEvent:event];
            NSLog(@"[TouchPlayer] Called touchesMoved:");
        }
    } else if (phase == UITouchPhaseEnded) {
        if ([hitView respondsToSelector:@selector(touchesEnded:withEvent:)]) {
            [hitView touchesEnded:touches withEvent:event];
            NSLog(@"[TouchPlayer] Called touchesEnded:");
        }
    } else if (phase == UITouchPhaseCancelled) {
        if ([hitView respondsToSelector:@selector(touchesCancelled:withEvent:)]) {
            [hitView touchesCancelled:touches withEvent:event];
            NSLog(@"[TouchPlayer] Called touchesCancelled:");
        }
    }
}

- (void)dealloc {
    [self stop];
}

@end
