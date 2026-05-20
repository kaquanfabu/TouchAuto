#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "TouchRecorder.h"
#import "TouchPlayer.h"
#import "TouchEvent.h"
#import "FloatingPanel.h"
#import "AdvancedFeatures.h"

static BOOL gIsAppReady = NO;
static Class gUIWindowClass = nil;
static IMP gOriginalSendEvent = NULL;

// 缓存真实的 UITouch 和 UIEvent 对象用于回放
static NSMutableArray *gCachedTouches = nil;
static NSMutableArray *gCachedEvents = nil;

static void swizzledSendEvent(id self, SEL _cmd, UIEvent *event);

@interface TouchAuto : NSObject

+ (void)load;
+ (void)setup;
+ (NSArray *)cachedTouches;
+ (NSArray *)cachedEvents;
+ (void)clearCachedObjects;

@end

@implementation TouchAuto

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [self swizzleMethods];
        gCachedTouches = [NSMutableArray array];
        gCachedEvents = [NSMutableArray array];
    });
}

+ (void)swizzleMethods {
    gUIWindowClass = objc_getClass("UIWindow");
    
    if (gUIWindowClass) {
        Method sendEventMethod = class_getInstanceMethod(gUIWindowClass, @selector(sendEvent:));
        if (sendEventMethod) {
            gOriginalSendEvent = method_setImplementation(sendEventMethod, (IMP)swizzledSendEvent);
        }
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(handleApplicationDidBecomeActive:) 
                                                 name:UIApplicationDidBecomeActiveNotification 
                                               object:nil];
}

+ (void)setup {
    if (gIsAppReady) return;
    gIsAppReady = YES;
    
    [self setupFloatingPanel];
    [self setupRecorder];
    [self setupPlayer];
}

+ (void)setupFloatingPanel {
    FloatingPanel *panel = [FloatingPanel sharedInstance];
    
    panel.startRecordingBlock = ^{
        [[TouchRecorder sharedInstance] startRecording];
    };
    
    panel.stopRecordingBlock = ^{
        [[TouchRecorder sharedInstance] stopRecording];
        [[TouchPlayer sharedInstance] stop];
    };
    
    panel.playBlock = ^{
        TouchRecorder *recorder = [TouchRecorder sharedInstance];
        TouchPlayer *player = [TouchPlayer sharedInstance];
        
        NSArray *events = recorder.recordedEvents;
        if (!events || events.count == 0) {
            [self showAlertWithTitle:@"提示" message:@"没有可播放的事件，请先录制触摸"];
            return;
        }
        
        [player setEvents:events];
        [player play];
    };
    
    panel.pauseBlock = ^{
        [[TouchPlayer sharedInstance] pause];
    };
    
    panel.saveBlock = ^{
        [self saveRecording];
    };
    
    panel.scriptManagerBlock = ^{
        [self showScriptManager];
    };
    
    panel.showLogsBlock = ^{
        [self showLogsWindow];
    };
    
    [panel show];
}

+ (void)setupRecorder {
    TouchRecorder *recorder = [TouchRecorder sharedInstance];
    
    recorder.stateChangeBlock = ^(BOOL isRecording) {
        [[FloatingPanel sharedInstance] updateRecordingState:isRecording];
    };
}

+ (void)setupPlayer {
    __weak TouchPlayer *weakPlayer = [TouchPlayer sharedInstance];
    
    weakPlayer.stateChangeBlock = ^(BOOL isPlaying) {
        __strong TouchPlayer *strongPlayer = weakPlayer;
        [[FloatingPanel sharedInstance] updatePlaybackState:isPlaying isPaused:strongPlayer.isPaused];
    };
    
    weakPlayer.progressBlock = ^(NSUInteger currentIndex, NSUInteger totalCount) {
        [[FloatingPanel sharedInstance] updateProgress:currentIndex totalCount:totalCount];
    };
}

