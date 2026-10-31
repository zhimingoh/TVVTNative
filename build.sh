#!/bin/zsh
set -eu
cd "${0:A:h}"
signing_dir="$HOME/Library/Application Support/TVVTNative/Signing"
signing_identity="${TVVT_SIGN_IDENTITY:-}"
if [[ -z "$signing_identity" && -f "$signing_dir/identity.sha1" ]]; then
    signing_identity=$(<"$signing_dir/identity.sha1")
fi
if [[ -z "$signing_identity" && -f "$signing_dir/identity.pending.sha1" ]]; then
    print -u2 "本机签名配置尚未完成，请先运行 python3 scripts/setup-signing.py 并完成系统解锁。"
    exit 1
fi
if [[ -z "$signing_identity" ]]; then
    signing_identity="-"
    print -u2 "未配置固定证书：使用临时签名；重新构建可能需要再次授权蓝牙。"
fi
if [[ "$signing_identity" != "-" ]]; then
    identity_list=$(security find-identity -v -p codesigning)
    if ! print -r -- "$identity_list" | /usr/bin/grep -Fq -- "$signing_identity"; then
        print -u2 "固定签名身份不可用：$signing_identity；请解锁钥匙串或恢复原证书。不会自动改用临时签名。"
        exit 1
    fi
fi
mkdir -p 'build/TVVT 散热器.app/Contents/MacOS'
xcrun swiftc -target "$(uname -m)-apple-macos14.0" -parse-as-library Sources/*.swift -o 'build/TVVT 散热器.app/Contents/MacOS/TVVTNative' -framework SwiftUI -framework AppKit -framework CoreBluetooth -framework IOKit -framework ServiceManagement
cat > 'build/TVVT 散热器.app/Contents/Info.plist' <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TVVTNative</string>
<key>CFBundleIdentifier</key><string>local.ouou.tvvt-native</string>
<key>CFBundleName</key><string>TVVT 散热器</string>
<key>CFBundleDisplayName</key><string>TVVT 散热器</string>
<key>CFBundleVersion</key><string>3</string>
<key>CFBundleShortVersionString</key><string>0.2.1</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSBluetoothAlwaysUsageDescription</key><string>通过本机蓝牙连接并控制你的 TVVT 散热器，读取温度和风扇状态。</string>
<key>NSBluetoothPeripheralUsageDescription</key><string>连接 TVVT 蓝牙散热器。</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --timestamp=none --sign "$signing_identity" 'build/TVVT 散热器.app'
codesign --verify --deep --strict 'build/TVVT 散热器.app'
codesign -d -r- 'build/TVVT 散热器.app'
