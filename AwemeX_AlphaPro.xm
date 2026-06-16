#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

@interface AWEElementStackView : UIView @end
@interface IESLiveStackView : UIView @end
@interface AWELandscapeFeedEntryView : UIView @end
@interface AWEFeedTopBarContainer : UIView @end
@interface AWESearchEntranceView : UIView @end
@interface AWEHPDiscoverFeedEntranceView : UIView @end
@interface AWEPlayInteractionSearchAnchorView : UIView @end
@interface AWEFeedAnchorContainerView : UIView @end
@interface AWEAwemeModel : NSObject @end
@interface AWEPlayInteractionViewController : UIViewController @end

static UIButton *axButton = nil;
static UIView *axPanel = nil;
static BOOL axApplyingElementEffects = NO;
static BOOL axSettingAlpha = NO;
static BOOL axMainRefreshScheduled = NO;
static UILongPressGestureRecognizer *axTwoFingerLongPressGesture = nil;
static UIWindow *axTwoFingerLongPressWindow = nil;

static NSString * const kAXTopAlpha = @"ax_top_alpha";
static NSString * const kAXRightAlpha = @"ax_right_alpha";
static NSString * const kAXScale = @"ax_scale";
static NSString * const kAXIconAlpha = @"ax_icon_alpha";
static NSString * const kAXGlobalAlpha = @"ax_global_alpha";
static NSString * const kAXNicknameScale = @"ax_nickname_scale";
static NSString * const kAXHideSearch = @"ax_hide_search";
static NSString * const kAXShowButton = @"ax_show_button";
static NSString * const kAXOFNicknameDescAlpha = @"ax_nickname_desc_alpha";
static NSString * const kAXHideRelatedArea = @"ax_hide_related_area";

// 单指长按面板功能开关：来自 DYYY 长按面板保存类功能；不包含“生成视频/制作视频”。
static NSString * const kAXLPPanelSaveVideo = @"ax_lp_panel_save_video";
static NSString * const kAXLPPanelSaveCover = @"ax_lp_panel_save_cover";
static NSString * const kAXLPPanelSaveAudio = @"ax_lp_panel_save_audio";
static NSString * const kAXLPPanelSaveImage = @"ax_lp_panel_save_image";
static NSString * const kAXLPPanelSaveAllImages = @"ax_lp_panel_save_all_images";
static NSString * const kAXLPPanelCopyText = @"ax_lp_panel_copy_text";

static CGFloat AXFloat(NSString *key, CGFloat def) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return v ? [v floatValue] : def;
}

static BOOL AXBool(NSString *key, BOOL def) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return v ? [v boolValue] : def;
}

static void AXSetFast(NSString *key, id value) {
    if (!key) return;
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:key];
}

static void AXSet(NSString *key, id value) {
    AXSetFast(key, value);
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static CGFloat AXClamp01(CGFloat v) {
    return MIN(MAX(v, 0.0), 1.0);
}

static CGFloat AXGlobalAlpha(void) {
    return AXClamp01(AXFloat(kAXGlobalAlpha, 1.0));
}

static CGFloat AXEffectiveAlpha(NSString *key, CGFloat def) {
    return AXClamp01(AXFloat(key, def) * AXGlobalAlpha());
}

static UIWindow *AXKeyWindow(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) return w;
            }
        }
    }
    for (UIWindow *w in app.windows) if (w.isKeyWindow) return w;
    return app.windows.firstObject;
}

static BOOL AXIsDescendantOf(UIView *v, UIView *ancestor) {
    if (!v || !ancestor) return NO;
    UIView *cur = v;
    while (cur) {
        if (cur == ancestor) return YES;
        cur = cur.superview;
    }
    return NO;
}

static BOOL AXIsAwemeXPanelView(UIView *v) {
    return AXIsDescendantOf(v, axPanel) || AXIsDescendantOf(v, axButton);
}

static NSHashTable *AXTrackedElementViews(void) {
    static NSHashTable *table = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ table = [NSHashTable weakObjectsHashTable]; });
    return table;
}

static NSHashTable *AXTrackedTopBarViews(void) {
    static NSHashTable *table = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ table = [NSHashTable weakObjectsHashTable]; });
    return table;
}


static NSHashTable *AXTrackedSearchViews(void) {
    static NSHashTable *table = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ table = [NSHashTable weakObjectsHashTable]; });
    return table;
}

static BOOL AXStringContainsAny(NSString *text, NSArray *needles) {
    if (text.length == 0) return NO;
    for (NSString *needle in needles) {
        if (needle.length > 0 && [text containsString:needle]) return YES;
    }
    return NO;
}

static BOOL AXIsHomeFeedContext(UIView *v) {
    if (!v || AXIsAwemeXPanelView(v)) return NO;
    NSString *selfName = NSStringFromClass(v.class);
    if ([selfName containsString:@"AWEFeedTopBar"] || [selfName containsString:@"AWESearchEntrance"] || [selfName containsString:@"AWEHPDiscoverFeedEntrance"]) return YES;

    NSArray *deny = @[@"AWEIM", @"IM", @"Chat", @"Message", @"Conversation", @"Profile", @"UserHome", @"Mine", @"MineView", @"Setting", @"Comment", @"Share", @"SearchResult", @"SearchPage", @"Publish", @"Input", @"Keyboard", @"Alert", @"Popup"];
    NSArray *allow = @[@"AWEPlayInteractionViewController", @"AWEFeedCellViewController", @"PureModePageCellViewController", @"AWEFeedPlayControl", @"AWELandscapeFeed", @"AWEFeedPlay", @"AWEPlayerFeed", @"AWEElementStackView", @"IESLiveStackView", @"AWELandscapeFeedEntryView"];

    UIResponder *responder = v;
    NSInteger steps = 0;
    while (responder && steps++ < 18) {
        NSString *name = NSStringFromClass([responder class]);
        if (AXStringContainsAny(name, deny)) return NO;
        if (AXStringContainsAny(name, allow)) return YES;
        responder = responder.nextResponder;
    }

    UIView *cur = v;
    steps = 0;
    while (cur && steps++ < 10) {
        NSString *name = NSStringFromClass([cur class]);
        if (AXStringContainsAny(name, deny)) return NO;
        if (AXStringContainsAny(name, allow)) return YES;
        cur = cur.superview;
    }
    return NO;
}

static BOOL AXIsElementStackLike(UIView *v) {
    if (!v) return NO;
    Class aweStack = NSClassFromString(@"AWEElementStackView");
    Class iesStack = NSClassFromString(@"IESLiveStackView");
    Class landStack = NSClassFromString(@"AWELandscapeFeedEntryView");
    if (aweStack && [v isKindOfClass:aweStack]) return YES;
    if (iesStack && [v isKindOfClass:iesStack]) return YES;
    if (landStack && [v isKindOfClass:landStack]) return YES;
    NSString *cls = NSStringFromClass(v.class);
    return [cls containsString:@"AWEElementStackView"] || [cls containsString:@"IESLiveStackView"] || [cls containsString:@"AWELandscapeFeedEntryView"];
}

static UIViewController *AXFirstViewControllerFromView(UIView *view) {
    UIResponder *responder = view;
    while (responder) {
        if ([responder isKindOfClass:UIViewController.class]) return (UIViewController *)responder;
        responder = responder.nextResponder;
    }
    return nil;
}

static BOOL AXContainsSubviewOfClass(UIView *container, Class cls) {
    if (!container || !cls) return NO;
    for (UIView *sub in container.subviews) {
        if ([sub isKindOfClass:cls]) return YES;
        if (AXContainsSubviewOfClass(sub, cls)) return YES;
    }
    return NO;
}

