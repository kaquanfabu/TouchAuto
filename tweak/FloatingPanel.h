#import <UIKit/UIKit.h>

typedef void (^PanelActionBlock)(void);

@interface FloatingPanel : UIView

@property (nonatomic, assign) BOOL isVisible;
@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, assign) CGFloat opacity;
@property (nonatomic, assign) BOOL autoHideEnabled;
@property (nonatomic, assign) NSTimeInterval autoHideDelay;
@property (nonatomic, copy) PanelActionBlock startRecordingBlock;
@property (nonatomic, copy) PanelActionBlock stopRecordingBlock;
@property (nonatomic, copy) PanelActionBlock playBlock;
@property (nonatomic, copy) PanelActionBlock pauseBlock;
@property (nonatomic, copy) PanelActionBlock saveBlock;
@property (nonatomic, copy) PanelActionBlock scriptManagerBlock;
@property (nonatomic, copy) PanelActionBlock showLogsBlock;

+ (instancetype)sharedInstance;

- (void)show;
- (void)hide;
- (void)toggleVisibility;
- (void)updateRecordingState:(BOOL)isRecording;
- (void)updatePlaybackState:(BOOL)isPlaying isPaused:(BOOL)isPaused;
- (void)updateProgress:(NSUInteger)currentIndex totalCount:(NSUInteger)totalCount;

@end