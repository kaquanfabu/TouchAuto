#import <Foundation/Foundation.h>
#import "TouchEvent.h"

typedef void (^PlaybackStateChangeBlock)(BOOL isPlaying);
typedef void (^PlaybackCompleteBlock)(void);
typedef void (^PlaybackProgressBlock)(NSUInteger currentIndex, NSUInteger totalCount);

@interface TouchPlayer : NSObject

@property (nonatomic, assign, readonly) BOOL isPlaying;
@property (nonatomic, assign, readonly) BOOL isPaused;
@property (nonatomic, assign) NSUInteger loopCount;
@property (nonatomic, assign) NSUInteger currentLoop;
@property (nonatomic, assign) CGFloat playbackSpeed;
@property (nonatomic, assign) CGFloat randomOffset;
@property (nonatomic, assign) NSTimeInterval randomDelayRange;
@property (nonatomic, assign) NSTimeInterval waitTimeAfterFinish; // 播放完成后等待时间（秒）
@property (nonatomic, copy) PlaybackStateChangeBlock stateChangeBlock;
@property (nonatomic, copy) PlaybackCompleteBlock completeBlock;
@property (nonatomic, copy) PlaybackProgressBlock progressBlock;

+ (instancetype)sharedInstance;

- (void)setEvents:(NSArray<TouchEvent *> *)events;
- (void)play;
- (void)pause;
- (void)stop;
- (void)setLoopCount:(NSUInteger)count;
- (void)setInfiniteLoop:(BOOL)infinite;
- (NSString *)getLogs;
- (void)clearLogs;

@end