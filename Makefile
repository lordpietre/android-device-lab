.PHONY: help lint test package clean check-tools

SKILL := android-device-lab
OUT   := ../$(SKILL).zip

help:
	@echo "android-device-lab"
	@echo
	@echo "  make lint      syntax, frontmatter, links and JSON checks"
	@echo "  make test      offline smoke tests (no device needed)"
	@echo "  make package   build $(OUT)"
	@echo "  make clean     remove build artifacts and caches"

lint:
	@bash scripts/lint.sh

test:
	@bash tests/smoke.sh

package: clean
	@cd .. && rm -f $(OUT) && zip -qr $(OUT) $(SKILL) -x '$(SKILL)/*/.git/*' -x '$(SKILL)/.git/*'
	@echo "built $(OUT)"

clean:
	@find . -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
	@rm -rf .pytest_cache .mypy_cache .ruff_cache