static BOOL AXStackHasElementClassName(UIView *container, NSString *targetName) {
    if (!container || targetName.length == 0) return NO;
    NSArray *subviews = [container.subviews copy];
    for (NSInteger i = (NSInteger)subviews.count - 1; i >= 0; i--) {
        UIView *sub = subviews[i];
        if ([sub respondsToSelector:@selector(elementClassName)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            NSString *name = [sub performSelector:@selector(elementClassName)];
#pragma clang diagnostic pop
            if ([name isEqualToString:targetName]) return YES;
        }
        if (AXStackHasElementClassName(sub, targetName)) return YES;
    }
    return NO;
}

static BOOL AXIsTopAreaFrame(UIView *v) {
    if (!v || !v.superview) return NO;
    UIWindow *w = v.window ?: AXKeyWindow();
    if (!w) return NO;
    CGRect f = [v.superview convertRect:v.frame toView:w];
    CGFloat screenW = UIScreen.mainScreen.bounds.size.width;
    CGFloat screenH = UIScreen.mainScreen.bounds.size.height;
    if (CGRectIsEmpty(f) || f.size.width <= 0 || f.size.height <= 0) return NO;
    if (f.origin.y < screenH * 0.015 || f.origin.y > screenH * 0.20) return NO;
    if (f.size.height > 120.0) return NO;
    if (f.size.width > screenW * 0.90) return NO;
    return YES;
}

static BOOL AXIsLooseRightAreaStack(UIView *v) {
    if (!v || AXIsAwemeXPanelView(v) || !v.superview || !AXIsHomeFeedContext(v)) return NO;
    if ([v isKindOfClass:UIScrollView.class]) return NO;
    UIWindow *w = v.window ?: AXKeyWindow();
    if (!w) return NO;
    CGRect f = [v.superview convertRect:v.frame toView:w];
    CGFloat screenW = UIScreen.mainScreen.bounds.size.width;
    CGFloat screenH = UIScreen.mainScreen.bounds.size.height;
    if (CGRectIsEmpty(f) || f.size.width <= 0 || f.size.height <= 0) return NO;
    if (f.origin.x < screenW * 0.55) return NO;
    if (f.origin.y < screenH * 0.22) return NO;
    if (f.size.width > MIN(screenW * 0.34, 260.0)) return NO;
    if (f.size.height < 90.0 || f.size.height > screenH * 0.82) return NO;
    if (v.subviews.count < 2) return NO;
    return YES;
}

static BOOL AXIsSafeRightAreaStack(UIView *v) {
    if (!v || AXIsAwemeXPanelView(v) || !v.superview || !AXIsHomeFeedContext(v)) return NO;
    if ([v isKindOfClass:UIScrollView.class]) return NO;
    UIWindow *w = v.window ?: AXKeyWindow();
    if (!w) return NO;
    CGRect f = [v.superview convertRect:v.frame toView:w];
    CGFloat screenW = UIScreen.mainScreen.bounds.size.width;
    CGFloat screenH = UIScreen.mainScreen.bounds.size.height;
    if (CGRectIsEmpty(f) || f.size.width <= 0 || f.size.height <= 0) return NO;
    if (f.origin.x < screenW * 0.68) return NO;
    if (f.origin.y < screenH * 0.18) return NO;
    if (f.size.width > screenW * 0.28) return NO;
    if (f.size.height < 80.0 || f.size.height > screenH * 0.78) return NO;
    if (v.subviews.count < 2) return NO;
    return YES;
}

static BOOL AXIsRightStack(UIView *v) {
    if (!AXIsElementStackLike(v)) return NO;
    if (AXIsAwemeXPanelView(v) || !AXIsHomeFeedContext(v)) return NO;
    NSString *label = v.accessibilityLabel ?: @"";
    BOOL hasAvatar = AXContainsSubviewOfClass(v, NSClassFromString(@"AWEPlayInteractionUserAvatarView"));
    BOOL hasUserAvatarElement = AXStackHasElementClassName(v, @"AWEPlayInteractionUserAvatarOptElementElement");
    if ([label isEqualToString:@"right"] || hasAvatar || hasUserAvatarElement) return YES;
    if (AXIsLooseRightAreaStack(v)) return YES;
    UIViewController *vc = AXFirstViewControllerFromView(v);
    NSString *vcName = vc ? NSStringFromClass(vc.class) : @"";
    BOOL inPlayVC = [vcName containsString:@"AWEPlayInteractionViewController"] || [vcName containsString:@"AWELiveNewPreStreamViewController"];
    return inPlayVC && AXIsSafeRightAreaStack(v);
}

static BOOL AXIsLooseLeftAreaStack(UIView *v) {
    if (!v || AXIsAwemeXPanelView(v) || !v.superview || !AXIsHomeFeedContext(v)) return NO;
    if ([v isKindOfClass:UIScrollView.class]) return NO;
    UIWindow *w = v.window ?: AXKeyWindow();
    if (!w) return NO;
    CGRect f = [v.superview convertRect:v.frame toView:w];
    CGFloat screenW = UIScreen.mainScreen.bounds.size.width;
    CGFloat screenH = UIScreen.mainScreen.bounds.size.height;
    if (CGRectIsEmpty(f) || f.size.width <= 0 || f.size.height <= 0) return NO;
    if (f.origin.x > screenW * 0.58) return NO;
    if (f.origin.y < screenH * 0.45) return NO;
    if (f.size.width > screenW * 0.75 || f.size.height > screenH * 0.45) return NO;
    if (v.subviews.count < 1) return NO;
    return YES;
}

static BOOL AXIsLeftStack(UIView *v) {
    if (!AXIsElementStackLike(v)) return NO;
    if (AXIsAwemeXPanelView(v) || !AXIsHomeFeedContext(v)) return NO;
    NSString *label = v.accessibilityLabel ?: @"";
    BOOL hasAnchor = AXContainsSubviewOfClass(v, NSClassFromString(@"AWEFeedAnchorContainerView"));
    BOOL hasDescElement = AXStackHasElementClassName(v, @"AWEPlayInteractionDescriptionElement");
    if ([label isEqualToString:@"left"] || hasAnchor || hasDescElement) return YES;
    return AXIsLooseLeftAreaStack(v);
}

static BOOL AXIsTopStack(UIView *v) {
    if (!AXIsElementStackLike(v)) return NO;
    if (AXIsAwemeXPanelView(v) || !AXIsHomeFeedContext(v)) return NO;
    NSString *label = v.accessibilityLabel ?: @"";
    if ([label isEqualToString:@"top"] || [label isEqualToString:@"center"]) return YES;
    return AXIsTopAreaFrame(v);
}


static char kAXStackKindKey;
static NSInteger AXStackKind(UIView *v) {
    if (!v) return 0;
    NSNumber *cached = objc_getAssociatedObject(v, &kAXStackKindKey);
    if (cached) return cached.integerValue;
    NSInteger kind = 0;
    if (AXIsRightStack(v)) kind = 1;
    else if (AXIsLeftStack(v)) kind = 2;
    else if (AXIsTopStack(v)) kind = 3;
    if (kind > 0) objc_setAssociatedObject(v, &kAXStackKindKey, @(kind), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return kind;
}

static void AXSetViewAlpha(UIView *v, CGFloat alpha) {
    if (!v) return;
    alpha = AXClamp01(alpha);
    if (fabs(v.alpha - alpha) <= 0.001) return;
    axSettingAlpha = YES;
    v.alpha = alpha;
    axSettingAlpha = NO;
}

static char kAXBaseAlphaKey;
static void AXApplyAlphaKeepingBase(UIView *v, CGFloat multiplier) {
    if (!v) return;
    NSNumber *stored = objc_getAssociatedObject(v, &kAXBaseAlphaKey);
    CGFloat baseAlpha = stored ? stored.floatValue : v.alpha;
    if (!stored) objc_setAssociatedObject(v, &kAXBaseAlphaKey, @(baseAlpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    AXSetViewAlpha(v, baseAlpha * multiplier);
}

static CGAffineTransform AXRightStackTargetTransform(UIView *v) {
    CGFloat scale = AXFloat(kAXScale, 0.81);
    if (scale <= 0 || fabs(scale - 1.0) <= 0.001) return CGAffineTransformIdentity;
    CGFloat ty = 0;
    for (UIView *view in [v.subviews copy]) ty += (view.frame.size.height - view.frame.size.height * scale) / 2.0;
    CGFloat frameWidth = v.frame.size.width;
    CGFloat rightTX = (frameWidth - frameWidth * scale) / 2.0;
    return CGAffineTransformMake(scale, 0, 0, scale, rightTX, ty);
}

static CGAffineTransform AXLeftStackTargetTransform(UIView *v) {
    CGFloat scale = AXFloat(kAXNicknameScale, 1.0);
    if (scale <= 0 || fabs(scale - 1.0) <= 0.001) return CGAffineTransformIdentity;
    CGFloat ty = 0;
    for (UIView *view in [v.subviews copy]) ty += (view.frame.size.height - view.frame.size.height * scale) / 2.0;
    CGFloat frameWidth = v.frame.size.width;
    CGFloat leftTX = (frameWidth - frameWidth * scale) / 2.0 - frameWidth * (1 - scale);
    CGAffineTransform t = CGAffineTransformMakeScale(scale, scale);
    return CGAffineTransformTranslate(t, leftTX / scale, ty / scale);
}

static NSString *AXViewText(UIView *v) {
    if (!v) return @"";
    NSMutableString *out = [NSMutableString string];
    NSString *acc = v.accessibilityLabel;
    if (acc.length) [out appendFormat:@" %@", acc];
    if ([v isKindOfClass:UILabel.class]) {
        NSString *t = ((UILabel *)v).text;
        if (t.length) [out appendFormat:@" %@", t];
    } else if ([v isKindOfClass:UIButton.class]) {
        NSString *t = [(UIButton *)v titleForState:UIControlStateNormal] ?: ((UIButton *)v).currentTitle;
        if (t.length) [out appendFormat:@" %@", t];
    }
    return out;
}

static BOOL AXIsRelatedTextOrClass(UIView *v) {
    if (!v) return NO;
    NSString *txt = AXViewText(v);
    NSArray *needles = @[@"相关搜索", @"搜一搜", @"猜你想搜", @"大家都在搜", @"看合集", @"合集", @"下一集", @"上一集", @"第", @"集"];
    if (AXStringContainsAny(txt, needles)) return YES;
    NSString *cls = NSStringFromClass(v.class);
    NSArray *classNeedles = @[@"RelatedSearch", @"SearchAnchor", @"SearchAnchorView", @"FeedAnchor", @"AnchorContainer", @"Collection", @"Mix", @"MixVideo", @"Series", @"Compilation", @"Playlet", @"RelatedVideo"];
    return AXStringContainsAny(cls, classNeedles);
}

static char kAXRelatedHiddenMarkKey;
static void AXSetMarkedHidden(UIView *v, BOOL hidden) {
    if (!v || AXIsAwemeXPanelView(v)) return;
    objc_setAssociatedObject(v, &kAXRelatedHiddenMarkKey, hidden ? (id)@YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    v.hidden = hidden;
    v.userInteractionEnabled = !hidden;
}

static UIView *AXBestRelatedContainer(UIView *hit, UIView *root) {
    if (!hit || !root) return hit;
    UIView *candidate = hit;
    UIView *cur = hit;
    while (cur.superview && cur.superview != root) {
        CGRect f = cur.frame;
        if (f.size.height > 0 && f.size.height <= 96.0) candidate = cur;
        cur = cur.superview;
    }
    return candidate ?: hit;
}

static void AXRestoreRelatedVisibilityRecursive(UIView *root, NSInteger depth) {
    if (!root || depth > 7) return;
    NSNumber *marked = objc_getAssociatedObject(root, &kAXRelatedHiddenMarkKey);
    if (marked.boolValue) AXSetMarkedHidden(root, NO);
    for (UIView *sub in [root.subviews copy]) AXRestoreRelatedVisibilityRecursive(sub, depth + 1);
}

static void AXHideRelatedVisibilityRecursive(UIView *root, UIView *container, NSInteger depth) {
    if (!root || !container || depth > 7) return;
    for (UIView *sub in [root.subviews copy]) {
        if (AXIsRelatedTextOrClass(sub)) {
            UIView *target = AXBestRelatedContainer(sub, container);
            if (target && target != container) AXSetMarkedHidden(target, YES);
        }
        AXHideRelatedVisibilityRecursive(sub, container, depth + 1);
    }
}

static void AXApplyRelatedAreaVisibility(UIView *leftStack) {
    if (!leftStack) return;
    if (!AXBool(kAXHideRelatedArea, NO)) {
        AXRestoreRelatedVisibilityRecursive(leftStack, 0);
        return;
    }
    AXHideRelatedVisibilityRecursive(leftStack, leftStack, 0);
}

static void AXApplyRelatedDirectVisibility(UIView *view) {
    if (!view || AXIsAwemeXPanelView(view)) return;
    BOOL shouldHide = AXBool(kAXHideRelatedArea, NO) && AXIsHomeFeedContext(view);
    NSNumber *marked = objc_getAssociatedObject(view, &kAXRelatedHiddenMarkKey);
    if (shouldHide) {
        AXSetMarkedHidden(view, YES);
    } else if (marked.boolValue) {
        AXSetMarkedHidden(view, NO);
    }
}

static NSString *AXModelReferString(id obj) {
    if (!obj || ![obj respondsToSelector:@selector(referString)]) return @"";
    NSString *refer = ((NSString *(*)(id, SEL))objc_msgSend)(obj, @selector(referString));
    return [refer isKindOfClass:NSString.class] ? refer : @"";
}

static BOOL AXShouldHideRelatedModel(id obj) {
    if (!AXBool(kAXHideRelatedArea, NO)) return NO;
    NSString *refer = AXModelReferString(obj);
    if (refer.length == 0) return YES;
    return [refer containsString:@"homepage"] || [refer isEqualToString:@"homepage_hot"] || [refer isEqualToString:@"homepage_familiar"] || [refer isEqualToString:@"homepage_follow"];
}

static void AXApplyElementEffects(UIView *v) {
    if (!v || AXIsAwemeXPanelView(v) || !AXIsHomeFeedContext(v)) return;
    if (axApplyingElementEffects) return;
    [AXTrackedElementViews() addObject:v];
    axApplyingElementEffects = YES;
    NSInteger kind = AXStackKind(v);

    if (kind == 1) {
        CGAffineTransform t = AXRightStackTargetTransform(v);
        if (!CGAffineTransformEqualToTransform(v.transform, t)) v.transform = t;
        AXApplyAlphaKeepingBase(v, AXEffectiveAlpha(kAXRightAlpha, 0.80));
        axApplyingElementEffects = NO;
        return;
    }

    if (kind == 2) {
        CGAffineTransform t = AXLeftStackTargetTransform(v);
        if (!CGAffineTransformEqualToTransform(v.transform, t)) v.transform = t;
        AXApplyAlphaKeepingBase(v, AXEffectiveAlpha(kAXOFNicknameDescAlpha, 1.00));
        AXApplyRelatedAreaVisibility(v);
        axApplyingElementEffects = NO;
        return;
    }

    if (kind == 3) {
        AXApplyAlphaKeepingBase(v, AXEffectiveAlpha(kAXTopAlpha, 0.65));
    }
    axApplyingElementEffects = NO;
}

static BOOL AXIsSearchEntranceCandidate(UIView *v) {
    if (!v || AXIsAwemeXPanelView(v)) return NO;
    NSString *cls = NSStringFromClass(v.class);
    NSString *txt = AXViewText(v);
    NSArray *needles = @[@"Search", @"Discover", @"Magnifier", @"搜索", @"放大镜"];
    if (!AXStringContainsAny(cls, needles) && !AXStringContainsAny(txt, needles)) return NO;
    UIWindow *w = v.window ?: AXKeyWindow();
    if (!w || !v.superview) return YES;
    CGRect f = [v.superview convertRect:v.frame toView:w];
    CGFloat screenW = UIScreen.mainScreen.bounds.size.width;
    CGFloat screenH = UIScreen.mainScreen.bounds.size.height;
    if (CGRectIsEmpty(f)) return YES;
    return f.origin.y < screenH * 0.22 && f.origin.x > screenW * 0.50;
}

static char kAXSearchHiddenMarkKey;
static void AXSetSearchViewHidden(UIView *v, BOOL hidden) {
    if (!v || AXIsAwemeXPanelView(v)) return;
    objc_setAssociatedObject(v, &kAXSearchHiddenMarkKey, hidden ? (id)@YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    v.hidden = hidden;
    v.userInteractionEnabled = !hidden;
}

static void AXApplySearchEntranceHide(UIView *v) {
    if (!v || AXIsAwemeXPanelView(v)) return;
    [AXTrackedSearchViews() addObject:v];
    BOOL shouldHide = AXBool(kAXHideSearch, NO);
    if (!shouldHide) {
        NSNumber *marked = objc_getAssociatedObject(v, &kAXSearchHiddenMarkKey);
        if (marked.boolValue) AXSetSearchViewHidden(v, NO);
        return;
    }
    AXSetSearchViewHidden(v, YES);
}

static void AXApplyTopBarSearchRecursive(UIView *root, NSInteger depth) {
    if (!root || depth > 6) return;
    BOOL shouldHide = AXBool(kAXHideSearch, NO);
    for (UIView *sub in [root.subviews copy]) {
        NSNumber *marked = objc_getAssociatedObject(sub, &kAXSearchHiddenMarkKey);
        if (!shouldHide && marked.boolValue) AXSetSearchViewHidden(sub, NO);
        if (shouldHide && AXIsSearchEntranceCandidate(sub)) AXSetSearchViewHidden(sub, YES);
        AXApplyTopBarSearchRecursive(sub, depth + 1);
    }
}

static void AXApplyTopBarEffects(UIView *v) {
    if (!v || AXIsAwemeXPanelView(v)) return;
    [AXTrackedTopBarViews() addObject:v];
    AXApplyAlphaKeepingBase(v, AXEffectiveAlpha(kAXTopAlpha, 0.65));
    AXApplyTopBarSearchRecursive(v, 0);
}

static void AXRefreshButton(void) {
    if (!axButton) return;
    axButton.hidden = !AXBool(kAXShowButton, YES);
    axButton.alpha = AXFloat(kAXIconAlpha, 0.34);
    axButton.userInteractionEnabled = YES;
    axButton.enabled = YES;
    axButton.layer.zPosition = CGFLOAT_MAX;
    UIWindow *w = AXKeyWindow();
    if (w && axButton.superview == w) [w bringSubviewToFront:axButton];
}

static void AXRefreshTrackedViews(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ AXRefreshTrackedViews(); });
        return;
    }
    for (UIView *v in [[AXTrackedElementViews() allObjects] copy]) {
        if (v.window) AXApplyElementEffects(v);
    }
    for (UIView *v in [[AXTrackedTopBarViews() allObjects] copy]) {
        if (v.window) AXApplyTopBarEffects(v);
    }
    for (UIView *v in [[AXTrackedSearchViews() allObjects] copy]) {
        if (v.window) AXApplySearchEntranceHide(v);
    }
}

static void AXScheduleMainRefresh(void) {
    if (axMainRefreshScheduled) return;
    axMainRefreshScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.16 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        axMainRefreshScheduled = NO;
        AXRefreshButton();
        AXRefreshTrackedViews();
    });
}

static void AXResetTransformRecursive(UIView *view) {
    if (!view) return;
    view.transform = CGAffineTransformIdentity;
    view.layer.anchorPoint = CGPointMake(0.5, 0.5);
    for (UIView *sub in view.subviews) AXResetTransformRecursive(sub);
}

static UILabel *AXLabel(NSString *text, CGFloat value, CGRect frame, CGFloat panelWidth) {
    UILabel *l = [[UILabel alloc] initWithFrame:frame];
    l.text = text;
    l.textColor = UIColor.whiteColor;
    l.font = [UIFont boldSystemFontOfSize:15];
    [axPanel addSubview:l];

    UILabel *r = [[UILabel alloc] initWithFrame:CGRectMake(panelWidth - 110, frame.origin.y, 80, frame.size.height)];
    r.textAlignment = NSTextAlignmentRight;
    r.textColor = UIColor.whiteColor;
    r.font = [UIFont systemFontOfSize:14];
    r.text = [NSString stringWithFormat:@"%.0f%%", value * 100.0];
    [axPanel addSubview:r];
    return r;
}

@interface AXMenuTarget : NSObject
+ (instancetype)shared;
- (void)openSettings;
- (void)closeSettings;
- (void)sliderChanged:(UISlider *)sender;
- (void)sliderCommit:(UISlider *)sender;
- (void)switchChanged:(UISwitch *)sender;
@end

@interface AXTwoFingerLongPressTarget : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)handleTwoFingerLongPress:(UILongPressGestureRecognizer *)gesture;
@end

