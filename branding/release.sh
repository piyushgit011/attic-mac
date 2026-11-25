#!/bin/zsh
# Builds, notarizes and staples Attic.app and Attic.dmg into build/release.
# Needs a Developer ID certificate and notarytool credentials: NOTARY_PROFILE (default: reelcut-notary).
set -e
cd "${0:A:h:h}"
PROFILE="${NOTARY_PROFILE:-reelcut-notary}"
REL=build/release; rm -rf $REL && mkdir -p $REL/stage
xcodebuild -project Attic.xcodeproj -scheme Attic -configuration Release -derivedDataPath build/release-dd \
  OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | sort -u
APP=build/release-dd/Build/Products/Release/Attic.app
codesign -d --entitlements - $APP 2>/dev/null | grep -q get-task-allow && { echo "get-task-allow still present"; exit 1; }
codesign --verify --deep --strict $APP
ditto -c -k --keepParent $APP $REL/Attic-app.zip
echo "== notarizing app"; xcrun notarytool submit $REL/Attic-app.zip --keychain-profile "$PROFILE" --wait | grep -E "status:" | tail -1
xcrun stapler staple $APP | tail -1
ditto $APP $REL/stage/Attic.app && ln -s /Applications $REL/stage/Applications
hdiutil create -volname "Attic" -srcfolder $REL/stage -ov -format UDZO $REL/Attic.dmg -quiet
codesign --sign "Developer ID Application" --timestamp $REL/Attic.dmg
echo "== notarizing dmg"; xcrun notarytool submit $REL/Attic.dmg --keychain-profile "$PROFILE" --wait | grep -E "status:" | tail -1
xcrun stapler staple $REL/Attic.dmg | tail -1
spctl -a -t open --context context:primary-signature -vv $REL/Attic.dmg 2>&1 | head -2
spctl -a -t exec -vv $APP 2>&1 | head -2
