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
static UIView *axPanelContent = nil;
static UIScrollView *axPanelScroll = nil;
static UIView *axLongPressOverlay = nil;
static UIView *axLongPressPanel = nil;
static NSArray *axLongPressCurrentItems = nil;
static NSArray *axVideoSourceCurrentItems = nil;
static id axNativeLongPressPlayVC = nil;
static BOOL axOpeningNativeLongPress = NO;
static BOOL axApplyingElementEffects = NO;
static BOOL axSettingAlpha = NO;
static BOOL axMainRefreshScheduled = NO;
static UILongPressGestureRecognizer *axTwoFingerLongPressGesture = nil;
static UIWindow *axTwoFingerLongPressWindow = nil;
static char kAXSingleLongPressGestureKey;
static char kAXSingleLongPressOwnerKey;
static char kAXSingleLongPressMarkerKey;

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
static NSString * const kAXLPPanelSettingsExpanded = @"ax_lp_panel_settings_expanded";
static NSString * const kAXUISettingsExpanded = @"ax_ui_settings_expanded";

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
    return AXIsDescendantOf(v, axPanel) || AXIsDescendantOf(v, axButton) || AXIsDescendantOf(v, axLongPressOverlay) || AXIsDescendantOf(v, axLongPressPanel);
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
    UIView *host = axPanelContent ?: axPanel;
    UILabel *l = [[UILabel alloc] initWithFrame:frame];
    l.text = text;
    l.textColor = UIColor.whiteColor;
    l.font = [UIFont boldSystemFontOfSize:15];
    [host addSubview:l];

    UILabel *r = [[UILabel alloc] initWithFrame:CGRectMake(panelWidth - 110, frame.origin.y, 80, frame.size.height)];
    r.textAlignment = NSTextAlignmentRight;
    r.textColor = UIColor.whiteColor;
    r.font = [UIFont systemFontOfSize:14];
    r.text = [NSString stringWithFormat:@"%.0f%%", value * 100.0];
    [host addSubview:r];
    return r;
}

@interface AXMenuTarget : NSObject
+ (instancetype)shared;
- (void)openSettings;
- (void)closeSettings;
- (void)sliderChanged:(UISlider *)sender;
- (void)sliderCommit:(UISlider *)sender;
- (void)switchChanged:(UISwitch *)sender;
- (void)toggleLongPressPanelSettings;
- (void)toggleUISettings;
- (void)showUpdateLog;
@end

static void AXBuildSettingsContent(UIScrollView *scroll, CGFloat width);
static void AXReloadSettingsContent(BOOL animated);
static void AXSB_Toast(NSString *text);

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


