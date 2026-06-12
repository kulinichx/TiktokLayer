#import <UIKit/UIKit.h>

static inline BOOL isIpad(void) {
    return [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
}

#pragma mark - ✅ 强制修复异常缩放（核心）

%hook UIView

- (void)setTransform:(CGAffineTransform)transform {
    if (isIpad()) {

        // ❗关键：拦截异常缩放（小于0.5直接修正）
        if (transform.a > 0.0 && transform.a < 0.5) {
            transform = CGAffineTransformMakeScale(0.6, 0.6);
        }

        // 防止叠加
        if (transform.a > 1.2) {
            transform = CGAffineTransformIdentity;
        }
    }

    %orig(transform);
}

%end

#pragma mark - ✅ 强制修复右侧按钮区域

%hook UIView

- (void)layoutSubviews {
    %orig;

    if (!isIpad()) return;

    for (UIView *sub in self.subviews) {

        CGFloat w = sub.bounds.size.width;
        CGFloat h = sub.bounds.size.height;

        // 🎯 精准识别右侧操作栏（比之前更稳）
        if (w < 150 && h > 250) {

            // ❗如果被缩小，直接恢复
            if (sub.transform.a < 0.6) {
                sub.transform = CGAffineTransformMakeScale(0.6, 0.6);
            }
        }
    }
}

%end

#pragma mark - ✅ 修复 iPad 长按菜单（核心）

%hook UIView

- (void)didMoveToWindow {
    %orig;

    if (!isIpad()) return;

    NSString *cls = NSStringFromClass([self class]);

    // ❗隐藏 iPad 原生菜单（让原插件逻辑触发）
    if ([cls containsString:@"ContextMenu"] ||
        [cls containsString:@"UIContextMenu"] ||
        [cls containsString:@"Menu"] ||
        [cls containsString:@"Interaction"]) {

        self.hidden = YES;
        self.alpha = 0.0;
    }
}

%end

#pragma mark - ✅ 强制启用长按（补充）

%hook UILongPressGestureRecognizer

- (void)setEnabled:(BOOL)enabled {
    if (isIpad()) {
        enabled = YES;
    }
    %orig(enabled);
}

%end
