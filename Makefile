FLUTTER ?= flutter
DART ?= dart

.PHONY: setup generate check migrations run-dev run-staging run-prod

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

migrations:
	$(DART) run drift_dev make-migrations

run-dev:
	$(FLUTTER) run --dart-define-from-file=config/dev.json

run-staging:
	$(FLUTTER) run --dart-define-from-file=config/staging.json

run-prod:
	$(FLUTTER) run --dart-define-from-file=config/prod.json
