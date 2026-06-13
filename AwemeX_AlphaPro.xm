#import <UIKit/UIKit.h>

static CGFloat gAlpha = 1.0;

static inline BOOL isIpad(void) {
    return [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
}

static void loadSettings() {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    CGFloat val = [d floatForKey:@"alpha_top"];
    if (val > 0) gAlpha = val;
}

%hook UIView

- (void)setAlpha:(CGFloat)alpha {

    if (isIpad()) {
        loadSettings();

        CGFloat finalAlpha = alpha * gAlpha;

        if (fabs(self.alpha - finalAlpha) > 0.01) {
            %orig(finalAlpha);
            return;
        }
    }

    %orig(alpha);
}

%end