static void AXBuildSettingsContent(UIScrollView *scroll, CGFloat width) {
    if (!scroll || !axPanelContent) return;
    for (UIView *subview in [axPanelContent.subviews copy]) {
        [subview removeFromSuperview];
    }
    CGFloat y = 10.0;
    BOOL uiExpanded = AXBool(kAXUISettingsExpanded, NO);
    UIButton *uiHeader = [UIButton buttonWithType:UIButtonTypeCustom];
    uiHeader.frame = CGRectMake(24, y, width - 48, 46);
    uiHeader.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.065];
    uiHeader.layer.cornerRadius = 13;
    [uiHeader addTarget:[AXMenuTarget shared] action:@selector(toggleUISettings) forControlEvents:UIControlEventTouchUpInside];
    [axPanelContent addSubview:uiHeader];

    UILabel *uiTitle = [[UILabel alloc] initWithFrame:CGRectMake(34, y + 9, width - 110, 28)];
    uiTitle.text = @"界面设置";
    uiTitle.textColor = UIColor.whiteColor;
    uiTitle.font = [UIFont boldSystemFontOfSize:16];
    [axPanelContent addSubview:uiTitle];

    UILabel *uiArrow = [[UILabel alloc] initWithFrame:CGRectMake(width - 58, y + 9, 28, 28)];
    uiArrow.text = uiExpanded ? @"⌃" : @"⌄";
    uiArrow.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.86];
    uiArrow.font = [UIFont boldSystemFontOfSize:18];
    uiArrow.textAlignment = NSTextAlignmentCenter;
    [axPanelContent addSubview:uiArrow];
    y += 56.0;

    if (uiExpanded) {
        NSArray *names = @[@"设置全局透明", @"顶部不透明度", @"右侧按钮不透明度", @"右侧按钮缩放比例", @"AX 图标不透明度", @"昵称文案缩放", @"昵称/文案不透明度"];
        NSArray *keys = @[kAXGlobalAlpha, kAXTopAlpha, kAXRightAlpha, kAXScale, kAXIconAlpha, kAXNicknameScale, kAXOFNicknameDescAlpha];
        NSArray *defs = @[@1.00, @0.65, @0.80, @0.81, @0.34, @1.00, @1.00];
        for (NSInteger i = 0; i < (NSInteger)names.count; i++) {
        CGFloat cur = AXFloat(keys[i], [defs[i] floatValue]);
        UILabel *val = AXLabel(names[i], cur, CGRectMake(30, y, width - 60, 24), width);
        val.tag = 8000 + i + 1;
        UISlider *sld = [[UISlider alloc] initWithFrame:CGRectMake(30, y + 30, width - 60, 30)];
        sld.tag = i + 1;
        BOOL isScaleSlider = (i == 3 || i == 5);
        sld.minimumValue = isScaleSlider ? 0.50 : 0.05;
        sld.maximumValue = isScaleSlider ? 1.30 : 1.00;
        sld.value = cur;
        [sld addTarget:[AXMenuTarget shared] action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        [sld addTarget:[AXMenuTarget shared] action:@selector(sliderCommit:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [axPanelContent addSubview:sld];
        y += 64.0;
        }

        NSArray *switchNames = @[@"隐藏右上搜索", @"隐藏相关搜索/合集", @"显示 AX 悬浮按钮"];
        NSArray *switchKeys = @[kAXHideSearch, kAXHideRelatedArea, kAXShowButton];
        NSArray *switchDefs = @[@NO, @NO, @YES];
        for (NSInteger i = 0; i < (NSInteger)switchNames.count; i++) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(30, y, width - 130, 34)];
        l.text = switchNames[i];
        l.textColor = UIColor.whiteColor;
        l.font = [UIFont boldSystemFontOfSize:15];
        [axPanelContent addSubview:l];
        UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(width - 88, y, 60, 32)];
        sw.tag = 11 + i;
        sw.on = AXBool(switchKeys[i], [switchDefs[i] boolValue]);
        [sw addTarget:[AXMenuTarget shared] action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        [axPanelContent addSubview:sw];
        y += 42.0;
        }
        y += 4.0;
    }

    BOOL lpExpanded = AXBool(kAXLPPanelSettingsExpanded, NO);
    UIButton *lpHeader = [UIButton buttonWithType:UIButtonTypeCustom];
    lpHeader.frame = CGRectMake(24, y, width - 48, 46);
    lpHeader.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.065];
    lpHeader.layer.cornerRadius = 13;
    [lpHeader addTarget:[AXMenuTarget shared] action:@selector(toggleLongPressPanelSettings) forControlEvents:UIControlEventTouchUpInside];
    [axPanelContent addSubview:lpHeader];

    UILabel *lpTitle = [[UILabel alloc] initWithFrame:CGRectMake(34, y + 9, width - 110, 28)];
    lpTitle.text = @"面板设置";
    lpTitle.textColor = UIColor.whiteColor;
    lpTitle.font = [UIFont boldSystemFontOfSize:16];
    [axPanelContent addSubview:lpTitle];

    UILabel *lpArrow = [[UILabel alloc] initWithFrame:CGRectMake(width - 58, y + 9, 28, 28)];
    lpArrow.text = lpExpanded ? @"⌃" : @"⌄";
    lpArrow.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.86];
    lpArrow.font = [UIFont boldSystemFontOfSize:18];
    lpArrow.textAlignment = NSTextAlignmentCenter;
    [axPanelContent addSubview:lpArrow];
    y += 56.0;

    if (lpExpanded) {
        NSArray *lpNames = @[@"保存视频", @"保存封面", @"保存音频", @"保存图片", @"保存所有图片", @"复制文案"];
        NSArray *lpKeys = @[kAXLPPanelSaveVideo, kAXLPPanelSaveCover, kAXLPPanelSaveAudio, kAXLPPanelSaveImage, kAXLPPanelSaveAllImages, kAXLPPanelCopyText];
        NSArray *lpDefs = @[@YES, @YES, @YES, @YES, @YES, @NO];
        for (NSInteger i = 0; i < (NSInteger)lpNames.count; i++) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(30, y, width - 130, 34.0)];
        l.text = lpNames[i];
        l.textColor = UIColor.whiteColor;
        l.font = [UIFont boldSystemFontOfSize:15];
        [axPanelContent addSubview:l];

        UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(width - 88, y, 60.0, 32.0)];
        sw.tag = 21 + i;
        sw.on = AXBool(lpKeys[i], [lpDefs[i] boolValue]);
        [sw addTarget:[AXMenuTarget shared] action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        [axPanelContent addSubview:sw];
        y += 42.0;
        }
    }

    y += 8.0;

    UIView *aboutCard = [[UIView alloc] initWithFrame:CGRectMake(24, y, width - 48, 88)];
    aboutCard.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.055];
    aboutCard.layer.cornerRadius = 13;
    aboutCard.clipsToBounds = YES;
    [axPanelContent addSubview:aboutCard];

    UILabel *versionIcon = [[UILabel alloc] initWithFrame:CGRectMake(14, 7, 34, 34)];
    versionIcon.text = @"🎅";
    versionIcon.font = [UIFont systemFontOfSize:20];
    versionIcon.textAlignment = NSTextAlignmentCenter;
    [aboutCard addSubview:versionIcon];

    UILabel *versionTitle = [[UILabel alloc] initWithFrame:CGRectMake(54, 8, width - 180, 32)];
    versionTitle.text = @"当前版本";
    versionTitle.textColor = [UIColor colorWithRed:0.34 green:0.68 blue:1.0 alpha:1.0];
    versionTitle.font = [UIFont boldSystemFontOfSize:15];
    [aboutCard addSubview:versionTitle];

    UILabel *versionValue = [[UILabel alloc] initWithFrame:CGRectMake(width - 150, 8, 96, 32)];
    versionValue.text = @"V48";
    versionValue.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.72];
    versionValue.font = [UIFont boldSystemFontOfSize:14];
    versionValue.textAlignment = NSTextAlignmentRight;
    [aboutCard addSubview:versionValue];

    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(54, 44, width - 126, 0.5)];
    line.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12];
    [aboutCard addSubview:line];

    UIButton *logButton = [UIButton buttonWithType:UIButtonTypeCustom];
    logButton.frame = CGRectMake(0, 45, width - 48, 43);
    [logButton addTarget:[AXMenuTarget shared] action:@selector(showUpdateLog) forControlEvents:UIControlEventTouchUpInside];
    [aboutCard addSubview:logButton];

    UILabel *logIcon = [[UILabel alloc] initWithFrame:CGRectMake(14, 49, 34, 34)];
    logIcon.text = @"📣";
    logIcon.font = [UIFont systemFontOfSize:19];
    logIcon.textAlignment = NSTextAlignmentCenter;
    [aboutCard addSubview:logIcon];

    UILabel *logTitle = [[UILabel alloc] initWithFrame:CGRectMake(54, 52, width - 170, 28)];
    logTitle.text = @"更新日志";
    logTitle.textColor = [UIColor colorWithRed:0.34 green:0.68 blue:1.0 alpha:1.0];
    logTitle.font = [UIFont boldSystemFontOfSize:15];
    [aboutCard addSubview:logTitle];

    UILabel *logArrow = [[UILabel alloc] initWithFrame:CGRectMake(width - 84, 52, 26, 28)];
    logArrow.text = @"›";
    logArrow.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.45];
    logArrow.font = [UIFont boldSystemFontOfSize:24];
    logArrow.textAlignment = NSTextAlignmentRight;
    [aboutCard addSubview:logArrow];

    y += 108.0;
    CGFloat maxHeight = MAX(y, scroll.bounds.size.height + 1.0);
    axPanelContent.frame = CGRectMake(0, 0, width, maxHeight);
    scroll.contentSize = CGSizeMake(width, maxHeight);
}

