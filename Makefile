FLUTTER ?= flutter
DART ?= dart
PYTHON ?= python3
ADB ?= $(HOME)/Library/Android/sdk/platform-tools/adb
DEVICE ?=

.PHONY: setup generate check migrations run-dev run-staging run-prod server check-server check-api android-reverse run-dev-android run-dev-emulator

setup:
	$(FLUTTER) pub get
	$(MAKE) generate

generate:
	$(FLUTTER) gen-l10n
	$(DART) run build_runner build

check:
	$(DART) format --output=none --set-exit-if-changed lib test
	$(FLUTTER) analyze --no-pub
	$(FLUTTER) test --no-pub
	$(MAKE) check-server

server:
	$(PYTHON) server/app.py --adb "$(ADB)"

check-server:
	$(PYTHON) -m unittest discover -s server/tests -v

check-api:
	$(DART) run tool/check_local_api.dart

android-reverse:
	$(ADB) $(if $(DEVICE),-s $(DEVICE)) reverse tcp:8787 tcp:8787

run-dev-android: android-reverse
	$(FLUTTER) run $(if $(DEVICE),-d $(DEVICE)) --dart-define-from-file=config/dev.json

run-dev-emulator:
	$(FLUTTER) run --dart-define-from-file=config/dev_android_emulator.json

migrations:
	$(DART) run drift_dev make-migrations

run-dev:
	$(FLUTTER) run --dart-define-from-file=config/dev.json

run-staging:
	$(FLUTTER) run --dart-define-from-file=config/staging.json

run-prod:
	$(FLUTTER) run --dart-define-from-file=config/prod.json
