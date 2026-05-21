ARCHS = arm64
TARGET = iphone:clang:16.5:15.0
SDKVERSION = 16.5

# PTFakeTouch library path
PTFAKETOUCH_LOCAL_PATH = $(THEOS_PROJECT_DIR)/vendor/PTFakeTouch

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TouchAuto

TouchAuto_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -DTROLLSTORE -I$(PTFAKETOUCH_LOCAL_PATH)
TouchAuto_FRAMEWORKS = UIKit CoreGraphics CoreText ImageIO QuartzCore Foundation IOKit
TouchAuto_FILES = tweak/TouchAuto.m \
                  tweak/TouchRecorder.m \
                  tweak/TouchPlayer.m \
                  tweak/TouchInjectManager.m \
                  tweak/FloatingPanel.m \
                  tweak/TouchEvent.m \
                  tweak/AdvancedFeatures.m \
                  $(PTFAKETOUCH_LOCAL_PATH)/PTFakeTouch/PTFakeMetaTouch.m \
                  $(PTFAKETOUCH_LOCAL_PATH)/PTFakeTouch/addition/UITouch-KIFAdditions.m \
                  $(PTFAKETOUCH_LOCAL_PATH)/PTFakeTouch/addition/UIEvent+KIFAdditions.m \
                  $(PTFAKETOUCH_LOCAL_PATH)/PTFakeTouch/addition/IOHIDEvent+KIF.m

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	@echo "TouchAuto dylib built successfully!"
	@echo "To inject into IPA, copy .theos/obj/arm64/TouchAuto.dylib to your app's Frameworks directory"
	@echo "Add LC_LOAD_DYLIB to the app's Info.plist under UIRequiredDeviceCapabilities"