static void AXReloadSettingsContent(BOOL animated) {
    (void)animated;
    if (!axPanel || !axPanelContent || !axPanelScroll) return;
    CGFloat width = axPanelScroll.bounds.size.width;
    CGPoint oldOffset = axPanelScroll.contentOffset;
    [UIView performWithoutAnimation:^{
        AXBuildSettingsContent(axPanelScroll, width);
        CGFloat maxY = MAX(0.0, axPanelScroll.contentSize.height - axPanelScroll.bounds.size.height);
        axPanelScroll.contentOffset = CGPointMake(oldOffset.x, MIN(oldOffset.y, maxY));
        [axPanelContent layoutIfNeeded];
    }];
}

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
    axPanelContent = nil;
    axPanelScroll = nil;
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

- (void)toggleLongPressPanelSettings {
    BOOL expanded = AXBool(kAXLPPanelSettingsExpanded, NO);
    AXSet(kAXLPPanelSettingsExpanded, @(!expanded));
    AXReloadSettingsContent(YES);
}

- (void)toggleUISettings {
    BOOL expanded = AXBool(kAXUISettingsExpanded, YES);
    AXSet(kAXUISettingsExpanded, @(!expanded));
    AXReloadSettingsContent(YES);
}

- (void)showUpdateLog {
    AXSB_Toast(@"V48：保存视频增加清晰度/来源选择；接口解析保留为后续可配置项。");
}

- (void)openSettings {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = AXKeyWindow();
        if (!w) return;
        if (axPanel) { [self closeSettings]; return; }

        CGRect b = UIScreen.mainScreen.bounds;
        CGFloat width = MIN(420.0, b.size.width - 120.0);
        width = MAX(340.0, width);
        CGFloat height = MIN(560.0, MAX(420.0, b.size.height * 0.58));
        axPanel = [[UIView alloc] initWithFrame:CGRectMake((b.size.width - width) / 2.0, (b.size.height - height) / 2.0, width, height)];
        axPanel.tag = 42029;
        axPanel.backgroundColor = [[UIColor colorWithWhite:0.08 alpha:1.0] colorWithAlphaComponent:0.88];
        axPanel.layer.cornerRadius = 20;
        axPanel.clipsToBounds = YES;
        axPanel.userInteractionEnabled = YES;
        axPanel.exclusiveTouch = YES;
        axPanel.layer.zPosition = CGFLOAT_MAX;
        [w addSubview:axPanel];
        [w bringSubviewToFront:axPanel];

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 16, width, 30)];
        title.text = @"AwemeX for iPad";
        title.textColor = UIColor.whiteColor;
        title.font = [UIFont boldSystemFontOfSize:18];
        title.textAlignment = NSTextAlignmentCenter;
        [axPanel addSubview:title];

        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.frame = CGRectMake(width - 52, 14, 36, 36);
        [close setTitle:@"×" forState:UIControlStateNormal];
        [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        close.titleLabel.font = [UIFont boldSystemFontOfSize:24];
        [close addTarget:self action:@selector(closeSettings) forControlEvents:UIControlEventTouchUpInside];
        [axPanel addSubview:close];

        UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 56, width, height - 64)];
        scroll.alwaysBounceVertical = YES;
        scroll.showsVerticalScrollIndicator = YES;
        scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
        [axPanel addSubview:scroll];

        axPanelContent = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, scroll.bounds.size.height + 1.0)];
        [scroll addSubview:axPanelContent];
        axPanelScroll = scroll;
        AXBuildSettingsContent(scroll, width);

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


