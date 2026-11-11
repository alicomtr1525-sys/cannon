TARGET := iphone:clang:latest:14.0
ARCHS = arm64
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CannonNougat
CannonNougat_FILES = Tweak.x
CannonNougat_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