@implementation AXTwoFingerLongPressTarget
+ (instancetype)shared {
    static AXTwoFingerLongPressTarget *target;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ target = [AXTwoFingerLongPressTarget new]; });
    return target;
}

- (void)handleTwoFingerLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    dispatch_async(dispatch_get_main_queue(), ^{ [[AXMenuTarget shared] openSettings]; });
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    UIView *touchedView = touch.view;
    if (AXIsDescendantOf(touchedView, axPanel) || AXIsDescendantOf(touchedView, axButton)) return NO;
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}
@end

@implementation AXMenuTarget
+ (instancetype)shared {
    static AXMenuTarget *target;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ target = [AXMenuTarget new]; });
    return target;
}

- (void)closeSettings {
    [axPanel removeFromSuperview];
    axPanel = nil;
    AXRefreshButton();
}

- (void)sliderChanged:(UISlider *)sender {
    NSArray *keys = @[@"", kAXGlobalAlpha, kAXTopAlpha, kAXRightAlpha, kAXScale, kAXIconAlpha, kAXNicknameScale, kAXOFNicknameDescAlpha];
    if (sender.tag <= 0 || sender.tag >= (NSInteger)keys.count) return;
    AXSetFast(keys[sender.tag], @(sender.value));
    UILabel *label = [axPanel viewWithTag:8000 + sender.tag];
    label.text = [NSString stringWithFormat:@"%.0f%%", sender.value * 100.0];
    if (sender.tag == 5) AXRefreshButton();
}

