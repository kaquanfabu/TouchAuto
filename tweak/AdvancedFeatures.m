#import "AdvancedFeatures.h"
#import <ImageIO/ImageIO.h>
#import <WebKit/WebKit.h>

@interface AdvancedFeatures ()

@property (nonatomic, strong) NSMutableArray *scheduledTimers;

// iOS 18 WebView 私有方法
- (NSString *)buildClickScriptForStrategy:(WebViewClickStrategy)strategy atPoint:(CGPoint)point webView:(WKWebView *)webView;
- (NSString *)buildAutoClickScript:(CGPoint)point;
- (NSString *)buildMouseEventScript:(CGPoint)point;
- (NSString *)buildPointerEventScript:(CGPoint)point;
- (NSString *)buildTouchEventScript:(CGPoint)point;
- (WKWebView *)findWebViewInHierarchy:(UIView *)view;

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
            [self triggerTouchAtLocation:point];
        } else if ([command isEqualToString:@"delay"]) {
            NSTimeInterval delay = [action[@"time"] doubleValue];
            usleep((useconds_t)(delay * 1000000));
        } else if ([command isEqualToString:@"swipe"]) {
            CGPoint from = CGPointMake([action[@"x1"] doubleValue], [action[@"y1"] doubleValue]);
            CGPoint to = CGPointMake([action[@"x2"] doubleValue], [action[@"y2"] doubleValue]);
            [self triggerSwipeFrom:from to:to];
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

- (void)triggerTouchAtLocation:(CGPoint)location {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [self getKeyWindow];
        if (!keyWindow) {
            NSLog(@"[AdvancedFeatures] No key window found");
            return;
        }
        
        UIView *hitView = [keyWindow hitTest:location withEvent:nil];
        if (!hitView) {
            NSLog(@"[AdvancedFeatures] No view found at location (%f, %f)", location.x, location.y);
            return;
        }
        
        NSLog(@"[AdvancedFeatures] Hit view: %@", hitView);
        
        [self triggerActionForView:hitView atLocation:location];
    });
}

- (void)triggerActionForView:(UIView *)view atLocation:(CGPoint)location {
    if ([self triggerUIButtonAction:view]) {
        NSLog(@"[AdvancedFeatures] Triggered UIButton action");
        return;
    }
    
    if ([self triggerUIControlAction:view]) {
        NSLog(@"[AdvancedFeatures] Triggered UIControl action");
        return;
    }
    
    if ([self triggerUITableViewAction:view atLocation:location]) {
        NSLog(@"[AdvancedFeatures] Triggered UITableView action");
        return;
    }
    
    if ([self triggerUICollectionViewAction:view atLocation:location]) {
        NSLog(@"[AdvancedFeatures] Triggered UICollectionView action");
        return;
    }
    
    if ([self triggerWKWebViewAction:view atLocation:location]) {
        NSLog(@"[AdvancedFeatures] Triggered WKWebView action");
        return;
    }
    
    if (view.superview) {
        [self triggerActionForView:view.superview atLocation:location];
    }
}

- (BOOL)triggerUIButtonAction:(UIView *)view {
    if (![view isKindOfClass:[UIButton class]]) {
        return NO;
    }
    
    UIButton *button = (UIButton *)view;
    [button sendActionsForControlEvents:UIControlEventTouchUpInside];
    return YES;
}

- (BOOL)triggerUIControlAction:(UIView *)view {
    if (![view isKindOfClass:[UIControl class]]) {
        return NO;
    }
    
    UIControl *control = (UIControl *)view;
    [control sendActionsForControlEvents:UIControlEventTouchUpInside];
    [control sendActionsForControlEvents:UIControlEventValueChanged];
    return YES;
}

