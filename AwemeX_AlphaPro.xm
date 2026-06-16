#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#pragma mark - Keys

static NSString * const kAXTopAlpha       = @"ax_top_alpha";
static NSString * const kAXRightAlpha     = @"ax_right_alpha";
static NSString * const kAXScale          = @"ax_scale";
static NSString * const kAXIconAlpha      = @"ax_icon_alpha";
static NSString * const kAXGlobalAlpha    = @"ax_global_alpha";
static NSString * const kAXNicknameScale  = @"ax_nickname_scale";
static NSString * const kAXHideSearch     = @"ax_hide_search";
static NSString * const kAXShowButton     = @"ax_show_button";

static char kAXBaseAlphaKey;
static char kAXTwoFingerGestureInstalledKey;
static BOOL axApplyingElementEffects = NO;
static UILongPressGestureRecognizer *axTwoFingerLongPressGesture = nil;

static const NSInteger kAXPanelTag = 77889931;

#pragma mark - Utilities

static inline BOOL AXIsIpad(void) {
    return [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
}

static inline CGFloat AXClamp(CGFloat v, CGFloat min, CGFloat max) {
    if (v < min) return min;
    if (v > max) return max;
    return v;
}

static CGFloat AXFloatForKey(NSString *key, CGFloat fallback) {
    id obj = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (!obj) return fallback;
    if (![obj respondsToSelector:@selector(floatValue)]) return fallback;
    return AXClamp([obj floatValue], 0.0, 1.5);
}

static BOOL AXBoolForKey(NSString *key, BOOL fallback) {
    id obj = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (!obj) return fallback;
    if (![obj respondsToSelector:@selector(boolValue)]) return fallback;
    return [obj boolValue];
}

static CGFloat AXGlobalAlpha(void) {
    return AXClamp(AXFloatForKey(kAXGlobalAlpha, 1.0), 0.05, 1.0);
}

static CGFloat AXEffectiveAlpha(NSString *key, CGFloat fallback) {
    CGFloat local = AXClamp(AXFloatForKey(key, fallback), 0.05, 1.0);
    return AXClamp(local * AXGlobalAlpha(), 0.03, 1.0);
}

static UIView *AXViewFromAny(id object) {
    if (!object) return nil;
    if (![(id)object isKindOfClass:[UIView class]]) return nil;
    return (UIView *)(id)object;
}

static NSString *AXClassName(id object) {
    if (!object) return @"";
    return NSStringFromClass([object class]);
}

static UIWindow *AXActiveWindow(void) {
    UIWindow *result = nil;

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            if (scene.activationState != UISceneActivationStateForegroundActive &&
                scene.activationState != UISceneActivationStateForegroundInactive) continue;

            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) return window;
                if (!result && !window.hidden && window.alpha > 0.01) result = window;
            }
        }
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (!result) {
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            if (window.isKeyWindow) return window;
            if (!result && !window.hidden && window.alpha > 0.01) result = window;
        }
    }
#pragma clang diagnostic pop

    return result;
}

static UIViewController *AXFirstViewControllerFromView(UIView *view) {
    UIResponder *responder = view;
    while (responder) {
        if ([responder isKindOfClass:[UIViewController class]]) return (UIViewController *)responder;
        responder = responder.nextResponder;
    }
    return nil;
}

static BOOL AXIsDescendantOf(UIView *view, UIView *ancestor) {
    if (!view || !ancestor) return NO;
    UIView *v = view;
    while (v) {
        if (v == ancestor) return YES;
        v = v.superview;
    }
    return NO;
}

static BOOL AXIsAwemeXPanelView(UIView *view) {
    if (!view) return NO;
    UIView *v = view;
    while (v) {
        if (v.tag == kAXPanelTag) return YES;
        v = v.superview;
    }
    return NO;
}

static BOOL AXContainsSubviewOfClass(UIView *view, Class cls) {
    if (!view || !cls) return NO;
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:cls]) return YES;
        if (AXContainsSubviewOfClass(subview, cls)) return YES;
    }
    return NO;
}

static BOOL AXStackHasElementClassName(UIView *view, NSString *needle) {
    if (!view || needle.length == 0) return NO;
    if ([AXClassName(view) containsString:needle]) return YES;
    for (UIView *subview in view.subviews) {
        if (AXStackHasElementClassName(subview, needle)) return YES;
    }
    return NO;
}

