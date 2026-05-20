#import "FloatingPanel.h"
#import "TouchPlayer.h"
#import "TouchRecorder.h"

@interface FloatingPanel ()

@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIButton *toggleButton;
@property (nonatomic, strong) UIButton *recordButton;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *pauseButton;
@property (nonatomic, strong) UIButton *stopButton;
@property (nonatomic, strong) UIButton *saveButton;
@property (nonatomic, strong) UIButton *scriptButton;
@property (nonatomic, strong) UIButton *logsButton;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *progressLabel;
@property (nonatomic, assign) CGPoint initialTouchPoint;
@property (nonatomic, assign) CGPoint initialPanelCenter;
@property (nonatomic, strong) NSTimer *autoHideTimer;
@property (nonatomic, strong) NSTimer *checkVisibilityTimer;
@property (nonatomic, assign) BOOL isRecording;
@property (nonatomic, assign) BOOL isPlaying;
@property (nonatomic, assign) BOOL isExpanded;
@property (nonatomic, strong) NSLayoutConstraint *contentViewWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *contentViewHeightConstraint;

@end

@implementation FloatingPanel

+ (instancetype)sharedInstance {
    static FloatingPanel *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[FloatingPanel alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height)];
        instance.backgroundColor = [UIColor clearColor];
        instance.clipsToBounds = NO;
    });
    return instance;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _opacity = 0.9;
        _cornerRadius = 12;
        _autoHideEnabled = YES;
        _autoHideDelay = 8.0;
        _isExpanded = NO;
        _isVisible = NO;
        [self setupPanel];
        [self setupNotifications];
    }
    return self;
}

