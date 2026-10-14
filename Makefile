.PHONY: lint ci

lint:
	./check-contents-list.sh

ci: lint
