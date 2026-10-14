#!/bin/sh
set -eu
# Requires a booted iOS simulator. Override SIMULATOR_ID to select one.
cd "$(dirname "$0")/.."
xcrun --sdk iphonesimulator swiftc \
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -target "$(uname -m)-apple-ios27.0-simulator" \
  'Sticker Deck/Models/Sticker.swift' \
  'Sticker Deck/Models/StickerAppearance.swift' \
  'Sticker Deck/Services/StickerRepository.swift' \
  'Sticker Deck/Services/StickerImageService.swift' \
  'Sticker Deck/Services/SubjectCutoutService.swift' \
  'Sticker Deck/Services/StickerSheetSplitter.swift' \
  'Sticker Deck/ViewModels/StickerEditorViewModel.swift' \
  'Sticker Deck/ViewModels/StickerSheetViewModel.swift' \
  'Sticker Deck/ViewModels/StickerLibraryViewModel.swift' \
  Tests/ServiceChecks.swift -o /tmp/sticker-deck-service-checks
xcrun simctl spawn "${SIMULATOR_ID:-booted}" /tmp/sticker-deck-service-checks "$@"
