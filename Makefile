SHELL := /bin/bash

.PHONY: init plan apply destroy fmt validate clean

init:
	terraform init

plan:
	./scripts/sync-nodes.sh plan

apply:
	./scripts/sync-nodes.sh apply

destroy:
	./scripts/sync-nodes.sh destroy

fmt:
	terraform fmt -recursive

validate: init
	terraform validate

clean:
	rm -f tfplan *.tfplan crash.log
