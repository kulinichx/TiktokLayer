#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <math.h>

static CGFloat gAlphaTop = 1.0;
static CFTimeInterval gLastPrefsRead = 0;
static const CGFloat kMinVisibleAlpha = 0.011;

static inline BOOL TLIsIpad(void) {
    return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad;
}

static inline CGFloat TLClampAlpha(CGFloat value) {
    if (isnan(value) || isinf(value)) return 1.0;
    if (value < 0.0) return 0.0;
    if (value > 1.0) return 1.0;
    return value;
}

static void TLLoadSettingsIfNeeded(void) {
    CFTimeInterval now = CACurrentMediaTime();
    if (now - gLastPrefsRead < 0.5) return;
    gLastPrefsRead = now;

    id raw = [[NSUserDefaults standardUserDefaults] objectForKey:@"alpha_top"];
    if ([raw respondsToSelector:@selector(floatValue)]) {
        CGFloat value = TLClampAlpha([raw floatValue]);
        gAlphaTop = value;
    } else {
        gAlphaTop = 1.0;
    }
}

static BOOL TLShouldAdjustView(UIView *view) {
    if (!view || !TLIsIpad()) return NO;
    if ([view isKindOfClass:[UIWindow class]]) return NO;

    NSString *className = NSStringFromClass([view class]);
    if ([className hasPrefix:@"UIKeyboard"] || [className hasPrefix:@"UIText"] || [className hasPrefix:@"WK"]) {
        return NO;
    }

    // 优先限制在抖音常见的顶栏 / 播放交互 / 直播图层，避免全局污染所有 UIKit 视图。
    static NSArray<NSString *> *targetKeywords;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        targetKeywords = @[
            @"TopBar", @"Tab", @"PlayInteraction", @"ElementStack",
            @"LandscapeFeed", @"Feed", @"Live", @"AWE", @"IESLive", @"AFD"
        ];
    });

    for (NSString *keyword in targetKeywords) {
        if ([className containsString:keyword]) return YES;
    }

    return NO;
}

%hook UIView

- (void)setAlpha:(CGFloat)alpha {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setAlpha:alpha];
        });
        return;
    }

    if (!TLShouldAdjustView(self)) {
        %orig(alpha);
        return;
    }

    TLLoadSettingsIfNeeded();

    CGFloat baseAlpha = TLClampAlpha(alpha);
    CGFloat finalAlpha = TLClampAlpha(baseAlpha * gAlphaTop);

    // 0 会让很多容器不可交互；保留极小 alpha，兼容原 DYYY 顶栏透明处理思路。
    if (baseAlpha > 0.0 && finalAlpha < kMinVisibleAlpha) {
        finalAlpha = kMinVisibleAlpha;
    }

    if (fabs(self.alpha - finalAlpha) <= 0.001) {
        return;
    }

    %orig(finalAlpha);
}

%end
