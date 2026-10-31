#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p build
xcrun swiftc Sources/Protocol.swift Tests/main.swift -o build/protocol-tests
./build/protocol-tests
xcrun swiftc -parse-as-library Sources/Protocol.swift Sources/CoolingPolicy.swift Tests/CoolingPolicyTests.swift -o build/cooling-tests
./build/cooling-tests
xcrun swiftc -parse-as-library Sources/ConnectionCoordinator.swift Tests/ConnectionCoordinatorTests.swift -o build/connection-tests
./build/connection-tests