static CGRect AXFrameInWindow(UIView *view) {
    if (!view || !view.window) return CGRectZero;
    return [view convertRect:view.bounds toView:view.window];
}

static BOOL AXIsElementStackLike(UIView *view) {
    if (!view) return NO;
    NSString *name = AXClassName(view);
    if ([name containsString:@"ElementStackView"]) return YES;
    if ([name containsString:@"IESLiveStackView"]) return YES;
    if ([view respondsToSelector:@selector(arrangedSubviews)]) return YES;
    return NO;
}

static BOOL AXIsRightStack(UIView *view) {
    if (!view || !view.window) return NO;
    CGRect f = AXFrameInWindow(view);
    CGFloat w = CGRectGetWidth(view.window.bounds);
    if (w <= 0 || CGRectIsEmpty(f)) return NO;

    if (CGRectGetMidX(f) > w * 0.62) return YES;
    if (AXStackHasElementClassName(view, @"UserAvatar")) return YES;
    if (AXStackHasElementClassName(view, @"Interaction") && CGRectGetMidX(f) > w * 0.52) return YES;
    return NO;
}

static BOOL AXIsLeftStack(UIView *view) {
    if (!view || !view.window) return NO;
    CGRect f = AXFrameInWindow(view);
    CGFloat w = CGRectGetWidth(view.window.bounds);
    CGFloat h = CGRectGetHeight(view.window.bounds);
    if (w <= 0 || h <= 0 || CGRectIsEmpty(f)) return NO;

    if (CGRectGetMidX(f) < w * 0.56 && CGRectGetMidY(f) > h * 0.42) return YES;
    if (AXStackHasElementClassName(view, @"DescriptionElement")) return YES;
    if (AXStackHasElementClassName(view, @"FeedAnchorContainerView")) return YES;
    return NO;
}

static BOOL AXIsTopAreaView(UIView *view) {
    if (!view || !view.window) return NO;
    CGRect f = AXFrameInWindow(view);
    CGFloat h = CGRectGetHeight(view.window.bounds);
    if (h <= 0 || CGRectIsEmpty(f)) return NO;
    if (CGRectGetMinY(f) < 130.0 && CGRectGetHeight(f) < 180.0) return YES;
    return NO;
}

static BOOL AXIsOverlayLeafView(UIView *view) {
    if (!view || AXIsAwemeXPanelView(view)) return NO;
    if ([view isKindOfClass:[UILabel class]]) return YES;
    if ([view isKindOfClass:[UIButton class]]) return YES;
    if ([view isKindOfClass:[UIImageView class]]) return YES;
    return NO;
}

static BOOL AXAncestorIsElementStackLike(UIView *view) {
    UIView *v = view.superview;
    while (v) {
        if (AXIsElementStackLike(v)) return YES;
        v = v.superview;
    }
    return NO;
}

