#import "TouchPlayer.h"
#import "FloatingPanel.h"
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach/mach_time.h>
#import <mach/mach_time.h>
#import <objc/message.h>

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef uint32_t IOHIDDigitizerTransducerType;
#define kIOHIDDigitizerTransducerTypeHand 3

extern IOHIDEventRef IOHIDEventCreateDigitizerEvent(
    CFAllocatorRef allocator,
    AbsoluteTime timeStamp,
    IOHIDDigitizerTransducerType type,
    uint32_t index,
    uint32_t identity,
    uint32_t eventMask,
    uint32_t buttonMask,
    int32_t x,
    int32_t y,
    int32_t z,
    int32_t tipPressure,
    Boolean range,
    Boolean touch,
    CFOptionFlags options,
    uint64_t reserved
);

extern IOHIDEventRef IOHIDEventCreateDigitizerFingerEvent(
    CFAllocatorRef allocator,
    AbsoluteTime timeStamp,
    uint32_t index,
    uint32_t identity,
    uint32_t eventMask,
    CGFloat x,
    CGFloat y,
    CGFloat z,
    CGFloat tipPressure,
    CGFloat twist,
    Boolean range,
    Boolean touch,
    CFOptionFlags options
);

extern void IOHIDEventAppendEvent(IOHIDEventRef parent, IOHIDEventRef child, CFOptionFlags flags);

@interface UIEvent (Private)
- (void)_setHIDEvent:(IOHIDEventRef)event;
@end


static inline AbsoluteTime TAAbsoluteTimeNow(void) {
    uint64_t t = mach_absolute_time();
    AbsoluteTime at;
    at.hi = (uint32_t)(t >> 32);
    at.lo = (uint32_t)(t & 0xffffffff);
    return at;
}
@interface UIEvent (Private)
- (void)_setHIDEvent:(IOHIDEventRef)event;
@end

@interface TouchPlayer ()

@property (nonatomic, assign) BOOL isPlaying;
@property (nonatomic, assign) BOOL isPaused;
@property (nonatomic, strong) NSArray<TouchEvent *> *events;
@property (nonatomic, assign) NSUInteger currentIndex;
@property (nonatomic, assign) BOOL infiniteLoop;
@property (nonatomic, strong) dispatch_queue_t playbackQueue;
@property (nonatomic, strong) dispatch_source_t timerSource;
@property (nonatomic, assign) NSTimeInterval startTime;
@property (nonatomic, strong) NSMutableArray<NSString *> *playbackLogs;

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
        _playbackLogs = [NSMutableArray array];
    }
    return self;
}

- (void)clearLogs {
    [_playbackLogs removeAllObjects];
}

- (NSString *)getLogs {
    return [_playbackLogs componentsJoinedByString:@"\n"];
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
        NSLog(@"[TouchPlayer] 播放已在进行中");
        return;
    }
    if (!_events || _events.count == 0) {
        NSLog(@"[TouchPlayer] 没有可播放的事件");
        return;
    }
    
    // 播放时禁用 FloatingPanel 交互，防止拦截触摸事件