- (void)setupPanel {
    _contentView = [[UIView alloc] initWithFrame:CGRectZero];
    _contentView.translatesAutoresizingMaskIntoConstraints = NO;
    _contentView.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:_opacity];
    _contentView.layer.cornerRadius = _cornerRadius;
    _contentView.clipsToBounds = YES;
    _contentView.layer.shadowColor = [UIColor blackColor].CGColor;
    _contentView.layer.shadowOffset = CGSizeMake(0, 3);
    _contentView.layer.shadowOpacity = 0.6;
    _contentView.layer.shadowRadius = 6;
    _contentView.layer.borderWidth = 1;
    _contentView.layer.borderColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:0.5].CGColor;
    _contentView.userInteractionEnabled = YES;
    
    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [_contentView addGestureRecognizer:panGesture];
    
    [self addSubview:_contentView];
    
    _contentViewWidthConstraint = [_contentView.widthAnchor constraintEqualToConstant:60];
    _contentViewHeightConstraint = [_contentView.heightAnchor constraintEqualToConstant:60];
    _contentViewWidthConstraint.active = YES;
    _contentViewHeightConstraint.active = YES;
    [_contentView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [_contentView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
    
    _toggleButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _toggleButton.frame = CGRectMake(0, 0, 60, 60);
    _toggleButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.9];
    _toggleButton.layer.cornerRadius = 10;
    [_toggleButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _toggleButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [_toggleButton setTitle:@"工具" forState:UIControlStateNormal];
    [_toggleButton addTarget:self action:@selector(toggleButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [_contentView addSubview:_toggleButton];
    
    CGFloat buttonSize = 50;
    CGFloat padding = 6;
    
    _recordButton = [self createButtonWithTitle:@"录制" action:@selector(recordButtonTapped)];
    _playButton = [self createButtonWithTitle:@"播放" action:@selector(playButtonTapped)];
    _pauseButton = [self createButtonWithTitle:@"暂停" action:@selector(pauseButtonTapped)];
    _pauseButton.hidden = YES;
    _stopButton = [self createButtonWithTitle:@"停止" action:@selector(stopButtonTapped)];
    _saveButton = [self createButtonWithTitle:@"保存" action:@selector(saveButtonTapped)];
    _scriptButton = [self createButtonWithTitle:@"脚本" action:@selector(scriptButtonTapped)];
    _logsButton = [self createButtonWithTitle:@"日志" action:@selector(logsButtonTapped)];
    
    NSArray *buttons = @[_recordButton, _playButton, _pauseButton, _stopButton, _saveButton, _scriptButton, _logsButton];
    
    NSLayoutYAxisAnchor *previousAnchor = nil;
    for (UIButton *button in buttons) {
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.alpha = 0;
        button.hidden = YES;
        [_contentView addSubview:button];
        
        [NSLayoutConstraint activateConstraints:@[
            [button.widthAnchor constraintEqualToConstant:buttonSize],
            [button.heightAnchor constraintEqualToConstant:buttonSize],
            [button.centerXAnchor constraintEqualToAnchor:_contentView.centerXAnchor],
        ]];
        
        if (previousAnchor) {
            [button.topAnchor constraintEqualToAnchor:previousAnchor constant:padding].active = YES;
        } else {
            [button.topAnchor constraintEqualToAnchor:_contentView.topAnchor constant:padding].active = YES;
        }
        previousAnchor = button.bottomAnchor;
    }
    
    _contentViewHeightConstraint.constant = 60;
    
    _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
    _progressView.translatesAutoresizingMaskIntoConstraints = NO;
    _progressView.tintColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:1.0];
    _progressView.hidden = YES;
    _progressView.layer.cornerRadius = 2;
    [_contentView addSubview:_progressView];
    
    _progressLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _progressLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _progressLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    _progressLabel.textColor = [UIColor colorWithRed:0.8 green:0.8 blue:0.8 alpha:1.0];
    _progressLabel.textAlignment = NSTextAlignmentCenter;
    _progressLabel.hidden = YES;
    _progressLabel.shadowColor = [UIColor blackColor];
    _progressLabel.shadowOffset = CGSizeMake(0, 1);
    [_contentView addSubview:_progressLabel];
}

- (void)setupNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(applicationDidBecomeActive:) 
                                                 name:UIApplicationDidBecomeActiveNotification 
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(windowDidBecomeKey:) 
                                                 name:UIWindowDidBecomeKeyNotification 
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(windowDidResignKey:) 
                                                 name:UIWindowDidResignKeyNotification 
                                               object:nil];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (_isVisible && self.hidden) {
            [self show];
        }
    });
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    UIWindow *window = notification.object;
    if (window && self.superview != window) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (_isVisible && !self.hidden) {
                [self removeFromSuperview];
                [window addSubview:self];
                self.frame = window.bounds;
            }
        });
    }
}

- (void)windowDidResignKey:(NSNotification *)notification {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (_isVisible && self.hidden) {
            [self show];
        }
    });
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if (_autoHideTimer) {
        [_autoHideTimer invalidate];
        _autoHideTimer = nil;
    }
    
    if (_checkVisibilityTimer) {
        [_checkVisibilityTimer invalidate];
        _checkVisibilityTimer = nil;
    }
}

- (UIButton *)createButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.9];
    button.layer.cornerRadius = 8;
    button.layer.borderWidth = 1;
    button.layer.borderColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:0.5].CGColor;
    
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    
    [button setBackgroundImage:[self imageWithColor:[UIColor colorWithRed:0.25 green:0.25 blue:0.25 alpha:1.0] size:CGSizeMake(1, 1)] forState:UIControlStateHighlighted];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    
    return button;
}

