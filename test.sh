#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p build
xcrun swiftc Sources/Protocol.swift Tests/main.swift -o build/protocol-tests
./build/protocol-tests