// AwemeX iPad 单指长按菜单：成熟稳定方案。
// 设计原则：不额外安装单指长按手势，不叠加原生面板；直接拦截抖音长按入口，显示 AwemeX 自己的轻量面板。
// 面板内容按当前作品类型自动区分：视频只显示视频/封面/音频相关，图集只显示图片相关；不包含“生成视频/制作视频”。

static id axCurrentLongPressAweme = nil;

@interface AXLongPressPanelTarget : NSObject
+ (instancetype)shared;
- (void)closeLongPressPanel;
- (void)actionTapped:(UIButton *)sender;
- (void)openNativeLongPressPanel;
- (void)videoSourceTapped:(UIButton *)sender;
- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo;
- (void)video:(NSString *)videoPath didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo;
@end

@interface AXSingleLongPressTarget : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)handleSingleLongPress:(UILongPressGestureRecognizer *)gesture;
@end

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


static NSString *AXSB_StringBySelectors(id obj, NSArray<NSString *> *sels) {
    if (!obj) return nil;
    for (NSString *name in sels) {
        id v = AXSB_Send0(obj, NSSelectorFromString(name));
        if ([v isKindOfClass:NSString.class] && [(NSString *)v length] > 0) return v;
        if ([v respondsToSelector:@selector(stringValue)]) {
            NSString *s = [v stringValue];
            if (s.length > 0) return s;
        }
    }
    return nil;
}

static NSArray *AXSB_ArrayBySelectors(id obj, NSArray<NSString *> *sels) {
    if (!obj) return nil;
    for (NSString *name in sels) {
        id v = AXSB_Send0(obj, NSSelectorFromString(name));
        if ([v isKindOfClass:NSArray.class]) return v;
    }
    return nil;
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

static id AXSB_AwemeModelFromPlayVC(id playVC) {
    NSArray *sels = @[@"awemeModel", @"aweme", @"model", @"currentAweme", @"currentAwemeModel", @"currentModel", @"item"];
    for (NSString *name in sels) {
        id value = AXSB_Send0(playVC, NSSelectorFromString(name));
        if (value) return value;
    }
    if ([playVC respondsToSelector:@selector(valueForKey:)]) {
        for (NSString *key in sels) {
            @try {
                id value = [playVC valueForKey:key];
                if (value) return value;
            } @catch (NSException *e) {}
        }
    }
    return nil;
}

static id AXSB_CurrentAwemeModel(void) {
    return axCurrentLongPressAweme;
}

static NSURL *AXSB_CoverURLFromAweme(id aweme) {
    if (!aweme) return nil;
    id video = AXSB_Send0(aweme, @selector(video));
    return AXSB_FirstURLBySelectors(video ?: aweme, @[@"originCover", @"cover", @"dynamicCover", @"animatedCover", @"coverUrl", @"coverURL"], 5);
}

static NSURL *AXSB_AudioURLFromAweme(id aweme) {
    if (!aweme) return nil;
    id music = AXSB_Send0(aweme, @selector(music));
    if (!music) music = AXSB_Send0(aweme, @selector(musicModel));
    return AXSB_FirstURLBySelectors(music ?: aweme, @[@"playUrl", @"playURL", @"playUrlModel", @"downloadUrl", @"downloadURL", @"urlModel"], 6);
}

static NSArray<NSURL *> *AXSB_ImageURLsFromAweme(id aweme) {
    if (!aweme) return @[];
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    NSArray *candidates = @[
        AXSB_Send0(aweme, @selector(albumImages)) ?: [NSNull null],
        AXSB_Send0(aweme, @selector(images)) ?: [NSNull null],
        AXSB_Send0(aweme, @selector(imageInfos)) ?: [NSNull null],
        AXSB_Send0(aweme, @selector(imageAlbum)) ?: [NSNull null],
        AXSB_Send0(aweme, @selector(imagePostInfo)) ?: [NSNull null]
    ];
    for (id c in candidates) {
        if (c == (id)[NSNull null]) continue;
        if ([c isKindOfClass:NSArray.class]) {
            for (id item in (NSArray *)c) {
                NSURL *u = AXSB_FirstURLInObject(item, 6);
                if (u && ![urls containsObject:u]) [urls addObject:u];
            }
        } else {
            NSURL *u = AXSB_FirstURLInObject(c, 6);
            if (u && ![urls containsObject:u]) [urls addObject:u];
        }
    }
    return urls;
}

static void AXSB_Toast(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = AXSB_KeyWindow();
        if (!w) return;
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
        l.text = text ?: @"";
        l.textColor = UIColor.whiteColor;
        l.font = [UIFont boldSystemFontOfSize:14];
        l.textAlignment = NSTextAlignmentCenter;
        l.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.72];
        l.layer.cornerRadius = 10;
        l.clipsToBounds = YES;
        CGSize size = [l sizeThatFits:CGSizeMake(360, 40)];
        CGFloat width = MIN(MAX(size.width + 28, 130), w.bounds.size.width - 60);
        l.frame = CGRectMake((w.bounds.size.width - width) / 2.0, w.bounds.size.height * 0.18, width, 40);
        l.alpha = 0;
        l.layer.zPosition = CGFLOAT_MAX;
        [w addSubview:l];
        [UIView animateWithDuration:0.18 animations:^{ l.alpha = 1; } completion:^(BOOL finished) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [UIView animateWithDuration:0.18 animations:^{ l.alpha = 0; } completion:^(BOOL done) { [l removeFromSuperview]; }];
            });
        }];
    });
}


