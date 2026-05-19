#import "TouchPlayer.h"
#import <WebKit/WebKit.h>

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
    
    [self triggerTouchAtLocation:location withType:event.type];
}

- (void)triggerTouchAtLocation:(CGPoint)location withType:(TouchEventType)type {
    UIWindow *keyWindow = [self getKeyWindow];
    if (!keyWindow) {
        NSLog(@"[TouchPlayer] No key window found");
        return;
    }
    
    // 使用 hitTest 定位目标视图
    UIView *hitView = [keyWindow hitTest:location withEvent:nil];
    if (!hitView) {
        NSLog(@"[TouchPlayer] No view found at location (%f, %f)", location.x, location.y);
        return;
    }
    
    NSLog(@"[TouchPlayer] Hit view: %@", hitView);
    
    // 根据视图类型触发相应行为
    [self triggerActionForView:hitView atLocation:location type:type];
}

- (void)triggerActionForView:(UIView *)view atLocation:(CGPoint)location type:(TouchEventType)type {
    // 检查是否是结束事件（TouchUpInside）
    BOOL isTouchUp = (type == TouchEventTypeEnded);
    
    // 1. 尝试触发 UIButton
    if ([self triggerUIButtonAction:view isTouchUp:isTouchUp]) {
        NSLog(@"[TouchPlayer] Triggered UIButton action");
        return;
    }
    
    // 2. 尝试触发 UIControl
    if ([self triggerUIControlAction:view isTouchUp:isTouchUp]) {
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
    
    // 7. 尝试查找父级视图中的可交互控件
    if (view.superview) {
        [self triggerActionForView:view.superview atLocation:location type:type];
    }
}

- (BOOL)triggerUIButtonAction:(UIView *)view isTouchUp:(BOOL)isTouchUp {
    if (![view isKindOfClass:[UIButton class]]) {
        return NO;
    }
    
    UIButton *button = (UIButton *)view;
    
    if (isTouchUp) {
        // 触发按钮点击
        [button sendActionsForControlEvents:UIControlEventTouchUpInside];
        return YES;
    }
    
    return NO;
}

- (BOOL)triggerUIControlAction:(UIView *)view isTouchUp:(BOOL)isTouchUp {
    if (![view isKindOfClass:[UIControl class]]) {
        return NO;
    }
    
    UIControl *control = (UIControl *)view;
    
    if (isTouchUp) {
        // 触发所有触摸事件
        [control sendActionsForControlEvents:UIControlEventTouchUpInside];
        [control sendActionsForControlEvents:UIControlEventValueChanged];
        return YES;
    }
    
    return NO;
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
    
    // 转换坐标
    CGPoint tableViewLocation = [tableView convertPoint:location fromView:view];
    
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
    
    // 转换坐标
    CGPoint collectionViewLocation = [collectionView convertPoint:location fromView:view];
    
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
    
    NSLog(@"[TouchPlayer] ScrollView found");
    
    // 滚动到点击位置
    CGPoint contentOffset = scrollView.contentOffset;
    contentOffset.x += (scrollView.bounds.size.width / 2 - location.x);
    contentOffset.y += (scrollView.bounds.size.height / 2 - location.y);
    
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
    
    // 转换坐标为 web view 坐标
    CGPoint webViewLocation = [webView convertPoint:location fromView:view];
    
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