[FloatingPanel sharedInstance].userInteractionEnabled = NO;
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSString *startTimeStr = [formatter stringFromDate:[NSDate date]];
    
    // 收集日志
    [_playbackLogs removeAllObjects];
    [_playbackLogs addObject:@"════════════════════════════════════"];
    [_playbackLogs addObject:@"           TouchAuto 播放日志"];
    [_playbackLogs addObject:@"════════════════════════════════════"];
    [_playbackLogs addObject:[NSString stringWithFormat:@"开始时间: %@", startTimeStr]];
    [_playbackLogs addObject:[NSString stringWithFormat:@"事件数量: %lu 个", (unsigned long)_events.count]];
    [_playbackLogs addObject:[NSString stringWithFormat:@"循环次数: %@", _infiniteLoop ? @"无限" : [NSString stringWithFormat:@"%lu", (unsigned long)_loopCount]]];
    [_playbackLogs addObject:[NSString stringWithFormat:@"播放速度: %.1fx", _playbackSpeed]];
    if (_randomOffset > 0) {
        [_playbackLogs addObject:[NSString stringWithFormat:@"随机偏移: ±%.1f", _randomOffset]];
    }
    if (_randomDelayRange > 0) {
        [_playbackLogs addObject:[NSString stringWithFormat:@"随机延迟: ±%.2f秒", _randomDelayRange]];
    }
    if (_waitTimeAfterFinish > 0) {
        [_playbackLogs addObject:[NSString stringWithFormat:@"完成后等待: %.1f秒", _waitTimeAfterFinish]];
    }
    [_playbackLogs addObject:@"════════════════════════════════════"];
    [_playbackLogs addObject:@"           播放事件详情"];
    [_playbackLogs addObject:@"════════════════════════════════════"];
    
    NSLog(@"[TouchPlayer] ========== 开始播放 ==========");
    NSLog(@"[TouchPlayer] 开始时间: %@", startTimeStr);
    NSLog(@"[TouchPlayer] 事件数量: %lu", (unsigned long)_events.count);
    NSLog(@"[TouchPlayer] 循环次数: %@", _infiniteLoop ? @"无限" : [NSString stringWithFormat:@"%lu", (unsigned long)_loopCount]);
    NSLog(@"[TouchPlayer] 播放速度: %.1fx", _playbackSpeed);
    if (_randomOffset > 0) {
        NSLog(@"[TouchPlayer] 随机偏移: ±%.1f", _randomOffset);
    }
    if (_randomDelayRange > 0) {
        NSLog(@"[TouchPlayer] 随机延迟: ±%.2f秒", _randomDelayRange);
    }
    if (_waitTimeAfterFinish > 0) {
        NSLog(@"[TouchPlayer] 完成后等待: %.1f秒", _waitTimeAfterFinish);
    }
    NSLog(@"[TouchPlayer] ==============================");
    
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
    
    [_playbackLogs addObject:@"──────────── 暂停播放 ────────────"];
    [_playbackLogs addObject:[NSString stringWithFormat:@"已播放: %lu/%lu 事件", (unsigned long)_currentIndex, (unsigned long)_events.count]];
    
    NSLog(@"[TouchPlayer] ========== 暂停播放 ==========");
    NSLog(@"[TouchPlayer] 已播放: %lu/%lu 事件", (unsigned long)_currentIndex, (unsigned long)_events.count);
    
    _isPaused = YES;
    
    if (_timerSource) {
        dispatch_source_cancel(_timerSource);
        _timerSource = nil;
    }
    
    // 恢复 FloatingPanel 交互
    [self enablePanelInteraction];
    
    if (_stateChangeBlock) {
        _stateChangeBlock(NO);
    }
}

- (void)stop {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"HH:mm:ss"];
    NSString *stopTimeStr = [formatter stringFromDate:[NSDate date]];
    
    NSTimeInterval totalTime = [[NSDate date] timeIntervalSince1970] - _startTime;
    
    [_playbackLogs addObject:@"════════════════════════════════════"];
    [_playbackLogs addObject:@"           播放已停止"];
    [_playbackLogs addObject:@"════════════════════════════════════"];
    [_playbackLogs addObject:[NSString stringWithFormat:@"停止时间: %@", stopTimeStr]];
    [_playbackLogs addObject:[NSString stringWithFormat:@"已播放: %lu/%lu 事件", (unsigned long)_currentIndex, (unsigned long)_events.count]];
    [_playbackLogs addObject:[NSString stringWithFormat:@"已完成: %lu 轮", (unsigned long)_currentLoop]];
    [_playbackLogs addObject:[NSString stringWithFormat:@"已耗时: %.2f 秒", totalTime]];
    [_playbackLogs addObject:@"════════════════════════════════════"];
    
    NSLog(@"[TouchPlayer] ========== 停止播放 ==========");
    NSLog(@"[TouchPlayer] 停止时间: %@", stopTimeStr);
    NSLog(@"[TouchPlayer] 已播放: %lu/%lu 事件", (unsigned long)_currentIndex, (unsigned long)_events.count);
    NSLog(@"[TouchPlayer] 已完成: %lu 轮", (unsigned long)_currentLoop);
    NSLog(@"[TouchPlayer] 已耗时: %.2f 秒", totalTime);
    NSLog(@"[TouchPlayer] =============================");
    
    _isPlaying = NO;
    _isPaused = NO;
    _currentIndex = 0;
    _currentLoop = 0;
    
    if (_timerSource) {
        dispatch_source_cancel(_timerSource);
        _timerSource = nil;
    }
    
    // 恢复 FloatingPanel 交互
    [self enablePanelInteraction];
    
    if (_stateChangeBlock) {
        _stateChangeBlock(NO);
    }
    
    if (_completeBlock) {
        _completeBlock();
    }
}