static UIButton *AXSB_MakePanelButton(NSString *title, NSInteger tag, CGRect frame);
static void AXSB_SaveVideoURL(NSURL *url);

static void AXSB_AddVideoSource(NSMutableArray<NSDictionary *> *items, NSString *title, NSURL *url) {
    if (!url || title.length == 0) return;
    NSString *abs = url.absoluteString;
    if (abs.length == 0) return;
    for (NSDictionary *it in items) {
        NSURL *old = it[@"url"];
        if ([old.absoluteString isEqualToString:abs]) return;
    }
    [items addObject:@{ @"title": title, @"url": url }];
}

static NSURL *AXSB_URLFromURLModel(id obj) {
    if (!obj) return nil;
    NSURL *u = AXSB_FirstURLBySelectors(obj, @[@"originURLList", @"urlList", @"URLList", @"url_list", @"urls"], 5);
    if (u) return u;
    return AXSB_FirstURLInObject(obj, 4);
}

static NSArray<NSDictionary *> *AXSB_VideoSourcesFromAweme(id aweme) {
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    if (!aweme) return items;
    id video = AXSB_Send0(aweme, @selector(video));
    id target = video ?: aweme;

    NSArray *bitRates = AXSB_ArrayBySelectors(target, @[@"bitRate", @"bitRates", @"bitrate", @"bitrateModels", @"playBitrateModels"]);
    if ([bitRates isKindOfClass:NSArray.class]) {
        NSInteger idx = 1;
        for (id br in bitRates) {
            NSURL *u = AXSB_FirstURLBySelectors(br, @[@"playAddr", @"playURL", @"playUrl", @"downloadAddr", @"urlModel", @"urlList"], 5);
            if (!u) u = AXSB_FirstURLInObject(br, 4);
            NSString *quality = AXSB_StringBySelectors(br, @[@"gearName", @"qualityType", @"qualityDesc", @"quality", @"definition", @"name"]);
            NSString *title = quality.length > 0 ? [NSString stringWithFormat:@"%@源", quality] : [NSString stringWithFormat:@"清晰度源 %ld", (long)idx];
            AXSB_AddVideoSource(items, title, u);
            idx++;
        }
    }

    id h264 = AXSB_Send0(target, @selector(h264URL));
    AXSB_AddVideoSource(items, @"高清 H264", AXSB_URLFromURLModel(h264));

    id play = AXSB_Send0(target, @selector(playURL));
    AXSB_AddVideoSource(items, @"播放地址", AXSB_URLFromURLModel(play));

    id playAddr = AXSB_Send0(target, @selector(playAddr));
    AXSB_AddVideoSource(items, @"播放源", AXSB_URLFromURLModel(playAddr));

    id download = AXSB_Send0(target, @selector(downloadAddr));
    AXSB_AddVideoSource(items, @"下载地址", AXSB_URLFromURLModel(download));

    NSURL *fallback = AXSB_FirstURLInObject(target, 5);
    AXSB_AddVideoSource(items, @"备用源", fallback);
    return items;
}

static void AXSB_ShowVideoSourcePanelForAweme(id aweme) {
    NSArray<NSDictionary *> *sources = AXSB_VideoSourcesFromAweme(aweme);
    if (sources.count == 0) { AXSB_Toast(@"视频链接为空"); return; }
    if (sources.count == 1) { AXSB_SaveVideoURL(sources.firstObject[@"url"]); return; }

    axVideoSourceCurrentItems = sources;
    UIWindow *w = AXSB_KeyWindow();
    if (!w) return;
    CGRect b = w.bounds;

    UIView *overlay = [[UIView alloc] initWithFrame:b];
    overlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.08];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.alpha = 0;
    overlay.layer.zPosition = CGFLOAT_MAX;
    [w addSubview:overlay];
    axLongPressOverlay = overlay;

    UIButton *dismiss = [UIButton buttonWithType:UIButtonTypeCustom];
    dismiss.frame = overlay.bounds;
    dismiss.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [dismiss addTarget:[AXLongPressPanelTarget shared] action:@selector(closeLongPressPanel) forControlEvents:UIControlEventTouchUpInside];
    [overlay addSubview:dismiss];

    CGFloat panelW = MIN(500.0, MAX(320.0, b.size.width - 96.0));
    CGFloat rowH = 50.0;
    CGFloat contentH = 76.0 + sources.count * (rowH + 10.0) + 20.0;
    CGFloat panelH = MIN(contentH, b.size.height * 0.64);
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake((b.size.width - panelW) / 2.0, (b.size.height - panelH) / 2.0, panelW, panelH)];
    panel.backgroundColor = [[UIColor colorWithWhite:0.08 alpha:1.0] colorWithAlphaComponent:0.90];
    panel.layer.cornerRadius = 22;
    panel.layer.masksToBounds = YES;
    [overlay addSubview:panel];
    axLongPressPanel = panel;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(24, 18, panelW - 90, 34)];
    title.text = @"选择视频源";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:20];
    [panel addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
    close.frame = CGRectMake(panelW - 58, 16, 40, 40);
    [close setTitle:@"×" forState:UIControlStateNormal];
    [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont boldSystemFontOfSize:30];
    [close addTarget:[AXLongPressPanelTarget shared] action:@selector(closeLongPressPanel) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:close];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 66, panelW, panelH - 66)];
    scroll.showsVerticalScrollIndicator = YES;
    [panel addSubview:scroll];

    CGFloat y = 4.0;
    for (NSInteger i = 0; i < (NSInteger)sources.count; i++) {
        UIButton *btn = AXSB_MakePanelButton(sources[i][@"title"], i, CGRectMake(24, y, panelW - 48, rowH));
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        [btn addTarget:[AXLongPressPanelTarget shared] action:@selector(videoSourceTapped:) forControlEvents:UIControlEventTouchUpInside];
        [scroll addSubview:btn];
        y += rowH + 10.0;
    }
    scroll.contentSize = CGSizeMake(panelW, MAX(y, scroll.bounds.size.height + 1.0));

    panel.transform = CGAffineTransformMakeScale(0.96, 0.96);
    [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        overlay.alpha = 1;
        panel.transform = CGAffineTransformIdentity;
    } completion:nil];
}