- (UIImage *)imageWithColor:(UIColor *)color size:(CGSize)size {
    CGRect rect = CGRectMake(0, 0, size.width, size.height);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    [color setFill];
    UIRectFill(rect);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    [self resetAutoHideTimer];
    
    CGPoint touchPoint = [gesture locationInView:self];
    
    if (gesture.state == UIGestureRecognizerStateBegan) {
        _initialTouchPoint = touchPoint;
        _initialPanelCenter = _contentView.center;
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = CGPointMake(touchPoint.x - _initialTouchPoint.x, touchPoint.y - _initialTouchPoint.y);
        CGPoint newCenter = CGPointMake(_initialPanelCenter.x + translation.x, _initialPanelCenter.y + translation.y);
        
        CGFloat halfWidth = _contentView.bounds.size.width / 2;
        CGFloat halfHeight = _contentView.bounds.size.height / 2;
        CGFloat maxX = self.bounds.size.width - halfWidth;
        CGFloat maxY = self.bounds.size.height - halfHeight;
        
        newCenter.x = MAX(halfWidth, MIN(maxX, newCenter.x));
        newCenter.y = MAX(halfHeight, MIN(maxY, newCenter.y));
        
        _contentView.center = newCenter;
    } else if (gesture.state == UIGestureRecognizerStateEnded) {
        [self snapToEdge];
    }
}

- (void)snapToEdge {
    CGFloat panelCenterX = _contentView.center.x;
    CGFloat screenWidth = self.bounds.size.width;
    CGFloat halfWidth = _contentView.bounds.size.width / 2;
    
    CGFloat targetX = (panelCenterX < screenWidth / 2) ? halfWidth : screenWidth - halfWidth;
    
    [UIView animateWithDuration:0.3 animations:^{
        _contentView.center = CGPointMake(targetX, _contentView.center.y);
    }];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    CGPoint pointInContentView = [self convertPoint:point toView:_contentView];
    
    // 如果面板收起，只检查toggleButton
    if (!_isExpanded) {
        if (_toggleButton.hidden == NO && CGRectContainsPoint(_toggleButton.frame, pointInContentView)) {
            return _toggleButton;
        }
        // 收起状态，其他区域穿透
        return nil;
    }
    
    // 展开状态，检查所有子视图
    for (UIView *subview in _contentView.subviews) {
        if (subview.hidden || subview.alpha < 0.01) continue;
        if (CGRectContainsPoint(subview.frame, pointInContentView)) {
            return subview;
        }
    }
    
    // 如果点击在contentView范围内但没有子视图响应，返回contentView
    if (CGRectContainsPoint(_contentView.bounds, pointInContentView)) {
        return _contentView;
    }
    
    // 点击在面板范围外，允许穿透
    return nil;
}

- (void)resetAutoHideTimer {
    if (_autoHideTimer) {
        [_autoHideTimer invalidate];
        _autoHideTimer = nil;
    }
    
    if (_autoHideEnabled) {
        _autoHideTimer = [NSTimer scheduledTimerWithTimeInterval:_autoHideDelay target:self selector:@selector(autoHide) userInfo:nil repeats:NO];
    }
}

- (void)autoHide {
    if (_isExpanded) {
        [self collapse];
    }
}

- (void)toggleButtonTapped {
    if (_isExpanded) {
        [self collapse];
    } else {
        [self expand];
    }
    [self resetAutoHideTimer];
}

- (void)expand {
    _isExpanded = YES;
    
    CGFloat buttonSize = 50;
    CGFloat padding = 6;
    NSUInteger buttonCount = 7;
    CGFloat contentHeight = buttonCount * (buttonSize + padding) + padding;
    
    _contentViewHeightConstraint.constant = contentHeight;
    
    [UIView animateWithDuration:0.3 animations:^{
        [self layoutIfNeeded];
        
        for (UIView *subview in _contentView.subviews) {
            if ([subview isKindOfClass:[UIButton class]] && subview != _toggleButton) {
                subview.alpha = 1;
                subview.hidden = NO;
            }
        }
        
        _toggleButton.alpha = 0;
    } completion:^(BOOL finished) {
        _toggleButton.hidden = YES;
    }];
}

- (void)collapse {
    _isExpanded = NO;
    
    _contentViewHeightConstraint.constant = 60;
    
    [UIView animateWithDuration:0.3 animations:^{
        [self layoutIfNeeded];
        
        for (UIView *subview in _contentView.subviews) {
            if ([subview isKindOfClass:[UIButton class]] && subview != _toggleButton) {
                subview.alpha = 0;
                subview.hidden = YES;
            }
        }
        
        _toggleButton.alpha = 1;
    } completion:^(BOOL finished) {
        _toggleButton.hidden = NO;
    }];
}

