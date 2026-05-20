ARCHS = arm64
TARGET = iphone:clang:16.5:15.0
SDKVERSION = 16.5

# PTFakeTouch library path
PTFAKETOUCH_LOCAL_PATH = $(TOP)/vendor/PTFakeTouch
PTFAKETOUCH_URL = https://github.com/Ret70/PTFakeTouch.git

# Clone PTFakeTouch if not present
PTFAKETOUCH_FOUND := $(wildcard $(PTFAKETOUCH_LOCAL_PATH)/PTFakeTouch/PTFakeTouch.h)
ifeq ($(PTFAKETOUCH_FOUND),)
$(error PTFakeTouch not found. Run: git submodule add https://github.com/Ret70/PTFakeTouch.git vendor/PTFakeTouch)
endif
PTFAKETOUCH_SOURCES = $(wildcard $(PTFAKETOUCH_LOCAL_PATH)/PTFakeTouch/PTFakeTouch/*.m) $(wildcard $(PTFAKETOUCH_LOCAL_PATH)/PTFakeTouch/addition/*.m)
PTFAKETOUCH_CFLAGS = -I$(PTFAKETOUCH_LOCAL_PATH)/PTFakeTouch/PTFakeTouch -I$(PTFAKETOUCH_LOCAL_PATH)/PTFakeTouch/addition

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TouchAuto

TouchAuto_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -DTROLLSTORE
TouchAuto_FRAMEWORKS = UIKit CoreGraphics CoreText ImageIO QuartzCore Foundation IOKit
TouchAuto_FILES = tweak/TouchAuto.m \
                  tweak/TouchRecorder.m \
                  tweak/TouchPlayer.m \
                  tweak/TouchInjectManager.m \
                  tweak/FloatingPanel.m \
                  tweak/TouchEvent.m \
                  tweak/AdvancedFeatures.m \
                  $(PTFAKETOUCH_SOURCES)

# Add PTFakeTouch include path
TouchAuto_CFLAGS += $(PTFAKETOUCH_CFLAGS)

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	@echo "TouchAuto dylib built successfully!"
	@echo "To inject into IPA, copy .theos/obj/arm64/TouchAuto.dylib to your app's Frameworks directory"
	@echo "Add LC_LOAD_DYLIB to the app's Info.plist under UIRequiredDeviceCapabilities"