static void AXSB_SaveImageURL(NSURL *url, NSString *name) {
    if (!url) { AXSB_Toast([NSString stringWithFormat:@"%@链接为空", name]); return; }
    AXSB_Toast([NSString stringWithFormat:@"正在保存%@…", name]);
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        UIImage *img = data ? [UIImage imageWithData:data] : nil;
        if (!img) { AXSB_Toast([NSString stringWithFormat:@"%@保存失败", name]); return; }
        UIImageWriteToSavedPhotosAlbum(img, [AXLongPressPanelTarget shared], @selector(image:didFinishSavingWithError:contextInfo:), nil);
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
        if (!UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(tmp)) { AXSB_Toast(@"视频格式不兼容"); return; }
        UISaveVideoAtPathToSavedPhotosAlbum(tmp, [AXLongPressPanelTarget shared], @selector(video:didFinishSavingWithError:contextInfo:), nil);
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
            if (!vc) return;
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
    if (!aweme) { AXSB_Toast(@"未找到当前作品模型"); return; }
    if ([kind isEqualToString:@"video"]) {
        AXSB_ShowVideoSourcePanelForAweme(aweme);
    } else if ([kind isEqualToString:@"cover"]) {
        AXSB_SaveImageURL(AXSB_CoverURLFromAweme(aweme), @"封面");
    } else if ([kind isEqualToString:@"audio"]) {
        AXSB_ShareAudioURL(AXSB_AudioURLFromAweme(aweme));
    } else if ([kind isEqualToString:@"image"]) {
        NSArray<NSURL *> *urls = AXSB_ImageURLsFromAweme(aweme);
        AXSB_SaveImageURL(urls.count > 0 ? urls.firstObject : nil, @"图片");
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

static NSInteger AXSB_AwemeContentType(id aweme) {
    if (!aweme) return 0;
    NSArray<NSURL *> *imgs = AXSB_ImageURLsFromAweme(aweme);
    if (imgs.count > 0) return 1; // 图集/图片

    id typeObj = AXSB_Send0(aweme, @selector(awemeType));
    if ([typeObj respondsToSelector:@selector(integerValue)] && [typeObj integerValue] == 68) return 1;
    if ([aweme respondsToSelector:@selector(valueForKey:)]) {
        @try {
            id v = [aweme valueForKey:@"awemeType"];
            if ([v respondsToSelector:@selector(integerValue)] && [v integerValue] == 68) return 1;
        } @catch (NSException *e) {}
    }
    return 2; // 视频/其它按视频处理
}

static NSArray<NSDictionary *> *AXSB_BuildLongPressItemsForAweme(id aweme) {
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    NSInteger contentType = AXSB_AwemeContentType(aweme);
    BOOL isImage = (contentType == 1);

    if (isImage) {
        if (AXSB_Bool(kAXLPPanelSaveImage, YES)) {
            [items addObject:@{ @"title": @"保存图片", @"kind": @"image" }];
        }
        if (AXSB_ImageURLsFromAweme(aweme).count > 1 && AXSB_Bool(kAXLPPanelSaveAllImages, YES)) {
            [items addObject:@{ @"title": @"保存所有图片", @"kind": @"image_all" }];
        }
    } else {
        if (AXSB_Bool(kAXLPPanelSaveVideo, YES)) {
            [items addObject:@{ @"title": @"保存视频", @"kind": @"video" }];
        }
        if (AXSB_Bool(kAXLPPanelSaveCover, YES)) {
            [items addObject:@{ @"title": @"保存封面", @"kind": @"cover" }];
        }
        if (AXSB_Bool(kAXLPPanelSaveAudio, YES)) {
            [items addObject:@{ @"title": @"保存音频", @"kind": @"audio" }];
        }
    }

    if (AXSB_Bool(kAXLPPanelCopyText, NO)) {
        [items addObject:@{ @"title": @"复制文案", @"kind": @"copy_text" }];
    }
    return items;
}

static void AXSB_CloseLongPressPanel(void) {
    UIView *overlay = axLongPressOverlay;
    axLongPressOverlay = nil;
    axLongPressPanel = nil;
    axLongPressCurrentItems = nil;
    axVideoSourceCurrentItems = nil;
    axNativeLongPressPlayVC = nil;
    if (!overlay) return;
    [UIView animateWithDuration:0.16 animations:^{
        overlay.alpha = 0;
    } completion:^(BOOL finished) {
        [overlay removeFromSuperview];
    }];
}

static UIButton *AXSB_MakePanelButton(NSString *title, NSInteger tag, CGRect frame) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = frame;
    button.tag = tag;
    button.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.075];
    button.layer.cornerRadius = 14;
    button.clipsToBounds = YES;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.titleEdgeInsets = UIEdgeInsetsMake(0, 20, 0, 20);
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    return button;
}

