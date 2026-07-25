# make cli    : CLI を release ビルドして $(BINDIR) にインストール
# make macOS  : macOS アプリをビルドして $(APPS_DIR) にインストール
# make iOS    : iOS アプリをビルドして Simulator にインストール (SIM=<UDID> 指定可)

BINDIR ?= $(HOME)/bin
APPS_DIR ?= $(HOME)/Applications
DERIVED ?= .build/DerivedData
CONFIG ?= Release

.PHONY: cli macOS iOS xcodeproj

cli:
	swift build -c release --product mailer
	mkdir -p "$(BINDIR)"
	install -m 755 "$$(swift build -c release --product mailer --show-bin-path)/mailer" "$(BINDIR)/mailer"
	@echo "installed: $(BINDIR)/mailer"

macOS: xcodeproj
	xcodebuild -project Mailer.xcodeproj -scheme MailerMac -configuration $(CONFIG) -derivedDataPath "$(DERIVED)" build
	mkdir -p "$(APPS_DIR)"
	rm -rf "$(APPS_DIR)/Mailer.app"
	ditto "$(DERIVED)/Build/Products/$(CONFIG)/Mailer.app" "$(APPS_DIR)/Mailer.app"
	@echo "installed: $(APPS_DIR)/Mailer.app"

# booted 指定は複数台起動時にインストール先を取り違えるため、UDID を一意に確定してから install する
iOS: xcodeproj
	xcodebuild -project Mailer.xcodeproj -scheme MailerApp -configuration $(CONFIG) -destination 'generic/platform=iOS Simulator' -derivedDataPath "$(DERIVED)" build
	@set -e; \
	udid="$(SIM)"; \
	if [ -z "$$udid" ]; then \
	  booted=$$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}'); \
	  count=$$(printf '%s\n' "$$booted" | grep -c . || true); \
	  if [ "$$count" -eq 1 ]; then udid="$$booted"; \
	  elif [ "$$count" -eq 0 ]; then echo "起動中の iOS Simulator がありません。sim-boot 等で起動するか SIM=<UDID> を指定してください"; exit 1; \
	  else echo "複数の Simulator が起動中です。SIM=<UDID> でインストール先を指定してください:"; xcrun simctl list devices booted | grep Booted; exit 1; fi; \
	fi; \
	xcrun simctl install "$$udid" "$(DERIVED)/Build/Products/$(CONFIG)-iphonesimulator/Mailer.app"; \
	echo "installed: Simulator $$udid に Mailer.app (com.bannzai.mailer)"

xcodeproj:
	xcodegen generate