- (void)sliderCommit:(UISlider *)sender {
    NSArray *keys = @[@"", kAXGlobalAlpha, kAXTopAlpha, kAXRightAlpha, kAXScale, kAXIconAlpha, kAXNicknameScale, kAXOFNicknameDescAlpha];
    if (sender.tag <= 0 || sender.tag >= (NSInteger)keys.count) return;
    AXSet(keys[sender.tag], @(sender.value));
    AXScheduleMainRefresh();
}

- (void)switchChanged:(UISwitch *)sender {
    NSString *key = nil;
    if (sender.tag == 11) key = kAXHideSearch;
    else if (sender.tag == 12) key = kAXHideRelatedArea;
    else if (sender.tag == 13) key = kAXShowButton;
    else if (sender.tag == 21) key = kAXLPPanelSaveVideo;
    else if (sender.tag == 22) key = kAXLPPanelSaveCover;
    else if (sender.tag == 23) key = kAXLPPanelSaveAudio;
    else if (sender.tag == 24) key = kAXLPPanelSaveImage;
    else if (sender.tag == 25) key = kAXLPPanelSaveAllImages;
    else if (sender.tag == 26) key = kAXLPPanelCopyText;
    if (!key) return;
    AXSet(key, @(sender.on));
    AXRefreshButton();
    AXScheduleMainRefresh();
}