- (void)enablePanelInteraction {
    [FloatingPanel sharedInstance].userInteractionEnabled = YES;
}

- (void)executeNextEvent {
    if (!_isPlaying || _isPaused) return;
    
    if (_currentIndex >= _events.count) {
        _currentLoop++;
        
        [_playbackLogs addObject:[NSString stringWithFormat:@"第 %lu 轮播放完成", (unsigned long)_currentLoop]];
        NSLog(@"[TouchPlayer] 第 %lu 轮播放完成", (unsigned long)_currentLoop);
        
        if (_infiniteLoop || _currentLoop < _loopCount) {
            if (_waitTimeAfterFinish > 0) {
                [_playbackLogs addObject:[NSString stringWithFormat:@"等待 %.1f 秒后开始第 %lu 轮...", _waitTimeAfterFinish, (unsigned long)(_currentLoop + 1)]];
                NSLog(@"[TouchPlayer] 等待 %.1f 秒后开始第 %lu 轮...", _waitTimeAfterFinish, (unsigned long)(_currentLoop + 1));
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
            NSTimeInterval totalTime = [[NSDate date] timeIntervalSince1970] - _startTime;
            
            [_playbackLogs addObject:@"════════════════════════════════════"];
            [_playbackLogs addObject:@"           播放全部完成"];
            [_playbackLogs addObject:@"════════════════════════════════════"];
            [_playbackLogs addObject:[NSString stringWithFormat:@"总播放轮数: %lu", (unsigned long)_currentLoop]];
            [_playbackLogs addObject:[NSString stringWithFormat:@"总事件数: %lu", (unsigned long)_events.count]];
            [_playbackLogs addObject:[NSString stringWithFormat:@"总耗时: %.2f 秒", totalTime]];
            [_playbackLogs addObject:@"════════════════════════════════════"];
            
            NSLog(@"[TouchPlayer] ========== 播放完成 ==========");
            NSLog(@"[TouchPlayer] 总播放轮数: %lu", (unsigned long)_currentLoop);
            NSLog(@"[TouchPlayer] 总事件数: %lu", (unsigned long)_events.count);
            NSLog(@"[TouchPlayer] 总耗时: %.2f 秒", totalTime);
            NSLog(@"[TouchPlayer] =============================");
            
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
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"HH:mm:ss.SSS"];
    NSString *currentTime = [formatter stringFromDate:[NSDate date]];
    
    // 修复要求1: 统一将所有事件视为点击结束事件处理
    NSString *eventTypeStr = @"回放(强制结束)";
    
    NSString *viewInfo = event.viewClass ?: @"未知视图";
    if (event.accessibilityIdentifier.length > 0) {
        viewInfo = [NSString stringWithFormat:@"%@ [id:%@]", viewInfo, event.accessibilityIdentifier];
    }
    
    NSString *logEntry = [NSString stringWithFormat:@"[%lu/%lu] %@ | %@ | (%.1f, %.1f) | %@",
                          (unsigned long)(_currentIndex + 1),
                          (unsigned long)_events.count,
                          currentTime,
                          eventTypeStr,
                          location.x, location.y,
                          viewInfo];
    [_playbackLogs addObject:logEntry];
    
    NSLog(@"[TouchPlayer] [事件 %lu/%lu] 时间:%@ 类型:%@ 坐标:(%.1f, %.1f) 视图:%@",
          (unsigned long)(_currentIndex + 1),
          (unsigned long)_events.count,
          currentTime,
          eventTypeStr,
          location.x, location.y,
          viewInfo);
    
    // 修复要求1: 强制使用 TouchEventTypeEnded
    [self triggerTouchAtLocation:location withType:TouchEventTypeEnded];
}

- (void)triggerTouchAtLocation:(CGPoint)location withType:(TouchEventType)type {
    UIWindow *window = [self getKeyWindow];
    if (!window) return;

    CGPoint p = [window convertPoint:location fromWindow:nil];

    BOOL isDown = (type != TouchEventTypeEnded);

    IOHIDEventRef parent = IOHIDEventCreateDigitizerEvent(
    kCFAllocatorDefault,
    TAAbsoluteTimeNow(),
    kIOHIDDigitizerTransducerTypeHand,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    isDown,
    isDown,
    NULL,
    0
);

    IOHIDEventRef child = IOHIDEventCreateDigitizerFingerEvent(
        kCFAllocatorDefault,
        mach_absolute_time(),
        1,
        2,
        0,
        p.x,
        p.y,
        0,
        0.4,
        0.4,
        isDown,
        isDown,
        0
    );

    IOHIDEventAppendEvent(parent, child,0);

    UIEvent *event = [[NSClassFromString(@"UITouchesEvent") alloc] init];
    SEL hidSel = NSSelectorFromString(@"_setHIDEvent:");
if ([event respondsToSelector:hidSel]) {
    ((void (*)(id, SEL, IOHIDEventRef))objc_msgSend)(event, hidSel, parent);
}

    [[UIApplication sharedApplication] sendEvent:event];

    CFRelease(child);
    CFRelease(parent);
}

- (UIView *)findInteractiveSuperview:(UIView *)view {
    // 如果当前视图是可交互的类型，直接返回
    if ([self isInteractiveView:view]) {
        return view;
    }
    
    // 向上查找父级
    UIView *superview = view.superview;
    while (superview) {
        if ([self isInteractiveView:superview]) {
            return superview;
        }
        superview = superview.superview;
    }
    
    // 找不到可交互的父级，返回原始视图
    return view;
}

- (BOOL)isInteractiveView:(UIView *)view {
    if (!view || view.hidden) {
        return NO;
    }
    
    // 先检查是否有 gesture recognizers（即使 userInteractionEnabled = NO，有 gesture 的视图也应该被视为可交互）
    if (view.gestureRecognizers && view.gestureRecognizers.count > 0) {
        return YES;
    }
    
    // 检查 userInteractionEnabled
    if (!view.userInteractionEnabled) {
        return NO;
    }
    
    // 检查是否是可交互的视图类型
    if ([view isKindOfClass:[UIButton class]]) return YES;
    if ([view isKindOfClass:[UIControl class]]) return YES;
    if ([view isKindOfClass:[UITableViewCell class]]) return YES;
    if ([view isKindOfClass:[UICollectionViewCell class]]) return YES;
    if ([view isKindOfClass:[UIScrollView class]]) return YES;
    if ([view isKindOfClass:[WKWebView class]]) return YES;
    
    return NO;
}

- (void)triggerActionForView:(UIView *)view atLocation:(CGPoint)location type:(TouchEventType)type {
    if (!view) return;
    
    NSLog(@"[TouchPlayer] triggerActionForView: %@ at (%.2f, %.2f)", 
          NSStringFromClass(view.class), location.x, location.y);
    
    // 修复要求4: 优先处理 gesture recognizer
    if ([self triggerGestureRecognizerAction:view atLocation:location]) {
        NSLog(@"[TouchPlayer] Triggered gesture recognizer action");
        return;
    }
    
    // 1. 尝试触发 UIButton
    if ([self triggerUIButtonAction:view]) {
        NSLog(@"[TouchPlayer] Triggered UIButton action");
        return;
    }
    
    // 2. 尝试触发 UIControl
    if ([self triggerUIControlAction:view]) {
        NSLog(@"[TouchPlayer] Triggered UIControl action");
        return;
    }
    
    // 3. 尝试触发 UITableView
    if ([self triggerUITableViewAction:view atLocation:location]) {
        NSLog(@"[TouchPlayer] Triggered UITableView action");
        return;
    }
    
    // 4. 尝试触发 UICollectionView
    if ([self triggerUICollectionViewAction:view atLocation:location]) {
        NSLog(@"[TouchPlayer] Triggered UICollectionView action");
        return;
    }
    
    // 5. 尝试触发 UIScrollView
    if ([self triggerUIScrollViewAction:view atLocation:location]) {
        NSLog(@"[TouchPlayer] Triggered UIScrollView action");
        return;
    }
    
    // 6. 尝试触发 WKWebView
    if ([self triggerWKWebViewAction:view atLocation:location]) {
        NSLog(@"[TouchPlayer] Triggered WKWebView action");
        return;
    }
    
    // 7. 如果是普通 UIView，尝试模拟点击
    if ([view isKindOfClass:[UIView class]] && 
        ![view isKindOfClass:[UIControl class]]) {
        NSLog(@"[TouchPlayer] Trying to simulate touch on plain UIView: %@", 
              NSStringFromClass(view.class));
        [self simulateTouchSequenceOnView:view];
        // 添加 return 防止继续递归
        return;
    }
    
    // 8. 尝试查找父级视图中的可交互控件（最多递归3层）
    static NSUInteger recursionDepth = 0;
    if (view.superview && recursionDepth < 3) {
        recursionDepth++;
        NSLog(@"[TouchPlayer] Moving to superview: %@ (depth: %lu)", 
              NSStringFromClass(view.superview.class), (unsigned long)recursionDepth);
        [self triggerActionForView:view.superview atLocation:location type:type];
        recursionDepth--;
    }
}

- (BOOL)triggerGestureRecognizerAction:(UIView *)view atLocation:(CGPoint)location {
    if (!view.gestureRecognizers || view.gestureRecognizers.count == 0) {
        return NO;
    }
    
    NSLog(@"[TouchPlayer] Found %lu gesture recognizers on %@", 
          (unsigned long)view.gestureRecognizers.count, NSStringFromClass(view.class));
    
    for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
        if (!gesture.enabled || gesture.state == UIGestureRecognizerStateCancelled) {
            continue;
        }
        
        NSLog(@"[TouchPlayer] Checking gesture: %@ state:%ld", 
              NSStringFromClass(gesture.class), (long)gesture.state);
        
        // 触发 tap gesture
        if ([gesture isKindOfClass:[UITapGestureRecognizer class]]) {
            UITapGestureRecognizer *tapGesture = (UITapGestureRecognizer *)gesture;
            // 设置状态为已识别
            [self simulateGestureRecognizer:tapGesture onView:view atLocation:location];
            return YES;
        }
        
        // 触发 long press gesture
        if ([gesture isKindOfClass:[UILongPressGestureRecognizer class]]) {
            UILongPressGestureRecognizer *longPressGesture = (UILongPressGestureRecognizer *)gesture;
            [self simulateGestureRecognizer:longPressGesture onView:view atLocation:location];
            return YES;
        }
        
        // 触发其他自定义 gesture
        [self simulateGestureRecognizer:gesture onView:view atLocation:location];
        return YES;
    }
    
    return NO;
}

- (void)simulateGestureRecognizer:(UIGestureRecognizer *)gesture onView:(UIView *)view atLocation:(CGPoint)location {
    // 对于 UITapGestureRecognizer，直接触发其 action
    if ([gesture isKindOfClass:[UITapGestureRecognizer class]]) {
        UITapGestureRecognizer *tapGesture = (UITapGestureRecognizer *)gesture;
        if (tapGesture.numberOfTapsRequired <= 1) {
            [self triggerGestureTargetActions:tapGesture];
        }
        return;
    }
    
    // 对于其他 gesture，尝试触发其 action
    [self triggerGestureTargetActions:gesture];
    
    NSLog(@"[TouchPlayer] Simulated gesture: %@", NSStringFromClass(gesture.class));
}

- (void)triggerGestureTargetActions:(UIGestureRecognizer *)gesture {
    // 安全地触发 gesture recognizer
    // 使用 touchesBegan/touchesEnded 模拟触摸事件
    UIView *view = gesture.view;
    if (!view) return;
    
    // 获取 gesture 在 view 中的位置（使用中心点）
    CGPoint center = CGPointMake(view.bounds.size.width / 2, view.bounds.size.height / 2);
    
    // 创建模拟触摸事件
    UITouch *touch = [[UITouch alloc] init];
    UIEvent *event = [[UIEvent alloc] init];
    
    // 使用 NSValue 包装触摸点
    NSValue *touchPoint = [NSValue valueWithCGPoint:[view convertPoint:center toView:nil]];
    
    // 使用 NSInvocation 来调用私有方法（更安全，避免警告）
    @try {
        // _setLocationInWindow:
        SEL setLocationSel = NSSelectorFromString(@"_setLocationInWindow:");
        if ([touch respondsToSelector:setLocationSel]) {
            NSMethodSignature *signature = [touch methodSignatureForSelector:setLocationSel];
            if (signature) {
                NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
                [invocation setSelector:setLocationSel];
                [invocation setTarget:touch];
                [invocation setArgument:&touchPoint atIndex:2];
                [invocation invoke];
            }
        }
        
        // _setView:
        SEL setViewSel = NSSelectorFromString(@"_setView:");
        if ([touch respondsToSelector:setViewSel]) {
            NSMethodSignature *signature = [touch methodSignatureForSelector:setViewSel];
            if (signature) {
                NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
                [invocation setSelector:setViewSel];
                [invocation setTarget:touch];
                [invocation setArgument:&view atIndex:2];
                [invocation invoke];
            }
        }
        
        // _setPhase:
        NSNumber *phaseBegan = @(UITouchPhaseBegan);
        SEL setPhaseSel = NSSelectorFromString(@"_setPhase:");
        if ([touch respondsToSelector:setPhaseSel]) {
            NSMethodSignature *signature = [touch methodSignatureForSelector:setPhaseSel];
            if (signature) {
                NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
                [invocation setSelector:setPhaseSel];
                [invocation setTarget:touch];
                [invocation setArgument:&phaseBegan atIndex:2];
                [invocation invoke];
            }
        }
        
        NSSet *touches = [NSSet setWithObject:touch];
        
        [gesture touchesBegan:touches withEvent:event];
        
        // _setPhase: UITouchPhaseEnded
        NSNumber *phaseEnded = @(UITouchPhaseEnded);
        if ([touch respondsToSelector:setPhaseSel]) {
            NSMethodSignature *signature = [touch methodSignatureForSelector:setPhaseSel];
            if (signature) {
                NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
                [invocation setSelector:setPhaseSel];
                [invocation setTarget:touch];
                [invocation setArgument:&phaseEnded atIndex:2];
                [invocation invoke];
            }
        }
        
        [gesture touchesEnded:touches withEvent:event];
        
        NSLog(@"[TouchPlayer] Successfully triggered gesture: %@", NSStringFromClass(gesture.class));
    }
    @catch (NSException *exception) {
        NSLog(@"[TouchPlayer] Failed to trigger gesture: %@, error: %@", 
              NSStringFromClass(gesture.class), exception.description);
    }
}

- (void)invokeSelector:(SEL)selector onObject:(id)object withObject:(id)argument {
    if (!object || ![object respondsToSelector:selector]) return;
    
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!signature) return;
    
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setSelector:selector];
    [invocation setTarget:object];
    if (argument) {
        [invocation setArgument:&argument atIndex:2];
    }
    [invocation invoke];
}