static void AXSB_ShowCustomLongPressPanelForAweme(id aweme, id playVC) {
    if (!aweme) { AXSB_Toast(@"未找到当前作品模型"); return; }
    NSArray<NSDictionary *> *items = AXSB_BuildLongPressItemsForAweme(aweme);
    if (items.count == 0) {
        if (playVC) {
            axOpeningNativeLongPress = YES;
            ((void (*)(id, SEL))objc_msgSend)(playVC, @selector(showDislikeOnVideo));
        }
        return;
    }

    AXSB_CloseLongPressPanel();
    axCurrentLongPressAweme = aweme;
    axNativeLongPressPlayVC = playVC;
    axLongPressCurrentItems = items;

    UIWindow *w = AXSB_KeyWindow();
    if (!w) return;
    CGRect b = w.bounds;

    UIView *overlay = [[UIView alloc] initWithFrame:b];
    overlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.08];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.alpha = 0;
    overlay.layer.zPosition = CGFLOAT_MAX;
    [w addSubview:overlay];
    axLongPressOverlay = overlay;

    UIButton *dismiss = [UIButton buttonWithType:UIButtonTypeCustom];
    dismiss.frame = overlay.bounds;
    dismiss.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [dismiss addTarget:[AXLongPressPanelTarget shared] action:@selector(closeLongPressPanel) forControlEvents:UIControlEventTouchUpInside];
    [overlay addSubview:dismiss];

    CGFloat panelW = MIN(520.0, MAX(320.0, b.size.width - 80.0));
    CGFloat rowH = 52.0;
    CGFloat contentH = 76.0 + items.count * (rowH + 12.0) + 70.0;
    CGFloat panelH = MIN(contentH, b.size.height * 0.72);
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake((b.size.width - panelW) / 2.0, (b.size.height - panelH) / 2.0, panelW, panelH)];
    panel.backgroundColor = [[UIColor colorWithWhite:0.08 alpha:1.0] colorWithAlphaComponent:0.90];
    panel.layer.cornerRadius = 22;
    panel.layer.masksToBounds = YES;
    [overlay addSubview:panel];
    axLongPressPanel = panel;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(24, 18, panelW - 90, 34)];
    title.text = (AXSB_AwemeContentType(aweme) == 1) ? @"图片面板" : @"视频面板";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:20];
    [panel addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
    close.frame = CGRectMake(panelW - 58, 16, 40, 40);
    [close setTitle:@"×" forState:UIControlStateNormal];
    [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont boldSystemFontOfSize:30];
    [close addTarget:[AXLongPressPanelTarget shared] action:@selector(closeLongPressPanel) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:close];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 66, panelW, panelH - 66)];
    scroll.showsVerticalScrollIndicator = YES;
    [panel addSubview:scroll];

    CGFloat y = 4.0;
    for (NSInteger i = 0; i < (NSInteger)items.count; i++) {
        UIButton *btn = AXSB_MakePanelButton(items[i][@"title"], i, CGRectMake(24, y, panelW - 48, rowH));
        [btn addTarget:[AXLongPressPanelTarget shared] action:@selector(actionTapped:) forControlEvents:UIControlEventTouchUpInside];
        [scroll addSubview:btn];
        y += rowH + 12.0;
    }

    UIButton *native = AXSB_MakePanelButton(@"打开原长按面板", 999, CGRectMake(24, y + 2.0, panelW - 48, 46.0));
    native.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [native addTarget:[AXLongPressPanelTarget shared] action:@selector(openNativeLongPressPanel) forControlEvents:UIControlEventTouchUpInside];
    [scroll addSubview:native];
    y += 58.0;
    scroll.contentSize = CGSizeMake(panelW, MAX(y, scroll.bounds.size.height + 1.0));

    panel.transform = CGAffineTransformMakeScale(0.96, 0.96);
    [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        overlay.alpha = 1;
        panel.transform = CGAffineTransformIdentity;
    } completion:nil];
}

@implementation AXLongPressPanelTarget
+ (instancetype)shared {
    static AXLongPressPanelTarget *target;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ target = [AXLongPressPanelTarget new]; });
    return target;
}

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    AXSB_Toast(error ? @"图片保存失败" : @"图片已保存到相册");
}