- (void)openSettings {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = AXKeyWindow();
        if (!w) return;
        if (axPanel) { [self closeSettings]; return; }

        CGRect b = UIScreen.mainScreen.bounds;
        CGFloat width = MIN(390.0, b.size.width - 90.0);
        CGFloat height = MIN(720.0, b.size.height - 50.0);
        axPanel = [[UIView alloc] initWithFrame:CGRectMake((b.size.width - width) / 2.0, (b.size.height - height) / 2.0, width, height)];
        axPanel.tag = 42029;
        axPanel.backgroundColor = [[UIColor colorWithWhite:0.08 alpha:1.0] colorWithAlphaComponent:0.86];
        axPanel.layer.cornerRadius = 20;
        axPanel.clipsToBounds = YES;
        axPanel.userInteractionEnabled = YES;
        axPanel.exclusiveTouch = YES;
        axPanel.layer.zPosition = CGFLOAT_MAX;
        [w addSubview:axPanel];
        [w bringSubviewToFront:axPanel];

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, width, 28)];
        title.text = @"AwemeX 设置 V43";
        title.textColor = UIColor.whiteColor;
        title.font = [UIFont boldSystemFontOfSize:18];
        title.textAlignment = NSTextAlignmentCenter;
        [axPanel addSubview:title];

        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.frame = CGRectMake(width - 50, 18, 34, 34);
        [close setTitle:@"×" forState:UIControlStateNormal];
        [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        close.titleLabel.font = [UIFont boldSystemFontOfSize:23];
        [close addTarget:self action:@selector(closeSettings) forControlEvents:UIControlEventTouchUpInside];
        [axPanel addSubview:close];

        NSArray *names = @[@"设置全局透明", @"顶部不透明度", @"右侧按钮不透明度", @"右侧按钮缩放比例", @"AX 图标不透明度", @"昵称文案缩放", @"昵称/文案不透明度"];
        NSArray *keys = @[kAXGlobalAlpha, kAXTopAlpha, kAXRightAlpha, kAXScale, kAXIconAlpha, kAXNicknameScale, kAXOFNicknameDescAlpha];
        NSArray *defs = @[@1.00, @0.65, @0.80, @0.81, @0.34, @1.00, @1.00];
        for (NSInteger i = 0; i < (NSInteger)names.count; i++) {
            CGFloat y = 62 + i * 61;
            CGFloat cur = AXFloat(keys[i], [defs[i] floatValue]);
            UILabel *val = AXLabel(names[i], cur, CGRectMake(30, y, 230, 24), width);
            val.tag = 8000 + i + 1;
            UISlider *s = [[UISlider alloc] initWithFrame:CGRectMake(30, y + 32, width - 60, 30)];
            s.tag = i + 1;
            BOOL isScaleSlider = (i == 3 || i == 5);
            s.minimumValue = isScaleSlider ? 0.50 : 0.05;
            s.maximumValue = isScaleSlider ? 1.30 : 1.00;
            s.value = cur;
            [s addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
            [s addTarget:self action:@selector(sliderCommit:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
            [axPanel addSubview:s];
        }

        NSArray *switchNames = @[@"隐藏右上搜索", @"隐藏相关搜索/合集", @"显示 AX 悬浮按钮"];
        NSArray *switchKeys = @[kAXHideSearch, kAXHideRelatedArea, kAXShowButton];
        NSArray *switchDefs = @[@NO, @NO, @YES];
        for (NSInteger i = 0; i < (NSInteger)switchNames.count; i++) {
            CGFloat y = 488 + i * 36;
            UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(30, y, 230, 30)];
            l.text = switchNames[i];
            l.textColor = UIColor.whiteColor;
            l.font = [UIFont boldSystemFontOfSize:15];
            [axPanel addSubview:l];
            UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(width - 85, y, 60, 32)];
            sw.tag = 11 + i;
            sw.on = AXBool(switchKeys[i], [switchDefs[i] boolValue]);
            [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
            [axPanel addSubview:sw];
        }

        UILabel *lpTitle = [[UILabel alloc] initWithFrame:CGRectMake(30, 594, width - 60, 22)];
        lpTitle.text = @"单指长按面板";
        lpTitle.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.78];
        lpTitle.font = [UIFont boldSystemFontOfSize:13];
        [axPanel addSubview:lpTitle];

        NSArray *lpNames = @[@"保存视频", @"保存封面", @"保存音频", @"保存图片", @"保存所有图片", @"复制文案"];
        NSArray *lpKeys = @[kAXLPPanelSaveVideo, kAXLPPanelSaveCover, kAXLPPanelSaveAudio, kAXLPPanelSaveImage, kAXLPPanelSaveAllImages, kAXLPPanelCopyText];
        NSArray *lpDefs = @[@YES, @YES, @YES, @YES, @YES, @NO];
        for (NSInteger i = 0; i < (NSInteger)lpNames.count; i++) {
            NSInteger col = i % 2;
            NSInteger row = i / 2;
            CGFloat baseX = col == 0 ? 30.0 : width / 2.0 + 8.0;
            CGFloat y = 617.0 + row * 32.0;
            UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(baseX, y, col == 0 ? 96.0 : 104.0, 30.0)];
            l.text = lpNames[i];
            l.textColor = UIColor.whiteColor;
            l.font = [UIFont boldSystemFontOfSize:12];
            [axPanel addSubview:l];

            UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(baseX + (col == 0 ? 98.0 : 108.0), y - 1.0, 52.0, 32.0)];
            sw.tag = 21 + i;
            sw.on = AXBool(lpKeys[i], [lpDefs[i] boolValue]);
            [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
            [axPanel addSubview:sw];
        }

        AXResetTransformRecursive(axPanel);
        [w bringSubviewToFront:axPanel];
    });
}
@end

static void AXInstallTwoFingerLongPressGesture(void) {
    UIWindow *w = AXKeyWindow();
    if (!w) return;
    if (axTwoFingerLongPressGesture && axTwoFingerLongPressWindow == w) {
        if (![w.gestureRecognizers containsObject:axTwoFingerLongPressGesture]) [w addGestureRecognizer:axTwoFingerLongPressGesture];
        return;
    }
    if (axTwoFingerLongPressGesture && axTwoFingerLongPressWindow) {
        [axTwoFingerLongPressWindow removeGestureRecognizer:axTwoFingerLongPressGesture];
    }
    AXTwoFingerLongPressTarget *target = [AXTwoFingerLongPressTarget shared];
    axTwoFingerLongPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:target action:@selector(handleTwoFingerLongPress:)];
    axTwoFingerLongPressGesture.minimumPressDuration = 0.55;
    axTwoFingerLongPressGesture.numberOfTouchesRequired = 2;
    axTwoFingerLongPressGesture.cancelsTouchesInView = NO;
    axTwoFingerLongPressGesture.delaysTouchesBegan = NO;
    axTwoFingerLongPressGesture.delaysTouchesEnded = NO;
    axTwoFingerLongPressGesture.delegate = target;
    [w addGestureRecognizer:axTwoFingerLongPressGesture];
    axTwoFingerLongPressWindow = w;
}

