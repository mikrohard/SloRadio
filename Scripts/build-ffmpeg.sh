#!/bin/sh
#
# Builds a minimal, audio-only FFmpeg for SloRadio as a dynamic xcframework.
#
#   Scripts/build-ffmpeg.sh [--force]
#
# Output (git-ignored):
#   Libraries/FFmpeg/FFmpeg.xcframework   dynamic framework (ios-arm64, ios-arm64_x86_64-simulator) + dSYMs
#   Libraries/FFmpeg/include/             public headers (add to HEADER_SEARCH_PATHS)
#   Libraries/FFmpeg/COPYING.LGPLv2.1     license, FFmpeg is used under the LGPL
#   Libraries/FFmpeg/BUILD_INFO.txt       version + configure flags (also the stamp checked by PrepareForBuild.sh)
#
# FFmpeg only demuxes and decodes here. All network I/O (HTTP, ICY, TLS) is done by the app through
# URLSession and handed to FFmpeg with a custom AVIOContext, so networking is disabled. HLS is played
# by AVPlayer, so the hls demuxer is left out as well.
#
# The libraries are linked as one dynamic framework (not static) so the LGPL relinking requirement
# is easy to meet: anyone can rebuild FFmpeg.framework from source with this script and swap it in.

set -eu

FFMPEG_VERSION="9.0.2"
FFMPEG_SHA256="8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e"
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
IOS_MIN_VERSION="15.0"
FRAMEWORK_NAME="FFmpeg"
BUNDLE_ID="org.ffmpeg.FFmpeg"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${ROOT_DIR}/Libraries/FFmpeg"
WORK_DIR="${ROOT_DIR}/Temp/ffmpeg-build"
JOBS="$(sysctl -n hw.ncpu)"

# --- component selection ------------------------------------------------------------------------

DEMUXERS="mp3 aac loas ogg flac mov wav mpegts"
DECODERS="mp3float mp3 mp2float mp2 aac aac_latm vorbis opus flac alac ac3 eac3 \
pcm_s16le pcm_s16be pcm_s24le pcm_s24be pcm_s32le pcm_f32le pcm_u8 pcm_alaw pcm_mulaw"
PARSERS="mpegaudio aac aac_latm vorbis opus flac ac3"
PROTOCOLS="file"   # only for loading local test fixtures; streams come in through a custom AVIOContext

join_components() { # $1 = option name, rest = components
	opt="$1"; shift
	for c in "$@"; do printf -- "--enable-%s=%s " "$opt" "$c"; done
}

# shellcheck disable=SC2086
CONFIGURE_FLAGS="--disable-everything --disable-autodetect --disable-programs --disable-doc \
--disable-avdevice --disable-avfilter --disable-swscale --disable-network \
--enable-avcodec --enable-avformat --enable-avutil --enable-swresample \
--enable-zlib \
--enable-static --disable-shared --enable-pic --disable-debug --enable-optimizations \
$(join_components demuxer $DEMUXERS)$(join_components decoder $DECODERS)$(join_components parser $PARSERS)$(join_components protocol $PROTOCOLS)"

STAMP="ffmpeg=${FFMPEG_VERSION} ios=${IOS_MIN_VERSION} flags=$(printf '%s' "$CONFIGURE_FLAGS" | shasum -a 256 | cut -c1-16)"

# --- up to date? ---------------------------------------------------------------------------------

if [ "${1:-}" != "--force" ] && [ -f "${OUTPUT_DIR}/BUILD_INFO.txt" ] && \
   [ "$(head -n 1 "${OUTPUT_DIR}/BUILD_INFO.txt")" = "$STAMP" ] && [ -d "${OUTPUT_DIR}/${FRAMEWORK_NAME}.xcframework" ]; then
	echo "FFmpeg ${FFMPEG_VERSION} is up to date."
	exit 0
fi

# --- source --------------------------------------------------------------------------------------