+ (void)saveRecording {
    TouchRecorder *recorder = [TouchRecorder sharedInstance];
    
    if (recorder.recordedEvents.count == 0) {
        [self showAlertWithTitle:@"提示" message:@"没有可保存的录制事件"];
        return;
    }
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyyMMdd_HHmmss"];
    NSString *fileName = [NSString stringWithFormat:@"TouchAuto_%@.json", [formatter stringFromDate:[NSDate date]]];
    
    // Create save directory: Documents/TouchAuto/
    NSString *docsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *saveDir = [docsPath stringByAppendingPathComponent:@"TouchAuto"];
    
    // Create directory if not exists
    NSError *dirError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:saveDir withIntermediateDirectories:YES attributes:nil error:&dirError];
    if (dirError) {
        NSLog(@"[TouchAuto] Failed to create directory: %@", dirError);
        [self showAlertWithTitle:@"保存失败" message:@"无法创建保存目录"];
        return;
    }
    
    NSString *filePath = [saveDir stringByAppendingPathComponent:fileName];
    
    NSMutableDictionary *scriptData = [NSMutableDictionary dictionary];
    
    // Version 2.0
    scriptData[@"version"] = @"2.0";
    scriptData[@"createdAt"] = [[NSDate date] description];
    scriptData[@"eventCount"] = @(recorder.recordedEvents.count);
    
    // App info
    NSDictionary *appInfo = [self getAppInfo];
    scriptData[@"app"] = appInfo;
    
    // Screen info
    NSDictionary *screenInfo = [self getScreenInfo];
    scriptData[@"screen"] = screenInfo;
    
    // Events with metadata
    scriptData[@"events"] = [self serializeEvents:recorder.recordedEvents];
    
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:scriptData options:NSJSONWritingPrettyPrinted error:nil];
    
    if ([jsonData writeToFile:filePath atomically:YES]) {
        [self showAlertWithTitle:@"保存成功" message:[NSString stringWithFormat:@"脚本已保存到:\n%@", filePath]];
        [self exportFileToFilesApp:filePath fileName:fileName];
    } else {
        [self showAlertWithTitle:@"保存失败" message:@"无法保存文件"];
    }
}

+ (NSDictionary *)getAppInfo {
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    if (!appName) {
        appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
    }
    
    return @{
        @"bundleId": bundleId ?: @"",
        @"appName": appName ?: @""
    };
}

+ (NSDictionary *)getScreenInfo {
    UIScreen *mainScreen = [UIScreen mainScreen];
    CGRect bounds = mainScreen.bounds;
    
    return @{
        @"width": @(bounds.size.width),
        @"height": @(bounds.size.height),
        @"scale": @(mainScreen.scale)
    };
}

+ (NSArray *)serializeEvents:(NSArray *)events {
    NSMutableArray *serialized = [NSMutableArray array];
    for (TouchEvent *event in events) {
        [serialized addObject:[event toDictionary]];
    }
    return serialized;
}

+ (void)exportFileToFilesApp:(NSString *)filePath fileName:(NSString *)fileName {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *fileURL = [NSURL fileURLWithPath:filePath];
        
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithURL:fileURL inMode:UIDocumentPickerModeExportToService];
        picker.delegate = (id<UIDocumentPickerDelegate>)self;
        picker.allowsMultipleSelection = NO;
        
        UIWindow *keyWindow = [self getKeyWindow];
        if (keyWindow && keyWindow.rootViewController) {
            [keyWindow.rootViewController presentViewController:picker animated:YES completion:nil];
        }
    });
}

+ (void)showScriptManager {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"脚本管理" message:@"选择操作" preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"导入脚本" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self importScriptFromFilesApp];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"导出当前录制" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self saveRecording];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"编辑脚本" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self showScriptEditor];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    UIWindow *keyWindow = [self getKeyWindow];
    if (keyWindow && keyWindow.rootViewController) {
        [keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
    }
}