static void AXApplyAlphaKeepingBase(UIView *view, CGFloat targetAlpha) {
    if (!view || AXIsAwemeXPanelView(view)) return;

    CGFloat cleanTarget = AXClamp(targetAlpha, 0.0, 1.0);
    NSNumber *stored = objc_getAssociatedObject(view, &kAXBaseAlphaKey);
    CGFloat baseAlpha = stored ? [stored floatValue] : view.alpha;

    // When the host app resets a view to fully visible, update the base so old values do not poison reused cells.
    if (!axApplyingElementEffects && view.alpha > 0.95 && (!stored || fabs([stored floatValue] - view.alpha) > 0.02)) {
        baseAlpha = view.alpha;
        objc_setAssociatedObject(view, &kAXBaseAlphaKey, @(baseAlpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (!stored) {
        objc_setAssociatedObject(view, &kAXBaseAlphaKey, @(baseAlpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    CGFloat finalAlpha = AXClamp(baseAlpha * cleanTarget, 0.0, 1.0);
    if (fabs(view.alpha - finalAlpha) > 0.005) {
        axApplyingElementEffects = YES;
        view.alpha = finalAlpha;
        axApplyingElementEffects = NO;
    }
}

static CGAffineTransform AXRightStackTargetTransform(UIView *view) {
    CGFloat scale = AXClamp(AXFloatForKey(kAXScale, 1.0), 0.50, 1.50);
    return CGAffineTransformMakeScale(scale, scale);
}

static CGAffineTransform AXLeftStackTargetTransform(UIView *view) {
    CGFloat scale = AXClamp(AXFloatForKey(kAXNicknameScale, 1.0), 0.50, 1.50);
    return CGAffineTransformMakeScale(scale, scale);
}

static void AXApplySearchEntranceHide(UIView *view) {
    if (!view || AXIsAwemeXPanelView(view)) return;
    BOOL hide = AXBoolForKey(kAXHideSearch, NO);
    view.hidden = hide;
    AXApplyAlphaKeepingBase(view, hide ? 0.0 : AXGlobalAlpha());
}

static void AXApplyOverlayLeafAlpha(UIView *view) {
    if (!AXIsOverlayLeafView(view)) return;
    if (AXAncestorIsElementStackLike(view)) return;
    if (!view.window) return;

    CGFloat target = AXGlobalAlpha();
    CGRect f = AXFrameInWindow(view);
    CGFloat w = CGRectGetWidth(view.window.bounds);
    CGFloat h = CGRectGetHeight(view.window.bounds);

    if (w > 0 && h > 0) {
        if (CGRectGetMidY(f) < 130.0) {
            target = AXEffectiveAlpha(kAXTopAlpha, 1.0);
        } else if (CGRectGetMidX(f) > w * 0.62) {
            target = AXEffectiveAlpha(kAXRightAlpha, 1.0);
        } else if (CGRectGetMidX(f) < w * 0.58 && CGRectGetMidY(f) > h * 0.42) {
            // 左下角昵称/文案区域只吃全局透明，不再二次套右侧栏/头像透明。
            target = AXGlobalAlpha();
        }
    }

    AXApplyAlphaKeepingBase(view, target);
}

static void AXApplyElementEffects(id object) {
    UIView *view = AXViewFromAny(object);
    if (!view || AXIsAwemeXPanelView(view)) return;

    CGFloat targetAlpha = AXGlobalAlpha();

    if (AXIsTopAreaView(view)) {
        targetAlpha = AXEffectiveAlpha(kAXTopAlpha, 1.0);
    }

    if (AXIsRightStack(view)) {
        targetAlpha = AXEffectiveAlpha(kAXRightAlpha, 1.0);
        view.layer.anchorPoint = CGPointMake(1.0, 0.5);
        view.transform = AXRightStackTargetTransform(view);
    } else if (AXIsLeftStack(view)) {
        // 左下角昵称/文案区域：保留全局透明，缩放单独处理，避免透明度重复相乘。
        targetAlpha = AXGlobalAlpha();
        view.layer.anchorPoint = CGPointMake(0.0, 0.5);
        view.transform = AXLeftStackTargetTransform(view);
    }

    if (AXStackHasElementClassName(view, @"UserAvatar") || AXStackHasElementClassName(view, @"Avatar")) {
        targetAlpha = AXEffectiveAlpha(kAXIconAlpha, 1.0);
    }

    AXApplyAlphaKeepingBase(view, targetAlpha);

    for (UIView *subview in view.subviews) {
        AXApplyOverlayLeafAlpha(subview);
    }
}

static void AXApplyToSubviews(UIView *view) {
    if (!view || AXIsAwemeXPanelView(view)) return;
    AXApplyElementEffects(view);
    AXApplyOverlayLeafAlpha(view);
    for (UIView *subview in view.subviews) {
        AXApplyToSubviews(subview);
    }
}

#pragma mark - Settings Panel

@interface AXMenuTarget : NSObject
+ (instancetype)shared;
- (void)openSettings;
- (void)closeSettings;
- (void)resetSettings;
- (void)sliderChanged:(UISlider *)slider;
- (void)switchChanged:(UISwitch *)sender;
@end

static UILabel *AXLabel(NSString *text, CGRect frame, CGFloat size, BOOL bold) {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.text = text;
    label.textColor = [UIColor whiteColor];
    label.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    label.numberOfLines = 1;
    return label;
}

static UISlider *AXSlider(UIView *panel, NSString *title, NSString *key, NSInteger tag, CGFloat y, CGFloat minValue, CGFloat maxValue, CGFloat fallback) {
    UILabel *name = AXLabel(title, CGRectMake(18, y, 170, 28), 14, NO);
    [panel addSubview:name];

    CGFloat value = AXFloatForKey(key, fallback);
    value = AXClamp(value, minValue, maxValue);

    UILabel *valueLabel = AXLabel([NSString stringWithFormat:@"%.0f%%", value * 100.0], CGRectMake(CGRectGetWidth(panel.bounds) - 70, y, 52, 28), 13, NO);
    valueLabel.textAlignment = NSTextAlignmentRight;
    valueLabel.tag = tag + 10000;
    [panel addSubview:valueLabel];

    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(18, y + 30, CGRectGetWidth(panel.bounds) - 36, 28)];
    slider.minimumValue = minValue;
    slider.maximumValue = maxValue;
    slider.value = value;
    slider.tag = tag;
    [slider addTarget:[AXMenuTarget shared] action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:slider];
    return slider;
}

static UISwitch *AXSwitch(UIView *panel, NSString *title, NSString *key, NSInteger tag, CGFloat y, BOOL fallback) {
    UILabel *name = AXLabel(title, CGRectMake(18, y, 220, 34), 14, NO);
    [panel addSubview:name];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(CGRectGetWidth(panel.bounds) - 68, y, 52, 34)];
    sw.tag = tag;
    sw.on = AXBoolForKey(key, fallback);
    [sw addTarget:[AXMenuTarget shared] action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:sw];
    return sw;
}

@implementation AXMenuTarget

+ (instancetype)shared {
    static AXMenuTarget *target = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        target = [AXMenuTarget new];
    });
    return target;
}

- (NSString *)keyForSliderTag:(NSInteger)tag {
    switch (tag) {
        case 1001: return kAXTopAlpha;
        case 1002: return kAXRightAlpha;
        case 1003: return kAXScale;
        case 1004: return kAXIconAlpha;
        case 1005: return kAXGlobalAlpha;
        case 1006: return kAXNicknameScale;
        default: return nil;
    }
}

- (NSString *)keyForSwitchTag:(NSInteger)tag {
    switch (tag) {
        case 2001: return kAXHideSearch;
        case 2002: return kAXShowButton;
        default: return nil;
    }
}

- (UILabel *)valueLabelForControl:(UIControl *)control {
    UIView *panel = control.superview;
    while (panel && panel.tag != kAXPanelTag) panel = panel.superview;
    UIView *label = [panel viewWithTag:control.tag + 10000];
    return [label isKindOfClass:[UILabel class]] ? (UILabel *)label : nil;
}

- (void)closeSettings {
    UIWindow *window = AXActiveWindow();
    UIView *old = [window viewWithTag:kAXPanelTag];
    [old removeFromSuperview];
}

- (void)resetSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@1.0 forKey:kAXTopAlpha];
    [defaults setObject:@1.0 forKey:kAXRightAlpha];
    [defaults setObject:@1.0 forKey:kAXScale];
    [defaults setObject:@1.0 forKey:kAXIconAlpha];
    [defaults setObject:@1.0 forKey:kAXGlobalAlpha];
    [defaults setObject:@1.0 forKey:kAXNicknameScale];
    [defaults setObject:@NO forKey:kAXHideSearch];
    [defaults setObject:@YES forKey:kAXShowButton];
    [defaults synchronize];

    UIWindow *window = AXActiveWindow();
    if (window) AXApplyToSubviews(window);

    [self closeSettings];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[AXMenuTarget shared] openSettings];
    });
}

