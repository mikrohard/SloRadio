#!/bin/sh
#
# Generates the synthetic audio fixtures (sine tones, no recorded audio) used by the decoder tests.
# Requires the ffmpeg command line tool with libmp3lame, libopus and AudioToolbox (brew install ffmpeg).
#
#   Scripts/make-test-fixtures.sh
#
set -eu
OUT="$(cd "$(dirname "$0")/.." && pwd)/SloRadioTests/Fixtures"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"
ff() { ffmpeg -hide_banner -loglevel error -y "$@"; }
tone() { echo "sine=frequency=$1:sample_rate=$2:duration=$3"; }

# 3 s, 44.1 kHz stereo MP3 (the most common radio stream)
ff -f lavfi -i "$(tone 440 44100 3)" -ac 2 -c:a libmp3lame -b:a 128k -id3v2_version 0 -write_xing 0 "$OUT/tone-44k-stereo.mp3"
# 3 s, 22.05 kHz mono MP3 (exercises resampling and upmixing)
ff -f lavfi -i "$(tone 440 22050 3)" -ac 1 -c:a libmp3lame -b:a 48k -id3v2_version 0 -write_xing 0 "$OUT/tone-22k-mono.mp3"
# 3 s AAC-LC and HE-AAC in ADTS
ff -f lavfi -i "$(tone 440 48000 3)" -ac 2 -c:a aac -b:a 128k -f adts "$OUT/tone-aac-lc.aac"
ff -f lavfi -i "$(tone 440 48000 3)" -ac 2 -c:a aac_at -profile:a 4 -b:a 64k -f adts "$OUT/tone-he-aac.aac"
# 3 s Opus and FLAC in their usual containers
ff -f lavfi -i "$(tone 440 48000 3)" -ac 2 -c:a libopus -b:a 96k "$OUT/tone.opus"
ff -f lavfi -i "$(tone 440 44100 3)" -ac 2 -c:a flac "$OUT/tone.flac"
# 3 s AAC in MPEG-TS (like an HLS segment)
ff -f lavfi -i "$(tone 440 48000 3)" -ac 2 -c:a aac -b:a 128k -f mpegts "$OUT/tone-aac.ts"
# chained Ogg Vorbis: two 1.5 s "songs" with their own comments, like an Icecast Ogg stream
ff -f lavfi -i "$(tone 440 44100 1.5)" -ac 2 -c:a vorbis -strict -2 -metadata TITLE="First Song" -metadata ARTIST="First Artist" "$TMP/a.ogg"
ff -f lavfi -i "$(tone 880 44100 1.5)" -ac 2 -c:a vorbis -strict -2 -metadata TITLE="Second Song" -metadata ARTIST="Second Artist" "$TMP/b.ogg"
cat "$TMP/a.ogg" "$TMP/b.ogg" > "$OUT/chained.ogg"
ls -l "$OUT"
