#import "AdvancedFeatures.h"
#import <ImageIO/ImageIO.h>

@interface AdvancedFeatures ()

@property (nonatomic, strong) NSMutableArray *scheduledTimers;

@end

@implementation AdvancedFeatures

+ (instancetype)sharedInstance {
    static AdvancedFeatures *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AdvancedFeatures alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _scheduledTimers = [NSMutableArray array];
        _isScheduledTaskRunning = NO;
    }
    return self;
}

- (void)scheduleTaskAtTime:(NSDate *)date block:(ScheduledTaskBlock)block {
    NSTimeInterval delay = [date timeIntervalSinceNow];
    if (delay < 0) delay = 0;
    [self scheduleTaskAfterDelay:delay block:block];
}

- (void)scheduleTaskAfterDelay:(NSTimeInterval)delay block:(ScheduledTaskBlock)block {
    __weak __typeof(self) weakSelf = self;
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:delay repeats:NO block:^(NSTimer *timer) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        strongSelf->_isScheduledTaskRunning = YES;
        if (block) {
            block();
        }
        strongSelf->_isScheduledTaskRunning = NO;
        [strongSelf->_scheduledTimers removeObject:timer];
    }];
    [_scheduledTimers addObject:timer];
}

- (void)cancelAllScheduledTasks {
    for (NSTimer *timer in _scheduledTimers) {
        [timer invalidate];
    }
    [_scheduledTimers removeAllObjects];
}

- (UIImage *)captureScreen {
    return [self captureRegion:[UIScreen mainScreen].bounds];
}

- (UIImage *)captureRegion:(CGRect)region {
    UIGraphicsBeginImageContextWithOptions(region.size, NO, [UIScreen mainScreen].scale);
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextTranslateCTM(context, -region.origin.x, -region.origin.y);
    
    [[UIApplication sharedApplication].keyWindow drawViewHierarchyInRect:[UIScreen mainScreen].bounds afterScreenUpdates:YES];
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return image;
}

- (UIColor *)getColorAtPoint:(CGPoint)point {
    UIImage *image = [self captureScreen];
    if (!image) return nil;
    
    CGImageRef imageRef = image.CGImage;
    NSUInteger width = CGImageGetWidth(imageRef);
    NSUInteger height = CGImageGetHeight(imageRef);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    unsigned char *rawData = (unsigned char *)calloc(height * width * 4, sizeof(unsigned char));
    
    NSUInteger bytesPerPixel = 4;
    NSUInteger bytesPerRow = bytesPerPixel * width;
    NSUInteger bitsPerComponent = 8;
    
    CGContextRef context = CGBitmapContextCreate(rawData, width, height, bitsPerComponent, bytesPerRow, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    
    CGColorSpaceRelease(colorSpace);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), imageRef);
    CGContextRelease(context);
    
    NSUInteger byteIndex = (bytesPerRow * (NSUInteger)point.y) + (NSUInteger)point.x * bytesPerPixel;
    CGFloat red = (CGFloat)rawData[byteIndex] / 255.0;
    CGFloat green = (CGFloat)rawData[byteIndex + 1] / 255.0;
    CGFloat blue = (CGFloat)rawData[byteIndex + 2] / 255.0;
    CGFloat alpha = (CGFloat)rawData[byteIndex + 3] / 255.0;
    
    free(rawData);
    
    return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
}

