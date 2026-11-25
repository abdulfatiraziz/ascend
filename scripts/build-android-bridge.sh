#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
bridge_jdk=$(print -l "$PWD"/build/tools/jdk-21*/Contents/Home(N) | tail -1)
[[ -n "$bridge_jdk" ]] || { echo "No JDK 21 under build/tools (see README → Phone app)"; exit 1; }
bridge_sdk="$PWD/build/tools/android-sdk"
bridge_tools=$(print -l "$bridge_sdk"/build-tools/*(N/) | sort -V | tail -1)
[[ -n "$bridge_tools" ]] || { echo "No Android build tools under $bridge_sdk/build-tools"; exit 1; }
bridge_android="$bridge_sdk/platforms/android-36/android.jar"
export JAVA_HOME="$bridge_jdk"
export PATH="$bridge_jdk/bin:$PATH"
rm -rf build/android/classes build/android/dex
mkdir -p build/android/classes build/android/dex
javac -source 17 -target 17 -Xlint:-options -classpath "$bridge_android" -d build/android/classes android/bridge/src/com/abdul/ascend/bridge/*.java
jar cf build/android/classes.jar -C build/android/classes .
"$bridge_tools/d8" --min-api 34 --lib "$bridge_android" --output build/android/dex build/android/classes.jar
# Icons are vector drawables, looked up by name at runtime, so no generated R class is needed.
# Black Tie fonts (OFL) ship as APK assets, copied from the Mac app's resources.
rm -rf build/android/assets && mkdir -p build/android/assets/fonts
cp Sources/Ascend/Resources/Fonts/*.ttf build/android/assets/fonts/
rm -f build/android/res.zip
"$bridge_tools/aapt2" compile --dir android/bridge/res -o build/android/res.zip
"$bridge_tools/aapt2" link -I "$bridge_android" --manifest android/bridge/AndroidManifest.xml -A Sources/Ascend/Resources/ExerciseDemos -A build/android/assets -o build/android/unsigned.apk build/android/res.zip
zip -q -j build/android/unsigned.apk build/android/dex/classes.dex
"$bridge_tools/zipalign" -f -p 4 build/android/unsigned.apk build/android/aligned.apk
# Keep the signing key outside build/ too: Android only installs an update signed with the same key.
key_backup="${CIPHER_BRIDGE_KEY:-$HOME/.secrets/personal/cipher-bridge-signing.p12}"
if [[ ! -f build/android/local-signing.p12 && -f "$key_backup" ]]; then install -m 600 "$key_backup" build/android/local-signing.p12; fi
if [[ ! -f build/android/local-signing.p12 ]]; then
 keytool -genkeypair -keystore build/android/local-signing.p12 -storepass ascend-local-development -keypass ascend-local-development -alias ascend -dname 'CN=Cipher Local Development' -keyalg RSA -keysize 3072 -validity 3650 -noprompt
 chmod 600 build/android/local-signing.p12
 [[ -d "${key_backup:h}" && ! -f "$key_backup" ]] && install -m 600 build/android/local-signing.p12 "$key_backup"
fi
"$bridge_tools/apksigner" sign --ks build/android/local-signing.p12 --ks-key-alias ascend --ks-pass pass:ascend-local-development --out build/android/AscendBridge.apk build/android/aligned.apk
"$bridge_tools/apksigner" verify build/android/AscendBridge.apk
printf 'Built local Android companion: build/android/AscendBridge.apk\n'
