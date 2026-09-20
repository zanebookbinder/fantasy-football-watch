.PHONY: help test sample fixture deploy typecheck refresh-cookies check-watch

help:
	@echo "test       Run the Lambda test suite"
	@echo "sample     Regenerate docs/sample-payload.json and the bundled copy"
	@echo "fixture    Rebuild the test fixture from a raw ESPN response"
	@echo "           make fixture RAW=~/Downloads/fantasy-data.json"
	@echo "typecheck  Type-check both watch targets against the watchOS SDK"
	@echo "check-watch  Run the watch-side change-tracking checks"
	@echo "deploy     sam build && sam deploy --guided"
	@echo "refresh-cookies  Paste fresh ESPN cookies into Secrets Manager"

VENV := .venv
PY := $(VENV)/bin/python

$(VENV):
	python3 -m venv $(VENV)
	$(VENV)/bin/pip install -q -r lambda/requirements-dev.txt

test: $(VENV)
	$(PY) -m pytest lambda/tests -q

fixture:
	python3 lambda/tools/capture_fixture.py $(RAW)

# The watch app decodes this exact file, so regenerate it whenever the contract
# changes and both halves stay in step.
sample:
	python3 lambda/tools/sample_payload.py -o docs/sample-payload.json
	cp docs/sample-payload.json FantasyWatch/Shared/sample-payload.json

# Full builds need the watchOS simulator runtime installed; this checks the
# Swift without it.
typecheck:
	@cd FantasyWatch && SDK=$$(xcrun --sdk watchos --show-sdk-path) && \
	  xcrun swiftc -typecheck -swift-version 5 -D DEBUG -sdk "$$SDK" \
	    -target arm64_32-apple-watchos10.0 Shared/*.swift WatchApp/*.swift && \
	  xcrun swiftc -typecheck -swift-version 5 -D DEBUG -sdk "$$SDK" \
	    -target arm64_32-apple-watchos10.0 Shared/*.swift WatchWidget/*.swift && \
	  echo "both targets type-check"

# No XCTest target, so the shared sources are compiled for the Mac and the
# rules are asserted against the bundled sample payload.
check-watch:
	@cd FantasyWatch && rm -rf .checks && mkdir -p .checks && \
	  xcrun swiftc -swift-version 5 -o .checks/checks \
	    Shared/ScorePayload.swift Shared/PlayerDisplay.swift \
	    Shared/Preferences.swift Shared/PlayerChanges.swift \
	    Checks/ChangeTrackingChecks.swift && \
	  ./.checks/checks && rm -rf .checks

deploy:
	cd lambda && sam build && sam deploy --guided

# Validates against ESPN before saving, so a bad paste can't break the stack.
refresh-cookies:
	@./scripts/refresh-cookies.sh
