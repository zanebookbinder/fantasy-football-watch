.PHONY: help test sample fixture deploy typecheck

help:
	@echo "test       Run the Lambda test suite"
	@echo "sample     Regenerate docs/sample-payload.json and the bundled copy"
	@echo "fixture    Rebuild the test fixture from a raw ESPN response"
	@echo "           make fixture RAW=~/Downloads/fantasy-data.json"
	@echo "typecheck  Type-check both watch targets against the watchOS SDK"
	@echo "deploy     sam build && sam deploy --guided"

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

deploy:
	cd lambda && sam build && sam deploy --guided
