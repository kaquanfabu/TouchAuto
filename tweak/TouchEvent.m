#import "TouchEvent.h"

@implementation TouchEvent

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithTouch:(UITouch *)touch event:(UIEvent *)event {
    if (self = [super init]) {
        _timestamp = [[NSDate date] timeIntervalSince1970];
        _location = [touch locationInView:touch.window];
        _previousLocation = [touch previousLocationInView:touch.window];
        _tapCount = touch.tapCount;
        _touchIdentifier = @(touch.hash);
        _pressure = touch.force;
        
        NSLog(@"[TouchEvent] Recording at (%f, %f) in window: %@", _location.x, _location.y, touch.window);
        
        switch (touch.phase) {
            case UITouchPhaseBegan:
                _type = TouchEventTypeBegan;
                break;
            case UITouchPhaseMoved:
                _type = TouchEventTypeMoved;
                break;
            case UITouchPhaseEnded:
                _type = TouchEventTypeEnded;
                break;
            case UITouchPhaseCancelled:
                _type = TouchEventTypeCancelled;
                break;
            default:
                _type = TouchEventTypeBegan;
        }
        
        if (touch.window) {
            _bounds = touch.window.bounds;
            NSLog(@"[TouchEvent] Window bounds: %@", NSStringFromCGRect(_bounds));
        }
        
        // Capture view metadata
        [self captureViewMetadata:touch.view];
    }
    return self;
}

- (void)captureViewMetadata:(UIView *)view {
    if (!view) return;
    
    // View class name
    _viewClass = NSStringFromClass([view class]);
    
    // Accessibility identifier
    if (view.accessibilityIdentifier) {
        _accessibilityIdentifier = view.accessibilityIdentifier;
    }
    
    // Accessibility label
    if (view.accessibilityLabel) {
        _accessibilityLabel = view.accessibilityLabel;
    }
    
    // Superview chain (index path)
    NSMutableArray *chain = [NSMutableArray array];
    UIView *currentView = view;
    while (currentView) {
        UIView *superview = currentView.superview;
        if (superview) {
            NSUInteger index = [superview.subviews indexOfObject:currentView];
            NSString *entry = [NSString stringWithFormat:@"%@:%lu", NSStringFromClass([currentView class]), (unsigned long)index];
            [chain addObject:entry];
        }
        currentView = superview;
    }
    _superviewChain = chain;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeDouble:_timestamp forKey:@"timestamp"];
    [coder encodeDouble:_delay forKey:@"delay"];
    [coder encodeInteger:_type forKey:@"type"];
    [coder encodeCGPoint:_location forKey:@"location"];
    [coder encodeCGPoint:_previousLocation forKey:@"previousLocation"];
    [coder encodeInteger:_tapCount forKey:@"tapCount"];
    [coder encodeBool:_isLongPress forKey:@"isLongPress"];
    [coder encodeDouble:_longPressDuration forKey:@"longPressDuration"];
    [coder encodeObject:_touchIdentifier forKey:@"touchIdentifier"];
    [coder encodeFloat:_pressure forKey:@"pressure"];
    [coder encodeCGRect:_bounds forKey:@"bounds"];
    
    // Encode view metadata
    [coder encodeObject:_viewClass forKey:@"viewClass"];
    [coder encodeObject:_accessibilityIdentifier forKey:@"accessibilityIdentifier"];
    [coder encodeObject:_accessibilityLabel forKey:@"accessibilityLabel"];
    [coder encodeObject:_superviewChain forKey:@"superviewChain"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _timestamp = [coder decodeDoubleForKey:@"timestamp"];
        _delay = [coder decodeDoubleForKey:@"delay"];
        _type = [coder decodeIntegerForKey:@"type"];
        _location = [coder decodeCGPointForKey:@"location"];
        _previousLocation = [coder decodeCGPointForKey:@"previousLocation"];
        _tapCount = [coder decodeIntegerForKey:@"tapCount"];
        _isLongPress = [coder decodeBoolForKey:@"isLongPress"];
        _longPressDuration = [coder decodeDoubleForKey:@"longPressDuration"];
        _touchIdentifier = [coder decodeObjectForKey:@"touchIdentifier"];
        _pressure = [coder decodeFloatForKey:@"pressure"];
        _bounds = [coder decodeCGRectForKey:@"bounds"];
        
        // Decode view metadata
        _viewClass = [coder decodeObjectForKey:@"viewClass"];
        _accessibilityIdentifier = [coder decodeObjectForKey:@"accessibilityIdentifier"];
        _accessibilityLabel = [coder decodeObjectForKey:@"accessibilityLabel"];
        _superviewChain = [coder decodeObjectForKey:@"superviewChain"];
    }
    return self;
}

- (NSDictionary *)toDictionary {
    return @{
        @"timestamp": @(_timestamp),
        @"delay": @(_delay),
        @"type": @(_type),
        @"location": @{@"x": @(_location.x), @"y": @(_location.y)},
        @"previousLocation": @{@"x": @(_previousLocation.x), @"y": @(_previousLocation.y)},
        @"tapCount": @(_tapCount),
        @"isLongPress": @(_isLongPress),
        @"longPressDuration": @(_longPressDuration),
        @"touchIdentifier": _touchIdentifier ?: @0,
        @"pressure": @(_pressure),
        @"bounds": @{@"x": @(_bounds.origin.x), @"y": @(_bounds.origin.y),
                     @"width": @(_bounds.size.width), @"height": @(_bounds.size.height)},
        @"viewClass": _viewClass ?: @"",
        @"accessibilityIdentifier": _accessibilityIdentifier ?: @"",
        @"accessibilityLabel": _accessibilityLabel ?: @"",
        @"superviewChain": _superviewChain ?: @[]
    };
}

+ (TouchEvent *)fromDictionary:(NSDictionary *)dict {
    TouchEvent *event = [[TouchEvent alloc] init];
    event.timestamp = [dict[@"timestamp"] doubleValue];
    event.delay = [dict[@"delay"] doubleValue];
    event.type = [dict[@"type"] integerValue];
    
    NSDictionary *locDict = dict[@"location"];
    event.location = CGPointMake([locDict[@"x"] doubleValue], [locDict[@"y"] doubleValue]);
    
    NSDictionary *prevLocDict = dict[@"previousLocation"];
    if (prevLocDict) {
        event.previousLocation = CGPointMake([prevLocDict[@"x"] doubleValue], [prevLocDict[@"y"] doubleValue]);
    } else {
        event.previousLocation = event.location;
    }
    
    event.tapCount = [dict[@"tapCount"] integerValue];
    event.isLongPress = [dict[@"isLongPress"] boolValue];
    event.longPressDuration = [dict[@"longPressDuration"] doubleValue];
    event.touchIdentifier = dict[@"touchIdentifier"];
    event.pressure = [dict[@"pressure"] floatValue];
    
    NSDictionary *boundsDict = dict[@"bounds"];
    if (boundsDict) {
        event.bounds = CGRectMake([boundsDict[@"x"] doubleValue], [boundsDict[@"y"] doubleValue],
                                  [boundsDict[@"width"] doubleValue], [boundsDict[@"height"] doubleValue]);
    } else {
        event.bounds = [UIScreen mainScreen].bounds;
    }
    
    // Parse view metadata (compatible with v1.0 which doesn't have these fields)
    event.viewClass = dict[@"viewClass"];
    event.accessibilityIdentifier = dict[@"accessibilityIdentifier"];
    event.accessibilityLabel = dict[@"accessibilityLabel"];
    event.superviewChain = dict[@"superviewChain"] ?: @[];
    
    return event;
}

@end