+ (void)importScriptFromFilesApp {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *types = @[@"public.json", @"public.text"];
        
        UIDocumentPickerViewController *picker = nil;
        if (@available(iOS 14.0, *)) {
            picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
        } else {
            picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:types inMode:UIDocumentPickerModeOpen];
        }
        
        picker.delegate = (id<UIDocumentPickerDelegate>)self;
        picker.allowsMultipleSelection = NO;
        
        UIWindow *keyWindow = [self getKeyWindow];
        if (keyWindow && keyWindow.rootViewController) {
            [keyWindow.rootViewController presentViewController:picker animated:YES completion:nil];
        }
    });
}

+ (void)loadScript {
    [self importScriptFromFilesApp];
}

+ (void)loadScriptFromFile:(NSString *)filePath {
    TouchRecorder *recorder = [TouchRecorder sharedInstance];
    
    NSError *error = nil;
    if ([recorder loadFromFile:filePath error:&error]) {
        [self showAlertWithTitle:@"加载成功" message:[NSString stringWithFormat:@"已加载 %lu 个事件", (unsigned long)recorder.recordedEvents.count]];
    } else {
        [self showAlertWithTitle:@"加载失败" message:[error localizedDescription]];
    }
}

+ (void)showScriptEditor {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"脚本编辑器" message:@"输入脚本命令" preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"tap 100 200\ndelay 1.0\nswipe 50 300 250 300";
        textField.text = @"tap 100 200\ndelay 0.5\nswipe 100 300 300 300";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"执行" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *scriptText = alert.textFields.firstObject.text;
        [self executeScriptFromString:scriptText];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *scriptText = alert.textFields.firstObject.text;
        [self saveScriptFromString:scriptText];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
}

+ (void)executeScriptFromString:(NSString *)scriptText {
    AdvancedFeatures *features = [AdvancedFeatures sharedInstance];
    NSArray *actions = [features parseScriptFromString:scriptText];
    
    if (actions.count == 0) {
        [self showAlertWithTitle:@"错误" message:@"脚本解析失败"];
        return;
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [features executeScript:actions];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showAlertWithTitle:@"执行完成" message:@"脚本已执行完毕"];
        });
    });
}