- (BOOL)compareColors:(UIColor *)color1 withColor:(UIColor *)color2 tolerance:(CGFloat)tolerance {
    if (!color1 || !color2) return NO;
    
    CGFloat r1, g1, b1, a1;
    CGFloat r2, g2, b2, a2;
    
    [color1 getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
    [color2 getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
    
    CGFloat diffR = fabs(r1 - r2);
    CGFloat diffG = fabs(g1 - g2);
    CGFloat diffB = fabs(b1 - b2);
    CGFloat diffA = fabs(a1 - a2);
    
    return (diffR <= tolerance && diffG <= tolerance && diffB <= tolerance && diffA <= tolerance);
}

- (BOOL)detectColor:(UIColor *)targetColor atPoint:(CGPoint)point tolerance:(CGFloat)tolerance {
    UIColor *pointColor = [self getColorAtPoint:point];
    return [self compareColors:pointColor withColor:targetColor tolerance:tolerance];
}

- (CGPoint)findColorOnScreen:(UIColor *)targetColor tolerance:(CGFloat)tolerance {
    UIImage *image = [self captureScreen];
    if (!image) return CGPointMake(-1, -1);
    
    CGImageRef imageRef = image.CGImage;
    NSUInteger width = CGImageGetWidth(imageRef);
    NSUInteger height = CGImageGetHeight(imageRef);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    unsigned char *rawData = (unsigned char *)calloc(height * width * 4, sizeof(unsigned char));
    
    NSUInteger bytesPerPixel = 4;
    NSUInteger bytesPerRow = bytesPerPixel * width;
    NSUInteger bitsPerComponent = 8;
    
    CGContextRef context = CGBitmapContextCreate(rawData, width, height, bitsPerComponent, bytesPerRow, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    
    CGColorSpaceRelease(colorSpace);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), imageRef);
    CGContextRelease(context);
    
    CGFloat tr, tg, tb, ta;
    [targetColor getRed:&tr green:&tg blue:&tb alpha:&ta];
    
    for (NSUInteger y = 0; y < height; y++) {
        for (NSUInteger x = 0; x < width; x++) {
            NSUInteger byteIndex = (bytesPerRow * y) + x * bytesPerPixel;
            CGFloat r = (CGFloat)rawData[byteIndex] / 255.0;
            CGFloat g = (CGFloat)rawData[byteIndex + 1] / 255.0;
            CGFloat b = (CGFloat)rawData[byteIndex + 2] / 255.0;
            CGFloat a = (CGFloat)rawData[byteIndex + 3] / 255.0;
            
            if (fabs(r - tr) <= tolerance && fabs(g - tg) <= tolerance && 
                fabs(b - tb) <= tolerance && fabs(a - ta) <= tolerance) {
                free(rawData);
                return CGPointMake((CGFloat)x / [UIScreen mainScreen].scale, 
                                   (CGFloat)y / [UIScreen mainScreen].scale);
            }
        }
    }
    
    free(rawData);
    return CGPointMake(-1, -1);
}

- (void)asyncFindColorOnScreen:(UIColor *)targetColor tolerance:(CGFloat)tolerance completion:(ColorDetectionBlock)completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        CGPoint position = [self findColorOnScreen:targetColor tolerance:tolerance];
        BOOL found = position.x >= 0 && position.y >= 0;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(found, position);
            }
        });
    });
}

- (BOOL)waitForColor:(UIColor *)targetColor timeout:(NSTimeInterval)timeout tolerance:(CGFloat)tolerance {
    NSDate *startTime = [NSDate date];
    
    while ([[NSDate date] timeIntervalSinceDate:startTime] < timeout) {
        CGPoint position = [self findColorOnScreen:targetColor tolerance:tolerance];
        if (position.x >= 0 && position.y >= 0) {
            return YES;
        }
        usleep(100000);
    }
    
    return NO;
}

- (BOOL)waitForText:(NSString *)text timeout:(NSTimeInterval)timeout {
    NSDate *startTime = [NSDate date];
    
    while ([[NSDate date] timeIntervalSinceDate:startTime] < timeout) {
        UIImage *screen = [self captureScreen];
        NSString *ocrText = [self performOCRWithImage:screen language:OCRLanguageEnglish];
        
        if ([ocrText rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
        usleep(500000);
    }
    
    return NO;
}

- (NSString *)performOCRWithImage:(UIImage *)image language:(OCRLanguage)language {
    if (!image) return @"";
    
    NSString *langCode = @"en-US";
    switch (language) {
        case OCRLanguageChineseSimplified:
            langCode = @"zh-Hans";
            break;
        case OCRLanguageChineseTraditional:
            langCode = @"zh-Hant";
            break;
        case OCRLanguageJapanese:
            langCode = @"ja-JP";
            break;
        case OCRLanguageKorean:
            langCode = @"ko-KR";
            break;
        default:
            langCode = @"en-US";
    }
    
    (void)langCode;
    return @"OCR result placeholder";
}

- (void)asyncPerformOCRWithImage:(UIImage *)image language:(OCRLanguage)language completion:(OCRResultBlock)completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *text = [self performOCRWithImage:image language:language];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(text, nil);
            }
        });
    });
}

