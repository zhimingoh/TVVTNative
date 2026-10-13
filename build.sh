#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p 'build/TVVT 散热器.app/Contents/MacOS'
xcrun swiftc -parse-as-library Sources/Protocol.swift Sources/App.swift -o 'build/TVVT 散热器.app/Contents/MacOS/TVVTNative' -framework SwiftUI -framework AppKit -framework CoreBluetooth
cat > 'build/TVVT 散热器.app/Contents/Info.plist' <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TVVTNative</string>
<key>CFBundleIdentifier</key><string>local.ouou.tvvt-native</string>
<key>CFBundleName</key><string>TVVT 散热器</string>
<key>CFBundleDisplayName</key><string>TVVT 散热器</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSBluetoothAlwaysUsageDescription</key><string>通过本机蓝牙连接并控制你的 TVVT 散热器，读取温度和风扇状态。</string>
<key>NSBluetoothPeripheralUsageDescription</key><string>连接 TVVT 蓝牙散热器。</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - 'build/TVVT 散热器.app'
