#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TouchInjectManager : NSObject

+ (instancetype)sharedInstance;

- (void)tapAtPoint:(CGPoint)point;
- (void)longPressAtPoint:(CGPoint)point duration:(NSTimeInterval)duration;
- (void)swipeFrom:(CGPoint)startPoint to:(CGPoint)endPoint duration:(NSTimeInterval)duration;
- (void)touchDown:(CGPoint)point;
- (void)touchMove:(CGPoint)point;
- (void)touchUp:(CGPoint)point;

@end

NS_ASSUME_NONNULL_END
