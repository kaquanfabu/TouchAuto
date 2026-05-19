#import "TouchRecorder.h"
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>

@interface TouchRecorder ()

@property (nonatomic, assign) BOOL isRecording;
@property (nonatomic, strong) NSMutableArray<TouchEvent *> *recordedEvents;
@property (nonatomic, assign) NSTimeInterval recordingStartTime;
@property (nonatomic, strong) NSMutableDictionary *touchStartTimes;
@property (nonatomic, strong) MPVolumeView *volumeView;

@end

@implementation TouchRecorder

+ (instancetype)sharedInstance {
    static TouchRecorder *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[TouchRecorder alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _recordedEvents = [NSMutableArray array];
        _touchStartTimes = [NSMutableDictionary dictionary];
        _longPressThreshold = 0.5;
        _isRecording = NO;
        
        [self setupVolumeListener];
    }
    return self;
}

- (void)setupVolumeListener {
    _volumeView = [[MPVolumeView alloc] init];
    _volumeView.hidden = YES;
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(handleVolumeChanged:) 
                                                 name:@"AVSystemController_SystemVolumeDidChangeNotification" 
                                               object:nil];
}

- (void)handleVolumeChanged:(NSNotification *)notification {
    if (!_isRecording) return;
    
    NSDictionary *userInfo = notification.userInfo;
    if (!userInfo) return;
    
    NSNumber *reason = userInfo[@"AVSystemController_AudioVolumeChangeReasonNotificationParameter"];
    if (!reason) return;
    
    NSInteger reasonValue = [reason integerValue];
    
    if (reasonValue == 1 || reasonValue == 0) {
        NSNumber *volume = userInfo[@"AVSystemController_AudioVolumeNotificationParameter"];
        if (volume) {
            NSLog(@"[TouchRecorder] Volume changed to %f, reason: %ld", [volume floatValue], (long)reasonValue);
            
            static float lastVolume = -1;
            if (lastVolume >= 0 && [volume floatValue] < lastVolume) {
                NSLog(@"[TouchRecorder] Volume down pressed, stopping recording...");
                [self stopRecording];
            }
            lastVolume = [volume floatValue];
        }
    }
}

- (void)startRecording {
    if (_isRecording) return;
    
    _isRecording = YES;
    _recordingStartTime = [[NSDate date] timeIntervalSince1970];
    [_recordedEvents removeAllObjects];
    [_touchStartTimes removeAllObjects];
    
    if (_stateChangeBlock) {
        _stateChangeBlock(YES);
    }
}

- (void)stopRecording {
    if (!_isRecording) return;
    
    _isRecording = NO;
    
    if (_stateChangeBlock) {
        _stateChangeBlock(NO);
    }
}

- (void)clearRecording {
    [_recordedEvents removeAllObjects];
    [_touchStartTimes removeAllObjects];
}

- (void)addEvent:(TouchEvent *)event {
    [_recordedEvents addObject:event];
}

- (void)recordEvent:(TouchEvent *)event {
    if (!_isRecording) return;
    
    NSLog(@"[TouchRecorder] Recording event: %@", event);
    
    NSTimeInterval eventDelay = event.timestamp - _recordingStartTime;
    if (_recordedEvents.count > 0) {
        TouchEvent *lastEvent = _recordedEvents.lastObject;
        eventDelay = event.timestamp - lastEvent.timestamp;
    }
    event.delay = eventDelay;
    
    NSNumber *touchID = event.touchIdentifier ?: @0;
    
    if (event.type == TouchEventTypeBegan) {
        _touchStartTimes[touchID] = @(event.timestamp);
    } else if (event.type == TouchEventTypeEnded || event.type == TouchEventTypeCancelled) {
        NSNumber *startTimeNum = _touchStartTimes[touchID];
        if (startTimeNum) {
            NSTimeInterval duration = event.timestamp - [startTimeNum doubleValue];
            if (duration >= _longPressThreshold) {
                event.isLongPress = YES;
                event.longPressDuration = duration;
            }
            [_touchStartTimes removeObjectForKey:touchID];
        }
    }
    
    [_recordedEvents addObject:event];
    NSLog(@"[TouchRecorder] Total events: %lu", (unsigned long)_recordedEvents.count);
    
    if (_eventRecordedBlock) {
        _eventRecordedBlock(event);
    }
}

- (BOOL)saveToFile:(NSString *)path error:(NSError **)error {
    NSData *jsonData = [self toJSONData];
    if (!jsonData) {
        if (error) {
            *error = [NSError errorWithDomain:@"TouchRecorder" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to serialize events"}];
        }
        return NO;
    }
    return [jsonData writeToFile:path options:NSDataWritingAtomic error:error];
}

- (BOOL)loadFromFile:(NSString *)path error:(NSError **)error {
    NSData *jsonData = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:error];
    if (!jsonData) return NO;
    return [self fromJSONData:jsonData];
}

- (NSData *)toJSONData {
    NSMutableArray *dictArray = [NSMutableArray array];
    for (TouchEvent *event in _recordedEvents) {
        [dictArray addObject:event.toDictionary];
    }
    
    NSDictionary *rootDict = @{
        @"version": @"1.0",
        @"recordedAt": @([[NSDate date] timeIntervalSince1970]),
        @"eventCount": @(dictArray.count),
        @"events": dictArray
    };
    
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:rootDict options:NSJSONWritingPrettyPrinted error:&error];
    return error ? nil : jsonData;
}

- (BOOL)fromJSONData:(NSData *)data {
    NSError *error = nil;
    NSDictionary *rootDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error) return NO;
    
    NSArray *eventsArray = rootDict[@"events"];
    if (![eventsArray isKindOfClass:[NSArray class]]) return NO;
    
    [_recordedEvents removeAllObjects];
    for (NSDictionary *eventDict in eventsArray) {
        TouchEvent *event = [TouchEvent fromDictionary:eventDict];
        if (event) {
            [_recordedEvents addObject:event];
        }
    }
    
    return YES;
}

@end