- (BOOL)triggerUITableViewAction:(UIView *)view atLocation:(CGPoint)location {
    UIView *superview = view;
    UITableView *tableView = nil;
    
    while (superview) {
        if ([superview isKindOfClass:[UITableView class]]) {
            tableView = (UITableView *)superview;
            break;
        }
        superview = superview.superview;
    }
    
    if (!tableView) {
        return NO;
    }
    
    CGPoint tableViewLocation = [tableView convertPoint:location fromView:view];
    NSIndexPath *indexPath = [tableView indexPathForRowAtPoint:tableViewLocation];
    if (!indexPath) {
        return NO;
    }
    
    if ([tableView.delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) {
        [tableView.delegate tableView:tableView didSelectRowAtIndexPath:indexPath];
        return YES;
    }
    
    [tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
    return YES;
}

- (BOOL)triggerUICollectionViewAction:(UIView *)view atLocation:(CGPoint)location {
    UIView *superview = view;
    UICollectionView *collectionView = nil;
    
    while (superview) {
        if ([superview isKindOfClass:[UICollectionView class]]) {
            collectionView = (UICollectionView *)superview;
            break;
        }
        superview = superview.superview;
    }
    
    if (!collectionView) {
        return NO;
    }
    
    CGPoint collectionViewLocation = [collectionView convertPoint:location fromView:view];
    NSIndexPath *indexPath = [collectionView indexPathForItemAtPoint:collectionViewLocation];
    if (!indexPath) {
        return NO;
    }
    
    if ([collectionView.delegate respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) {
        [collectionView.delegate collectionView:collectionView didSelectItemAtIndexPath:indexPath];
        return YES;
    }
    
    [collectionView selectItemAtIndexPath:indexPath animated:NO scrollPosition:UICollectionViewScrollPositionNone];
    return YES;
}

- (BOOL)triggerWKWebViewAction:(UIView *)view atLocation:(CGPoint)location {
    UIView *superview = view;
    WKWebView *webView = nil;
    
    while (superview) {
        if ([superview isKindOfClass:[WKWebView class]]) {
            webView = (WKWebView *)superview;
            break;
        }
        superview = superview.superview;
    }
    
    if (!webView) {
        return NO;
    }
    
    NSLog(@"[AdvancedFeatures] iOS 18 triggering WKWebView action");
    NSLog(@"[AdvancedFeatures] Input location: (%.2f, %.2f)", location.x, location.y);
    NSLog(@"[AdvancedFeatures] WKWebView frame: %@", NSStringFromCGRect(webView.frame));
    
    // 获取 WebView 在 window 中的位置
    CGRect webViewBoundsInWindow = [webView convertRect:webView.bounds toView:nil];
    NSLog(@"[AdvancedFeatures] WKWebView bounds in window: %@", NSStringFromCGRect(webViewBoundsInWindow));
    
    // 计算相对于 webView 内部的坐标
    CGPoint webViewLocation = location;
    if (CGRectContainsPoint(webViewBoundsInWindow, location)) {
        webViewLocation.x = location.x - webViewBoundsInWindow.origin.x;
        webViewLocation.y = location.y - webViewBoundsInWindow.origin.y;
        
        // 考虑 scroll offset
        UIScrollView *scrollView = webView;
        if ([webView isKindOfClass:[UIScrollView class]]) {
            scrollView = (UIScrollView *)webView;
            webViewLocation.x += scrollView.contentOffset.x;
            webViewLocation.y += scrollView.contentOffset.y;
        }
        
        NSLog(@"[AdvancedFeatures] Adjusted webView location: (%.2f, %.2f)", webViewLocation.x, webViewLocation.y);
    }
    
    // iOS 18 使用增强的 JavaScript 点击策略
    NSString *javascript = [self buildAutoClickScript:webViewLocation];
    
    [webView evaluateJavaScript:javascript completionHandler:^(id result, NSError *error) {
        if (error) {
            NSLog(@"[AdvancedFeatures] iOS 18 WKWebView JavaScript error: %@", error);
            // 降级到简单的 click() 方法
            NSString *fallbackScript = [NSString stringWithFormat:
                @"var e=document.elementFromPoint(%f,%f);if(e)e.click();", 
                webViewLocation.x, webViewLocation.y];
            [webView evaluateJavaScript:fallbackScript completionHandler:nil];
        } else {
            NSLog(@"[AdvancedFeatures] iOS 18 WKWebView JavaScript executed: %@", result);
        }
    }];
    
    return YES;
}

- (void)triggerSwipeFrom:(CGPoint)from to:(CGPoint)to {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [self getKeyWindow];
        if (!keyWindow) {
            NSLog(@"[AdvancedFeatures] No key window found");
            return;
        }
        
        UIScrollView *scrollView = [self findScrollViewInHierarchy:keyWindow];
        if (scrollView) {
            CGPoint contentOffset = scrollView.contentOffset;
            contentOffset.x += (from.x - to.x);
            contentOffset.y += (from.y - to.y);
            
            [scrollView setContentOffset:contentOffset animated:YES];
            NSLog(@"[AdvancedFeatures] Swiped scrollView");
        } else {
            NSLog(@"[AdvancedFeatures] No scrollView found for swipe");
        }
    });
}

- (UIScrollView *)findScrollViewInHierarchy:(UIView *)view {
    if ([view isKindOfClass:[UIScrollView class]] && 
        ![view isKindOfClass:[UITableView class]] && 
        ![view isKindOfClass:[UICollectionView class]]) {
        return (UIScrollView *)view;
    }
    
    for (UIView *subview in view.subviews) {
        UIScrollView *scrollView = [self findScrollViewInHierarchy:subview];
        if (scrollView) {
            return scrollView;
        }
    }
    
    return nil;
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
    
    return keyWindow;
}

- (void)dealloc {
    [self cancelAllScheduledTasks];
}

#pragma mark - iOS 18 WebView 高级功能

- (BOOL)clickWebViewElementAtPoint:(CGPoint)point strategy:(WebViewClickStrategy)strategy {
    WKWebView *webView = [self findFrontWebView];
    if (!webView) {
        NSLog(@"[AdvancedFeatures] No WebView found for iOS 18 click");
        return NO;
    }
    
    NSLog(@"[AdvancedFeatures] iOS 18 WebView click at (%.2f, %.2f), strategy: %ld", point.x, point.y, (long)strategy);
    
    NSString *javascript = [self buildClickScriptForStrategy:strategy atPoint:point webView:webView];
    
    __block BOOL success = NO;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [webView evaluateJavaScript:javascript completionHandler:^(id result, NSError *error) {
        if (error) {
            NSLog(@"[AdvancedFeatures] iOS 18 WebView click failed: %@", error);
        } else {
            NSLog(@"[AdvancedFeatures] iOS 18 WebView click succeeded, result: %@", result);
            success = YES;
        }
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)));
    
    return success;
}

