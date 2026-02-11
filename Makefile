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
	chmod +x run-samples.sh

SHARD ?= 1
SPLITS ?= 1

test: venv ## Run all samples
	$(VENV_RUN); bash ./run-samples.sh $(SHARD) $(SPLITS)

logs: venv ## Get LocalStack logs
	$(VENV_RUN); localstack logs

.PHONY: venv install test logs
