#import "FloatingPanel.h"

@interface FloatingPanel ()

@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIButton *recordButton;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *pauseButton;
@property (nonatomic, strong) UIButton *stopButton;
@property (nonatomic, strong) UIButton *saveButton;
@property (nonatomic, strong) UIButton *scriptButton;
@property (nonatomic, strong) UIButton *logsButton;
@property (nonatomic, strong) UIButton *hideButton;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *progressLabel;
@property (nonatomic, assign) CGPoint initialTouchPoint;
@property (nonatomic, assign) CGPoint initialPanelCenter;
@property (nonatomic, strong) NSTimer *autoHideTimer;
@property (nonatomic, assign) BOOL isRecording;
@property (nonatomic, assign) BOOL isPlaying;

@end

@implementation FloatingPanel

+ (instancetype)sharedInstance {
    static FloatingPanel *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[FloatingPanel alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height)];
    });
    return instance;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.windowLevel = UIWindowLevelAlert + 1;
        self.backgroundColor = [UIColor clearColor];
        self.hidden = YES;
        _opacity = 0.8;
        _cornerRadius = 12;
        _autoHideEnabled = YES;
        _autoHideDelay = 5.0;
        [self setupPanel];
    }
    return self;
}

- (void)setupPanel {
    _contentView = [[UIView alloc] initWithFrame:CGRectMake(20, 200, 60, 240)];
    _contentView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:_opacity];
    _contentView.layer.cornerRadius = _cornerRadius;
    _contentView.clipsToBounds = YES;
    _contentView.layer.shadowColor = [UIColor blackColor].CGColor;
    _contentView.layer.shadowOffset = CGSizeMake(0, 2);
    _contentView.layer.shadowOpacity = 0.5;
    _contentView.layer.shadowRadius = 4;
    
    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [_contentView addGestureRecognizer:panGesture];
    
    [self addSubview:_contentView];
    
    CGFloat buttonSize = 44;
    CGFloat padding = 8;
    NSArray *buttons = @[
        ({ _recordButton = [self createButtonWithImage:@"record" action:@selector(recordButtonTapped)]; _recordButton; }),
        ({ _playButton = [self createButtonWithImage:@"play" action:@selector(playButtonTapped)]; _playButton; }),
        ({ _pauseButton = [self createButtonWithImage:@"pause" action:@selector(pauseButtonTapped)]; _pauseButton; _pauseButton.hidden = YES; }),
        ({ _stopButton = [self createButtonWithImage:@"stop" action:@selector(stopButtonTapped)]; _stopButton; }),
        ({ _saveButton = [self createButtonWithImage:@"save" action:@selector(saveButtonTapped)]; _saveButton; }),
        ({ _scriptButton = [self createButtonWithImage:@"script" action:@selector(scriptButtonTapped)]; _scriptButton; }),
        ({ _logsButton = [self createButtonWithImage:@"logs" action:@selector(logsButtonTapped)]; _logsButton; }),
        ({ _hideButton = [self createButtonWithImage:@"hide" action:@selector(hideButtonTapped)]; _hideButton; }),
    ];
    
    NSLayoutConstraint *previousConstraint = nil;
    for (UIButton *button in buttons) {
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [_contentView addSubview:button];
        
        [NSLayoutConstraint activateConstraints:@[
            [button.widthAnchor constraintEqualToConstant:buttonSize],
            [button.heightAnchor constraintEqualToConstant:buttonSize],
            [button.centerXAnchor constraintEqualToAnchor:_contentView.centerXAnchor],
        ]];
        
        if (previousConstraint) {
            [button.topAnchor constraintEqualToAnchor:previousConstraint.bottomAnchor constant:padding].active = YES;
        } else {
            [button.topAnchor constraintEqualToAnchor:_contentView.topAnchor constant:padding].active = YES;
        }
        previousConstraint = button.bottomAnchor;
    }
    
    [_contentView.bottomAnchor constraintEqualToAnchor:previousConstraint constant:padding].active = YES;
    
    _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _progressView.translatesAutoresizingMaskIntoConstraints = NO;
    _progressView.tintColor = [UIColor greenColor];
    _progressView.hidden = YES;
    [_contentView addSubview:_progressView];
    
    [NSLayoutConstraint activateConstraints:@[
        [_progressView.leadingAnchor constraintEqualToAnchor:_contentView.leadingAnchor constant:4],
        [_progressView.trailingAnchor constraintEqualToAnchor:_contentView.trailingAnchor constant:-4],
        [_progressView.heightAnchor constraintEqualToConstant:2],
        [_progressView.topAnchor constraintEqualToAnchor:_stopButton.bottomAnchor constant:4],
    ]];
    
    _progressLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _progressLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _progressLabel.font = [UIFont systemFontOfSize:10];
    _progressLabel.textColor = [UIColor whiteColor];
    _progressLabel.textAlignment = NSTextAlignmentCenter;
    _progressLabel.hidden = YES;
    [_contentView addSubview:_progressLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [_progressLabel.leadingAnchor constraintEqualToAnchor:_contentView.leadingAnchor],
        [_progressLabel.trailingAnchor constraintEqualToAnchor:_contentView.trailingAnchor],
        [_progressLabel.topAnchor constraintEqualToAnchor:_progressView.bottomAnchor constant:2],
    ]];
}

- (UIButton *)createButtonWithImage:(NSString *)imageName action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setImage:[self imageWithColor:[UIColor whiteColor] size:CGSizeMake(24, 24)] forState:UIControlStateNormal];
    [button setImage:[self imageWithColor:[UIColor grayColor] size:CGSizeMake(24, 24)] forState:UIControlStateHighlighted];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    button.tintColor = [UIColor whiteColor];
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
    [self hide];
}

- (void)show {
    if (self.hidden) {
        self.hidden = NO;
        _isVisible = YES;
        [self resetAutoHideTimer];
    }
}

- (void)hide {
    if (!self.hidden) {
        self.hidden = YES;
        _isVisible = NO;
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
    _recordButton.tintColor = isRecording ? [UIColor redColor] : [UIColor whiteColor];
    
    if (isRecording) {
        _playButton.enabled = NO;
        _pauseButton.enabled = NO;
        _stopButton.enabled = YES;
    } else {
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
        _recordButton.enabled = NO;
        _progressView.hidden = NO;
        _progressLabel.hidden = NO;
    } else {
        _recordButton.enabled = YES;
        _progressView.hidden = YES;
        _progressLabel.hidden = YES;
        _progressView.progress = 0;
        _progressLabel.text = @"";
    }
}

- (void)updateProgress:(NSUInteger)currentIndex totalCount:(NSUInteger)totalCount {
    if (totalCount == 0) return;
    _progressView.progress = (CGFloat)currentIndex / totalCount;
    _progressLabel.text = [NSString stringWithFormat:@"%lu/%lu", (unsigned long)currentIndex + 1, (unsigned long)totalCount];
}

- (void)recordButtonTapped {
    [self resetAutoHideTimer];
    if (_startRecordingBlock) {
        _startRecordingBlock();
    }
}

- (void)playButtonTapped {
    [self resetAutoHideTimer];
    if (_playBlock) {
        _playBlock();
    }
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

- (void)hideButtonTapped {
    [self hide];
}

@end