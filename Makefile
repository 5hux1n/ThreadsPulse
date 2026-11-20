export TARGET := iphone:clang:latest:15.0
export ARCHS = arm64
THEOS_PACKAGE_SCHEME ?= rootless
VERSION ?= 1.31.0+16
BASE_PACKAGE = com.h4x.threadspulse
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
ARCHS = arm64e
endif

INSTALL_TARGET_PROCESSES = Threads
include $(THEOS)/makefiles/common.mk

TP_LOCALIZATION_SOURCE = resources/localization
TP_LOCALIZATION_HEADER = .generated/TPLocalizationData.h
$(TP_LOCALIZATION_HEADER): scripts/generate-localization.py $(TP_LOCALIZATION_SOURCE)/Info.plist $(wildcard $(TP_LOCALIZATION_SOURCE)/*.lproj/Localizable.strings)
	@python3 scripts/generate-localization.py --source "$(TP_LOCALIZATION_SOURCE)" --output "$@"

before-all before-ThreadsPulse-all:: $(TP_LOCALIZATION_HEADER)

TWEAK_NAME = ThreadsPulse
ThreadsPulse_FILES = Tweak.x ThreadsPulseNotifications.x TPLocalization.m TPPrefs.m TPNotificationPrefs.m TPURLCleaner.m TPDownloader.m TPHUD.m TPCapsule.m TPAuthorInfo.m TPAuthorStatsViewController.m TPUI.m TPSettingsViewController.m TPWelcomeViewController.m TPSideloadFix.m TPUpdateChecker.m TPMusicAttachment.m TPMusicCompat.m
ThreadsPulse_CFLAGS = -Ivendor/libvpx/include -Ivendor/dav1d/include -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable
ThreadsPulse_FRAMEWORKS = UIKit Photos AVFoundation AVKit VideoToolbox CoreMedia UniformTypeIdentifiers SafariServices Security UserNotifications
ThreadsPulse_LDFLAGS = -Lvendor/libvpx/lib -Lvendor/dav1d/lib -lvpx -ldav1d
ThreadsPulse_LOGOS_DEFAULT_GENERATOR = internal
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
ThreadsPulse_LDFLAGS += -Wl,-rpath,@loader_path/.jbroot/Library/Frameworks -Wl,-rpath,@loader_path/.jbroot/usr/lib
endif

before-package::
	@sed -i '' 's/^Version: .*/Version: $(VERSION)/' $(THEOS_STAGING_DIR)/DEBIAN/control
	@if [ "$(THEOS_PACKAGE_SCHEME)" = roothide ]; then sed -i '' 's/^Package: .*/Package: $(BASE_PACKAGE).roothide/' $(THEOS_STAGING_DIR)/DEBIAN/control; sed -i '' 's/^Architecture: .*/Architecture: iphoneos-arm64e/' $(THEOS_STAGING_DIR)/DEBIAN/control; sed -i '' 's/^Name: .*/Name: ThreadsPulse (Roothide)/' $(THEOS_STAGING_DIR)/DEBIAN/control; fi

include $(THEOS_MAKE_PATH)/tweak.mk

after-package::
	@mkdir -p dist
	@cp "$(__THEOS_LAST_PACKAGE_FILENAME)" "dist/ThreadsPulse_$(VERSION)_$(ARCHS).deb"