mkdir -p "$WORK_DIR"
TARBALL="${WORK_DIR}/ffmpeg-${FFMPEG_VERSION}.tar.xz"
SRC_DIR="${WORK_DIR}/ffmpeg-${FFMPEG_VERSION}"
if [ ! -f "$TARBALL" ]; then
	echo "Downloading FFmpeg ${FFMPEG_VERSION}..."
	curl -sSfL "$FFMPEG_URL" -o "${TARBALL}.part"
	mv "${TARBALL}.part" "$TARBALL"
fi
if [ "$(shasum -a 256 "$TARBALL" | cut -d ' ' -f 1)" != "$FFMPEG_SHA256" ]; then
	echo "error: checksum mismatch for $TARBALL" >&2
	rm -f "$TARBALL"
	exit 1
fi
rm -rf "$SRC_DIR"
tar -xJf "$TARBALL" -C "$WORK_DIR"

# --- per architecture builds ---------------------------------------------------------------------

build_arch() { # $1 = sdk (iphoneos|iphonesimulator), $2 = arch (arm64|x86_64)
	sdk="$1"; arch="$2"
	case "$sdk" in
		iphoneos) target="${arch}-apple-ios${IOS_MIN_VERSION}" ;;
		*)        target="${arch}-apple-ios${IOS_MIN_VERSION}-simulator" ;;
	esac
	case "$arch" in
		arm64) ffarch="aarch64"; asm_flags="" ;;
		*)     ffarch="x86_64";  asm_flags="--disable-x86asm" ;;   # no nasm needed, x86_64 is simulator only
	esac
	sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
	build_dir="${WORK_DIR}/build-${sdk}-${arch}"
	prefix="${WORK_DIR}/install-${sdk}-${arch}"
	rm -rf "$build_dir" "$prefix"
	mkdir -p "$build_dir"
	echo "Configuring FFmpeg for ${sdk} ${arch}..."
	# shellcheck disable=SC2086
	(cd "$build_dir" && "${SRC_DIR}/configure" \
		--prefix="$prefix" \
		--enable-cross-compile --target-os=darwin --arch="$ffarch" \
		--cc="xcrun --sdk $sdk clang" \
		--sysroot="$sysroot" \
		--extra-cflags="-target $target -g" \
		--extra-ldflags="-target $target" \
		$asm_flags $CONFIGURE_FLAGS > configure.log 2>&1) || { tail -n 30 "${build_dir}/config.log" >&2; exit 1; }
	echo "Building FFmpeg for ${sdk} ${arch}..."
	(cd "$build_dir" && make -j"$JOBS" > make.log 2>&1 && make install > install.log 2>&1) || { tail -n 30 "${build_dir}/make.log" >&2; exit 1; }
}

# Links the static libraries of one architecture into the framework's dynamic library.
link_dylib() { # $1 = sdk, $2 = arch, $3 = output
	sdk="$1"; arch="$2"; out="$3"
	case "$sdk" in
		iphoneos) target="${arch}-apple-ios${IOS_MIN_VERSION}" ;;
		*)        target="${arch}-apple-ios${IOS_MIN_VERSION}-simulator" ;;
	esac
	prefix="${WORK_DIR}/install-${sdk}-${arch}"
	xcrun --sdk "$sdk" clang -dynamiclib -target "$target" -isysroot "$(xcrun --sdk "$sdk" --show-sdk-path)" \
		-install_name "@rpath/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}" \
		-compatibility_version 1 -current_version 1 \
		-Wl,-all_load \
		"${prefix}/lib/libavformat.a" "${prefix}/lib/libavcodec.a" \
		"${prefix}/lib/libswresample.a" "${prefix}/lib/libavutil.a" \
		-framework CoreFoundation \
		-lz -g -o "$out"
}

