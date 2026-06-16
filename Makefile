TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = Aweme

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AwemeXAlphaPro
AwemeXAlphaPro_FILES = AwemeX_AlphaPro.xm
AwemeXAlphaPro_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
AwemeXAlphaPro_CFLAGS = -fobjc-arc -Wno-error=deprecated-declarations

include $(THEOS_MAKE_PATH)/tweak.mk