- (void)video:(NSString *)videoPath didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    AXSB_Toast(error ? @"视频保存失败" : @"视频已保存到相册");
}

- (void)closeLongPressPanel {
    AXSB_CloseLongPressPanel();
}

- (void)actionTapped:(UIButton *)sender {
    NSInteger idx = sender.tag;
    if (idx < 0 || idx >= (NSInteger)axLongPressCurrentItems.count) return;
    NSDictionary *item = axLongPressCurrentItems[idx];
    NSString *kind = item[@"kind"];
    AXSB_CloseLongPressPanel();
    AXSB_HandleSaveKind(kind);
}

- (void)videoSourceTapped:(UIButton *)sender {
    NSInteger idx = sender.tag;
    if (idx < 0 || idx >= (NSInteger)axVideoSourceCurrentItems.count) return;
    NSDictionary *item = axVideoSourceCurrentItems[idx];
    NSURL *url = item[@"url"];
    AXSB_CloseLongPressPanel();
    AXSB_SaveVideoURL(url);
}

- (void)openNativeLongPressPanel {
    id vc = axNativeLongPressPlayVC;
    AXSB_CloseLongPressPanel();
    if (!vc) return;
    axOpeningNativeLongPress = YES;
    ((void (*)(id, SEL))objc_msgSend)(vc, @selector(showDislikeOnVideo));
}
@end


static BOOL AXGestureIsOurSingleLongPress(UIGestureRecognizer *g) {
    return g && [objc_getAssociatedObject(g, &kAXSingleLongPressMarkerKey) boolValue];
}

static void AXInstallSingleLongPressForPlayVC(id playVC) {
    if (!playVC || ![playVC respondsToSelector:@selector(view)]) return;
    UIView *view = ((UIView *(*)(id, SEL))objc_msgSend)(playVC, @selector(view));
    if (!view || ![view isKindOfClass:UIView.class]) return;

    UILongPressGestureRecognizer *existing = objc_getAssociatedObject(view, &kAXSingleLongPressGestureKey);
    if (existing && [view.gestureRecognizers containsObject:existing]) {
        objc_setAssociatedObject(existing, &kAXSingleLongPressOwnerKey, playVC, OBJC_ASSOCIATION_ASSIGN);
        return;
    }

    AXSingleLongPressTarget *target = [AXSingleLongPressTarget shared];
    UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc] initWithTarget:target action:@selector(handleSingleLongPress:)];
    gesture.minimumPressDuration = 0.55;
    gesture.numberOfTouchesRequired = 1;
    gesture.cancelsTouchesInView = YES;
    gesture.delaysTouchesBegan = NO;
    gesture.delaysTouchesEnded = NO;
    gesture.delegate = target;

    objc_setAssociatedObject(gesture, &kAXSingleLongPressMarkerKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(gesture, &kAXSingleLongPressOwnerKey, playVC, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(view, &kAXSingleLongPressGestureKey, gesture, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [view addGestureRecognizer:gesture];

    // 关键：让抖音原生长按手势等待我们的手势失败，避免两个面板叠加。
    for (UIGestureRecognizer *g in view.gestureRecognizers) {
        if (g != gesture && [g isKindOfClass:UILongPressGestureRecognizer.class]) {
            [g requireGestureRecognizerToFail:gesture];
        }
    }
}

@implementation AXSingleLongPressTarget
+ (instancetype)shared {
    static AXSingleLongPressTarget *target;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ target = [AXSingleLongPressTarget new]; });
    return target;
}

- (void)handleSingleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    id playVC = objc_getAssociatedObject(gesture, &kAXSingleLongPressOwnerKey);
    id aweme = AXSB_AwemeModelFromPlayVC(playVC);
    if (!aweme && playVC && [playVC respondsToSelector:@selector(showDislikeOnVideo)]) {
        axOpeningNativeLongPress = YES;
        ((void (*)(id, SEL))objc_msgSend)(playVC, @selector(showDislikeOnVideo));
        return;
    }
    AXSB_ShowCustomLongPressPanelForAweme(aweme, playVC);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (AXGestureIsOurSingleLongPress(gestureRecognizer) || AXGestureIsOurSingleLongPress(otherGestureRecognizer)) return NO;
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    UIView *v = touch.view;
    while (v) {
        if (AXIsAwemeXPanelView(v)) return NO;
        NSString *name = NSStringFromClass(v.class);
        if ([name containsString:@"Comment"] || [name containsString:@"Input"] || [name containsString:@"TextField"] || [name containsString:@"TextView"]) return NO;
        v = v.superview;
    }
    return YES;
}
@end

%hook AWEPlayInteractionViewController
- (void)viewDidLoad {
    %orig;
    AXInstallSingleLongPressForPlayVC((id)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    AXInstallSingleLongPressForPlayVC((id)self);
}

- (void)showDislikeOnVideo {
    if (axOpeningNativeLongPress) {
        axOpeningNativeLongPress = NO;
        %orig;
        return;
    }
    id aweme = AXSB_AwemeModelFromPlayVC((id)self);
    if (!aweme) {
        %orig;
        return;
    }
    AXSB_ShowCustomLongPressPanelForAweme(aweme, (id)self);
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