- (NSString *)buildClickScriptForStrategy:(WebViewClickStrategy)strategy atPoint:(CGPoint)point webView:(WKWebView *)webView {
    CGPoint webViewPoint = [webView convertPoint:point fromView:nil];
    
    switch (strategy) {
        case WebViewClickStrategyAuto:
            return [self buildAutoClickScript:webViewPoint];
        case WebViewClickStrategyClick:
            return [NSString stringWithFormat:
                @"var e=document.elementFromPoint(%f,%f);if(e)e.click();", 
                webViewPoint.x, webViewPoint.y];
        case WebViewClickStrategyMouseEvent:
            return [self buildMouseEventScript:webViewPoint];
        case WebViewClickStrategyPointerEvent:
            return [self buildPointerEventScript:webViewPoint];
        case WebViewClickStrategyTouchEvent:
            return [self buildTouchEventScript:webViewPoint];
    }
}

- (NSString *)buildAutoClickScript:(CGPoint)point {
    return [NSString stringWithFormat:
        @"(function(){"
        "   var x=%f,y=%f,e=document.elementFromPoint(x,y);"
        "   if(!e)return {success:false};"
        "   try{"
        "       var t=new PointerEvent('pointerdown',{bubbles:true,cancelable:true,view:window,clientX:x,clientY:y,pointerType:'touch'});"
        "       e.dispatchEvent(t);"
        "       var p=new PointerEvent('pointerup',{bubbles:true,cancelable:true,view:window,clientX:x,clientY:y,pointerType:'touch'});"
        "       e.dispatchEvent(p);"
        "   }catch(a){"
        "       try{"
        "           var m=new MouseEvent('click',{bubbles:true,cancelable:true,view:window,clientX:x,clientY:y});"
        "           e.dispatchEvent(m);"
        "       }catch(b){"
        "           if(e.click)e.click();"
        "       }"
        "   }"
        "   return {success:true};"
        "})();", 
        point.x, point.y];
}

- (NSString *)buildMouseEventScript:(CGPoint)point {
    return [NSString stringWithFormat:
        @"(function(){"
        "   var x=%f,y=%f,e=document.elementFromPoint(x,y);"
        "   if(!e)return {success:false};"
        "   var m=new MouseEvent('click',{bubbles:true,cancelable:true,view:window,clientX:x,clientY:y});"
        "   e.dispatchEvent(m);"
        "   return {success:true};"
        "})();", 
        point.x, point.y];
}

- (NSString *)buildPointerEventScript:(CGPoint)point {
    return [NSString stringWithFormat:
        @"(function(){"
        "   var x=%f,y=%f,e=document.elementFromPoint(x,y);"
        "   if(!e)return {success:false};"
        "   var d=new PointerEvent('pointerdown',{bubbles:true,cancelable:true,view:window,clientX:x,clientY:y,pointerType:'touch'});"
        "   e.dispatchEvent(d);"
        "   var u=new PointerEvent('pointerup',{bubbles:true,cancelable:true,view:window,clientX:x,clientY:y,pointerType:'touch'});"
        "   e.dispatchEvent(u);"
        "   return {success:true};"
        "})();", 
        point.x, point.y];
}

- (NSString *)buildTouchEventScript:(CGPoint)point {
    return [NSString stringWithFormat:
        @"(function(){"
        "   var x=%f,y=%f,e=document.elementFromPoint(x,y);"
        "   if(!e)return {success:false};"
        "   var t=new Touch({target:e,clientX:x,clientY:y});"
        "   var ts=new TouchEvent('touchstart',{touches:[t],targetTouches:[t],changedTouches:[t],bubbles:true});"
        "   e.dispatchEvent(ts);"
        "   var te=new TouchEvent('touchend',{touches:[],targetTouches:[],changedTouches:[t],bubbles:true});"
        "   e.dispatchEvent(te);"
        "   return {success:true};"
        "})();", 
        point.x, point.y];
}