write_info_plist() { # $1 = framework dir, $2 = platform
	cat > "$1/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleExecutable</key><string>${FRAMEWORK_NAME}</string>
	<key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>${FRAMEWORK_NAME}</string>
	<key>CFBundlePackageType</key><string>FMWK</string>
	<key>CFBundleShortVersionString</key><string>${FFMPEG_VERSION}</string>
	<key>CFBundleVersion</key><string>${FFMPEG_VERSION}</string>
	<key>CFBundleSupportedPlatforms</key><array><string>$2</string></array>
	<key>MinimumOSVersion</key><string>${IOS_MIN_VERSION}</string>
</dict>
</plist>
EOF
}

make_framework() { # $1 = slice name, $2 = platform, $3 = sdk, rest = archs
	slice="$1"; platform="$2"; sdk="$3"; shift 3
	fw="${WORK_DIR}/frameworks/${slice}/${FRAMEWORK_NAME}.framework"
	rm -rf "$fw"; mkdir -p "$fw"
	dylibs=""
	for arch in "$@"; do
		link_dylib "$sdk" "$arch" "${WORK_DIR}/frameworks/${slice}/${FRAMEWORK_NAME}-${arch}"
		dylibs="$dylibs ${WORK_DIR}/frameworks/${slice}/${FRAMEWORK_NAME}-${arch}"
	done
	# shellcheck disable=SC2086
	lipo -create $dylibs -output "${fw}/${FRAMEWORK_NAME}"
	write_info_plist "$fw" "$platform"
	dsymutil "${fw}/${FRAMEWORK_NAME}" -o "${WORK_DIR}/frameworks/${slice}/${FRAMEWORK_NAME}.framework.dSYM"
	strip -x "${fw}/${FRAMEWORK_NAME}"
	# shellcheck disable=SC2086
	rm -f $dylibs
}

build_arch iphoneos arm64
build_arch iphonesimulator arm64
build_arch iphonesimulator x86_64

# Headers are architecture independent for these targets (all little endian, 64-bit), verify that.
for other in install-iphonesimulator-arm64 install-iphonesimulator-x86_64; do
	if ! diff -r "${WORK_DIR}/install-iphoneos-arm64/include" "${WORK_DIR}/${other}/include" > /dev/null; then
		echo "error: public headers differ between iphoneos-arm64 and ${other}" >&2
		exit 1
	fi
done

echo "Creating ${FRAMEWORK_NAME}.xcframework..."
make_framework ios-arm64 iPhoneOS iphoneos arm64
make_framework ios-arm64_x86_64-simulator iPhoneSimulator iphonesimulator arm64 x86_64

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
xcodebuild -create-xcframework \
	-framework "${WORK_DIR}/frameworks/ios-arm64/${FRAMEWORK_NAME}.framework" \
	-debug-symbols "${WORK_DIR}/frameworks/ios-arm64/${FRAMEWORK_NAME}.framework.dSYM" \
	-framework "${WORK_DIR}/frameworks/ios-arm64_x86_64-simulator/${FRAMEWORK_NAME}.framework" \
	-debug-symbols "${WORK_DIR}/frameworks/ios-arm64_x86_64-simulator/${FRAMEWORK_NAME}.framework.dSYM" \
	-output "${OUTPUT_DIR}/${FRAMEWORK_NAME}.xcframework" > /dev/null
cp -R "${WORK_DIR}/install-iphoneos-arm64/include" "${OUTPUT_DIR}/include"
cp "${SRC_DIR}/COPYING.LGPLv2.1" "${OUTPUT_DIR}/"
{
	echo "$STAMP"
	echo "FFmpeg ${FFMPEG_VERSION} (${FFMPEG_URL}, sha256 ${FFMPEG_SHA256})"
	echo "Built $(date '+%Y-%m-%d %H:%M') with $(xcodebuild -version | head -n 1), iOS ${IOS_MIN_VERSION}+"
	echo "Configure flags: ${CONFIGURE_FLAGS}"
} > "${OUTPUT_DIR}/BUILD_INFO.txt"

rm -rf "$WORK_DIR"
rmdir "${ROOT_DIR}/Temp" 2>/dev/null || true
echo "FFmpeg ${FFMPEG_VERSION} built into ${OUTPUT_DIR}"
