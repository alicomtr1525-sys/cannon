# iPhone 7 (A10, arm64) + palera1n rootless + iOS 15.x
# THEOS_PACKAGE_SCHEME=rootless: https://theos.dev/docs/rootless
export THEOS_PACKAGE_SCHEME = rootless

ARCHS = arm64
TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Cannon

Cannon_FILES = Tweak.x CNDrawerView.m
Cannon_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
Cannon_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