- (BOOL)executeWebViewJavaScript:(NSString *)script completion:(WebViewJSCompletion)completion {
    WKWebView *webView = [self findFrontWebView];
    if (!webView) {
        NSLog(@"[AdvancedFeatures] No WebView found for iOS 18 JS execution");
        if (completion) completion(nil, [NSError errorWithDomain:@"AdvancedFeatures" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"No WebView found"}]);
        return NO;
    }
    
    NSLog(@"[AdvancedFeatures] iOS 18 executing JavaScript: %@", script);
    
    [webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (error) {
            NSLog(@"[AdvancedFeatures] iOS 18 JS execution failed: %@", error);
        } else {
            NSLog(@"[AdvancedFeatures] iOS 18 JS execution succeeded, result: %@", result);
        }
        if (completion) completion(result, error);
    }];
    
    return YES;
}

- (BOOL)fillWebViewInput:(NSString *)selector text:(NSString *)text {
    WKWebView *webView = [self findFrontWebView];
    if (!webView) {
        NSLog(@"[AdvancedFeatures] No WebView found for iOS 18 input fill");
        return NO;
    }
    
    // 转义反斜杠
    NSString *escapedText = [text stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    // 转义单引号
    escapedText = [escapedText stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
    // 转义双引号
    escapedText = [escapedText stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    
    NSString *javascript = [NSString stringWithFormat:
        @"(function(){"
        "   var e=document.querySelector('%@');"
        "   if(!e)return {success:false,error:'Element not found'};"
        "   e.value='%@';"
        "   e.dispatchEvent(new Event('input',{bubbles:true}));"
        "   e.dispatchEvent(new Event('change',{bubbles:true}));"
        "   return {success:true};"
        "})();", 
        selector, escapedText];
    
    __block BOOL success = NO;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [webView evaluateJavaScript:javascript completionHandler:^(id result, NSError *error) {
        success = (error == nil && [result isKindOfClass:[NSDictionary class]] && [result[@"success"] boolValue]);
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)));
    
    return success;
}

- (NSString *)getWebViewElementText:(NSString *)selector {
    WKWebView *webView = [self findFrontWebView];
    if (!webView) {
        NSLog(@"[AdvancedFeatures] No WebView found for iOS 18 text get");
        return nil;
    }
    
    NSString *javascript = [NSString stringWithFormat:
        @"(function(){"
        "   var e=document.querySelector('%@');"
        "   return e?e.textContent:null;"
        "})();", 
        selector];
    
    __block NSString *text = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [webView evaluateJavaScript:javascript completionHandler:^(id result, NSError *error) {
        if (!error && [result isKindOfClass:[NSString class]]) {
            text = result;
        }
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)));
    
    return text;
}

- (BOOL)scrollWebViewToElement:(NSString *)selector {
    WKWebView *webView = [self findFrontWebView];
    if (!webView) {
        NSLog(@"[AdvancedFeatures] No WebView found for iOS 18 scroll");
        return NO;
    }
    
    NSString *javascript = [NSString stringWithFormat:
        @"(function(){"
        "   var e=document.querySelector('%@');"
        "   if(!e)return {success:false};"
        "   e.scrollIntoView({behavior:'smooth',block:'center'});"
        "   return {success:true};"
        "})();", 
        selector];
    
    __block BOOL success = NO;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [webView evaluateJavaScript:javascript completionHandler:^(id result, NSError *error) {
        success = (error == nil);
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)));
    
    return success;
}

- (WKWebView *)findFrontWebView {
    NSLog(@"[AdvancedFeatures] Finding front WebView for iOS 18");
    
    UIWindow *keyWindow = [self getKeyWindow];
    if (!keyWindow) {
        return nil;
    }
    
    WKWebView *webView = [self findWebViewInHierarchy:keyWindow];
    if (webView) {
        NSLog(@"[AdvancedFeatures] Found WebView: %@", webView);
    } else {
        NSLog(@"[AdvancedFeatures] No WebView found");
    }
    
    return webView;
}

- (WKWebView *)findWebViewInHierarchy:(UIView *)view {
    if ([view isKindOfClass:[WKWebView class]]) {
        return (WKWebView *)view;
    }
    
    for (UIView *subview in [view.subviews reverseObjectEnumerator]) {
        WKWebView *webView = [self findWebViewInHierarchy:subview];
        if (webView) {
            return webView;
        }
    }
    
    return nil;
}

@end