- (void)show {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self startVisibilityCheck];
        
        UIWindow *keyWindow = [self getKeyWindow];
        if (!keyWindow) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self show];
            });
            return;
        }
        
        if (self.superview != keyWindow) {
            [self removeFromSuperview];
            [keyWindow addSubview:self];
        }
        
        self.frame = keyWindow.bounds;
        self.hidden = NO;
        _isVisible = YES;
        _isExpanded = NO;
        
        [self collapse];
        [self resetAutoHideTimer];
    });
}

- (void)startVisibilityCheck {
    if (_checkVisibilityTimer) {
        [_checkVisibilityTimer invalidate];
        _checkVisibilityTimer = nil;
    }
    
    _checkVisibilityTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 
                                                          target:self 
                                                        selector:@selector(checkVisibility) 
                                                        userInfo:nil 
                                                         repeats:YES];
}

- (void)checkVisibility {
    if (!_isVisible) return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.hidden || !self.superview) {
            [self show];
        }
    });
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
    
    if (!keyWindow) {
        NSArray *windows = [UIApplication sharedApplication].windows;
        for (UIWindow *window in windows) {
            if (!window.hidden && window.windowLevel == UIWindowLevelNormal) {
                keyWindow = window;
                break;
            }
        }
    }
    
    if (!keyWindow && [UIApplication sharedApplication].windows.count > 0) {
        keyWindow = [UIApplication sharedApplication].windows.lastObject;
    }
    
    return keyWindow;
}

- (void)hide {
    if (!self.hidden) {
        self.hidden = YES;
        _isVisible = NO;
        
        if (_checkVisibilityTimer) {
            [_checkVisibilityTimer invalidate];
            _checkVisibilityTimer = nil;
        }
    }
}

- (void)toggleVisibility {
    if (self.hidden) {
        [self show];
    } else {
        [self hide];
    }
}

- (void)updateRecordingState:(BOOL)isRecording {
    _isRecording = isRecording;
    
    if (isRecording) {
        _recordButton.backgroundColor = [UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:0.9];
        _recordButton.layer.borderColor = [UIColor colorWithRed:1.0 green:0.4 blue:0.4 alpha:0.8].CGColor;
        [_recordButton setTitle:@"● 录制中" forState:UIControlStateNormal];
        _playButton.enabled = NO;
        _pauseButton.enabled = NO;
        _stopButton.enabled = YES;
    } else {
        _recordButton.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.9];
        _recordButton.layer.borderColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:0.5].CGColor;
        [_recordButton setTitle:@"录制" forState:UIControlStateNormal];
        _playButton.enabled = YES;
        _pauseButton.enabled = _isPlaying;
        _stopButton.enabled = YES;
    }
}

