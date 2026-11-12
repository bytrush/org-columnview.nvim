clean:
	nvim --headless --clean -n -c "lua vim.fn.delete('./tests/.deps', 'rf')" +q
test:
	nvim --headless --clean -u tests/test.lua "$(FILE)"
# Re-run tests up to 3 times for local flake triage; CI runs `make test` once.
test-ci:
	for i in {1..3}; do nvim --headless --clean -u tests/test.lua && s=0 && break || s=$$? && sleep 1; done; exit $$s
lint:
	stylua --check lua/ tests/
format:
	stylua lua/ tests/