- (BOOL)triggerUIButtonAction:(UIView *)view {
    if (![view isKindOfClass:[UIButton class]]) {
        return NO;
    }
    
    UIButton *button = (UIButton *)view;
    
    if (!button.enabled || button.hidden) {
        return NO;
    }
    
    NSLog(@"[TouchPlayer] Triggering UIButton: %@ title:%@", 
          NSStringFromClass(button.class), button.currentTitle);
    
    // 方法1: 模拟完整触摸流程
    [self simulateTouchSequenceOnView:view];
    
    // 方法2: 直接调用 sendActionsForControlEvents
    [button sendActionsForControlEvents:UIControlEventTouchDown];
    [button sendActionsForControlEvents:UIControlEventTouchUpInside];
    
    return YES;
}

- (void)triggerTargetActionsForControl:(UIControl *)control {
    // 尝试获取所有绑定的 actions
    SEL allTargetsSel = NSSelectorFromString(@"allTargets");
    if ([control respondsToSelector:allTargetsSel]) {
        NSSet *targets = nil;
        NSMethodSignature *signature = [control methodSignatureForSelector:allTargetsSel];
        if (signature) {
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setSelector:allTargetsSel];
            [invocation setTarget:control];
            [invocation invoke];
            [invocation getReturnValue:&targets];
        }
        
        for (id __weak weakTarget in targets) {
            id target = weakTarget;
            if (!target) continue;
            
            SEL actionsForTargetSel = NSSelectorFromString(@"actionsForTarget:forControlEvent:");
            if ([control respondsToSelector:actionsForTargetSel]) {
                NSArray *actions = nil;
                signature = [control methodSignatureForSelector:actionsForTargetSel];
                if (signature) {
                    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
                    [invocation setSelector:actionsForTargetSel];
                    [invocation setTarget:control];
                    [invocation setArgument:&target atIndex:2];
                    NSNumber *eventNum = @(UIControlEventTouchUpInside);
                    [invocation setArgument:&eventNum atIndex:3];
                    [invocation invoke];
                    [invocation getReturnValue:&actions];
                }
                
                for (NSString *actionName in actions) {
                    SEL action = NSSelectorFromString(actionName);
                    if ([target respondsToSelector:action]) {
                        NSLog(@"[TouchPlayer] Calling target action: %@ on %@", 
                              NSStringFromSelector(action), NSStringFromClass([target class]));
                        // 使用 NSInvocation 避免 performSelector 警告
                        NSMethodSignature *actionSignature = [target methodSignatureForSelector:action];
                        if (actionSignature) {
                            NSInvocation *actionInvocation = [NSInvocation invocationWithMethodSignature:actionSignature];
                            [actionInvocation setSelector:action];
                            [actionInvocation setTarget:target];
                            NSUInteger paramCount = actionSignature.numberOfArguments;
                            if (paramCount >= 3) {
                                [actionInvocation setArgument:&control atIndex:2];
                            }
                            [actionInvocation invoke];
                        }
                    }
                }
            }
        }
    }
}