- (void)updatePlaybackState:(BOOL)isPlaying isPaused:(BOOL)isPaused {
    _isPlaying = isPlaying;
    _playButton.hidden = isPlaying;
    _pauseButton.hidden = !isPlaying || isPaused;
    
    if (isPlaying) {
        if (isPaused) {
            [_pauseButton setTitle:@"▶ 继续" forState:UIControlStateNormal];
        } else {
            [_pauseButton setTitle:@"⏸ 暂停" forState:UIControlStateNormal];
        }
        _recordButton.enabled = NO;
        
        // 显示进度条和标签，设置约束
        _progressView.hidden = NO;
        _progressLabel.hidden = NO;
        
        // 移除旧约束
        for (NSLayoutConstraint *constraint in _contentView.constraints) {
            if (constraint.firstItem == _progressView || constraint.secondItem == _progressView ||
                constraint.firstItem == _progressLabel || constraint.secondItem == _progressLabel) {
                constraint.active = NO;
            }
        }
        
        // 添加新约束：进度条在日志按钮下方
        [NSLayoutConstraint activateConstraints:@[
            [_progressView.leadingAnchor constraintEqualToAnchor:_contentView.leadingAnchor constant:8],
            [_progressView.trailingAnchor constraintEqualToAnchor:_contentView.trailingAnchor constant:-8],
            [_progressView.heightAnchor constraintEqualToConstant:3],
            [_progressView.topAnchor constraintEqualToAnchor:_logsButton.bottomAnchor constant:8],
            
            [_progressLabel.leadingAnchor constraintEqualToAnchor:_contentView.leadingAnchor],
            [_progressLabel.trailingAnchor constraintEqualToAnchor:_contentView.trailingAnchor],
            [_progressLabel.topAnchor constraintEqualToAnchor:_progressView.bottomAnchor constant:4],
            [_progressLabel.bottomAnchor constraintEqualToAnchor:_contentView.bottomAnchor constant:-8],
        ]];
        
        // 展开面板以显示进度条
        if (!_isExpanded) {
            [self expand];
        }
    } else {
        // 播放结束时恢复按钮状态
        _playButton.hidden = NO;
        _pauseButton.hidden = YES;
        [_pauseButton setTitle:@"暂停" forState:UIControlStateNormal];
        _recordButton.enabled = YES;
        _progressView.hidden = YES;
        _progressLabel.hidden = YES;
        _progressView.progress = 0;
        _progressLabel.text = @"";
        
        // 移除进度条相关约束
        for (NSLayoutConstraint *constraint in _contentView.constraints) {
            if (constraint.firstItem == _progressView || constraint.secondItem == _progressView ||
                constraint.firstItem == _progressLabel || constraint.secondItem == _progressLabel) {
                constraint.active = NO;
            }
        }
    }
}

- (void)updateProgress:(NSUInteger)currentIndex totalCount:(NSUInteger)totalCount {
    if (totalCount == 0) return;
    _progressView.progress = (CGFloat)currentIndex / totalCount;
    _progressLabel.text = [NSString stringWithFormat:@"进度：%lu/%lu", (unsigned long)currentIndex + 1, (unsigned long)totalCount];
}

- (void)recordButtonTapped {
    [self resetAutoHideTimer];
    if (_startRecordingBlock) {
        _startRecordingBlock();
    }
}

- (void)playButtonTapped {
    [self resetAutoHideTimer];
    [self showPlaybackPanel];
}

- (void)pauseButtonTapped {
    [self resetAutoHideTimer];
    if (_pauseBlock) {
        _pauseBlock();
    }
}

- (void)stopButtonTapped {
    [self resetAutoHideTimer];
    if (_stopRecordingBlock) {
        _stopRecordingBlock();
    }
}

- (void)saveButtonTapped {
    [self resetAutoHideTimer];
    if (_saveBlock) {
        _saveBlock();
    }
}

- (void)scriptButtonTapped {
    [self resetAutoHideTimer];
    if (_scriptManagerBlock) {
        _scriptManagerBlock();
    }
}

- (void)logsButtonTapped {
    [self resetAutoHideTimer];
    if (_showLogsBlock) {
        _showLogsBlock();
    }
}

