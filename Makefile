export TARGET := iphone:clang:latest:15.0
export ARCHS = arm64
# export THEOS_PACKAGE_SCHEME = rootless

INSTALL_TARGET_PROCESSES = Threads
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ThreadsPulse
ThreadsPulse_FILES = Tweak.x TPLocalization.m TPPrefs.m TPURLCleaner.m TPDownloader.m TPHUD.m TPUI.m TPSettingsViewController.m TPWelcomeViewController.m TPSideloadFix.m
ThreadsPulse_CFLAGS = -Ivendor/libvpx/include -Ivendor/dav1d/include -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable
ThreadsPulse_FRAMEWORKS = UIKit Photos AVFoundation VideoToolbox CoreMedia UniformTypeIdentifiers SafariServices Security
ThreadsPulse_LDFLAGS = -Lvendor/libvpx/lib -Lvendor/dav1d/lib -lvpx -ldav1d
ThreadsPulse_LOGOS_DEFAULT_GENERATOR = internal

include $(THEOS_MAKE_PATH)/tweak.mk
