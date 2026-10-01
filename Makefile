ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = mediaserverd cameracaptured

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = iCamV3 iCamV3Controls
iCamV3_FILES = tweak/Tweak.mm shared/LMCConfig.m shared/LMCRender.m
iCamV3_CFLAGS = -fobjc-arc -Ishared
iCamV3_FRAMEWORKS = Foundation CoreMedia CoreVideo CoreImage AVFoundation QuartzCore
iCamV3_LIBRARIES = substrate roothide

APPLICATION_NAME = iCamV3App
iCamV3App_FILES = app/main.m app/AppDelegate.m app/MainViewController.m shared/LMCConfig.m shared/LMCRender.m shared/LMCControlPanel.m
iCamV3App_CFLAGS = -fobjc-arc -Ishared
iCamV3App_FRAMEWORKS = UIKit PhotosUI Photos AVFoundation UniformTypeIdentifiers CoreImage CoreVideo CoreMedia QuartzCore
iCamV3App_LIBRARIES = roothide
iCamV3App_CODESIGN_FLAGS = -SiCamV3App.entitlements
iCamV3App_INSTALL_PATH = /Applications
iCamV3App_RESOURCE_FILES = iCamV3App/Info.plist
iCamV3App_RESOURCE_DIRS = iCamV3App/Resources

iCamV3Controls_FILES = tweak/Controls.mm shared/LMCConfig.m shared/LMCControlPanel.m
iCamV3Controls_CFLAGS = -fobjc-arc -Ishared
iCamV3Controls_FRAMEWORKS = UIKit Foundation
iCamV3Controls_LIBRARIES = substrate roothide
include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/application.mk

after-install::
	install.exec "killall mediaserverd cameracaptured 2>/dev/null || true"
