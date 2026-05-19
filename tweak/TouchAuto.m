#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "TouchRecorder.h"
#import "TouchPlayer.h"
#import "TouchEvent.h"
#import "FloatingPanel.h"
#import "AdvancedFeatures.h"

static BOOL gIsAppReady = NO;
static Class gUIWindowClass = nil;
static Class gUIApplicationClass = nil;
static IMP gOriginalSendEvent = NULL;
static IMP gOriginalApplicationDidBecomeActive = NULL;

static void swizzledSendEvent(id self, SEL _cmd, UIEvent *event);
static void swizzledApplicationDidBecomeActive(id self, SEL _cmd, UIApplication *application);

@interface TouchAuto : NSObject

+ (void)load;
+ (void)setup;

@end

@implementation TouchAuto

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [self swizzleMethods];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self setup];
        });
    });
}

+ (void)swizzleMethods {
    gUIWindowClass = objc_getClass("UIWindow");
    gUIApplicationClass = objc_getClass("UIApplication");
    
    if (gUIWindowClass) {
        Method sendEventMethod = class_getInstanceMethod(gUIWindowClass, @selector(sendEvent:));
        if (sendEventMethod) {
            gOriginalSendEvent = method_setImplementation(sendEventMethod, (IMP)swizzledSendEvent);
        }
    }
    
    if (gUIApplicationClass) {
        Method didBecomeActiveMethod = class_getInstanceMethod(gUIApplicationClass, @selector(applicationDidBecomeActive:));
        if (didBecomeActiveMethod) {
            gOriginalApplicationDidBecomeActive = method_setImplementation(didBecomeActiveMethod, (IMP)swizzledApplicationDidBecomeActive);
        }
    }
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
        
        if (recorder.recordedEvents.count > 0) {
            [player setEvents:recorder.recordedEvents];
            [player play];
        }
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
    
    NSString *docsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *fileName = [NSString stringWithFormat:@"touch_recording_%f.json", [[NSDate date] timeIntervalSince1970]];
    NSString *filePath = [docsPath stringByAppendingPathComponent:fileName];
    
    NSError *error = nil;
    if ([recorder saveToFile:filePath error:&error]) {
        [self showAlertWithTitle:@"保存成功" message:[NSString stringWithFormat:@"文件已保存到:\n%@", filePath]];
    } else {
        [self showAlertWithTitle:@"保存失败" message:[error localizedDescription]];
    }
}

+ (void)showScriptManager {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"脚本管理" message:@"选择操作" preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"加载脚本" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self loadScript];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"编辑脚本" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self showScriptEditor];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
}

+ (void)loadScript {
    NSString *docsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    
    NSError *error = nil;
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docsPath error:&error];
    
    NSMutableArray *jsonFiles = [NSMutableArray array];
    for (NSString *file in files) {
        if ([file hasSuffix:@".json"]) {
            [jsonFiles addObject:file];
        }
    }
    
    if (jsonFiles.count == 0) {
        [self showAlertWithTitle:@"提示" message:@"没有找到脚本文件"];
        return;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择脚本" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    for (NSString *file in jsonFiles) {
        [alert addAction:[UIAlertAction actionWithTitle:file style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self loadScriptFromFile:[docsPath stringByAppendingPathComponent:file]];
        }]];
    }
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
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
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"运行日志" message:@"TouchAuto 运行日志\n\n最近录制: 0 个事件\n播放状态: 停止" preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"复制日志" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = @"TouchAuto Logs\n---\nRecording: 0 events\nPlaying: Stopped";
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"清空日志" style:UIAlertActionStyleDestructive handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
}

+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
}

@end

static void swizzledSendEvent(id self, SEL _cmd, UIEvent *event) {
    if (gOriginalSendEvent) {
        ((void (*)(id, SEL, UIEvent *))gOriginalSendEvent)(self, _cmd, event);
    }
    
    if (!gIsAppReady) return;
    
    TouchRecorder *recorder = [TouchRecorder sharedInstance];
    if (!recorder.isRecording) return;
    
    NSSet *touches = [event allTouches];
    for (UITouch *touch in touches) {
        TouchEvent *touchEvent = [[TouchEvent alloc] initWithTouch:touch event:event];
        [recorder recordEvent:touchEvent];
    }
}

static void swizzledApplicationDidBecomeActive(id self, SEL _cmd, UIApplication *application) {
    if (gOriginalApplicationDidBecomeActive) {
        ((void (*)(id, SEL, UIApplication *))gOriginalApplicationDidBecomeActive)(self, _cmd, application);
    }
    
    [TouchAuto setup];
}