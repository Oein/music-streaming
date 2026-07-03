#!/usr/bin/env bash
# musicplayer 클라이언트 빌드/배포
# ---------------------------------------------------------------------------
# 서버는 GitOps 로 별도 배포된다(oe2n/musicplayer: main push → GHCR → Komodo).
# 이 스크립트는 클라이언트 아티팩트(web/APK/DMG/IPA)만 빌드해 TrueNAS 로 올린다.
#
#   web(작은 파일 다수)  → SSD  ssd16/data-ssd/musicplayer/web   (컨테이너 WEB_DIR=/data/web)
#   APK/DMG/IPA(대용량)  → HDD  hdd-4tb/data/musicplayer/downloads (SMR → --bwlimit)
#
# 경로 소유자가 root 라 truenas 쪽 rsync 는 sudo 로 실행(truenas_admin NOPASSWD).
# oeindev→truenas 직접 ssh 는 막혀 있어 이 Mac 을 경유한다(truenas 접근은 Mac 에만).
#
# 사용: ./scripts/deploy.sh [web|apk|macos|ios|all]
# ---------------------------------------------------------------------------
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/../app" && pwd)"
STAGE="${TMPDIR:-/tmp}/musicplayer-deploy"
mkdir -p "$STAGE"

TN_WEB=/mnt/ssd16/data-ssd/musicplayer/web            # SSD
TN_DL=/mnt/hdd-4tb/data/musicplayer/downloads         # HDD (SMR)
OEINDEV_APP='~/musicplayer-app'
SYNC_EXCLUDES=(--exclude .dart_tool --exclude build --exclude '.flutter-plugins*')

sync_to_oeindev() {
  rsync -az "${SYNC_EXCLUDES[@]}" -e ssh "$APP_DIR/" "oeindev:$OEINDEV_APP/"
}
push_web() { rsync -a --delete --rsync-path="sudo rsync" "$1/" "truenas:$TN_WEB/"; }
push_dl()  { rsync -a --bwlimit=8000 --rsync-path="sudo rsync" "$1" "truenas:$TN_DL/"; }

build_web() {
  echo "== web (oeindev) =="
  sync_to_oeindev
  # base-href=/app/ 필수 (서버가 /app/ prefix 로 서빙)
  ssh oeindev "cd $OEINDEV_APP && /opt/flutter/bin/flutter build web --release --base-href=/app/"
  rsync -az "oeindev:$OEINDEV_APP/build/web/" "$STAGE/web/"
  push_web "$STAGE/web"
  echo "web → SSD 배포 완료"
}

build_apk() {
  echo "== APK (oeindev) =="
  # R8(minify/shrink) 는 android/ 설정에서 OFF 유지해야 audio_service 정상 (앱 설정에 이미 반영)
  sync_to_oeindev
  ssh oeindev "cd $OEINDEV_APP && /opt/flutter/bin/flutter build apk --release"
  rsync -az "oeindev:$OEINDEV_APP/build/app/outputs/flutter-apk/app-release.apk" "$STAGE/music.apk"
  push_dl "$STAGE/music.apk"
  echo "APK → HDD downloads 배포 완료"
}

build_macos() {
  echo "== macOS DMG (local) =="
  ( cd "$APP_DIR" && flutter build macos --release )
  hdiutil create -volname "Music Player" \
    -srcfolder "$APP_DIR/build/macos/Build/Products/Release/musicplayer.app" \
    -ov -format UDZO "$STAGE/MusicPlayer.dmg"
  push_dl "$STAGE/MusicPlayer.dmg"
  echo "DMG → HDD downloads 배포 완료"
}

build_ios() {
  echo "== iOS IPA (local, no-codesign) =="
  ( cd "$APP_DIR" && flutter build ios --release --no-codesign )
  rm -rf "$STAGE/Payload"; mkdir -p "$STAGE/Payload"
  cp -r "$APP_DIR/build/ios/iphoneos/Runner.app" "$STAGE/Payload/"
  ( cd "$STAGE" && rm -f MusicPlayer.ipa && zip -qr MusicPlayer.ipa Payload )
  push_dl "$STAGE/MusicPlayer.ipa"
  echo "IPA → HDD downloads 배포 완료"
}

case "${1:-all}" in
  web)        build_web ;;
  apk)        build_apk ;;
  macos|dmg)  build_macos ;;
  ios|ipa)    build_ios ;;
  all)        build_web; build_apk; build_macos; build_ios ;;
  *) echo "usage: $0 [web|apk|macos|ios|all]"; exit 1 ;;
esac
