#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

typedef NS_ENUM(NSInteger, ColorMatchMode) {
    ColorMatchModeExact,
    ColorMatchModeTolerance,
    ColorMatchModePercentage
};

typedef NS_ENUM(NSInteger, OCRLanguage) {
    OCRLanguageEnglish,
    OCRLanguageChineseSimplified,
    OCRLanguageChineseTraditional,
    OCRLanguageJapanese,
    OCRLanguageKorean
};

typedef NS_ENUM(NSInteger, WebViewClickStrategy) {
    WebViewClickStrategyAuto,          // 自动选择最佳策略 (iOS 18 默认)
    WebViewClickStrategyClick,         // 原生 click() 方法
    WebViewClickStrategyMouseEvent,    // MouseEvent
    WebViewClickStrategyPointerEvent,  // PointerEvent (iOS 18 优先)
    WebViewClickStrategyTouchEvent     // TouchEvent
};

typedef void (^ScheduledTaskBlock)(void);
typedef void (^ColorDetectionBlock)(BOOL found, CGPoint position);
typedef void (^OCRResultBlock)(NSString *text, NSArray *boundingBoxes);
typedef void (^WebViewJSCompletion)(id result, NSError *error);

@interface AdvancedFeatures : NSObject

@property (nonatomic, assign) BOOL isScheduledTaskRunning;

+ (instancetype)sharedInstance;

- (void)scheduleTaskAtTime:(NSDate *)date block:(ScheduledTaskBlock)block;
- (void)scheduleTaskAfterDelay:(NSTimeInterval)delay block:(ScheduledTaskBlock)block;
- (void)cancelAllScheduledTasks;

- (BOOL)detectColor:(UIColor *)targetColor atPoint:(CGPoint)point tolerance:(CGFloat)tolerance;
- (CGPoint)findColorOnScreen:(UIColor *)targetColor tolerance:(CGFloat)tolerance;
- (void)asyncFindColorOnScreen:(UIColor *)targetColor tolerance:(CGFloat)tolerance completion:(ColorDetectionBlock)completion;

- (BOOL)compareColors:(UIColor *)color1 withColor:(UIColor *)color2 tolerance:(CGFloat)tolerance;
- (UIColor *)getColorAtPoint:(CGPoint)point;

- (NSString *)performOCRWithImage:(UIImage *)image language:(OCRLanguage)language;
- (void)asyncPerformOCRWithImage:(UIImage *)image language:(OCRLanguage)language completion:(OCRResultBlock)completion;

- (BOOL)waitForColor:(UIColor *)targetColor timeout:(NSTimeInterval)timeout tolerance:(CGFloat)tolerance;
- (BOOL)waitForText:(NSString *)text timeout:(NSTimeInterval)timeout;

- (UIImage *)captureScreen;
- (UIImage *)captureRegion:(CGRect)region;

- (NSArray *)parseScriptFromString:(NSString *)scriptString;
- (BOOL)executeScript:(NSArray *)scriptActions;

// iOS 18 WebView 高级功能
- (BOOL)clickWebViewElementAtPoint:(CGPoint)point strategy:(WebViewClickStrategy)strategy;
- (BOOL)executeWebViewJavaScript:(NSString *)script completion:(WebViewJSCompletion)completion;
- (BOOL)fillWebViewInput:(NSString *)selector text:(NSString *)text;
- (NSString *)getWebViewElementText:(NSString *)selector;
- (BOOL)scrollWebViewToElement:(NSString *)selector;
- (WKWebView *)findFrontWebView;

@end