#import "TouchPlayer.h"
#include <objc/runtime.h>
#include <CoreFoundation/CoreFoundation.h>

@interface TouchPlayer ()

@property (nonatomic, assign) BOOL isPlaying;
@property (nonatomic, assign) BOOL isPaused;
@property (nonatomic, strong) NSArray<TouchEvent *> *events;
@property (nonatomic, assign) NSUInteger currentIndex;
@property (nonatomic, assign) BOOL infiniteLoop;
@property (nonatomic, strong) dispatch_queue_t playbackQueue;
@property (nonatomic, strong) dispatch_source_t timerSource;
@property (nonatomic, assign) NSTimeInterval startTime;
@property (nonatomic, assign) uint64_t lastTouchId;

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
        _lastTouchId = (uint64_t)arc4random();
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
    
    [self injectTouchAtLocation:location withType:event.type];
}

- (void)injectTouchAtLocation:(CGPoint)location withType:(TouchEventType)type {
    UIWindow *keyWindow = [self getKeyWindow];
    if (!keyWindow) {
        NSLog(@"[TouchPlayer] No key window found");
        return;
    }
    
    CGSize screenSize = keyWindow.screen.bounds.size;
    
    // 尝试多种注入方式
    BOOL success = NO;
    
    // 方法1: 使用 UIApplication 的私有方法
    success = [self simulateTouchWithUIApplication:location type:type];
    
    if (!success) {
        // 方法2: 使用系统事件注入
        success = [self simulateTouchWithSystemEvent:location type:type];
    }
    
    if (!success) {
        // 方法3: 使用视图层级直接触发
        success = [self simulateTouchWithHitTest:location type:type];
    }
    
    if (!success) {
        NSLog(@"[TouchPlayer] All injection methods failed for location (%f, %f)", location.x, location.y);
    }
}

- (BOOL)simulateTouchWithUIApplication:(CGPoint)location type:(TouchEventType)type {
    @try {
        UIApplication *app = [UIApplication sharedApplication];
        
        // 尝试使用 _sendTouchesForEvent: 方法
        SEL sendTouchesSel = NSSelectorFromString(@"_sendTouchesForEvent:");
        if (![app respondsToSelector:sendTouchesSel]) {
            NSLog(@"[TouchPlayer] _sendTouchesForEvent: not available");
            return NO;
        }
        
        // 创建触摸事件
        UIEvent *event = [self createSystemEventWithLocation:location type:type];
        if (!event) {
            NSLog(@"[TouchPlayer] Failed to create system event");
            return NO;
        }
        
        NSMethodSignature *sig = [app methodSignatureForSelector:sendTouchesSel];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
        [invocation setSelector:sendTouchesSel];
        [invocation setTarget:app];
        [invocation setArgument:&event atIndex:2];
        [invocation invoke];
        
        return YES;
    }
    @catch (NSException *e) {
        NSLog(@"[TouchPlayer] simulateTouchWithUIApplication failed: %@", e);
        return NO;
    }
}

- (BOOL)simulateTouchWithSystemEvent:(CGPoint)location type:(TouchEventType)type {
    @try {
        UIApplication *app = [UIApplication sharedApplication];
        
        // 尝试使用 _postEvent: 方法
        SEL postEventSel = NSSelectorFromString(@"_postEvent:");
        if (![app respondsToSelector:postEventSel]) {
            NSLog(@"[TouchPlayer] _postEvent: not available");
            return NO;
        }
        
        UIEvent *event = [self createSystemEventWithLocation:location type:type];
        if (!event) {
            NSLog(@"[TouchPlayer] Failed to create system event");
            return NO;
        }
        
        NSMethodSignature *sig = [app methodSignatureForSelector:postEventSel];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
        [invocation setSelector:postEventSel];
        [invocation setTarget:app];
        [invocation setArgument:&event atIndex:2];
        [invocation invoke];
        
        return YES;
    }
    @catch (NSException *e) {
        NSLog(@"[TouchPlayer] simulateTouchWithSystemEvent failed: %@", e);
        return NO;
    }
}