- (BOOL)triggerUIControlAction:(UIView *)view {
    if (![view isKindOfClass:[UIControl class]]) {
        return NO;
    }
    
    UIControl *control = (UIControl *)view;
    
    if (!control.enabled || control.hidden) {
        return NO;
    }
    
    NSLog(@"[TouchPlayer] Triggering UIControl: %@", NSStringFromClass(control.class));
    
    // 模拟完整触摸流程
    [self simulateTouchSequenceOnView:view];
    
    // 触发所有触摸事件
    [control sendActionsForControlEvents:UIControlEventTouchDown];
    [control sendActionsForControlEvents:UIControlEventTouchUpInside];
    [control sendActionsForControlEvents:UIControlEventValueChanged];
    
    return YES;
}

- (void)simulateTouchSequenceOnView:(UIView *)view {
    // 对于 UIControl，不需要模拟完整触摸序列，sendActionsForControlEvents 已经足够
    if ([view isKindOfClass:[UIControl class]]) {
        return;
    }
    
    // 对于普通 UIView，尝试查找并触发 gesture recognizers
    if (view.gestureRecognizers && view.gestureRecognizers.count > 0) {
        CGPoint center = CGPointMake(view.bounds.size.width / 2, view.bounds.size.height / 2);
        CGPoint windowPoint = [view convertPoint:center toView:nil];
        [self triggerGestureRecognizerAction:view atLocation:windowPoint];
    }
}

