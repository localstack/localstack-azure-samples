VENV_BIN = python3 -m venv
VENV_DIR ?= .venv
VENV_ACTIVATE = $(VENV_DIR)/bin/activate
VENV_RUN = . $(VENV_ACTIVATE)

ifeq ($(OS),Windows_NT)
	VENV_ACTIVATE = $(VENV_DIR)/Scripts/activate
	VENV_RUN = $(VENV_DIR)/Scripts/activate
endif

venv: $(VENV_ACTIVATE)

$(VENV_ACTIVATE): pyproject.toml
	test -d $(VENV_DIR) || $(VENV_BIN) $(VENV_DIR)
	$(VENV_RUN); pip install --upgrade pip setuptools wheel
	touch $(VENV_ACTIVATE)

install: venv ## Install dependencies
	$(VENV_RUN); pip install -r requirements-dev.txt
	chmod +x run-samples.sh cleanup.sh

clean: ## Clean the environment
	rm -rf $(VENV_DIR)
	rm -rf build/
	rm -rf dist/
	rm -rf *.egg-info/
	find . -name "*.pyc" -delete
	find . -name "__pycache__" -delete

SHARD ?= 1
SPLITS ?= 1

test: venv ## Run all samples
	$(VENV_RUN); bash ./run-samples.sh $(SHARD) $(SPLITS)

start: venv ## Start LocalStack
	$(VENV_RUN); localstack start -d

stop: venv ## Stop LocalStack
	$(VENV_RUN); localstack stop

status: venv ## Check LocalStack status
	$(VENV_RUN); localstack status

logs: venv ## Get LocalStack logs
	$(VENV_RUN); localstack logs

.PHONY: venv install clean test start stop status logs help

help: ## Display this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
