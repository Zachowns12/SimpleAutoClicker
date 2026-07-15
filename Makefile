export THEOS_PACKAGE_SCHEME = rootless

TARGET := iphone:clang:latest:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SimpleAutoClicker

SimpleAutoClicker_FILES = Tweak.xm
SimpleAutoClicker_CFLAGS = -fobjc-arc
SimpleAutoClicker_FRAMEWORKS = UIKit CoreGraphics
SimpleAutoClicker_PRIVATE_FRAMEWORKS = IOKit

include $(THEOS_MAKE_PATH)/tweak.mk
