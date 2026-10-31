#!/bin/zsh
set -eu
cd "${0:A:h}"
./build.sh
app_name='TVVT 散热器.app'
destination="/Applications/$app_name"
identity_file="$HOME/Library/Application Support/TVVTNative/Signing/identity.sha1"
if [[ ! -f "$identity_file" || "${TVVT_SIGN_IDENTITY:-}" == "-" ]]; then
    print -u2 '日常安装需要固定签名，请先运行 python3 scripts/setup-signing.py。'
    exit 1
fi
if [[ -e "$destination" ]]; then
    bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")
    [[ "$bundle_id" == 'local.ouou.tvvt-native' ]] || { print -u2 '目标位置有其他应用，停止安装。'; exit 1; }
fi
app_pids=$(/usr/bin/pgrep -u "$UID" -x TVVTNative || true)
if [[ -n "$app_pids" ]]; then
    print '正在关闭运行中的散热器应用以完成更新…'
    for pid in ${(f)app_pids}; do kill -TERM "$pid"; done
    for attempt in {1..10}; do
        /usr/bin/pgrep -u "$UID" -x TVVTNative >/dev/null || break
        sleep 1
    done
    if /usr/bin/pgrep -u "$UID" -x TVVTNative >/dev/null; then
        print -u2 '应用尚未退出，安装已停止。'; exit 1
    fi
fi
/usr/bin/ditto "build/$app_name" "$destination"
codesign --verify --deep --strict "$destination"
lsregister='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
"$lsregister" -u "$PWD/build/$app_name" || true
"$lsregister" -f "$destination"
print "已安装到 $destination；请从这个固定位置启动。"
