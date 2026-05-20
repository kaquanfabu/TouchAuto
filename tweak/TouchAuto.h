#import <UIKit/UIKit.h>

@interface TouchAuto : NSObject

+ (NSArray *)cachedTouches;
+ (NSArray *)cachedEvents;
+ (void)clearCachedObjects;
+ (UIWindow *)getKeyWindow;

@end
