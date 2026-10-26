#!/bin/bash
# R188 · monta o plugin nativo do iPhone (fraiha_ios.mm) e coloca no projeto, SÓ na montagem do iPhone (Mac).
# Resultado (nada disso vai para o Git — está no .gitignore):
#   addons/fraiha_ios/bin/FraihaIOS.xcframework   (aparelho arm64 + iPhone virtual x86_64)
#   addons/fraiha_ios/bin/<SDK da Agora>.xcframework
#   addons/fraiha_ios/fraiha_ios.gdextension      (só existe na montagem do iPhone: Web/PC/Android não veem)
# Uso: bash ios_plugin/build_ios_plugin.sh   (na raiz do projeto, num Mac com Xcode)
set -eo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/ios_plugin/.work"
OUT="$ROOT/addons/fraiha_ios"
BIN="$OUT/bin"
GODOT_CPP_REF="${GODOT_CPP_REF:-godot-4.5-stable}"
AGORA_VER="${AGORA_VER:-4.7.0}"     # mesmo par que a Agora fixa no Package.swift do AgoraAudio_iOS
AOSL_VER="${AOSL_VER:-1.3.16}"
MIN_IOS="14.0"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

mkdir -p "$WORK" "$BIN"

echo "== SDK de voz da Agora $AGORA_VER (só áudio)"
get_fw() {   # $1 = url do .xcframework.zip
	local name; name="$(basename "$1" .zip)"
	if [ ! -d "$BIN/$name" ]; then
		curl -fsSL -o "$WORK/$name.zip" "$1"
		rm -rf "$WORK/unz" && mkdir -p "$WORK/unz"
		unzip -q "$WORK/$name.zip" -d "$WORK/unz"
		local found; found="$(find "$WORK/unz" -maxdepth 3 -name "$name" -type d | head -1)"
		[ -n "$found" ] || { echo "faltou $name no zip"; exit 1; }
		mv "$found" "$BIN/$name"
	fi
	echo "  ok $name"
}
AGORA_FWS="AgoraRtcKit Agorafdkaac AgoraffmpegExtension AgoraSoundTouch"
for f in $AGORA_FWS; do
	get_fw "https://download.agora.io/swiftpm/AgoraAudio_iOS/$AGORA_VER/$f.xcframework.zip"
done
get_fw "https://download.agora.io/swiftpm/AgoraInfra_iOS/$AOSL_VER/aosl.xcframework.zip"

echo "== godot-cpp ($GODOT_CPP_REF)"
if [ ! -d "$WORK/godot-cpp" ]; then
	git clone -q --depth 1 --branch "$GODOT_CPP_REF" https://github.com/godotengine/godot-cpp "$WORK/godot-cpp"
fi
command -v scons > /dev/null || python3 -m pip install -q --user scons || pip3 install -q --break-system-packages scons
SCONS="$(command -v scons || echo "python3 -m SCons")"
cd "$WORK/godot-cpp"
$SCONS -s platform=ios arch=arm64 target=template_release ios_min_version=$MIN_IOS -j"$JOBS"
$SCONS -s platform=ios arch=x86_64 ios_simulator=yes target=template_release ios_min_version=$MIN_IOS -j"$JOBS"
LIB_DEV="$(ls bin/libgodot-cpp.ios.template_release.arm64*.a | grep -v simulator | head -1)"
LIB_SIM="$(ls bin/libgodot-cpp.ios.template_release*x86_64*.a | head -1)"
echo "  $LIB_DEV"
echo "  $LIB_SIM"
cd "$ROOT"

slice() {   # $1 = xcframework, $2 = "dev" | "sim" → pasta da fatia certa
	local names; names="$(ls -d "$1"/*/ | sed 's#/$##' | while read -r d; do basename "$d"; done | grep '^ios-' | grep -v maccatalyst)"
	if [ "$2" = "sim" ]; then echo "$names" | grep 'simulator$' | head -1
	else echo "$names" | grep -v simulator | head -1; fi
}

build() {   # $1 = dev|sim  $2 = arch  $3 = sdk  $4 = lib godot-cpp  $5 = alvo de versão
	local fdirs=""
	for f in $AGORA_FWS aosl; do
		local s; s="$(slice "$BIN/$f.xcframework" "$1")"
		[ -n "$s" ] || { echo "sem fatia $1 em $f"; ls "$BIN/$f.xcframework"; exit 1; }
		fdirs="$fdirs -F$BIN/$f.xcframework/$s"
	done
	mkdir -p "$WORK/$1"
	xcrun --sdk "$3" clang++ -std=c++17 -fobjc-arc -fno-exceptions -O2 -arch "$2" "$5" \
		-isysroot "$(xcrun --sdk "$3" --show-sdk-path)" \
		-I"$WORK/godot-cpp/include" -I"$WORK/godot-cpp/gen/include" -I"$WORK/godot-cpp/gdextension" \
		$fdirs -dynamiclib -install_name @rpath/libfraiha_ios.dylib \
		-Wl,-rpath,@executable_path/Frameworks \
		"$ROOT/ios_plugin/fraiha_ios/fraiha_ios.mm" "$WORK/godot-cpp/$4" \
		-framework AgoraRtcKit -framework UIKit -framework PhotosUI -framework AVFoundation -framework AuthenticationServices -framework Foundation \
		-o "$WORK/$1/libfraiha_ios.dylib"
	echo "  ok $1 ($2)"
}

echo "== plugin FRAIHA (Objective-C++)"
build dev arm64 iphoneos "$LIB_DEV" "-miphoneos-version-min=$MIN_IOS"
build sim x86_64 iphonesimulator "$LIB_SIM" "-mios-simulator-version-min=$MIN_IOS"
rm -rf "$BIN/FraihaIOS.xcframework"
xcodebuild -create-xcframework -library "$WORK/dev/libfraiha_ios.dylib" -library "$WORK/sim/libfraiha_ios.dylib" \
	-output "$BIN/FraihaIOS.xcframework" > /dev/null
echo "  ok FraihaIOS.xcframework"

DEPS=""
for f in $AGORA_FWS aosl; do DEPS="$DEPS\"res://addons/fraiha_ios/bin/$f.xcframework\": \"\", "; done
DEPS="{${DEPS%, }}"
cat > "$OUT/fraiha_ios.gdextension" <<EOF
[configuration]
entry_symbol = "fraiha_ios_init"
compatibility_minimum = "4.5"

[libraries]
ios.debug = "res://addons/fraiha_ios/bin/FraihaIOS.xcframework"
ios.release = "res://addons/fraiha_ios/bin/FraihaIOS.xcframework"

[dependencies]
ios.debug = $DEPS
ios.release = $DEPS
EOF
echo "== pronto: $OUT/fraiha_ios.gdextension"
cat "$OUT/fraiha_ios.gdextension"
