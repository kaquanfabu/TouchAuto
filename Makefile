ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TouchAuto

TouchAuto_FILES = \
tweak/TouchAuto.xm \
tweak/TouchRecorder.m \
tweak/TouchPlayer.m \
tweak/FloatingPanel.m \
tweak/TouchEvent.m \
tweak/AdvancedFeatures.m

TouchAuto_CFLAGS = -fobjc-arc
TouchAuto_FRAMEWORKS = UIKit CoreGraphics QuartzCore Foundation

TouchAuto_PRIVATE_FRAMEWORKS = GraphicsServices IOKit

INSTALL_TARGET_PROCESSES = TargetApp

include $(THEOS_MAKE_PATH)/tweak.mk
