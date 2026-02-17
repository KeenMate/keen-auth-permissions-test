.PHONY: setup dev test compile clean

setup:
	mix deps.get
	mix compile

dev:
	mix phx.server

test:
	mix test

compile:
	mix compile

clean:
	mix clean
	rm -rf _build deps
