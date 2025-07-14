PROJECT_NAME := $(shell awk '/^name:/ {print $$2}' shard.yml)
PROJECT_VERSION := $(shell awk '/^version:/ {print $$2}' shard.yml)

CRYSTAL_VERSION := 1.16
FIXUID ?= $(shell id -u)
FIXGID ?= $(shell id -g)

export CRYSTAL_VERSION
export FIXUID
export FIXGID

# Usage examples:

## Install dependencies
##   $ make setup
## Run the application services
##   $ make dev
## Interactive console session
##   $ make console
## Restart the containers
##   $ make restart
## Stop the application containers
##   $ make stop
## Show available tasks
##   $ make help

# Make `help` the default task
.DEFAULT_GOAL := help

.PHONY: build console logs restart setup start stop help

console: ## start a console session
	@docker compose exec app sh -i 2>/dev/null || docker compose run --rm app -- sh -i

dev: ## run the application services
	@docker compose up

# Inspired by Crystal's Makefile
# Ref: https://github.com/crystal-lang/crystal/blob/master/Makefile#L286
help: ## Show available tasks [default]
	@printf "Project: \033[1m$(PROJECT_NAME)\033[0m\n"
	@printf "Version: \033[33;1m$(PROJECT_VERSION)\033[0m\n"
	@echo
	@printf '\033[34mTasks:\033[0m\n'
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) |\
		sort |\
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo
	@printf '\033[34mUsage:\033[0m\n'
	@grep -hE '^##.*$$' $(MAKEFILE_LIST) |\
		awk 'BEGIN {FS = "## "}; /^## [a-zA-Z_-]/ {printf "  \033[36m%s\033[0m\n", $$2}; /^##  / {printf "  %s\n\n", $$2}'
	@echo

restart: ## restart the containers
	@docker compose restart

setup: ## initialize the project
	@docker compose build app
	@docker compose run --rm app -- sh -c '(shards check || shards install)'

stop: ## stop running containers
	@docker compose down
