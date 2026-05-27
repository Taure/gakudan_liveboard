.PHONY: all compile serve setup assets fonts clean

all: compile

compile:
	@rebar3 compile
	@$(MAKE) assets

assets:
	@mkdir -p priv/static/assets/js
	@cp _build/default/lib/arizona/priv/static/assets/js/*.min.js priv/static/assets/js/ 2>/dev/null || true

fonts:
	@./scripts/fetch-fonts.sh

serve: compile
	@rebar3 nova serve

setup:
	@rebar3 compile
	@$(MAKE) assets
	@$(MAKE) fonts

clean:
	@rebar3 clean
	@rm -rf priv/static/assets/js/arizona*.min.js priv/static/assets/js/index.min.js