static void AXShow(void) {
    UIWindow *w = AXKeyWindow();
    if (!w) return;
    if (!axButton || axButton.superview != w) {
        [axButton removeFromSuperview];
        axButton = [UIButton buttonWithType:UIButtonTypeCustom];
        axButton.frame = CGRectMake(w.bounds.size.width - 76, 120, 52, 52);
        axButton.layer.cornerRadius = 26;
        axButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.38];
        [axButton setTitle:@"AX" forState:UIControlStateNormal];
        [axButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        axButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        [axButton addTarget:[AXMenuTarget shared] action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
        [w addSubview:axButton];
    }
    AXRefreshButton();
}

%hook AWEElementStackView
- (void)layoutSubviews { %orig; AXApplyElementEffects((UIView *)(id)self); }
- (void)didMoveToWindow { %orig; AXApplyElementEffects((UIView *)(id)self); }
- (NSArray *)arrangedSubviews { NSArray *r = %orig; AXApplyElementEffects((UIView *)(id)self); return r; }
- (void)setTransform:(CGAffineTransform)transform {
    UIView *view = (UIView *)(id)self;
    NSInteger kind = AXStackKind(view);
    if (!axApplyingElementEffects && kind == 1) { %orig(AXRightStackTargetTransform(view)); return; }
    if (!axApplyingElementEffects && kind == 2) { %orig(AXLeftStackTargetTransform(view)); return; }
    %orig(transform);
}
- (void)setAlpha:(CGFloat)alpha {
    UIView *view = (UIView *)(id)self;
    NSInteger kind = AXStackKind(view);
    if (!axSettingAlpha && kind == 1) { %orig(AXClamp01(alpha * AXEffectiveAlpha(kAXRightAlpha, 0.80))); return; }
    if (!axSettingAlpha && kind == 2) { %orig(AXClamp01(alpha * AXEffectiveAlpha(kAXOFNicknameDescAlpha, 1.00))); return; }
    if (!axSettingAlpha && kind == 3) { %orig(AXClamp01(alpha * AXEffectiveAlpha(kAXTopAlpha, 0.65))); return; }
    %orig(alpha);
}
%end

%hook IESLiveStackView
- (void)layoutSubviews { %orig; AXApplyElementEffects((UIView *)(id)self); }
- (void)didMoveToWindow { %orig; AXApplyElementEffects((UIView *)(id)self); }
- (NSArray *)arrangedSubviews { NSArray *r = %orig; AXApplyElementEffects((UIView *)(id)self); return r; }
- (void)setTransform:(CGAffineTransform)transform {
    UIView *view = (UIView *)(id)self;
    NSInteger kind = AXStackKind(view);
    if (!axApplyingElementEffects && kind == 1) { %orig(AXRightStackTargetTransform(view)); return; }
    if (!axApplyingElementEffects && kind == 2) { %orig(AXLeftStackTargetTransform(view)); return; }
    %orig(transform);
}
- (void)setAlpha:(CGFloat)alpha {
    UIView *view = (UIView *)(id)self;
    NSInteger kind = AXStackKind(view);
    if (!axSettingAlpha && kind == 1) { %orig(AXClamp01(alpha * AXEffectiveAlpha(kAXRightAlpha, 0.80))); return; }
    if (!axSettingAlpha && kind == 2) { %orig(AXClamp01(alpha * AXEffectiveAlpha(kAXOFNicknameDescAlpha, 1.00))); return; }
    if (!axSettingAlpha && kind == 3) { %orig(AXClamp01(alpha * AXEffectiveAlpha(kAXTopAlpha, 0.65))); return; }
    %orig(alpha);
}
%end

%hook AWELandscapeFeedEntryView
- (void)layoutSubviews { %orig; AXApplyElementEffects((UIView *)(id)self); }
- (void)didMoveToWindow { %orig; AXApplyElementEffects((UIView *)(id)self); }
- (void)setAlpha:(CGFloat)alpha {
    UIView *view = (UIView *)(id)self;
    NSInteger kind = AXStackKind(view);
    if (!axSettingAlpha && kind == 1) { %orig(AXClamp01(alpha * AXEffectiveAlpha(kAXRightAlpha, 0.80))); return; }
    if (!axSettingAlpha && kind == 2) { %orig(AXClamp01(alpha * AXEffectiveAlpha(kAXOFNicknameDescAlpha, 1.00))); return; }
    if (!axSettingAlpha && kind == 3) { %orig(AXClamp01(alpha * AXEffectiveAlpha(kAXTopAlpha, 0.65))); return; }
    %orig(alpha);
}
%end

%hook AWEFeedTopBarContainer
- (void)layoutSubviews { %orig; AXApplyTopBarEffects((UIView *)(id)self); }
- (void)didMoveToWindow { %orig; AXApplyTopBarEffects((UIView *)(id)self); }
- (void)setAlpha:(CGFloat)alpha {
    if (!axSettingAlpha) { %orig(AXClamp01(alpha * AXEffectiveAlpha(kAXTopAlpha, 0.65))); return; }
    %orig(alpha);
}
%end

%hook AWESearchEntranceView
- (void)layoutSubviews { %orig; AXApplySearchEntranceHide((UIView *)(id)self); }
- (void)didMoveToWindow { %orig; AXApplySearchEntranceHide((UIView *)(id)self); }
%end

%hook AWEHPDiscoverFeedEntranceView
- (void)layoutSubviews { %orig; AXApplySearchEntranceHide((UIView *)(id)self); }
- (void)didMoveToWindow { %orig; AXApplySearchEntranceHide((UIView *)(id)self); }
%end

%hook AWEPlayInteractionSearchAnchorView
- (void)layoutSubviews { %orig; AXApplyRelatedDirectVisibility((UIView *)(id)self); }
- (void)didMoveToWindow { %orig; AXApplyRelatedDirectVisibility((UIView *)(id)self); }
%end

%hook AWEFeedAnchorContainerView
- (void)layoutSubviews { %orig; AXApplyRelatedDirectVisibility((UIView *)(id)self); }
- (void)didMoveToWindow { %orig; AXApplyRelatedDirectVisibility((UIView *)(id)self); }
%end

%hook AWEAwemeModel
- (id)relatedVideoExtra { if (AXShouldHideRelatedModel((id)self)) return nil; return %orig; }
- (id)relatedVideo { if (AXShouldHideRelatedModel((id)self)) return nil; return %orig; }
- (id)playletRelatedVideoInfoModel { if (AXShouldHideRelatedModel((id)self)) return nil; return %orig; }
- (id)mixInfo { if (AXShouldHideRelatedModel((id)self)) return nil; return %orig; }
- (id)playletInfoModel { if (AXShouldHideRelatedModel((id)self)) return nil; return %orig; }
- (id)anchorInfo { if (AXShouldHideRelatedModel((id)self)) return nil; return %orig; }
- (void)setAnchorInfo:(id)info { if (AXShouldHideRelatedModel((id)self)) { %orig(nil); return; } %orig; }
- (id)commonAnchor { if (AXShouldHideRelatedModel((id)self)) return nil; return %orig; }
- (void)setCommonAnchor:(id)anchor { if (AXShouldHideRelatedModel((id)self)) { %orig(nil); return; } %orig; }
- (id)commonSearchAnchor { if (AXShouldHideRelatedModel((id)self)) return nil; return %orig; }
- (void)setCommonSearchAnchor:(id)anchor { if (AXShouldHideRelatedModel((id)self)) { %orig(nil); return; } %orig; }
%end

// AwemeX iPad 单指长按菜单：按设置开关追加保存/复制按钮，不改菜单背景/布局
// 用法：把本模块粘贴到现有 AwemeX_AlphaPro.xm 末尾，重新 make package。
// 目标：在 AWEUserActionSheetView 的 actions 里追加：保存视频 / 保存封面 / 保存音频 / 保存图片 / 保存所有图片 / 复制文案；不加入生成视频。
// 注意：这是安全测试模块，默认开启；如果按钮出现但保存失败，说明当前抖音版本的 awemeModel 字段名需要再适配。


static char kAXSaveButtonsInjectedKey;

static BOOL AXSB_Bool(NSString *key, BOOL def) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return v ? [v boolValue] : def;
}

static id AXSB_Send0(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}

static BOOL AXSB_StrHasHTTP(NSString *s) {
    return [s isKindOfClass:NSString.class] && ([s hasPrefix:@"http://"] || [s hasPrefix:@"https://"]);
}

static NSURL *AXSB_URLFromString(NSString *s) {
    if (!AXSB_StrHasHTTP(s)) return nil;
    return [NSURL URLWithString:s];
}

static NSURL *AXSB_FirstURLInObject(id obj, NSInteger depth);

static NSURL *AXSB_FirstURLBySelectors(id obj, NSArray<NSString *> *sels, NSInteger depth) {
    if (!obj || depth <= 0) return nil;
    for (NSString *name in sels) {
        SEL sel = NSSelectorFromString(name);
        id value = AXSB_Send0(obj, sel);
        NSURL *u = AXSB_FirstURLInObject(value, depth - 1);
        if (u) return u;
    }
    return nil;
}

static NSURL *AXSB_FirstURLInObject(id obj, NSInteger depth) {
    if (!obj || depth <= 0) return nil;

    if ([obj isKindOfClass:NSURL.class]) return (NSURL *)obj;
    if ([obj isKindOfClass:NSString.class]) return AXSB_URLFromString((NSString *)obj);

    if ([obj isKindOfClass:NSArray.class]) {
        for (id item in (NSArray *)obj) {
            NSURL *u = AXSB_FirstURLInObject(item, depth - 1);
            if (u) return u;
        }
        return nil;
    }

    if ([obj isKindOfClass:NSDictionary.class]) {
        NSDictionary *dict = (NSDictionary *)obj;
        NSArray *preferred = @[@"urlList", @"url_list", @"urls", @"url", @"URL", @"uri", @"playAddr", @"downloadAddr", @"cover", @"originCover", @"playUrl"];
        for (NSString *k in preferred) {
            NSURL *u = AXSB_FirstURLInObject(dict[k], depth - 1);
            if (u) return u;
        }
        for (id value in dict.allValues) {
            NSURL *u = AXSB_FirstURLInObject(value, depth - 1);
            if (u) return u;
        }
        return nil;
    }

    NSArray *common = @[
        @"urlList", @"URLList", @"url_list", @"urls", @"url", @"URL", @"uri",
        @"playAddr", @"downloadAddr", @"playURL", @"playUrl", @"originURL", @"originUrl",
        @"cover", @"originCover", @"dynamicCover", @"animatedCover", @"coverUrl", @"coverURL",
        @"image", @"imageURL", @"imageUrl", @"imageUrlModel", @"urlModel"
    ];
    return AXSB_FirstURLBySelectors(obj, common, depth - 1);
}

