#import "TouchPlayer.h"
#include <objc/runtime.h>

@interface TouchPlayer ()

@property (nonatomic, assign) BOOL isPlaying;
@property (nonatomic, assign) BOOL isPaused;
@property (nonatomic, strong) NSArray<TouchEvent *> *events;
@property (nonatomic, assign) NSUInteger currentIndex;
@property (nonatomic, assign, readwrite) NSUInteger loopCount;
@property (nonatomic, assign, readwrite) NSUInteger currentLoop;
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
    if (_isPlaying || !_events || _events.count == 0) return;
    
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
        
        [strongSelf injectTouchEvent:event];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (strongSelf->_progressBlock) {
                strongSelf->_progressBlock(strongSelf->_currentIndex, strongSelf->_events.count);
            }
        });
        
        strongSelf->_currentIndex++;
        [strongSelf executeNextEvent];
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
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self simulateTouchAtLocation:location withType:event.type];
    });
}

- (void)simulateTouchAtLocation:(CGPoint)location withType:(TouchEventType)type {
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) return;
    
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

- (void)injectPrivateTouchAtLocation:(CGPoint)location phase:(UITouchPhase)phase window:(UIWindow *)window {
    Class UITouchClass = objc_getClass("UITouch");
    Class UIEventClass = objc_getClass("UIEvent");
    
    if (!UITouchClass || !UIEventClass) return;
    
    UITouch *touch = [UITouchClass alloc];
    if (!touch) return;
    
    SEL initSel = NSSelectorFromString(@"_initWithView:location:");
    if ([touch respondsToSelector:initSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        touch = [touch performSelector:initSel withObject:window withObject:[NSValue valueWithCGPoint:location]];
#pragma clang diagnostic pop
    } else {
        touch = [touch init];
    }
    
    SEL setPhaseSel = NSSelectorFromString(@"setPhase:");
    if ([touch respondsToSelector:setPhaseSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [touch performSelector:setPhaseSel withObject:@(phase)];
#pragma clang diagnostic pop
    }
    
    SEL setLocationInWindowSel = NSSelectorFromString(@"_setLocationInWindow:");
    if ([touch respondsToSelector:setLocationInWindowSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [touch performSelector:setLocationInWindowSel withObject:[NSValue valueWithCGPoint:location]];
#pragma clang diagnostic pop
    }
    
    SEL setWindowSel = NSSelectorFromString(@"setWindow:");
    if ([touch respondsToSelector:setWindowSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [touch performSelector:setWindowSel withObject:window];
#pragma clang diagnostic pop
    }
    
    UIEvent *event = [UIEventClass alloc];
    SEL eventInitSel = NSSelectorFromString(@"_initWithEventSubtype:timestamp:");
    if ([event respondsToSelector:eventInitSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        event = [event performSelector:eventInitSel withObject:@(UIEventSubtypeNone) withObject:@([[NSDate date] timeIntervalSince1970])];
#pragma clang diagnostic pop
    } else {
        event = [event init];
    }
    
    SEL setTouchesSel = NSSelectorFromString(@"_setTouches:");
    if ([event respondsToSelector:setTouchesSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [event performSelector:setTouchesSel withObject:@[touch]];
#pragma clang diagnostic pop
    }
    
    SEL setWindowSel2 = NSSelectorFromString(@"_setWindow:");
    if ([event respondsToSelector:setWindowSel2]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [event performSelector:setWindowSel2 withObject:window];
#pragma clang diagnostic pop
    }
    
    SEL sendEventSel = @selector(sendEvent:);
    if ([window respondsToSelector:sendEventSel]) {
        [window sendEvent:event];
    }
}

- (void)dealloc {
    [self stop];
}

@end