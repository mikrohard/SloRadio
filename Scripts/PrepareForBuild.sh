#!/bin/sh

# Variables
FRAMEWORK_NAME="MobileVLCKit.framework"
LIBRARIES_PATH="${SOURCE_ROOT}/Libraries/"
VLCKIT_FRAMEWORK="${LIBRARIES_PATH}${FRAMEWORK_NAME}"
VLCKIT_FILE="MobileVLCKit-3.1.5-5b3b1db-c6718efd1a.tar.xz"
VLCKIT_URL="http://download.videolan.org/pub/cocoapods/prod/${VLCKIT_FILE}"
TEMP_PATH="${SOURCE_ROOT}/Temp"

if [ ! -d "$VLCKIT_FRAMEWORK" ]; then
	mkdir -p "$TEMP_PATH"
	pushd "$TEMP_PATH"
	curl $VLCKIT_URL --output $VLCKIT_FILE
	tar -xJf $VLCKIT_FILE
	FRAMEWORK_PATH=$(find "$TEMP_PATH" -type d -name $FRAMEWORK_NAME)
	mv "$FRAMEWORK_PATH" "$LIBRARIES_PATH"
	popd
	rm -r "$TEMP_PATH"
fi
