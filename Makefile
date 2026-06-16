TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES := Aweme

TWEAK_NAME := AwemeX_AlphaPro
AwemeX_AlphaPro_FILES := AwemeX_AlphaPro.xm
AwemeX_AlphaPro_FRAMEWORKS := UIKit QuartzCore
AwemeX_AlphaPro_CFLAGS := -fobjc-arc

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
