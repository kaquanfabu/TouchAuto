#import "TouchPlayer.h"
#import "TouchAuto.h"

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
    
    NSString *eventTypeStr = @"未知";
    switch (event.type) {
        case TouchEventTypeBegan: eventTypeStr = @"按下"; break;
        case TouchEventTypeMoved: eventTypeStr = @"移动"; break;
        case TouchEventTypeEnded: eventTypeStr = @"抬起"; break;
        case TouchEventTypeCancelled: eventTypeStr = @"取消"; break;
    }
    
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
    
    // 使用缓存的真实 UITouch/UIEvent 对象进行回放
    [self replayTouchAtLocation:location withType:event.type];
}

- (void)replayTouchAtLocation:(CGPoint)location withType:(TouchEventType)type {
    // 获取缓存的真实触摸对象
    NSArray *cachedTouches = [TouchAuto cachedTouches];
    NSArray *cachedEvents = [TouchAuto cachedEvents];
    
    if (cachedTouches.count == 0 || cachedEvents.count == 0) {
        NSLog(@"[TouchPlayer] 没有缓存的触摸对象，跳过此事件");
        return;
    }
    
    // 获取一个缓存的 UITouch 对象
    UITouch *cachedTouch = cachedTouches.lastObject;
    UIEvent *cachedEvent = cachedEvents.lastObject;
    
    if (!cachedTouch || !cachedEvent) {
        NSLog(@"[TouchPlayer] 缓存对象无效，跳过此事件");
        return;
    }
    
    UIWindow *keyWindow = [TouchAuto getKeyWindow];
    if (!keyWindow) {
        NSLog(@"[TouchPlayer] 无法获取 keyWindow");
        return;
    }
    
    // 使用 KVC 设置触摸属性
    @try {
        // 设置 phase
        UITouchPhase phase;
        switch (type) {
            case TouchEventTypeBegan: phase = UITouchPhaseBegan; break;
            case TouchEventTypeMoved: phase = UITouchPhaseMoved; break;
            case TouchEventTypeEnded: phase = UITouchPhaseEnded; break;
            case TouchEventTypeCancelled: phase = UITouchPhaseCancelled; break;
            default: phase = UITouchPhaseEnded;
        }
        
        // 获取之前的位置用于 previousLocationInWindow
        CGPoint previousLocation = [cachedTouch locationInWindow];
        
        // 使用 KVC 设置属性
        [cachedTouch setValue:@(phase) forKey:@"phase"];
        [cachedTouch setValue:[NSValue valueWithCGPoint:location] forKey:@"locationInWindow"];
        [cachedTouch setValue:[NSValue valueWithCGPoint:previousLocation] forKey:@"previousLocationInWindow"];
        [cachedTouch setValue:@([[NSDate date] timeIntervalSince1970]) forKey:@"timestamp"];
        [cachedTouch setValue:keyWindow forKey:@"window"];
        
        // 更新事件中的触摸集合
        NSMutableSet *touchesSet = [NSMutableSet setWithObject:cachedTouch];
        
        // 使用 KVC 更新事件的 touches
        [cachedEvent setValue:touchesSet forKey:@"touches"];
        [cachedEvent setValue:keyWindow forKey:@"window"];
        [cachedEvent setValue:@([[NSDate date] timeIntervalSince1970]) forKey:@"timestamp"];
        
        NSLog(@"[TouchPlayer] 重放触摸事件: phase=%d, location=(%.1f, %.1f)", phase, location.x, location.y);
        
        // 发送事件
        [[UIApplication sharedApplication] sendEvent:cachedEvent];
        
    } @catch (NSException *exception) {
        NSLog(@"[TouchPlayer] KVC 设置失败: %@", exception);
    }
}

@end