static UIViewController *AXSB_TopVCFrom(UIViewController *vc) {
    if (!vc) return nil;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if ([vc isKindOfClass:UINavigationController.class]) return AXSB_TopVCFrom(((UINavigationController *)vc).topViewController);
    if ([vc isKindOfClass:UITabBarController.class]) return AXSB_TopVCFrom(((UITabBarController *)vc).selectedViewController);
    return vc;
}

static UIWindow *AXSB_KeyWindow(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) return w;
            }
        }
    }
    for (UIWindow *w in app.windows) if (w.isKeyWindow) return w;
    return app.windows.firstObject;
}

static UIViewController *AXSB_FindPlayVCInTree(UIViewController *vc) {
    if (!vc) return nil;
    NSString *name = NSStringFromClass(vc.class);
    if ([name containsString:@"AWEPlayInteractionViewController"] || [name containsString:@"PlayInteraction"]) return vc;
    for (UIViewController *child in vc.childViewControllers) {
        UIViewController *hit = AXSB_FindPlayVCInTree(child);
        if (hit) return hit;
    }
    return nil;
}

static UIViewController *AXSB_CurrentPlayVC(void) {
    UIWindow *w = AXSB_KeyWindow();
    UIViewController *top = AXSB_TopVCFrom(w.rootViewController);
    UIViewController *hit = AXSB_FindPlayVCInTree(top);
    if (hit) return hit;
    return AXSB_FindPlayVCInTree(w.rootViewController);
}

static id AXSB_CurrentAwemeModel(void) {
    UIViewController *vc = AXSB_CurrentPlayVC();
    NSArray *sels = @[@"awemeModel", @"aweme", @"model", @"currentAweme", @"currentAwemeModel", @"currentModel", @"item"];
    for (NSString *name in sels) {
        id value = AXSB_Send0(vc, NSSelectorFromString(name));
        if (value) return value;
    }
    return nil;
}

static NSURL *AXSB_VideoURLFromAweme(id aweme) {
    if (!aweme) return nil;
    id video = AXSB_Send0(aweme, @selector(video));
    NSURL *u = AXSB_FirstURLBySelectors(video ?: aweme, @[@"downloadAddr", @"playAddr", @"h264PlayAddr", @"playApi", @"bitRate", @"video"], 6);
    return u ?: AXSB_FirstURLInObject(video ?: aweme, 5);
}

static NSURL *AXSB_CoverURLFromAweme(id aweme) {
    if (!aweme) return nil;
    id video = AXSB_Send0(aweme, @selector(video));
    NSURL *u = AXSB_FirstURLBySelectors(video ?: aweme, @[@"originCover", @"cover", @"dynamicCover", @"animatedCover", @"coverUrl", @"coverURL"], 5);
    return u;
}

static NSURL *AXSB_AudioURLFromAweme(id aweme) {
    if (!aweme) return nil;
    id music = AXSB_Send0(aweme, @selector(music));
    if (!music) music = AXSB_Send0(aweme, @selector(musicModel));
    NSURL *u = AXSB_FirstURLBySelectors(music ?: aweme, @[@"playUrl", @"playURL", @"playUrlModel", @"downloadUrl", @"downloadURL", @"urlModel"], 6);
    return u;
}

static NSArray<NSURL *> *AXSB_ImageURLsFromAweme(id aweme) {
    if (!aweme) return @[];
    NSMutableArray<NSURL *> *out = [NSMutableArray array];
    NSArray *containers = @[
        AXSB_Send0(aweme, @selector(images)),
        AXSB_Send0(aweme, @selector(imageInfos)),
        AXSB_Send0(aweme, @selector(albumImages)),
        AXSB_Send0(aweme, @selector(imageAlbum)),
        AXSB_Send0(aweme, @selector(imagePostInfo))
    ];
    for (id c in containers) {
        if (!c) continue;
        if ([c isKindOfClass:NSArray.class]) {
            for (id item in (NSArray *)c) {
                NSURL *u = AXSB_FirstURLInObject(item, 6);
                if (u && ![out containsObject:u]) [out addObject:u];
            }
        } else {
            NSURL *u = AXSB_FirstURLInObject(c, 6);
            if (u && ![out containsObject:u]) [out addObject:u];
        }
    }
    return out;
}

static void AXSB_Toast(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = AXSB_KeyWindow();
        if (!w) return;
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 260, 44)];
        l.center = CGPointMake(CGRectGetMidX(w.bounds), CGRectGetMidY(w.bounds));
        l.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.78];
        l.textColor = UIColor.whiteColor;
        l.font = [UIFont boldSystemFontOfSize:14];
        l.textAlignment = NSTextAlignmentCenter;
        l.text = text;
        l.layer.cornerRadius = 12;
        l.clipsToBounds = YES;
        l.layer.zPosition = CGFLOAT_MAX;
        [w addSubview:l];
        [UIView animateWithDuration:0.25 delay:1.15 options:0 animations:^{ l.alpha = 0; } completion:^(BOOL finished) { [l removeFromSuperview]; }];
    });
}

static void AXSB_SaveImageURL(NSURL *url, NSString *name) {
    if (!url) { AXSB_Toast([NSString stringWithFormat:@"%@链接为空", name]); return; }
    AXSB_Toast([NSString stringWithFormat:@"正在保存%@…", name]);
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        UIImage *img = data ? [UIImage imageWithData:data] : nil;
        if (!img) { AXSB_Toast([NSString stringWithFormat:@"%@保存失败", name]); return; }
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil);
        AXSB_Toast([NSString stringWithFormat:@"%@已保存到相册", name]);
    }] resume];
}

static void AXSB_SaveVideoURL(NSURL *url) {
    if (!url) { AXSB_Toast(@"视频链接为空"); return; }
    AXSB_Toast(@"正在保存视频…");
    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (!location || error) { AXSB_Toast(@"视频下载失败"); return; }
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"awemex_%@.mp4", NSUUID.UUID.UUIDString]];
        NSURL *dst = [NSURL fileURLWithPath:tmp];
        [[NSFileManager defaultManager] removeItemAtURL:dst error:nil];
        NSError *moveErr = nil;
        [[NSFileManager defaultManager] moveItemAtURL:location toURL:dst error:&moveErr];
        if (moveErr) { AXSB_Toast(@"视频缓存失败"); return; }
        UISaveVideoAtPathToSavedPhotosAlbum(tmp, nil, nil, nil);
        AXSB_Toast(@"视频已保存到相册");
    }];
    [task resume];
}

static void AXSB_ShareAudioURL(NSURL *url) {
    if (!url) { AXSB_Toast(@"音频链接为空"); return; }
    AXSB_Toast(@"正在准备音频…");
    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (!location || error) { AXSB_Toast(@"音频下载失败"); return; }
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"awemex_audio_%@.m4a", NSUUID.UUID.UUIDString]];
        NSURL *dst = [NSURL fileURLWithPath:tmp];
        [[NSFileManager defaultManager] removeItemAtURL:dst error:nil];
        [[NSFileManager defaultManager] moveItemAtURL:location toURL:dst error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *vc = AXSB_TopVCFrom(AXSB_KeyWindow().rootViewController);
            UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[dst] applicationActivities:nil];
            avc.popoverPresentationController.sourceView = vc.view;
            avc.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(vc.view.bounds), CGRectGetMidY(vc.view.bounds), 1, 1);
            [vc presentViewController:avc animated:YES completion:nil];
        });
    }];
    [task resume];
}