+ (void)saveScriptFromString:(NSString *)scriptText {
    NSString *docsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *fileName = [NSString stringWithFormat:@"script_%f.txt", [[NSDate date] timeIntervalSince1970]];
    NSString *filePath = [docsPath stringByAppendingPathComponent:fileName];
    
    NSError *error = nil;
    if ([scriptText writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        [self showAlertWithTitle:@"保存成功" message:[NSString stringWithFormat:@"脚本已保存到:\n%@", filePath]];
    } else {
        [self showAlertWithTitle:@"保存失败" message:[error localizedDescription]];
    }
}

+ (void)showLogsWindow {
    UIViewController *logsVC = [[UIViewController alloc] init];
    logsVC.view.backgroundColor = [UIColor whiteColor];
    logsVC.title = @"运行日志";
    
    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height - 150)];
    scrollView.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.95 alpha:1.0];
    
    UILabel *logsLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 16, [UIScreen mainScreen].bounds.size.width - 32, 0)];
    logsLabel.numberOfLines = 0;
    logsLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    logsLabel.textColor = [UIColor darkGrayColor];
    
    NSMutableString *logText = [NSMutableString string];
    [logText appendString:@"══════════════════════════════════════════════════════\n"];
    [logText appendString:@"                     TouchAuto 运行日志\n"];
    [logText appendString:@"══════════════════════════════════════════════════════\n\n"];
    
    TouchRecorder *recorder = [TouchRecorder sharedInstance];
    TouchPlayer *player = [TouchPlayer sharedInstance];
    
    [logText appendFormat:@"▶ 录制状态: %@\n", recorder.isRecording ? @"录制中" : @"未录制"];
    [logText appendFormat:@"▶ 录制事件数: %lu 个\n", (unsigned long)recorder.recordedEvents.count];
    [logText appendFormat:@"▶ 播放状态: %@\n", player.isPlaying ? @"播放中" : @"已停止"];
    [logText appendFormat:@"▶ 暂停状态: %@\n", player.isPaused ? @"已暂停" : @"未暂停"];
    [logText appendFormat:@"▶ 循环次数: %lu/%lu\n\n", (unsigned long)player.currentLoop, (unsigned long)player.loopCount];
    
    // 显示播放时间日志
    NSString *playbackLogs = [player getLogs];
    if (playbackLogs && playbackLogs.length > 0) {
        [logText appendString:@"══════════════════════════════════════════════════════\n"];
        [logText appendString:@"播放时间日志:\n"];
        [logText appendString:@"══════════════════════════════════════════════════════\n"];
        [logText appendString:playbackLogs];
        [logText appendString:@"\n"];
    }
    
    [logText appendString:@"══════════════════════════════════════════════════════\n"];
    [logText appendString:@"录制事件记录:\n"];
    [logText appendString:@"══════════════════════════════════════════════════════\n"];
    
    if (recorder.recordedEvents.count > 0) {
        [logText appendFormat:@"已录制 %lu 个触摸事件\n", (unsigned long)recorder.recordedEvents.count];
        for (NSUInteger i = 0; i < MIN(10, recorder.recordedEvents.count); i++) {
            TouchEvent *event = recorder.recordedEvents[i];
            NSString *viewInfo = event.viewClass ?: @"-";
            if (event.accessibilityIdentifier.length > 0) {
                viewInfo = [NSString stringWithFormat:@"%@ [%@]", viewInfo, event.accessibilityIdentifier];
            }
            [logText appendFormat:@"  %lu. %@ | X:%.1f Y:%.1f | %@\n",
             (unsigned long)(i + 1),
             [self typeStringForTouchType:event.type],
             event.location.x,
             event.location.y,
             viewInfo];
        }
        if (recorder.recordedEvents.count > 10) {
            [logText appendFormat:@"  ... 还有 %lu 个事件\n", (unsigned long)(recorder.recordedEvents.count - 10)];
        }
    } else {
        [logText appendString:@"暂无录制事件\n"];
    }
    
    [logText appendString:@"\n══════════════════════════════════════════════════════\n"];
    [logText appendFormat:@"生成时间: %@\n", [[NSDate date] description]];
    [logText appendString:@"══════════════════════════════════════════════════════\n"];
    
    logsLabel.text = logText;
    [logsLabel sizeToFit];
    scrollView.contentSize = CGSizeMake([UIScreen mainScreen].bounds.size.width, logsLabel.frame.size.height + 32);
    [scrollView addSubview:logsLabel];
    
    UIViewController *containerVC = logsVC;
    if (@available(iOS 13.0, *)) {
        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:logsVC];
        
        UIBarButtonItem *copyButton = [[UIBarButtonItem alloc] initWithTitle:@"复制" 
                                                                      style:UIBarButtonItemStylePlain 
                                                                     target:self 
                                                                     action:@selector(copyLogs)];
        
        UIBarButtonItem *closeButton = [[UIBarButtonItem alloc] initWithTitle:@"关闭" 
                                                                       style:UIBarButtonItemStyleDone 
                                                                      target:self 
                                                                      action:@selector(dismissLogs)];
        
        navController.topViewController.navigationItem.rightBarButtonItems = @[closeButton, copyButton];
        navController.topViewController.title = @"运行日志";
        
        containerVC = navController;
        
        if (@available(iOS 15.0, *)) {
            UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
            [appearance configureWithOpaqueBackground];
            appearance.backgroundColor = [UIColor systemBlueColor];
            appearance.titleTextAttributes = @{NSForegroundColorAttributeName: [UIColor whiteColor]};
            navController.navigationBar.standardAppearance = appearance;
            navController.navigationBar.scrollEdgeAppearance = appearance;
            navController.navigationBar.tintColor = [UIColor whiteColor];
        }
    } else {
        logsVC.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭" 
                                                                                  style:UIBarButtonItemStyleDone 
                                                                                 target:self 
                                                                                 action:@selector(dismissLogs)];
    }
    
    [logsVC.view addSubview:scrollView];
    
    UIWindow *keyWindow = [self getKeyWindow];
    if (keyWindow) {
        [keyWindow.rootViewController presentViewController:containerVC animated:YES completion:nil];
    }
}

