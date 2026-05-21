#import "TouchPlayer.h"
#import <WebKit/WebKit.h>
#import <UIKit/UIGestureRecognizer.h>
#import <UIKit/UITableView.h>
#import <UIKit/UICollectionView.h>
#import <UIKit/UIScrollView.h>

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
    
    // 【修复3】播放期间隐藏 FloatingPanel，避免拦截 hitTest
    [self hideFloatingPanel];
    
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
    
    // 【修复3】恢复 FloatingPanel 显示
    [self showFloatingPanel];
    
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
    
    // 【修复3】恢复 FloatingPanel 显示
    [self showFloatingPanel];
    
    if (_stateChangeBlock) {
        _stateChangeBlock(NO);
    }
    
    if (_completeBlock) {
        _completeBlock();
    }
}

- (void)hideFloatingPanel {
    Class FloatingPanelClass = NSClassFromString(@"FloatingPanel");
    if (FloatingPanelClass) {
        id panel = [FloatingPanelClass performSelector:NSSelectorFromString(@"sharedInstance")];
        if (panel && [panel respondsToSelector:@selector(setHidden:)]) {
            [panel performSelector:@selector(setHidden:) withObject:@(YES)];
            NSLog(@"[TouchPlayer] FloatingPanel hidden");
        }
    }
}