- (BOOL)simulateTouchWithHitTest:(CGPoint)location type:(TouchEventType)type {
    @try {
        UIWindow *window = [self getKeyWindow];
        if (!window) {
            NSLog(@"[TouchPlayer] No window for hit test");
            return NO;
        }
        
        // 使用 hitTest 找到目标视图
        UIView *hitView = [window hitTest:location withEvent:nil];
        if (!hitView) {
            NSLog(@"[TouchPlayer] No view found at location");
            return NO;
        }
        
        NSLog(@"[TouchPlayer] Hit view: %@", hitView);
        
        // 尝试直接调用按钮方法
        if ([hitView respondsToSelector:@selector(sendActionsForControlEvents:)]) {
            [hitView sendActionsForControlEvents:UIControlEventTouchUpInside];
            return YES;
        }
        
        // 尝试发送点击事件
        SEL tapSel = NSSelectorFromString(@"touchesEnded:withEvent:");
        if ([hitView respondsToSelector:tapSel]) {
            NSSet *touches = [NSSet set];
            UIEvent *event = [[UIEvent alloc] init];
            [hitView performSelector:tapSel withObject:touches withObject:event];
            return YES;
        }
        
        return NO;
    }
    @catch (NSException *e) {
        NSLog(@"[TouchPlayer] simulateTouchWithHitTest failed: %@", e);
        return NO;
    }
}

- (UIEvent *)createSystemEventWithLocation:(CGPoint)location type:(TouchEventType)type {
    // 获取 UITouch 类
    Class UITouchClass = NSClassFromString(@"UITouch");
    Class UIEventClass = NSClassFromString(@"UIEvent");
    
    if (!UITouchClass || !UIEventClass) {
        NSLog(@"[TouchPlayer] UITouch or UIEvent class not found");
        return nil;
    }
    
    // 使用 NSInvocation 创建 UITouch
    SEL touchInitSel = NSSelectorFromString(@"_initWithView:location:");
    if (![UITouchClass instancesRespondToSelector:touchInitSel]) {
        touchInitSel = NSSelectorFromString(@"init");
    }
    
    UITouch *touch = [[UITouchClass alloc] performSelector:touchInitSel];
    if (!touch) {
        NSLog(@"[TouchPlayer] Failed to create UITouch");
        return nil;
    }
    
    // 设置触摸属性
    SEL setLocationSel = NSSelectorFromString(@"_setLocationInWindow:");
    if ([touch respondsToSelector:setLocationSel]) {
        [touch performSelector:setLocationSel withObject:[NSValue valueWithCGPoint:location]];
    }
    
    SEL setPhaseSel = NSSelectorFromString(@"_setPhase:");
    if ([touch respondsToSelector:setPhaseSel]) {
        UITouchPhase phase = UITouchPhaseBegan;
        if (type == TouchEventTypeMoved) phase = UITouchPhaseMoved;
        else if (type == TouchEventTypeEnded) phase = UITouchPhaseEnded;
        else if (type == TouchEventTypeCancelled) phase = UITouchPhaseCancelled;
        [touch performSelector:setPhaseSel withObject:@(phase)];
    }
    
    SEL setWindowSel = NSSelectorFromString(@"_setWindow:");
    if ([touch respondsToSelector:setWindowSel]) {
        [touch performSelector:setWindowSel withObject:[self getKeyWindow]];
    }
    
    SEL setTapCountSel = NSSelectorFromString(@"setTapCount:");
    if ([touch respondsToSelector:setTapCountSel]) {
        [touch performSelector:setTapCountSel withObject:@1];
    }
    
    // 创建 UIEvent
    UIEvent *event = [[UIEventClass alloc] init];
    
    SEL setTouchesSel = NSSelectorFromString(@"_setTouches:");
    if ([event respondsToSelector:setTouchesSel]) {
        [event performSelector:setTouchesSel withObject:[NSSet setWithObject:touch]];
    }
    
    SEL setTypeSel = NSSelectorFromString(@"_setType:");
    if ([event respondsToSelector:setTypeSel]) {
        [event performSelector:setTypeSel withObject:@(UIEventTypeTouches)];
    }
    
    return event;
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

- (void)dealloc {
    [self stop];
}

@end
