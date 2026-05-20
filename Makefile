ARCHS = arm64
TARGET = iphone:clang:16.5:15.0
SDKVERSION = 16.5

# PTFakeTouch library path
PTFAKETOUCH_PATH = $(THEOS_VENDOR_PATH)/PTFakeTouch
PTFAKETOUCH_LOCAL_PATH = $(TOP)/vendor/PTFakeTouch
PTFAKETOUCH_SUBDIR = $(PTFAKETOUCH_LOCAL_PATH)
SUBMODULES += $(PTFAKETOUCH_LOCAL_PATH)

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TouchAuto

TouchAuto_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -DTROLLSTORE
TouchAuto_FRAMEWORKS = UIKit CoreGraphics CoreText ImageIO QuartzCore Foundation
TouchAuto_FILES = tweak/TouchAuto.m \
                  tweak/TouchRecorder.m \
                  tweak/TouchPlayer.m \
                  tweak/TouchInjectManager.m \
                  tweak/FloatingPanel.m \
                  tweak/TouchEvent.m \
                  tweak/AdvancedFeatures.m

# PTFakeTouch library
TouchAuto_LDFLAGS = -L$(PTFAKETOUCH_PATH) -lPTFakeTouch

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	@echo "TouchAuto dylib built successfully!"
	@echo "To inject into IPA, copy .theos/obj/arm64/TouchAuto.dylib to your app's Frameworks directory"
	@echo "Add LC_LOAD_DYLIB to the app's Info.plist under UIRequiredDeviceCapabilities"