- (NSArray *)parseScriptFromString:(NSString *)scriptString {
    NSMutableArray *actions = [NSMutableArray array];
    
    NSArray *lines = [scriptString componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSString *trimmedLine = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmedLine.length == 0 || [trimmedLine hasPrefix:@"//"]) continue;
        
        NSArray *parts = [trimmedLine componentsSeparatedByString:@" "];
        if (parts.count < 1) continue;
        
        NSString *command = parts[0];
        NSMutableDictionary *action = [NSMutableDictionary dictionaryWithObject:command forKey:@"command"];
        
        if ([command isEqualToString:@"tap"]) {
            if (parts.count >= 3) {
                action[@"x"] = @([parts[1] doubleValue]);
                action[@"y"] = @([parts[2] doubleValue]);
            }
        } else if ([command isEqualToString:@"delay"]) {
            if (parts.count >= 2) {
                action[@"time"] = @([parts[1] doubleValue]);
            }
        } else if ([command isEqualToString:@"swipe"]) {
            if (parts.count >= 5) {
                action[@"x1"] = @([parts[1] doubleValue]);
                action[@"y1"] = @([parts[2] doubleValue]);
                action[@"x2"] = @([parts[3] doubleValue]);
                action[@"y2"] = @([parts[4] doubleValue]);
            }
        } else if ([command isEqualToString:@"waitForColor"]) {
            if (parts.count >= 5) {
                action[@"r"] = @([parts[1] doubleValue]);
                action[@"g"] = @([parts[2] doubleValue]);
                action[@"b"] = @([parts[3] doubleValue]);
                action[@"timeout"] = @([parts[4] doubleValue]);
            }
        } else if ([command isEqualToString:@"waitForText"]) {
            action[@"text"] = [trimmedLine substringFromIndex:[trimmedLine rangeOfString:@" "].location + 1];
        }
        
        [actions addObject:action];
    }
    
    return actions;
}

- (BOOL)executeScript:(NSArray *)scriptActions {
    for (NSDictionary *action in scriptActions) {
        NSString *command = action[@"command"];
        
        if ([command isEqualToString:@"tap"]) {
            CGPoint point = CGPointMake([action[@"x"] doubleValue], [action[@"y"] doubleValue]);
            [self performSelector:@selector(simulateTap:) withObject:[NSValue valueWithCGPoint:point] afterDelay:0];
        } else if ([command isEqualToString:@"delay"]) {
            NSTimeInterval delay = [action[@"time"] doubleValue];
            usleep((useconds_t)(delay * 1000000));
        } else if ([command isEqualToString:@"swipe"]) {
            CGPoint from = CGPointMake([action[@"x1"] doubleValue], [action[@"y1"] doubleValue]);
            CGPoint to = CGPointMake([action[@"x2"] doubleValue], [action[@"y2"] doubleValue]);
            [self simulateSwipe:[NSValue valueWithCGPoint:from] to:[NSValue valueWithCGPoint:to]];
        } else if ([command isEqualToString:@"waitForColor"]) {
            UIColor *color = [UIColor colorWithRed:[action[@"r"] doubleValue] green:[action[@"g"] doubleValue] blue:[action[@"b"] doubleValue] alpha:1.0];
            NSTimeInterval timeout = [action[@"timeout"] doubleValue];
            [self waitForColor:color timeout:timeout tolerance:0.1];
        } else if ([command isEqualToString:@"waitForText"]) {
            NSString *text = action[@"text"];
            [self waitForText:text timeout:10.0];
        }
        
        usleep(10000);
    }
    
    return YES;
}

- (void)simulateTap:(NSValue *)pointValue {
    CGPoint point = [pointValue CGPointValue];
    (void)point;
    [[UIApplication sharedApplication] sendAction:@selector(touchesBegan:withEvent:) to:nil from:nil forEvent:nil];
}

- (void)simulateSwipe:(NSValue *)fromValue to:(NSValue *)toValue {
    
}

@end