+ (void)copyLogs {
    TouchPlayer *player = [TouchPlayer sharedInstance];
    NSString *logs = [player getLogs];
    
    if (logs && logs.length > 0) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = logs;
        [self showAlertWithTitle:@"复制成功" message:@"日志已复制到剪贴板"];
    } else {
        [self showAlertWithTitle:@"提示" message:@"暂无日志可复制"];
    }
}

+ (void)dismissLogs {
    UIWindow *keyWindow = [self getKeyWindow];
    if (keyWindow && keyWindow.rootViewController.presentedViewController) {
        [keyWindow.rootViewController.presentedViewController dismissViewControllerAnimated:YES completion:nil];
    }
}

+ (NSString *)typeStringForTouchType:(TouchEventType)type {
    switch (type) {
        case TouchEventTypeBegan: return @"抬起";
        case TouchEventTypeMoved: return @"移动";
        case TouchEventTypeEnded: return @"抬起";
        case TouchEventTypeCancelled: return @"取消";
        default: return @"未知";
    }
}

+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        
        UIWindow *keyWindow = [self getKeyWindow];
        if (keyWindow && keyWindow.rootViewController) {
            [keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
        }
    });
}

+ (void)handleApplicationDidBecomeActive:(NSNotification *)notification {
    [self setup];
}

+ (UIWindow *)getKeyWindow {
    UIWindow *keyWindow = nil;
    
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                keyWindow = scene.windows.firstObject;
                break;
            }
        }
    }
    
    if (!keyWindow) {
        keyWindow = [UIApplication sharedApplication].keyWindow;
    }
    
    if (!keyWindow) {
        keyWindow = [UIApplication sharedApplication].windows.firstObject;
    }
    
    return keyWindow;
}

+ (NSArray *)cachedTouches {
    return gCachedTouches;
}

+ (NSArray *)cachedEvents {
    return gCachedEvents;
}

+ (void)clearCachedObjects {
    [gCachedTouches removeAllObjects];
    [gCachedEvents removeAllObjects];
}

@end

static void swizzledSendEvent(id self, SEL _cmd, UIEvent *event) {
    // 缓存真实的 UITouch 和 UIEvent 对象
    if (event.type == UIEventTypeTouches) {
        NSSet *touches = [event allTouches];
        if (touches && touches.count > 0) {
            [gCachedTouches addObjectsFromArray:[touches allObjects]];
            [gCachedEvents addObject:event];
            
            // 限制缓存数量
            if (gCachedTouches.count > 100) {
                [gCachedTouches removeObjectsInRange:NSMakeRange(0, gCachedTouches.count - 50)];
            }
            if (gCachedEvents.count > 50) {
                [gCachedEvents removeObjectsInRange:NSMakeRange(0, gCachedEvents.count - 25)];
            }
        }
    }
    
    // 调用原始方法
    if (gOriginalSendEvent) {
        ((void (*)(id, SEL, UIEvent *))gOriginalSendEvent)(self, _cmd, event);
    }
}

#pragma mark - UIDocumentPickerDelegate

@implementation TouchAuto (UIDocumentPickerDelegate)

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count > 0) {
        NSString *filePath = [urls.firstObject path];
        if ([[filePath pathExtension] isEqualToString:@"json"]) {
            [TouchAuto loadScriptFromFile:filePath];
        } else {
            [TouchAuto showAlertWithTitle:@"提示" message:@"请选择 JSON 文件"];
        }
    }
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    // Do nothing
}

@end