- (void)showPlaybackPanel {
    UIWindow *keyWindow = [self getKeyWindow];
    if (!keyWindow) return;
    
    CGFloat panelWidth = 300;
    CGFloat panelHeight = 290;
    CGFloat padding = 20;
    
    UIView *backdropView = [[UIView alloc] initWithFrame:keyWindow.bounds];
    backdropView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    backdropView.tag = 9998;
    [keyWindow addSubview:backdropView];
    
    UIView *panelView = [[UIView alloc] init];
    panelView.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.95];
    panelView.layer.cornerRadius = 16;
    panelView.layer.shadowColor = [UIColor blackColor].CGColor;
    panelView.layer.shadowOpacity = 0.5;
    panelView.layer.shadowRadius = 10;
    panelView.tag = 9999;
    
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"播放控制台";
    titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    
    UILabel *loopCountLabel = [[UILabel alloc] init];
    loopCountLabel.text = @"播放次数:";
    loopCountLabel.font = [UIFont systemFontOfSize:14];
    loopCountLabel.textColor = [UIColor lightGrayColor];
    
    UITextField *loopCountField = [[UITextField alloc] init];
    loopCountField.placeholder = @"输入次数";
    loopCountField.keyboardType = UIKeyboardTypeNumberPad;
    loopCountField.backgroundColor = [UIColor whiteColor];
    loopCountField.textColor = [UIColor blackColor];
    loopCountField.font = [UIFont systemFontOfSize:14];
    loopCountField.textAlignment = NSTextAlignmentCenter;
    loopCountField.layer.cornerRadius = 8;
    loopCountField.text = @"1";
    loopCountField.tag = 1001;
    
    UISwitch *infiniteSwitch = [[UISwitch alloc] init];
    infiniteSwitch.on = NO;
    infiniteSwitch.tag = 1002;
    [infiniteSwitch addTarget:self action:@selector(infiniteSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    
    UILabel *infiniteLabel = [[UILabel alloc] init];
    infiniteLabel.text = @"无限播放";
    infiniteLabel.font = [UIFont systemFontOfSize:14];
    infiniteLabel.textColor = [UIColor lightGrayColor];
    
    UILabel *waitTimeLabel = [[UILabel alloc] init];
    waitTimeLabel.text = @"完成后等待:";
    waitTimeLabel.font = [UIFont systemFontOfSize:14];
    waitTimeLabel.textColor = [UIColor lightGrayColor];
    
    UITextField *waitTimeField = [[UITextField alloc] init];
    waitTimeField.placeholder = @"0";
    waitTimeField.keyboardType = UIKeyboardTypeDecimalPad;
    waitTimeField.backgroundColor = [UIColor whiteColor];
    waitTimeField.textColor = [UIColor blackColor];
    waitTimeField.font = [UIFont systemFontOfSize:14];
    waitTimeField.textAlignment = NSTextAlignmentCenter;
    waitTimeField.layer.cornerRadius = 8;
    waitTimeField.text = @"0";
    waitTimeField.tag = 1003;
    
    UILabel *waitTimeUnitLabel = [[UILabel alloc] init];
    waitTimeUnitLabel.text = @"秒";
    waitTimeUnitLabel.font = [UIFont systemFontOfSize:14];
    waitTimeUnitLabel.textColor = [UIColor lightGrayColor];
    
    UIButton *playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [playButton setTitle:@"开始播放" forState:UIControlStateNormal];
    [playButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    playButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0];
    playButton.layer.cornerRadius = 8;
    playButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    [playButton addTarget:self action:@selector(startPlaybackFromPanel:) forControlEvents:UIControlEventTouchUpInside];
    
    UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancelButton setTitle:@"取消" forState:UIControlStateNormal];
    [cancelButton setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];
    cancelButton.backgroundColor = [UIColor colorWithWhite:0.3 alpha:1.0];
    cancelButton.layer.cornerRadius = 8;
    cancelButton.titleLabel.font = [UIFont systemFontOfSize:16];
    [cancelButton addTarget:self action:@selector(dismissPlaybackPanel) forControlEvents:UIControlEventTouchUpInside];
    
    [panelView addSubview:titleLabel];
    [panelView addSubview:loopCountLabel];
    [panelView addSubview:loopCountField];
    [panelView addSubview:infiniteSwitch];
    [panelView addSubview:infiniteLabel];
    [panelView addSubview:waitTimeLabel];
    [panelView addSubview:waitTimeField];
    [panelView addSubview:waitTimeUnitLabel];
    [panelView addSubview:playButton];
    [panelView addSubview:cancelButton];
    
    panelView.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    loopCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    loopCountField.translatesAutoresizingMaskIntoConstraints = NO;
    infiniteSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    infiniteLabel.translatesAutoresizingMaskIntoConstraints = NO;
    waitTimeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    waitTimeField.translatesAutoresizingMaskIntoConstraints = NO;
    waitTimeUnitLabel.translatesAutoresizingMaskIntoConstraints = NO;
    playButton.translatesAutoresizingMaskIntoConstraints = NO;
    cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    [keyWindow addSubview:panelView];
    
    [NSLayoutConstraint activateConstraints:@[
        [panelView.centerXAnchor constraintEqualToAnchor:keyWindow.centerXAnchor],
        [panelView.centerYAnchor constraintEqualToAnchor:keyWindow.centerYAnchor],
        [panelView.widthAnchor constraintEqualToConstant:panelWidth],
        [panelView.heightAnchor constraintEqualToConstant:panelHeight],
        
        [titleLabel.topAnchor constraintEqualToAnchor:panelView.topAnchor constant:padding],
        [titleLabel.leadingAnchor constraintEqualToAnchor:panelView.leadingAnchor constant:padding],
        [titleLabel.trailingAnchor constraintEqualToAnchor:panelView.trailingAnchor constant:-padding],
        
        [loopCountLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:20],
        [loopCountLabel.leadingAnchor constraintEqualToAnchor:panelView.leadingAnchor constant:padding],
        
        [loopCountField.topAnchor constraintEqualToAnchor:loopCountLabel.topAnchor],
        [loopCountField.leadingAnchor constraintEqualToAnchor:loopCountLabel.trailingAnchor constant:15],
        [loopCountField.widthAnchor constraintEqualToConstant:80],
        [loopCountField.heightAnchor constraintEqualToConstant:35],
        
        [infiniteSwitch.topAnchor constraintEqualToAnchor:loopCountLabel.bottomAnchor constant:20],
        [infiniteSwitch.trailingAnchor constraintEqualToAnchor:panelView.trailingAnchor constant:-padding],
        
        [infiniteLabel.topAnchor constraintEqualToAnchor:infiniteSwitch.topAnchor],
        [infiniteLabel.centerYAnchor constraintEqualToAnchor:infiniteSwitch.centerYAnchor],
        [infiniteLabel.trailingAnchor constraintEqualToAnchor:infiniteSwitch.leadingAnchor constant:-10],
        
        [waitTimeLabel.topAnchor constraintEqualToAnchor:infiniteSwitch.bottomAnchor constant:20],
        [waitTimeLabel.leadingAnchor constraintEqualToAnchor:panelView.leadingAnchor constant:padding],
        
        [waitTimeField.topAnchor constraintEqualToAnchor:waitTimeLabel.topAnchor],
        [waitTimeField.leadingAnchor constraintEqualToAnchor:waitTimeLabel.trailingAnchor constant:15],
        [waitTimeField.widthAnchor constraintEqualToConstant:80],
        [waitTimeField.heightAnchor constraintEqualToConstant:35],
        
        [waitTimeUnitLabel.topAnchor constraintEqualToAnchor:waitTimeField.topAnchor],
        [waitTimeUnitLabel.leadingAnchor constraintEqualToAnchor:waitTimeField.trailingAnchor constant:8],
        
        [playButton.topAnchor constraintEqualToAnchor:waitTimeLabel.bottomAnchor constant:25],
        [playButton.leadingAnchor constraintEqualToAnchor:panelView.leadingAnchor constant:padding],
        [playButton.trailingAnchor constraintEqualToAnchor:cancelButton.leadingAnchor constant:-10],
        [playButton.heightAnchor constraintEqualToConstant:40],
        
        [cancelButton.topAnchor constraintEqualToAnchor:playButton.topAnchor],
        [cancelButton.trailingAnchor constraintEqualToAnchor:panelView.trailingAnchor constant:-padding],
        [cancelButton.widthAnchor constraintEqualToConstant:80],
        [cancelButton.heightAnchor constraintEqualToConstant:40],
    ]];
    
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissPlaybackPanel)];
    [backdropView addGestureRecognizer:tapGesture];
}