- (void)sliderChanged:(UISlider *)slider {
    NSString *key = [self keyForSliderTag:slider.tag];
    if (!key) return;

    CGFloat value = AXClamp(slider.value, slider.minimumValue, slider.maximumValue);
    [[NSUserDefaults standardUserDefaults] setObject:@(value) forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];

    UILabel *valueLabel = [self valueLabelForControl:slider];
    if (valueLabel) {
        valueLabel.text = [NSString stringWithFormat:@"%.0f%%", value * 100.0];
    }

    UIWindow *window = AXActiveWindow();
    if (window) AXApplyToSubviews(window);
}

- (void)switchChanged:(UISwitch *)sender {
    NSString *key = [self keyForSwitchTag:sender.tag];
    if (!key) return;

    [[NSUserDefaults standardUserDefaults] setObject:@(sender.isOn) forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];

    UIWindow *window = AXActiveWindow();
    if (window) AXApplyToSubviews(window);
}


- (void)openSettings {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = AXActiveWindow();
        if (!window) return;

        UIView *old = [window viewWithTag:kAXPanelTag];
        if (old) {
            [old removeFromSuperview];
            return;
        }

        CGRect bounds = window.bounds;
        UIView *container = [[UIView alloc] initWithFrame:bounds];
        container.tag = kAXPanelTag;
        container.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];
        container.userInteractionEnabled = YES;
        container.layer.zPosition = 999999;

        CGFloat panelWidth = MIN(430.0, CGRectGetWidth(bounds) - 48.0);
        CGFloat panelHeight = MIN(560.0, CGRectGetHeight(bounds) - 80.0);
        UIView *panel = [[UIView alloc] initWithFrame:CGRectMake((CGRectGetWidth(bounds) - panelWidth) / 2.0,
                                                                 (CGRectGetHeight(bounds) - panelHeight) / 2.0,
                                                                 panelWidth,
                                                                 panelHeight)];
        panel.backgroundColor = [[UIColor colorWithWhite:0.08 alpha:1.0] colorWithAlphaComponent:0.94];
        panel.layer.cornerRadius = 18.0;
        panel.clipsToBounds = YES;
        [container addSubview:panel];

        UILabel *title = AXLabel(@"AwemeX iPad 设置", CGRectMake(18, 14, panelWidth - 36, 34), 19, YES);
        title.textAlignment = NSTextAlignmentCenter;
        [panel addSubview:title];

        CGFloat y = 58.0;
        AXSlider(panel, @"顶栏透明", kAXTopAlpha, 1001, y, 0.05, 1.0, 1.0); y += 70.0;
        AXSlider(panel, @"右侧栏透明", kAXRightAlpha, 1002, y, 0.05, 1.0, 1.0); y += 70.0;
        AXSlider(panel, @"右侧栏缩放", kAXScale, 1003, y, 0.50, 1.50, 1.0); y += 70.0;
        AXSlider(panel, @"头像透明", kAXIconAlpha, 1004, y, 0.05, 1.0, 1.0); y += 70.0;
        AXSlider(panel, @"全局透明", kAXGlobalAlpha, 1005, y, 0.05, 1.0, 1.0); y += 70.0;
        AXSlider(panel, @"昵称文案缩放", kAXNicknameScale, 1006, y, 0.50, 1.50, 1.0); y += 72.0;

        AXSwitch(panel, @"隐藏搜索入口", kAXHideSearch, 2001, y, NO); y += 44.0;
        AXSwitch(panel, @"显示按钮区域", kAXShowButton, 2002, y, YES); y += 52.0;

        UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
        reset.frame = CGRectMake(18, panelHeight - 54, (panelWidth - 54) / 2.0, 38);
        [reset setTitle:@"重置" forState:UIControlStateNormal];
        [reset setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        reset.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.14];
        reset.layer.cornerRadius = 10.0;
        [reset addTarget:[AXMenuTarget shared] action:@selector(resetSettings) forControlEvents:UIControlEventTouchUpInside];
        [panel addSubview:reset];

        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.frame = CGRectMake(CGRectGetMaxX(reset.frame) + 18, panelHeight - 54, (panelWidth - 54) / 2.0, 38);
        [close setTitle:@"关闭" forState:UIControlStateNormal];
        [close setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        close.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.14];
        close.layer.cornerRadius = 10.0;
        [close addTarget:[AXMenuTarget shared] action:@selector(closeSettings) forControlEvents:UIControlEventTouchUpInside];
        [panel addSubview:close];

        [window addSubview:container];
        [window bringSubviewToFront:container];
    });
}

