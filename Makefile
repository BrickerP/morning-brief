.PHONY: bootstrap doctor run run-fetch test test-swift-runner install-schedule open typecheck-swift app

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

test-swift-runner:
	./scripts/test_swift_runner.sh

install-schedule:
	./bin/briefctl install-schedule

open:
	./bin/briefctl open

typecheck-swift:
	cd apps/MorningBrief && swiftc -typecheck -parse-as-library -sdk $$(xcrun --show-sdk-path) -target arm64-apple-macos14.0 $$(find Sources -name '*.swift' | sort)

app:
	./scripts/build_app.sh
	# Launch from / so `open` does not stamp Downloads into the app's PWD.
	cd / && open "$(HOME)/Applications/MorningBrief.app"
