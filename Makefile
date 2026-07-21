.PHONY: bootstrap doctor run run-fetch test install-schedule open typecheck-swift app

bootstrap:
	./scripts/bootstrap.sh

doctor:
	./bin/briefctl doctor

run:
	./bin/briefctl run

run-fetch:
	./bin/briefctl run --skip-synth

test:
	packages/morningbrief/.venv/bin/python scripts/run_tests.py

install-schedule:
	./bin/briefctl install-schedule

open:
	./bin/briefctl open

typecheck-swift:
	cd apps/MorningBrief && swiftc -typecheck -sdk $$(xcrun --show-sdk-path) -target arm64-apple-macos14.0 Sources/*.swift

app:
	./scripts/build_app.sh
	open dist/MorningBrief.app
