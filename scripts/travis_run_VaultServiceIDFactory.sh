#!/usr/bin/env bash

# delayed added to ensure consul has started on host - intermittent failures
sleep 5

go get ./...
go build -o VaultServiceIDFactory main.go
./VaultServiceIDFactory &

# Put new API Test Here
curl -sSf http://localhost:8314/initialiseme > /dev/null
curl -sSf http://localhost:8314/approlename > /dev/null
curl -sSf http://localhost:8314/health > /dev/null
# exit 0
# The End
