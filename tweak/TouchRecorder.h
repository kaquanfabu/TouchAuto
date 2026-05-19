#import <Foundation/Foundation.h>
#import "TouchEvent.h"

typedef void (^RecordingStateChangeBlock)(BOOL isRecording);
typedef void (^EventRecordedBlock)(TouchEvent *event);

@interface TouchRecorder : NSObject

@property (nonatomic, assign, readonly) BOOL isRecording;
@property (nonatomic, strong, readonly) NSArray<TouchEvent *> *recordedEvents;
@property (nonatomic, assign) NSTimeInterval longPressThreshold;
@property (nonatomic, copy) RecordingStateChangeBlock stateChangeBlock;
@property (nonatomic, copy) EventRecordedBlock eventRecordedBlock;

+ (instancetype)sharedInstance;

- (void)startRecording;
- (void)stopRecording;
- (void)clearRecording;
- (void)recordEvent:(TouchEvent *)event;
- (BOOL)saveToFile:(NSString *)path error:(NSError **)error;
- (BOOL)loadFromFile:(NSString *)path error:(NSError **)error;
- (NSData *)toJSONData;
- (BOOL)fromJSONData:(NSData *)data;

@end