- (void)showFloatingPanel {
    Class FloatingPanelClass = NSClassFromString(@"FloatingPanel");
    if (FloatingPanelClass) {
        id panel = [FloatingPanelClass performSelector:NSSelectorFromString(@"sharedInstance")];
        if (panel && [panel respondsToSelector:@selector(setHidden:)]) {
            [panel performSelector:@selector(setHidden:) withObject:@(NO)];
            NSLog(@"[TouchPlayer] FloatingPanel shown");
        }
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
    
    NSString *eventTypeStr = @"";
    switch (event.type) {
        case TouchEventTypeBegan:
            eventTypeStr = @"Began";
            break;
        case TouchEventTypeMoved:
            eventTypeStr = @"Moved";
            break;
        case TouchEventTypeEnded:
            eventTypeStr = @"Ended";
            break;
        case TouchEventTypeCancelled:
            eventTypeStr = @"Cancelled";
            break;
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
    
    // 【修复4】使用改进的窗口获取逻辑
    UIWindow *targetWindow = [self findTargetWindowAtLocation:location];
    if (!targetWindow) {
        NSLog(@"[TouchPlayer] No valid window found at location (%.1f, %.1f)", location.x, location.y);
        return;
    }
    
    // 【修复2】发送完整触摸生命周期 (began -> moved -> ended)
    // 优先使用智能点击系统，只有 fallback 才使用 UIKit 触摸模拟
    BOOL handled = [self performSmartTouchAtLocation:location inWindow:targetWindow event:event];
    
    if (!handled) {
        NSLog(@"[TouchPlayer] Smart touch failed, using UIKit fallback");
        [self injectIOHIDTouchAtLocation:location window:targetWindow event:event];
    }
}

#pragma mark - 【修复4】改进的 Window 获取逻辑

- (UIWindow *)findTargetWindowAtLocation:(CGPoint)location {
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return nil;
    
    // 【修复4】遍历 windows.reverseObjectEnumerator
    // 跳过 hidden window
    // 仅允许 windowLevel == UIWindowLevelNormal
    // 对每个 window 执行 hitTest 找到真正业务 window
    
    NSEnumerator *windowEnumerator = [app.windows reverseObjectEnumerator];
    
    for (UIWindow *window in windowEnumerator) {
        if (window.hidden) continue;
        if (window.windowLevel != UIWindowLevelNormal) continue;
        
        // 使用 hitTest 验证 window 是否能接收事件
        CGPoint windowPoint = [window convertPoint:location fromWindow:nil];
        UIView *hit = [window hitTest:windowPoint withEvent:nil];
        
        if (hit && hit.window == window) {
            NSLog(@"[TouchPlayer] Found target window: %@ (level:%.1f)", 
                  NSStringFromClass(window.class), window.windowLevel);
            
            // 【修复6】输出 window class
            NSLog(@"[TouchPlayer] window class: %@", NSStringFromClass(window.class));
            
            return window;
        }
    }
    
    // Fallback: 尝试使用 keyWindow
    UIWindow *keyWindow = [self getKeyWindow];
    if (keyWindow && !keyWindow.hidden && keyWindow.windowLevel == UIWindowLevelNormal) {
        return keyWindow;
    }
    
    return nil;
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

#pragma mark - 【修复5】智能点击系统

- (BOOL)performSmartTouchAtLocation:(CGPoint)location inWindow:(UIWindow *)window event:(TouchEvent *)event {
    // location 是屏幕坐标，需要转换为 window 坐标
    CGPoint windowPoint = [window convertPoint:location fromWindow:nil];
    
    // 使用 hitTest 定位目标视图
    UIView *hitView = [window hitTest:windowPoint withEvent:nil];
    
    if (!hitView) {
        NSLog(@"[TouchPlayer] No view found at location (%.1f, %.1f)", windowPoint.x, windowPoint.y);
        return NO;
    }
    
    // 【修复6】输出详细调试日志
    [self logViewDebugInfo:hitView window:window location:windowPoint];
    
    // 向上查找可交互的父视图
    UIView *interactiveView = [self findInteractiveSuperview:hitView];
    
    if (interactiveView != hitView) {
        NSLog(@"[TouchPlayer] Using interactive superview: %@", NSStringFromClass(interactiveView.class));
    }
    
    // 点击优先级：
    // 1. UICollectionView delegate
    // 2. UITableView delegate
    // 3. GestureRecognizer
    // 4. UIControl
    // 5. IOHID 注入
    
    // 1. 尝试 UICollectionView (最高优先级)
    UICollectionView *collectionView = [self findParentCollectionView:interactiveView];
    if (collectionView) {
        if ([self triggerUICollectionViewAction:collectionView atLocation:windowPoint]) {
            return YES;
        }
    }
    
    // 2. 尝试 UITableView
    UITableView *tableView = [self findParentTableView:interactiveView];
    if (tableView) {
        if ([self triggerUITableViewAction:tableView atLocation:windowPoint]) {
            return YES;
        }
    }
    
    // 3. 尝试 GestureRecognizer
    if ([self triggerGestureRecognizerAction:interactiveView atLocation:windowPoint]) {
        return YES;
    }
    
    // 4. 尝试 UIControl (UIButton 等)
    if ([interactiveView isKindOfClass:[UIControl class]]) {
        if ([self triggerUIControlAction:(UIControl *)interactiveView]) {
            return YES;
        }
    }
    
    // 5. 尝试 WKWebView
    if ([self triggerWKWebViewAction:interactiveView atLocation:windowPoint]) {
        return YES;
    }
    
    return NO;
}

- (void)logViewDebugInfo:(UIView *)hitView window:(UIWindow *)window location:(CGPoint)location {
    NSLog(@"[TouchPlayer] =======================================");
    NSLog(@"[TouchPlayer] 【修复6】UIView 调试日志");
    NSLog(@"[TouchPlayer] =======================================");
    
    // 命中 view class
    NSLog(@"[TouchPlayer] hit view: %@", NSStringFromClass(hitView.class));
    NSLog(@"[TouchPlayer] hit view frame: %@", NSStringFromCGRect(hitView.frame));
    
    // superview chain
    NSMutableString *superChain = [NSMutableString string];
    UIView *superview = hitView.superview;
    while (superview) {
        if (superChain.length > 0) [superChain appendString:@"\n              "];
        [superChain appendFormat:@"%@", NSStringFromClass(superview.class)];
        superview = superview.superview;
        if (superChain.length > 500) break;
    }
    NSLog(@"[TouchPlayer] super chain:\n              %@", superChain);
    
    // gestureRecognizers
    if (hitView.gestureRecognizers && hitView.gestureRecognizers.count > 0) {
        NSMutableArray *gestureNames = [NSMutableArray array];
        for (UIGestureRecognizer *gr in hitView.gestureRecognizers) {
            [gestureNames addObject:NSStringFromClass([gr class])];
        }
        NSLog(@"[TouchPlayer] gestureRecognizers: %@", [gestureNames componentsJoinedByString:@", "]);
    } else {
        NSLog(@"[TouchPlayer] gestureRecognizers: (none)");
    }
    
    // delegate class
    if ([hitView isKindOfClass:[UITableView class]]) {
        id delegate = ((UITableView *)hitView).delegate;
        if (delegate) {
            NSLog(@"[TouchPlayer] delegate class: %@", NSStringFromClass([delegate class]));
        } else {
            NSLog(@"[TouchPlayer] delegate class: nil");
        }
    } else if ([hitView isKindOfClass:[UICollectionView class]]) {
        id delegate = ((UICollectionView *)hitView).delegate;
        if (delegate) {
            NSLog(@"[TouchPlayer] delegate class: %@", NSStringFromClass([delegate class]));
        } else {
            NSLog(@"[TouchPlayer] delegate class: nil");
        }
    }
    
    // window class
    NSLog(@"[TouchPlayer] window class: %@", NSStringFromClass([window class]));
    NSLog(@"[TouchPlayer] window level: %.1f", window.windowLevel);
    
    // responder chain
    NSMutableString *responderChain = [NSMutableString string];
    id responder = hitView;
    int count = 0;
    while (responder && count < 10) {
        if (responderChain.length > 0) [responderChain appendString:@" -> "];
        [responderChain appendFormat:@"%@", NSStringFromClass([responder class])];
        if ([responder respondsToSelector:@selector(nextResponder)]) {
            responder = [responder nextResponder];
        } else {
            break;
        }
        count++;
    }
    NSLog(@"[TouchPlayer] responder chain: %@", responderChain);
    NSLog(@"[TouchPlayer] =======================================");
}

- (UIView *)findInteractiveSuperview:(UIView *)view {
    if (!view || view.hidden || !view.userInteractionEnabled) {
        return view;
    }
    
    // 如果当前视图是可交互的类型，直接返回
    if ([self isInteractiveView:view]) {
        return view;
    }
    
    // 向上查找父级
    UIView *superview = view.superview;
    while (superview && !superview.hidden && superview.userInteractionEnabled) {
        if ([self isInteractiveView:superview]) {
            return superview;
        }
        superview = superview.superview;
    }
    
    // 找不到可交互的父级，返回原始视图
    return view;
}

- (BOOL)isInteractiveView:(UIView *)view {
    if (!view || view.hidden || !view.userInteractionEnabled) {
        return NO;
    }
    
    // 检查是否是可交互的视图类型
    if ([view isKindOfClass:[UIButton class]]) return YES;
    if ([view isKindOfClass:[UIControl class]]) return YES;
    if ([view isKindOfClass:[UITableViewCell class]]) return YES;
    if ([view isKindOfClass:[UICollectionViewCell class]]) return YES;
    if ([view isKindOfClass:[UITableView class]]) return YES;
    if ([view isKindOfClass:[UICollectionView class]]) return YES;
    if ([view isKindOfClass:[UIScrollView class]]) return YES;
    if ([view isKindOfClass:[WKWebView class]]) return YES;
    
    // 检查是否有 gesture recognizers
    if (view.gestureRecognizers && view.gestureRecognizers.count > 0) {
        return YES;
    }
    
    return NO;
}

- (UICollectionView *)findParentCollectionView:(UIView *)view {
    UIView *superview = view;
    while (superview) {
        if ([superview isKindOfClass:[UICollectionView class]]) {
            return (UICollectionView *)superview;
        }
        superview = superview.superview;
    }
    return nil;
}

- (UITableView *)findParentTableView:(UIView *)view {
    UIView *superview = view;
    while (superview) {
        if ([superview isKindOfClass:[UITableView class]]) {
            return (UITableView *)superview;
        }
        superview = superview.superview;
    }
    return nil;
}

#pragma mark - 【修复1】重构 UICollectionView 点击逻辑

- (BOOL)triggerUICollectionViewAction:(UICollectionView *)collectionView atLocation:(CGPoint)location {
    if (!collectionView) return NO;
    
    // 【修复1】使用 convertPoint:location fromView:nil
    CGPoint collectionViewLocation = [collectionView convertPoint:location fromView:nil];
    
    NSLog(@"[TouchPlayer] CollectionView location: (%.2f, %.2f)", collectionViewLocation.x, collectionViewLocation.y);
    NSLog(@"[TouchPlayer] CollectionView class: %@", NSStringFromClass(collectionView.class));
    
    // 【修复】检查 delegate 是否为 nil
    delegate = collectionView.delegate;
    if (delegate) {
        NSLog(@"[TouchPlayer] CollectionView delegate: %@", NSStringFromClass([delegate class]));
    } else {
        NSLog(@"[TouchPlayer] CollectionView delegate: nil");
    }
    
    // 获取 indexPath
    NSIndexPath *indexPath = [collectionView indexPathForItemAtPoint:collectionViewLocation];
    if (!indexPath) {
        NSLog(@"[TouchPlayer] No indexPath found at location");
        return NO;
    }
    
    NSLog(@"[TouchPlayer] CollectionView cell at indexPath: %@", indexPath);
    NSLog(@"[TouchPlayer] CollectionView select item");
    
    // 【修复1】先执行 selectItemAtIndexPath
    [collectionView selectItemAtIndexPath:indexPath 
                                 animated:NO 
                           scrollPosition:UICollectionViewScrollPositionNone];
    
    // 【修复1】然后调用 delegate 的 didSelectItemAtIndexPath
    delegate = collectionView.delegate;
    if (delegate && [delegate respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) {
        NSLog(@"[TouchPlayer] didSelectItemAtIndexPath triggered");
        [delegate collectionView:collectionView didSelectItemAtIndexPath:indexPath];
        return YES;
    }
    
    // 如果没有 delegate，尝试调用数据源的 didSelect
    id dataSource = collectionView.dataSource;
    if (dataSource && [dataSource respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) {
        NSLog(@"[TouchPlayer] didSelectItemAtIndexPath triggered (via dataSource)");
        [dataSource collectionView:collectionView didSelectItemAtIndexPath:indexPath];
        return YES;
    }
    
    return YES;
}

#pragma mark - UITableView 点击逻辑

- (BOOL)triggerUITableViewAction:(UITableView *)tableView atLocation:(CGPoint)location {
    if (!tableView) return NO;
    
    // 使用 convertPoint:location fromView:nil
    CGPoint tableViewLocation = [tableView convertPoint:location fromView:nil];
    
    NSLog(@"[TouchPlayer] TableView location: (%.2f, %.2f)", tableViewLocation.x, tableViewLocation.y);
    NSLog(@"[TouchPlayer] TableView class: %@", NSStringFromClass(tableView.class));
    
    // 【修复】检查 delegate 是否为 nil
    id tvDelegate = tableView.delegate;
    if (tvDelegate) {
        NSLog(@"[TouchPlayer] TableView delegate: %@", NSStringFromClass([tvDelegate class]));
    } else {
        NSLog(@"[TouchPlayer] TableView delegate: nil");
    }
    
    // 获取 indexPath
    NSIndexPath *indexPath = [tableView indexPathForRowAtPoint:tableViewLocation];
    if (!indexPath) {
        NSLog(@"[TouchPlayer] No indexPath found at location");
        return NO;
    }
    
    NSLog(@"[TouchPlayer] TableView cell at indexPath: %@", indexPath);
    
    // 先执行 selectRowAtIndexPath
    [tableView selectRowAtIndexPath:indexPath 
                            animated:NO 
                      scrollPosition:UITableViewScrollPositionNone];
    
    // 然后调用 delegate 的 didSelectRowAtIndexPath
    id tableDelegate = tableView.delegate;
    if (tableDelegate && [tableDelegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) {
        [tableDelegate tableView:tableView didSelectRowAtIndexPath:indexPath];
        return YES;
    }
    
    return YES;
}

#pragma mark - GestureRecognizer 处理

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
            [self simulateGestureRecognizer:tapGesture onView:view atLocation:location];
            return YES;
        }
        
        // 触发 long press gesture
        if ([gesture isKindOfClass:[UILongPressGestureRecognizer class]]) {
            UILongPressGestureRecognizer *longPressGesture = (UILongPressGestureRecognizer *)gesture;
            [self simulateGestureRecognizer:longPressGesture onView:view atLocation:location];
            return YES;
        }
    }
    
    return NO;
}

- (void)simulateGestureRecognizer:(UIGestureRecognizer *)gesture onView:(UIView *)view atLocation:(CGPoint)location {
    UITouch *touch = [self createSimulatedTouchAtLocation:location inView:view];
    if (touch) {
        NSSet *touches = [NSSet setWithObject:touch];
        UIEvent *event = [self createSimulatedEventWithTouches:touches];
        
        [gesture touchesBegan:touches withEvent:event];
        [gesture touchesEnded:touches withEvent:event];
    }
    
    NSLog(@"[TouchPlayer] Simulated gesture: %@", NSStringFromClass(gesture.class));
}

#pragma mark - UIControl 处理

- (BOOL)triggerUIControlAction:(UIControl *)control {
    if (!control.enabled || control.hidden) {
        return NO;
    }
    
    NSLog(@"[TouchPlayer] Triggering UIControl: %@", NSStringFromClass(control.class));
    
    // 模拟完整触摸流程
    [self simulateTouchSequenceOnView:control];
    
    // 触发所有触摸事件
    [control sendActionsForControlEvents:UIControlEventTouchDown];
    [control sendActionsForControlEvents:UIControlEventTouchUpInside];
    
    // 触发目标 action
    [self triggerTargetActionsForControl:control];
    
    return YES;
}

- (void)triggerTargetActionsForControl:(UIControl *)control {
    SEL allTargetsSel = NSSelectorFromString(@"allTargets");
    if (![control respondsToSelector:allTargetsSel]) return;
    
    NSSet *targets = nil;
    NSMethodSignature *signature = [control methodSignatureForSelector:allTargetsSel];
    if (signature) {
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        [invocation setSelector:allTargetsSel];
        [invocation setTarget:control];
        [invocation invoke];
        [invocation getReturnValue:&targets];
    }
    
    if (!targets || targets.count == 0) return;
    
    for (id target in targets) {
        if (!target) continue;
        
        SEL actionsForTargetSel = NSSelectorFromString(@"actionsForTarget:forControlEvent:");
        if ([control respondsToSelector:actionsForTargetSel]) {
            NSArray *actions = nil;
            signature = [control methodSignatureForSelector:actionsForTargetSel];
            if (signature) {
                NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
                [invocation setSelector:actionsForTargetSel];
                [invocation setTarget:control];
                void *targetPtr = (__bridge void *)target;
                [invocation setArgument:&targetPtr atIndex:2];
                NSNumber *eventNum = @(UIControlEventTouchUpInside);
                [invocation setArgument:&eventNum atIndex:3];
                [invocation invoke];
                [invocation getReturnValue:&actions];
            }
            
            if (actions && actions.count > 0) {
                for (NSString *actionName in actions) {
                    SEL action = NSSelectorFromString(actionName);
                    if ([target respondsToSelector:action]) {
                        NSLog(@"[TouchPlayer] Calling target action: %@ on %@", 
                              NSStringFromSelector(action), NSStringFromClass([target class]));
                        [self invokeSelector:action onObject:target withObject:control];
                    }
                }
            }
        }
    }
}

#pragma mark - WKWebView 处理

- (BOOL)triggerWKWebViewAction:(UIView *)view atLocation:(CGPoint)location {
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
    
    CGPoint webViewLocation = [webView convertPoint:location fromView:nil];
    NSLog(@"[TouchPlayer] WKWebView location: (%.2f, %.2f)", webViewLocation.x, webViewLocation.y);
    
    NSString *javascript = [NSString stringWithFormat:
        @"document.elementFromPoint(%f, %f).click();", 
        webViewLocation.x, 
        webViewLocation.y];
    
    [webView evaluateJavaScript:javascript completionHandler:^(id result, NSError *error) {
        if (error) {
            NSLog(@"[TouchPlayer] JavaScript error: %@", error);
        } else {
            NSLog(@"[TouchPlayer] JavaScript executed successfully");
        }
    }];
    
    return YES;
}

#pragma mark - 触摸模拟辅助方法

- (void)simulateTouchSequenceOnView:(UIView *)view {
    CGPoint center = CGPointMake(view.bounds.size.width / 2, view.bounds.size.height / 2);
    CGPoint windowPoint = [view convertPoint:center toView:nil];
    
    UITouch *touch = [self createSimulatedTouchAtLocation:windowPoint inView:view];
    if (touch) {
        NSSet *touches = [NSSet setWithObject:touch];
        UIEvent *event = [self createSimulatedEventWithTouches:touches];
        
        [self invokeSelector:@selector(_setPhase:) onObject:touch withObject:@(UITouchPhaseBegan)];
        [view touchesBegan:touches withEvent:event];
        
        [self invokeSelector:@selector(_setPhase:) onObject:touch withObject:@(UITouchPhaseEnded)];
        [view touchesEnded:touches withEvent:event];
    }
}

- (UITouch *)createSimulatedTouchAtLocation:(CGPoint)location inView:(UIView *)view {
    Class UITouchClass = NSClassFromString(@"UITouch");
    if (!UITouchClass) return nil;
    
    UITouch *touch = [[UITouchClass alloc] init];
    
    SEL setLocationInWindowSel = NSSelectorFromString(@"_setLocationInWindow:");
    [self invokeSelector:setLocationInWindowSel onObject:touch withObject:[NSValue valueWithCGPoint:location]];
    
    SEL setViewSel = NSSelectorFromString(@"_setView:");
    [self invokeSelector:setViewSel onObject:touch withObject:view];
    
    SEL setPhaseSel = NSSelectorFromString(@"_setPhase:");
    [self invokeSelector:setPhaseSel onObject:touch withObject:@(UITouchPhaseBegan)];
    
    return touch;
}

- (UIEvent *)createSimulatedEventWithTouches:(NSSet *)touches {
    Class UIEventClass = NSClassFromString(@"UIEvent");
    if (!UIEventClass) return nil;
    
    UIEvent *event = [[UIEventClass alloc] init];
    
    SEL setTouchesSel = NSSelectorFromString(@"_setTouches:");
    [self invokeSelector:setTouchesSel onObject:event withObject:touches];
    
    return event;
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

#pragma mark - UIKit 触摸注入 (Fallback)

- (void)injectIOHIDTouchAtLocation:(CGPoint)location window:(UIWindow *)window event:(TouchEvent *)event {
    // 使用 UIKit 触摸模拟作为 fallback
    [self injectUIKitTouchAtLocation:location window:window event:event];
}

- (void)injectUIKitTouchAtLocation:(CGPoint)location window:(UIWindow *)window event:(TouchEvent *)event {
    // 【修复2】发送完整触摸生命周期
    // Began -> Moved -> Ended
    
    UIView *hitView = [window hitTest:location withEvent:nil];
    if (!hitView) {
        NSLog(@"[TouchPlayer] No view to receive touch at (%.1f, %.1f)", location.x, location.y);
        return;
    }
    
    // 创建触摸对象
    UITouch *touch = [self createUITouchAtLocation:location inView:hitView];
    if (!touch) {
        NSLog(@"[TouchPlayer] Failed to create touch object");
        return;
    }
    
    NSSet *touches = [NSSet setWithObject:touch];
    UIEvent *eventObj = [self createUIEventWithTouches:touches];
    
    // 1. Touch Began
    [self invokeSelector:@selector(_setPhase:) onObject:touch withObject:@(UITouchPhaseBegan)];
    [hitView touchesBegan:touches withEvent:eventObj];
    NSLog(@"[TouchPlayer] UIKit Touch Began at (%.1f, %.1f)", location.x, location.y);
    
    // 2. Touch Moved (如果是从 began 过来的或者 type 是 moved)
    if (event.type == TouchEventTypeMoved || event.previousLocation.x != location.x || event.previousLocation.y != location.y) {
        [self invokeSelector:@selector(_setPhase:) onObject:touch withObject:@(UITouchPhaseMoved)];
        [hitView touchesMoved:touches withEvent:eventObj];
        NSLog(@"[TouchPlayer] UIKit Touch Moved");
    }
    
    // 3. Touch Ended
    [self invokeSelector:@selector(_setPhase:) onObject:touch withObject:@(UITouchPhaseEnded)];
    [hitView touchesEnded:touches withEvent:eventObj];
    NSLog(@"[TouchPlayer] UIKit Touch Ended at (%.1f, %.1f)", location.x, location.y);
}

- (UITouch *)createUITouchAtLocation:(CGPoint)location inView:(UIView *)view {
    Class UITouchClass = NSClassFromString(@"UITouch");
    if (!UITouchClass) return nil;
    
    UITouch *touch = [[UITouchClass alloc] init];
    
    // 设置触摸位置
    SEL setLocationSel = NSSelectorFromString(@"_setLocationInWindow:");
    if ([touch respondsToSelector:setLocationSel]) {
        NSMethodSignature *sig = [touch methodSignatureForSelector:setLocationSel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setSelector:setLocationSel];
        [inv setTarget:touch];
        CGPoint *locPtr = &location;
        [inv setArgument:locPtr atIndex:2];
        [inv invoke];
    }
    
    // 设置视图
    SEL setViewSel = NSSelectorFromString(@"_setView:");
    if ([touch respondsToSelector:setViewSel]) {
        NSMethodSignature *sig = [touch methodSignatureForSelector:setViewSel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setSelector:setViewSel];
        [inv setTarget:touch];
        [inv setArgument:&view atIndex:2];
        [inv invoke];
    }
    
    // 设置阶段
    SEL setPhaseSel = NSSelectorFromString(@"_setPhase:");
    if ([touch respondsToSelector:setPhaseSel]) {
        NSMethodSignature *sig = [touch methodSignatureForSelector:setPhaseSel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setSelector:setPhaseSel];
        [inv setTarget:touch];
        UITouchPhase phase = UITouchPhaseBegan;
        [inv setArgument:&phase atIndex:2];
        [inv invoke];
    }
    
    return touch;
}

- (UIEvent *)createUIEventWithTouches:(NSSet *)touches {
    Class UIEventClass = NSClassFromString(@"UIEvent");
    if (!UIEventClass) return nil;
    
    UIEvent *event = [[UIEventClass alloc] init];
    return event;
}

- (void)dealloc {
    [self stop];
}

@end
