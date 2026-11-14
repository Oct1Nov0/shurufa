#!/bin/bash
# Builds the lexicon into iOS/Generated and generates the Xcode project.
# Needs macOS with Xcode, Python 3 and XcodeGen.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build iOS/Generated
# Traditional/Simplified conversion comes from Foundation, so this runs on macOS.
swiftc scripts/ConvertScript.swift -o .build/convert-script
python3 scripts/compile-native-lexicon.py iOS/Generated "$PWD/.build/convert-script"
rm -rf iOS/Generated/Licenses
mkdir -p iOS/Generated/Licenses
cp LICENSE iOS/Generated/Licenses/Meowpuut-MIT.txt
cp THIRD_PARTY.md iOS/Generated/Licenses/THIRD_PARTY.md
cp DataSources/mimo-tc/LICENSE.txt iOS/Generated/Licenses/mimo-tc-MIT.txt
cp DataSources/mimo-tc/OPENCC-LICENSE.txt iOS/Generated/Licenses/OpenCC-Apache-2.0.txt
cp DataSources/mimo-tc/JIEBA-LICENSE.txt iOS/Generated/Licenses/jieba-MIT.txt
cp DataSources/mimo-tc/SOURCE.json iOS/Generated/Licenses/mimo-tc-SOURCE.json
cp DataSources/mimo-sc/LICENSE iOS/Generated/Licenses/mimo-sc-MIT.txt
cp DataSources/mimo-sc/SOURCE.json iOS/Generated/Licenses/mimo-sc-SOURCE.json
cp DataSources/mimo-jp/LICENSE.txt iOS/Generated/Licenses/mimo-jp-derived-BSD.txt
cp DataSources/mimo-jp/BSD.txt iOS/Generated/Licenses/mimo-jp-BSD.txt
cp DataSources/mimo-jp/COPYING.txt iOS/Generated/Licenses/mimo-jp-COPYING.txt
cp DataSources/mimo-jp/SOURCE.json iOS/Generated/Licenses/mimo-jp-SOURCE.json
cp DataSources/cldr-emoji/LICENSE.txt iOS/Generated/Licenses/CLDR-Unicode-3.0.txt
cp DataSources/cldr-emoji/SOURCE.json iOS/Generated/Licenses/cldr-emoji-SOURCE.json
cp DataSources/mimo-jp/MOZC-LICENSE.txt iOS/Generated/Licenses/mimo-jp-Mozc-BSD.txt
cp DataSources/mimo-jp/UNICODE-LICENSE.txt iOS/Generated/Licenses/mimo-jp-Unicode-3.0.txt
cp DataSources/mimo-pairs/SOURCE.json iOS/Generated/Licenses/mimo-pairs-SOURCE.json
cp DataSources/mimo-pairs/Apache-2.0.txt iOS/Generated/Licenses/mimo-pairs-Apache-2.0.txt
cp DataSources/mimo-pairs/CC-BY-4.0.txt iOS/Generated/Licenses/mimo-pairs-CC-BY-4.0.txt
cp DataSources/mimo-names/SOURCE.json iOS/Generated/Licenses/mimo-names-SOURCE.json
cp DataSources/mimo-phrases/SOURCE.json iOS/Generated/Licenses/mimo-phrases-SOURCE.json
cp DataSources/mimo-pairs/CC-BY-2.0-FR.html iOS/Generated/Licenses/mimo-pairs-Tatoeba-CC-BY-2.0-FR.html
cp DataSources/mimo-pairs/CC0-1.0.txt iOS/Generated/Licenses/mimo-pairs-CommonVoice-CC0-1.0.txt
cp DataSources/mimo-latin/SOURCE.json iOS/Generated/Licenses/mimo-latin-SOURCE.json
xcodegen generate --spec iOS/project.yml