@end

#pragma mark - Two Finger Long Press

@interface AXTwoFingerLongPressTarget : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)handleTwoFingerLongPress:(UILongPressGestureRecognizer *)gesture;
@end

@implementation AXTwoFingerLongPressTarget

+ (instancetype)shared {
    static AXTwoFingerLongPressTarget *target = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        target = [AXTwoFingerLongPressTarget new];
    });
    return target;
}

- (void)handleTwoFingerLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[AXMenuTarget shared] openSettings];
    });
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    UIView *view = touch.view;
    if (AXIsAwemeXPanelView(view)) return YES;
    return YES;
}

@end

static void AXInstallTwoFingerLongPressGesture(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = AXActiveWindow();
        if (!window) return;

        NSNumber *installed = objc_getAssociatedObject(window, &kAXTwoFingerGestureInstalledKey);
        if (installed.boolValue) return;

        UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc] initWithTarget:[AXTwoFingerLongPressTarget shared]
                                                                                              action:@selector(handleTwoFingerLongPress:)];
        gesture.numberOfTouchesRequired = 2;
        gesture.minimumPressDuration = 0.75;
        gesture.cancelsTouchesInView = NO;
        gesture.delaysTouchesBegan = NO;
        gesture.delaysTouchesEnded = NO;
        gesture.delegate = [AXTwoFingerLongPressTarget shared];
        gesture.name = @"AwemeXTwoFingerLongPress";
        [window addGestureRecognizer:gesture];

        axTwoFingerLongPressGesture = gesture;
        objc_setAssociatedObject(window, &kAXTwoFingerGestureInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

#pragma mark - Hooks

%hook AWEElementStackView
- (void)layoutSubviews {
    %orig;
    AXApplyElementEffects((id)self);
}
- (void)didMoveToWindow {
    %orig;
    AXApplyElementEffects((id)self);
}
- (NSArray *)arrangedSubviews {
    NSArray *arr = %orig;
    AXApplyElementEffects((id)self);
    return arr;
}
- (void)setTransform:(CGAffineTransform)transform {
    %orig(transform);
    AXApplyElementEffects((id)self);
}
%end

%hook IESLiveStackView
- (void)layoutSubviews {
    %orig;
    AXApplyElementEffects((id)self);
}
- (void)didMoveToWindow {
    %orig;
    AXApplyElementEffects((id)self);
}
- (NSArray *)arrangedSubviews {
    NSArray *arr = %orig;
    AXApplyElementEffects((id)self);
    return arr;
}
- (void)setTransform:(CGAffineTransform)transform {
    %orig(transform);
    AXApplyElementEffects((id)self);
}
%end

%hook AWESearchEntranceView
- (void)layoutSubviews {
    %orig;
    AXApplySearchEntranceHide(AXViewFromAny((id)self));
}
- (void)didMoveToWindow {
    %orig;
    AXApplySearchEntranceHide(AXViewFromAny((id)self));
}
%end

%hook AWEHPDiscoverFeedEntranceView
- (void)layoutSubviews {
    %orig;
    AXApplySearchEntranceHide(AXViewFromAny((id)self));
}
- (void)didMoveToWindow {
    %orig;
    AXApplySearchEntranceHide(AXViewFromAny((id)self));
}
%end

%hook UILabel
- (void)layoutSubviews {
    %orig;
    AXApplyOverlayLeafAlpha((UIView *)self);
}
%end

%hook UIButton
- (void)layoutSubviews {
    %orig;
    AXApplyOverlayLeafAlpha((UIView *)self);
}
%end

%hook UIImageView
- (void)layoutSubviews {
    %orig;
    AXApplyOverlayLeafAlpha((UIView *)self);
}
%end

%hook UIApplication
- (void)applicationDidBecomeActive:(id)application {
    %orig(application);
    AXInstallTwoFingerLongPressGesture();
    UIWindow *window = AXActiveWindow();
    if (window) AXApplyToSubviews(window);
}
%end

%ctor {
    @autoreleasepool {
        if (!AXIsIpad()) return;

        %init;

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            AXInstallTwoFingerLongPressGesture();
            UIWindow *window = AXActiveWindow();
            if (window) AXApplyToSubviews(window);
        });

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            AXInstallTwoFingerLongPressGesture();
            UIWindow *window = AXActiveWindow();
            if (window) AXApplyToSubviews(window);
        });
    }
}