static void AXSB_HandleSaveKind(NSString *kind) {
    id aweme = AXSB_CurrentAwemeModel();
    if (!aweme) { AXSB_Toast(@"未找到当前视频模型"); return; }
    if ([kind isEqualToString:@"video"]) {
        AXSB_SaveVideoURL(AXSB_VideoURLFromAweme(aweme));
    } else if ([kind isEqualToString:@"cover"]) {
        AXSB_SaveImageURL(AXSB_CoverURLFromAweme(aweme), @"封面");
    } else if ([kind isEqualToString:@"audio"]) {
        AXSB_ShareAudioURL(AXSB_AudioURLFromAweme(aweme));
    } else if ([kind isEqualToString:@"image"]) {
        NSArray<NSURL *> *urls = AXSB_ImageURLsFromAweme(aweme);
        NSURL *u = urls.count > 0 ? urls.firstObject : nil;
        AXSB_SaveImageURL(u, @"图片");
    } else if ([kind isEqualToString:@"image_all"]) {
        NSArray<NSURL *> *urls = AXSB_ImageURLsFromAweme(aweme);
        if (urls.count == 0) { AXSB_Toast(@"图片链接为空"); return; }
        AXSB_Toast([NSString stringWithFormat:@"正在保存%lu张图片…", (unsigned long)urls.count]);
        for (NSURL *u in urls) AXSB_SaveImageURL(u, @"图片");
    } else if ([kind isEqualToString:@"copy_text"]) {
        NSString *desc = nil;
        NSArray *sels = @[@"descriptionString", @"itemDescription", @"desc", @"text", @"title"];
        for (NSString *name in sels) {
            id value = AXSB_Send0(aweme, NSSelectorFromString(name));
            if ([value isKindOfClass:NSString.class] && ((NSString *)value).length > 0) { desc = value; break; }
        }
        if (!desc && [aweme respondsToSelector:@selector(valueForKey:)]) {
            @try { id value = [aweme valueForKey:@"descriptionString"]; if ([value isKindOfClass:NSString.class]) desc = value; } @catch (NSException *e) {}
        }
        if (desc.length == 0) { AXSB_Toast(@"文案为空"); return; }
        UIPasteboard.generalPasteboard.string = desc;
        AXSB_Toast(@"文案已复制");
    }
}

static id AXSB_MakeAction(NSString *title, NSString *kind) {
    Class cls = NSClassFromString(@"AWEUserSheetAction");
    if (!cls) return nil;

    void (^handler)(id) = ^(id action) { AXSB_HandleSaveKind(kind); };
    UIImage *img = nil;
    if (@available(iOS 13.0, *)) {
        NSString *sys = [kind isEqualToString:@"video"] ? @"arrow.down.circle" :
                        [kind isEqualToString:@"cover"] ? @"photo" :
                        [kind isEqualToString:@"audio"] ? @"music.note" :
                        [kind isEqualToString:@"copy_text"] ? @"doc.on.doc" : @"photo.on.rectangle";
        img = [UIImage systemImageNamed:sys];
    }

    SEL s1 = NSSelectorFromString(@"actionWithTitle:description:image:imageStyle:handler:");
    if ([cls respondsToSelector:s1]) {
        return ((id (*)(id, SEL, id, id, id, NSInteger, id))objc_msgSend)(cls, s1, title, nil, img, 0, handler);
    }

    SEL s2 = NSSelectorFromString(@"actionWithTitle:image:handler:");
    if ([cls respondsToSelector:s2]) {
        return ((id (*)(id, SEL, id, id, id))objc_msgSend)(cls, s2, title, img, handler);
    }

    SEL s3 = NSSelectorFromString(@"actionWithTitle:handler:");
    if ([cls respondsToSelector:s3]) {
        return ((id (*)(id, SEL, id, id))objc_msgSend)(cls, s3, title, handler);
    }

    // 抖音/DYYY 常见构造方法：actionWithTitle:imgName:handler:
    SEL s4 = NSSelectorFromString(@"actionWithTitle:imgName:handler:");
    if ([cls respondsToSelector:s4]) {
        return ((id (*)(id, SEL, id, id, id))objc_msgSend)(cls, s4, title, nil, handler);
    }
    return nil;
}

static NSString *AXSB_ActionTitle(id action) {
    id t = AXSB_Send0(action, @selector(title));
    if (!t) t = AXSB_Send0(action, @selector(actionTitle));
    if (!t) t = AXSB_Send0(action, @selector(text));
    if (!t && [action respondsToSelector:@selector(valueForKey:)]) {
        @try { t = [action valueForKey:@"title"]; } @catch (NSException *e) {}
        if (!t) { @try { t = [action valueForKey:@"_title"]; } @catch (NSException *e) {} }
        if (!t) { @try { t = [action valueForKey:@"name"]; } @catch (NSException *e) {} }
    }
    return [t isKindOfClass:NSString.class] ? (NSString *)t : nil;
}

static BOOL AXSB_IsLikelyVideoLongPressActions(NSArray *actions, id sheet) {
    if (![actions isKindOfClass:NSArray.class] || actions.count == 0) return NO;

    // 不碰分享/评论等右侧入口弹层。它们也可能复用 AWEUserActionSheetView，
    // V31 在这里追加保存按钮会导致“分享给/评论”内容空白。
    NSArray *deny = @[@"分享", @"私信", @"朋友", @"微信", @"QQ", @"评论", @"回复", @"转发"];
    NSArray *allow = @[@"不感兴趣", @"举报", @"清屏", @"倍速", @"保存", @"复制链接", @"一起看", @"稍后再看"];
    BOOL hasAllow = NO;
    NSInteger shareLikeCount = 0;
    for (id a in actions) {
        NSString *t = AXSB_ActionTitle(a) ?: @"";
        for (NSString *d in deny) {
            if ([t containsString:d]) shareLikeCount++;
        }
        for (NSString *ok in allow) {
            if ([t containsString:ok]) hasAllow = YES;
        }
    }
    // V36：部分 iPad 长按菜单标题取不到；只要不是明显分享/评论弹层，就允许注入。
    if (shareLikeCount >= 2) return NO;

    if (sheet) {
        NSString *sheetName = NSStringFromClass([sheet class]);
        if ([sheetName containsString:@"Share"] || [sheetName containsString:@"Comment"] || [sheetName containsString:@"Input"] || [sheetName containsString:@"Keyboard"]) return NO;
    }
    if (hasAllow) return YES;
    return actions.count <= 12;
}

static NSArray *AXSB_ActionsByAppendingSaveButtons(NSArray *actions, id sheet) {
    if (![actions isKindOfClass:NSArray.class]) return actions;
    if (!AXSB_IsLikelyVideoLongPressActions(actions, sheet)) return actions;

    NSNumber *done = objc_getAssociatedObject(sheet, &kAXSaveButtonsInjectedKey);
    if (done.boolValue) return actions;

    NSMutableArray *titles = [NSMutableArray array];
    NSMutableArray *kinds = [NSMutableArray array];
    if (AXSB_Bool(kAXLPPanelSaveVideo, YES)) { [titles addObject:@"保存视频"]; [kinds addObject:@"video"]; }
    if (AXSB_Bool(kAXLPPanelSaveCover, YES)) { [titles addObject:@"保存封面"]; [kinds addObject:@"cover"]; }
    if (AXSB_Bool(kAXLPPanelSaveAudio, YES)) { [titles addObject:@"保存音频"]; [kinds addObject:@"audio"]; }
    if (AXSB_Bool(kAXLPPanelSaveImage, YES)) { [titles addObject:@"保存图片"]; [kinds addObject:@"image"]; }
    if (AXSB_Bool(kAXLPPanelSaveAllImages, YES)) { [titles addObject:@"保存所有图片"]; [kinds addObject:@"image_all"]; }
    if (AXSB_Bool(kAXLPPanelCopyText, NO)) { [titles addObject:@"复制文案"]; [kinds addObject:@"copy_text"]; }
    if (titles.count == 0) return actions;

    NSMutableArray *m = [actions mutableCopy];
    for (NSInteger i = 0; i < (NSInteger)titles.count; i++) {
        BOOL exists = NO;
        for (id a in m) {
            NSString *t = AXSB_ActionTitle(a);
            if ([t isEqualToString:titles[i]]) { exists = YES; break; }
        }
        if (!exists) {
            id action = AXSB_MakeAction(titles[i], kinds[i]);
            if (action) [m addObject:action];
        }
    }

    objc_setAssociatedObject(sheet, &kAXSaveButtonsInjectedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return m;
}

%hook AWEUserActionSheetView
- (void)setActions:(NSArray *)actions {
    NSArray *patched = AXSB_ActionsByAppendingSaveButtons(actions, self);
    %orig(patched);
}
%end

%hook UIApplication
- (void)applicationDidBecomeActive:(UIApplication *)app {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ AXShow(); AXInstallTwoFingerLongPressGesture(); });
}
%end

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ AXShow(); AXInstallTwoFingerLongPressGesture(); });
}
