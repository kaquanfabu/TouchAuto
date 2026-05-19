#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TouchEventType) {
    TouchEventTypeBegan,
    TouchEventTypeMoved,
    TouchEventTypeEnded,
    TouchEventTypeCancelled
};

@interface TouchEvent : NSObject <NSCoding, NSSecureCoding>

@property (nonatomic, assign) NSTimeInterval timestamp;
@property (nonatomic, assign) NSTimeInterval delay;
@property (nonatomic, assign) TouchEventType type;
@property (nonatomic, assign) CGPoint location;
@property (nonatomic, assign) CGPoint previousLocation;
@property (nonatomic, assign) NSUInteger tapCount;
@property (nonatomic, assign) BOOL isLongPress;
@property (nonatomic, assign) NSTimeInterval longPressDuration;
@property (nonatomic, strong) NSNumber *touchIdentifier;
@property (nonatomic, assign) CGFloat pressure;
@property (nonatomic, assign) CGRect bounds;

- (instancetype)initWithTouch:(UITouch *)touch event:(UIEvent *)event;
- (NSDictionary *)toDictionary;
+ (TouchEvent *)fromDictionary:(NSDictionary *)dict;

@end