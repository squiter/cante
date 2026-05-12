SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

CANTE_REPO_DIR := $(shell pwd)
HOMEBREW_CANTE_DIR ?= $(abspath $(CANTE_REPO_DIR)/../homebrew-cante)
RELEASE_TIMEOUT_SEC ?= 900
RELEASE_POLL_SEC ?= 10

.PHONY: help
help:
	@printf "Cante release helpers\n\n"
	@printf "Usage:\n"
	@printf "  make release VERSION=x.y.z   Tag cante, wait for the release workflow,\n"
	@printf "                                then bump the Homebrew tap formula.\n"
	@printf "  make check-tap                Sanity check that the tap path is reachable.\n\n"
	@printf "Env vars:\n"
	@printf "  HOMEBREW_CANTE_DIR   Path to homebrew-cante checkout (default: ../homebrew-cante)\n"
	@printf "  RELEASE_TIMEOUT_SEC  Total seconds to wait for release artifacts (default: 900)\n"
	@printf "  RELEASE_POLL_SEC     Poll interval while waiting (default: 10)\n"

.PHONY: check-tap
check-tap:
	@if [[ ! -d "$(HOMEBREW_CANTE_DIR)" ]]; then \
		echo "ERROR: HOMEBREW_CANTE_DIR not found at $(HOMEBREW_CANTE_DIR)"; exit 1; \
	fi
	@if [[ ! -f "$(HOMEBREW_CANTE_DIR)/Formula/cante.rb" ]]; then \
		echo "ERROR: Formula/cante.rb missing in $(HOMEBREW_CANTE_DIR)"; exit 1; \
	fi
	@echo "OK: tap at $(HOMEBREW_CANTE_DIR)"

.PHONY: release
release:
	@if [[ -z "$${VERSION:-}" ]]; then \
		echo "ERROR: VERSION is required. Usage: make release VERSION=0.4.0"; exit 1; \
	fi
	@if [[ ! "$(VERSION)" =~ ^[0-9]+\.[0-9]+\.[0-9]+$$ ]]; then \
		echo "ERROR: VERSION must look like 0.4.0 (no leading v, no suffix)"; exit 1; \
	fi
	@$(MAKE) --no-print-directory check-tap
	@TAG="v$(VERSION)"; \
	echo "→ Release $$TAG"; \
	if [[ -n "$$(git status --porcelain)" ]]; then \
		echo "ERROR: cante working tree is not clean"; exit 1; \
	fi; \
	BRANCH=$$(git symbolic-ref --short HEAD); \
	if [[ "$$BRANCH" != "main" ]]; then \
		echo "ERROR: must be on main (currently on $$BRANCH)"; exit 1; \
	fi; \
	git fetch origin --quiet; \
	if [[ "$$(git rev-parse HEAD)" != "$$(git rev-parse origin/main)" ]]; then \
		echo "ERROR: local main is not in sync with origin/main"; exit 1; \
	fi; \
	if git rev-parse "$$TAG" >/dev/null 2>&1; then \
		echo "ERROR: tag $$TAG already exists locally"; exit 1; \
	fi; \
	if gh release view "$$TAG" >/dev/null 2>&1; then \
		echo "ERROR: release $$TAG already exists on GitHub"; exit 1; \
	fi; \
	if ! grep -q "^## \[$(VERSION)\]" CHANGELOG.md; then \
		echo "ERROR: CHANGELOG.md has no entry for $(VERSION)"; exit 1; \
	fi; \
	echo "→ Tagging and pushing $$TAG"; \
	git tag "$$TAG"; \
	git push origin "$$TAG"; \
	echo "→ Waiting up to $(RELEASE_TIMEOUT_SEC)s for release workflow to publish artifacts"; \
	DEADLINE=$$(($$(date +%s) + $(RELEASE_TIMEOUT_SEC))); \
	ASSET_NAME="cante-$$TAG-macos-arm64.tar.gz.sha256"; \
	while (( $$(date +%s) < DEADLINE )); do \
		if gh release view "$$TAG" --json assets --jq '.assets[].name' 2>/dev/null | grep -qx "$$ASSET_NAME"; then \
			echo "✓ Release artifacts published"; \
			break; \
		fi; \
		printf "."; \
		sleep $(RELEASE_POLL_SEC); \
	done; \
	echo; \
	if ! gh release view "$$TAG" --json assets --jq '.assets[].name' 2>/dev/null | grep -qx "$$ASSET_NAME"; then \
		echo "ERROR: timed out waiting for $$ASSET_NAME"; exit 1; \
	fi; \
	TMP_SHA=$$(mktemp); \
	gh release download "$$TAG" -p "$$ASSET_NAME" -O "$$TMP_SHA" --clobber; \
	SHA=$$(awk '{print $$1}' "$$TMP_SHA"); \
	rm -f "$$TMP_SHA"; \
	if [[ ! "$$SHA" =~ ^[a-f0-9]{64}$$ ]]; then \
		echo "ERROR: unexpected sha256 contents: $$SHA"; exit 1; \
	fi; \
	echo "→ sha256: $$SHA"; \
	echo "→ Updating tap at $(HOMEBREW_CANTE_DIR)"; \
	pushd "$(HOMEBREW_CANTE_DIR)" >/dev/null; \
	if [[ -n "$$(git status --porcelain)" ]]; then \
		echo "ERROR: tap working tree is not clean"; exit 1; \
	fi; \
	git fetch origin --quiet; \
	git checkout main; \
	git pull --ff-only origin main; \
	FORMULA=Formula/cante.rb; \
	cp "$$FORMULA" "$$FORMULA.bak"; \
	sed -E -i '' \
		-e "s|/releases/download/v[0-9]+\.[0-9]+\.[0-9]+/cante-v[0-9]+\.[0-9]+\.[0-9]+-|/releases/download/$$TAG/cante-$$TAG-|g" \
		-e "s|^  version \"[0-9]+\.[0-9]+\.[0-9]+\"|  version \"$(VERSION)\"|" \
		-e "s|^  sha256 \"[a-f0-9]{64}\"|  sha256 \"$$SHA\"|" \
		"$$FORMULA"; \
	rm -f "$$FORMULA.bak"; \
	if ! grep -q "version \"$(VERSION)\"" "$$FORMULA"; then \
		echo "ERROR: version replacement in $$FORMULA failed"; exit 1; \
	fi; \
	if ! grep -q "$$SHA" "$$FORMULA"; then \
		echo "ERROR: sha256 replacement in $$FORMULA failed"; exit 1; \
	fi; \
	if ! grep -q "/releases/download/$$TAG/cante-$$TAG-" "$$FORMULA"; then \
		echo "ERROR: url replacement in $$FORMULA failed"; exit 1; \
	fi; \
	git add "$$FORMULA"; \
	git commit -m "Bump cante to $(VERSION)"; \
	git push origin main; \
	popd >/dev/null; \
	echo "✓ Released $$TAG and bumped the tap"
