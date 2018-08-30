#!/usr/bin/env bash

# delayed added to ensure consul has started on host - intermittent failures
sleep 5

go get ./...
go build -o VaultServiceIDFactory main.go
./VaultServiceIDFactory &

# Put new API Test Here

exit 0
# The End
