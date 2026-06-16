#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <math.h>

static const CGFloat TLInvalidAlpha = -1.0;
static const CGFloat TLMinVisibleAlpha = 0.011;
static NSString *const TLGlobalTransparencyKey = @"DYYYGlobalTransparency";
static NSString *const TLTopBarTransparencyKey = @"DYYYTopBarTransparent";
static NSString *const TLAvatarTransparencyKey = @"DYYYAvatarViewTransparency";
static char TLBaseAlphaKey;
static NSInteger TLAlphaMutationDepth = 0;
static CFTimeInterval TLLastPrefsRead = 0;
static CGFloat TLGlobalAlpha = TLInvalidAlpha;
static CGFloat TLTopBarAlpha = TLInvalidAlpha;
static CGFloat TLAvatarAlpha = TLInvalidAlpha;

static inline BOOL TLIsIpad(void) {
    return [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
}

static inline CGFloat TLClampAlpha(CGFloat value) {
    if (isnan(value) || isinf(value)) return 1.0;
    if (value < 0.0) return 0.0;
    if (value > 1.0) return 1.0;
    return value;
}

static CGFloat TLReadAlphaForKey(NSString *key) {
    id raw = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (![raw respondsToSelector:@selector(floatValue)]) return TLInvalidAlpha;
    NSString *stringValue = [raw isKindOfClass:[NSString class]] ? (NSString *)raw : [raw stringValue];
    if (stringValue.length == 0) return TLInvalidAlpha;
    return TLClampAlpha([raw floatValue]);
}

static void TLLoadPrefsIfNeeded(BOOL force) {
    CFTimeInterval now = CACurrentMediaTime();
    if (!force && now - TLLastPrefsRead < 0.25) return;
    TLLastPrefsRead = now;
    TLGlobalAlpha = TLReadAlphaForKey(TLGlobalTransparencyKey);
    TLTopBarAlpha = TLReadAlphaForKey(TLTopBarTransparencyKey);
    TLAvatarAlpha = TLReadAlphaForKey(TLAvatarTransparencyKey);
}

static CGFloat TLEffectiveAlpha(CGFloat baseAlpha, CGFloat factor) {
    baseAlpha = TLClampAlpha(baseAlpha);
    if (factor == TLInvalidAlpha) return baseAlpha;
    CGFloat finalAlpha = TLClampAlpha(baseAlpha * factor);
    if (baseAlpha > 0.0 && finalAlpha < TLMinVisibleAlpha) finalAlpha = TLMinVisibleAlpha;
    return finalAlpha;
}

static void TLSetAlphaWithoutRebase(id view, CGFloat alpha) {
    if (!view || ![view isKindOfClass:[UIView class]]) return;
    UIView *targetView = (UIView *)view;
    TLAlphaMutationDepth++;
    targetView.alpha = alpha;
    TLAlphaMutationDepth--;
}

static void TLApplyGlobalAlpha(id view) {
    if (!view || ![view isKindOfClass:[UIView class]]) return;
    UIView *targetView = (UIView *)view;
    if (!TLIsIpad() || !targetView.window) return;
    TLLoadPrefsIfNeeded(NO);
    NSNumber *stored = objc_getAssociatedObject(targetView, &TLBaseAlphaKey);
    CGFloat baseAlpha = stored ? stored.floatValue : targetView.alpha;
    if (!stored) {
        objc_setAssociatedObject(targetView, &TLBaseAlphaKey, @(baseAlpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat finalAlpha = TLEffectiveAlpha(baseAlpha, TLGlobalAlpha);
    if (fabs(targetView.alpha - finalAlpha) >= 0.001) {
        TLSetAlphaWithoutRebase(targetView, finalAlpha);
    }
}

static CGFloat TLAlphaForStackView(id view, CGFloat alpha) {
    if (!view || ![view isKindOfClass:[UIView class]]) return alpha;
    UIView *targetView = (UIView *)view;
    if (!TLIsIpad() || TLAlphaMutationDepth > 0) return alpha;
    TLLoadPrefsIfNeeded(NO);
    CGFloat baseAlpha = TLClampAlpha(alpha);
    objc_setAssociatedObject(targetView, &TLBaseAlphaKey, @(baseAlpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return TLEffectiveAlpha(baseAlpha, TLGlobalAlpha);
}

static void TLDelayedApplyGlobalAlpha(id view) {
    if (!view || ![view isKindOfClass:[UIView class]]) return;
    UIView *targetView = (UIView *)view;
    if (!targetView.window || !TLIsIpad()) return;
    TLApplyGlobalAlpha(targetView);
    __weak UIView *weakView = targetView;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        TLApplyGlobalAlpha(weakView);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        TLApplyGlobalAlpha(weakView);
    });
}

%hook AWEFeedTopBarContainer
- (void)didMoveToSuperview {
    %orig;
    if (!TLIsIpad()) return;
    TLLoadPrefsIfNeeded(NO);
    if (TLTopBarAlpha != TLInvalidAlpha) {
        TLSetAlphaWithoutRebase(self, TLEffectiveAlpha(1.0, TLTopBarAlpha));
    }
}
- (void)setAlpha:(CGFloat)alpha {
    if (!TLIsIpad() || TLAlphaMutationDepth > 0) {
        %orig(alpha);
        return;
    }
    TLLoadPrefsIfNeeded(NO);
    if (TLTopBarAlpha == TLInvalidAlpha) {
        %orig(alpha);
    } else {
        %orig(TLEffectiveAlpha(alpha, TLTopBarAlpha));
    }
}
%end

%hook AWEAdAvatarView
- (void)layoutSubviews {
    %orig;
    if (!TLIsIpad()) return;
    TLLoadPrefsIfNeeded(NO);
    if (TLAvatarAlpha != TLInvalidAlpha) {
        TLSetAlphaWithoutRebase(self, TLEffectiveAlpha(1.0, TLAvatarAlpha));
    }
}
%end

%hook LOTAnimationView
- (void)layoutSubviews {
    %orig;
    if (!TLIsIpad()) return;
    UIView *targetView = [(id)self isKindOfClass:[UIView class]] ? (UIView *)(id)self : nil;
    if (targetView && [targetView.superview isKindOfClass:NSClassFromString(@"AWEPlayInteractionFollowPromptView")]) {
        TLLoadPrefsIfNeeded(NO);
        if (TLAvatarAlpha != TLInvalidAlpha) {
            TLSetAlphaWithoutRebase(self, TLEffectiveAlpha(1.0, TLAvatarAlpha));
        }
    }
}
%end

%hook AWEElementStackView
- (void)setAlpha:(CGFloat)alpha {
    %orig(TLAlphaForStackView(self, alpha));
}
- (void)didMoveToWindow {
    %orig;
    TLDelayedApplyGlobalAlpha(self);
}
%end

%hook IESLiveStackView
- (void)setAlpha:(CGFloat)alpha {
    %orig(TLAlphaForStackView(self, alpha));
}
- (void)didMoveToWindow {
    %orig;
    TLDelayedApplyGlobalAlpha(self);
}
%end

%hook AWELandscapeFeedEntryView
- (void)setAlpha:(CGFloat)alpha {
    %orig(TLAlphaForStackView(self, alpha));
}
- (void)didMoveToWindow {
    %orig;
    TLDelayedApplyGlobalAlpha(self);
}
%end

%ctor {
    TLLoadPrefsIfNeeded(YES);
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(__unused NSNotification *note) {
        TLLoadPrefsIfNeeded(YES);
    }];
}