- (BOOL)triggerUITableViewAction:(UIView *)view atLocation:(CGPoint)location {
    // 查找父级 UITableView
    UIView *superview = view;
    UITableView *tableView = nil;
    
    while (superview) {
        if ([superview isKindOfClass:[UITableView class]]) {
            tableView = (UITableView *)superview;
            break;
        }
        superview = superview.superview;
    }
    
    if (!tableView) {
        return NO;
    }
    
    // 修复: location 已经是 window 坐标，需要转换为 tableView 坐标
    CGPoint tableViewLocation = [tableView convertPoint:location fromView:nil];
    
    NSLog(@"[TouchPlayer] TableView location: (%.2f, %.2f)", tableViewLocation.x, tableViewLocation.y);
    
    // 获取 indexPath
    NSIndexPath *indexPath = [tableView indexPathForRowAtPoint:tableViewLocation];
    if (!indexPath) {
        NSLog(@"[TouchPlayer] No indexPath found at location");
        return NO;
    }
    
    NSLog(@"[TouchPlayer] TableView cell at indexPath: %@", indexPath);
    
    // 尝试触发 delegate
    if ([tableView.delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) {
        [tableView.delegate tableView:tableView didSelectRowAtIndexPath:indexPath];
        return YES;
    }
    
    // 尝试直接选中单元格
    [tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
    
    // 尝试触发 didSelectRow 通知
    [[NSNotificationCenter defaultCenter] postNotificationName:@"UITableViewDidSelectRowNotification" 
                                                        object:tableView 
                                                      userInfo:@{@"indexPath": indexPath}];
    
    return YES;
}

- (BOOL)triggerUICollectionViewAction:(UIView *)view atLocation:(CGPoint)location {
    // 查找父级 UICollectionView
    UIView *superview = view;
    UICollectionView *collectionView = nil;
    
    while (superview) {
        if ([superview isKindOfClass:[UICollectionView class]]) {
            collectionView = (UICollectionView *)superview;
            break;
        }
        superview = superview.superview;
    }
    
    if (!collectionView) {
        return NO;
    }
    
    // 修复: location 已经是 window 坐标，需要转换为 collectionView 坐标
    CGPoint collectionViewLocation = [collectionView convertPoint:location fromView:nil];
    
    NSLog(@"[TouchPlayer] CollectionView location: (%.2f, %.2f)", collectionViewLocation.x, collectionViewLocation.y);
    
    // 获取 indexPath
    NSIndexPath *indexPath = [collectionView indexPathForItemAtPoint:collectionViewLocation];
    if (!indexPath) {
        NSLog(@"[TouchPlayer] No indexPath found at location");
        return NO;
    }
    
    NSLog(@"[TouchPlayer] CollectionView cell at indexPath: %@", indexPath);
    
    // 尝试触发 delegate
    if ([collectionView.delegate respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) {
        [collectionView.delegate collectionView:collectionView didSelectItemAtIndexPath:indexPath];
        return YES;
    }
    
    // 尝试直接选中单元格
    [collectionView selectItemAtIndexPath:indexPath animated:NO scrollPosition:UICollectionViewScrollPositionNone];
    
    return YES;
}

- (BOOL)triggerUIScrollViewAction:(UIView *)view atLocation:(CGPoint)location {
    // 查找父级 UIScrollView
    UIView *superview = view;
    UIScrollView *scrollView = nil;
    
    while (superview) {
        if ([superview isKindOfClass:[UIScrollView class]] && 
            ![superview isKindOfClass:[UITableView class]] && 
            ![superview isKindOfClass:[UICollectionView class]]) {
            scrollView = (UIScrollView *)superview;
            break;
        }
        superview = superview.superview;
    }
    
    if (!scrollView) {
        return NO;
    }
    
    // 修复: location 已经是 window 坐标，需要转换为 scrollView 坐标
    CGPoint scrollViewLocation = [scrollView convertPoint:location fromView:nil];
    
    NSLog(@"[TouchPlayer] ScrollView found, location: (%.2f, %.2f)", 
          scrollViewLocation.x, scrollViewLocation.y);
    
    // 滚动到点击位置
    CGPoint contentOffset = scrollView.contentOffset;
    contentOffset.x += (scrollView.bounds.size.width / 2 - scrollViewLocation.x);
    contentOffset.y += (scrollView.bounds.size.height / 2 - scrollViewLocation.y);
    
    [scrollView setContentOffset:contentOffset animated:YES];
    
    return YES;
}

- (BOOL)triggerWKWebViewAction:(UIView *)view atLocation:(CGPoint)location {
    // 查找 WKWebView
    UIView *superview = view;
    WKWebView *webView = nil;
    
    while (superview) {
        if ([superview isKindOfClass:[WKWebView class]]) {
            webView = (WKWebView *)superview;
            break;
        }
        superview = superview.superview;
    }
    
    if (!webView) {
        return NO;
    }
    
    NSLog(@"[TouchPlayer] WKWebView found");
    
    // 修复: location 已经是 window 坐标，需要转换为 web view 坐标
    CGPoint webViewLocation = [webView convertPoint:location fromView:nil];
    
    NSLog(@"[TouchPlayer] WKWebView location: (%.2f, %.2f)", webViewLocation.x, webViewLocation.y);
    
    // 构建 JavaScript 点击代码
    NSString *javascript = [NSString stringWithFormat:
        @"document.elementFromPoint(%f, %f).click();", 
        webViewLocation.x, 
        webViewLocation.y];
    
    // 执行 JavaScript
    [webView evaluateJavaScript:javascript completionHandler:^(id result, NSError *error) {
        if (error) {
            NSLog(@"[TouchPlayer] JavaScript error: %@", error);
        } else {
            NSLog(@"[TouchPlayer] JavaScript executed successfully");
        }
    }];
    
    return YES;
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