- (void)infiniteSwitchChanged:(UISwitch *)sender {
    UIView *panelView = [self findViewWithTag:9999];
    if (!panelView) return;
    
    UITextField *loopCountField = (UITextField *)[panelView viewWithTag:1001];
    if (loopCountField) {
        loopCountField.enabled = !sender.on;
        loopCountField.alpha = sender.on ? 0.5 : 1.0;
    }
}

- (void)startPlaybackFromPanel:(UIButton *)sender {
    UIView *panelView = [self findViewWithTag:9999];
    if (!panelView) return;
    
    UISwitch *infiniteSwitch = (UISwitch *)[panelView viewWithTag:1002];
    UITextField *loopCountField = (UITextField *)[panelView viewWithTag:1001];
    UITextField *waitTimeField = (UITextField *)[panelView viewWithTag:1003];
    
    TouchPlayer *player = [TouchPlayer sharedInstance];
    TouchRecorder *recorder = [TouchRecorder sharedInstance];
    
    NSArray *events = recorder.recordedEvents;
    if (!events || events.count == 0) {
        [self dismissPlaybackPanel];
        [self showAlertWithTitle:@"提示" message:@"没有可播放的事件，请先录制触摸"];
        return;
    }
    
    [player setEvents:events];
    
    if (infiniteSwitch.on) {
        [player setInfiniteLoop:YES];
    } else {
        [player setInfiniteLoop:NO];
        NSUInteger loopCount = 1;
        if (loopCountField.text.length > 0) {
            loopCount = [loopCountField.text integerValue];
        }
        [player setLoopCount:loopCount];
    }
    
    NSTimeInterval waitTime = 0;
    if (waitTimeField.text.length > 0) {
        waitTime = [waitTimeField.text doubleValue];
    }
    player.waitTimeAfterFinish = waitTime;
    
    [self dismissPlaybackPanel];
    
    // 启动播放！
    [player play];
    
    if (_playBlock) {
        _playBlock();
    }
}

