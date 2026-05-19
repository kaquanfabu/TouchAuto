THEOS_DEVICE_IP = localhost
THEOS_DEVICE_PORT = 2222

ARCHS = arm64
TARGET = iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TouchAuto

TouchAuto_FILES = tweak/TouchAuto.xm \
                  tweak/TouchRecorder.h \
                  tweak/TouchRecorder.m \
                  tweak/TouchPlayer.h \
                  tweak/TouchPlayer.m \
                  tweak/FloatingPanel.h \
                  tweak/FloatingPanel.m \
                  tweak/TouchEvent.h \
                  tweak/TouchEvent.m \
                  tweak/AdvancedFeatures.h \
                  tweak/AdvancedFeatures.m

TouchAuto_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
TouchAuto_FRAMEWORKS = UIKit CoreGraphics CoreText ImageIO QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"