- (void)dismissPlaybackPanel {
    UIWindow *keyWindow = [self getKeyWindow];
    if (!keyWindow) return;
    
    UIView *backdropView = [keyWindow viewWithTag:9998];
    UIView *panelView = [keyWindow viewWithTag:9999];
    
    [backdropView removeFromSuperview];
    [panelView removeFromSuperview];
}

- (UIView *)findViewWithTag:(NSInteger)tag {
    UIWindow *keyWindow = [self getKeyWindow];
    if (!keyWindow) return nil;
    
    for (UIView *subview in keyWindow.subviews) {
        if (subview.tag == tag) {
            return subview;
        }
    }
    return nil;
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    
    UIWindow *keyWindow = [self getKeyWindow];
    if (keyWindow.rootViewController) {
        [keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
    }
}

- (void)setUserInteractionEnabled:(BOOL)enabled {
    _contentView.userInteractionEnabled = enabled;
    _toggleButton.userInteractionEnabled = enabled;
    
    // 如果禁用交互，确保按钮都不可点击
    if (!enabled) {
        for (UIButton *btn in @[_recordButton, _playButton, _pauseButton, _stopButton, _saveButton, _scriptButton, _logsButton]) {
            btn.userInteractionEnabled = NO;
        }
    } else {
        // 恢复交互，根据状态决定按钮是否可用
        _recordButton.userInteractionEnabled = !_isPlaying;
        _playButton.userInteractionEnabled = !_isRecording && !_isPlaying;
        _pauseButton.userInteractionEnabled = _isPlaying && !_isRecording;
        _stopButton.userInteractionEnabled = _isPlaying || _isRecording;
        _saveButton.userInteractionEnabled = YES;
        _scriptButton.userInteractionEnabled = YES;
        _logsButton.userInteractionEnabled = YES;
    }
}

@end
