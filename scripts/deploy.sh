#!/usr/bin/env bash
# musicplayer 클라이언트 빌드/배포
# ---------------------------------------------------------------------------
# 서버는 publix(github.com/Oein/publix)가 별도로 배포한다(프로젝트 musicplayer).
# 이 스크립트는 클라이언트 아티팩트(web/APK/DMG/IPA)만 빌드해 publix 호스트의
# 프로젝트 볼륨(프로젝트 ID c258d2fb)에 올린다.
#
#   web(작은 파일 다수)  → /mnt/data-ssd/c258d2fb/web        (컨테이너 WEB_DIR=/data/web)
#   APK/DMG/IPA(대용량)  → /mnt/data-hdd/c258d2fb/downloads  (컨테이너 DOWNLOADS_DIR=/mnt/data/downloads)
#                          data-hdd 는 TrueNAS hdd-4tb NFS 마운트(SMR → --bwlimit)
#
# 볼륨 디렉터리는 root 소유라 publix 쪽 rsync 는 sudo 로 실행하고, 파일은
# 컨테이너 사용자(3000:staff) 소유로 맞춘다.
#
# 앱 기본 서버 URL 은 app/lib/config/server_url.dart(gitignore)에서 읽는다.
#
# 사용: ./scripts/deploy.sh [web|apk|macos|ios|all]
# ---------------------------------------------------------------------------
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/../app" && pwd)"
STAGE="${TMPDIR:-/tmp}/musicplayer-deploy"
mkdir -p "$STAGE"

PUBLIX_HOST=publix
PUBLIX_WEB=/mnt/data-ssd/c258d2fb/web           # SSD
PUBLIX_DL=/mnt/data-hdd/c258d2fb/downloads      # HDD (SMR, NFS)
OEINDEV_APP='~/musicplayer-app'
SYNC_EXCLUDES=(--exclude .dart_tool --exclude build --exclude '.flutter-plugins*')

sync_to_oeindev() {
  rsync -az "${SYNC_EXCLUDES[@]}" -e ssh "$APP_DIR/" "oeindev:$OEINDEV_APP/"
}
push_web() { rsync -a --delete --chown=3000:staff --rsync-path="sudo rsync" "$1/" "$PUBLIX_HOST:$PUBLIX_WEB/"; }
push_dl()  { rsync -a --bwlimit=8000 --chown=3000:staff --rsync-path="sudo rsync" "$1" "$PUBLIX_HOST:$PUBLIX_DL/"; }

if [[ ! -f "$APP_DIR/lib/config/server_url.dart" ]]; then
  echo "app/lib/config/server_url.dart 가 없습니다 (server_url.template.dart 를 복사해 URL 설정)" >&2
  exit 1
fi

build_web() {
  echo "== web (oeindev) =="
  sync_to_oeindev
  # base-href=/app/ 필수 (서버가 /app/ prefix 로 서빙)
  ssh oeindev "cd $OEINDEV_APP && /opt/flutter/bin/flutter build web --release --base-href=/app/"
  rsync -az "oeindev:$OEINDEV_APP/build/web/" "$STAGE/web/"
  push_web "$STAGE/web"
  echo "web → publix SSD 배포 완료"
}

build_apk() {
  echo "== APK (oeindev) =="
  # R8(minify/shrink) 는 android/ 설정에서 OFF 유지해야 audio_service 정상 (앱 설정에 이미 반영)
  sync_to_oeindev
  ssh oeindev "cd $OEINDEV_APP && /opt/flutter/bin/flutter build apk --release"
  rsync -az "oeindev:$OEINDEV_APP/build/app/outputs/flutter-apk/app-release.apk" "$STAGE/music.apk"
  push_dl "$STAGE/music.apk"
  echo "APK → publix HDD downloads 배포 완료"
}

build_macos() {
  echo "== macOS DMG (local) =="
  ( cd "$APP_DIR" && flutter build macos --release )
  hdiutil create -volname "Music Player" \
    -srcfolder "$APP_DIR/build/macos/Build/Products/Release/musicplayer.app" \
    -ov -format UDZO "$STAGE/MusicPlayer.dmg"
  push_dl "$STAGE/MusicPlayer.dmg"
  echo "DMG → publix HDD downloads 배포 완료"
}

build_ios() {
  echo "== iOS IPA (local, no-codesign) =="
  ( cd "$APP_DIR" && flutter build ios --release --no-codesign )
  rm -rf "$STAGE/Payload"; mkdir -p "$STAGE/Payload"
  cp -r "$APP_DIR/build/ios/iphoneos/Runner.app" "$STAGE/Payload/"
  ( cd "$STAGE" && rm -f MusicPlayer.ipa && zip -qr MusicPlayer.ipa Payload )
  push_dl "$STAGE/MusicPlayer.ipa"
  echo "IPA → publix HDD downloads 배포 완료"
}

case "${1:-all}" in
  web)        build_web ;;
  apk)        build_apk ;;
  macos|dmg)  build_macos ;;
  ios|ipa)    build_ios ;;
  all)        build_web; build_apk; build_macos; build_ios ;;
  *) echo "usage: $0 [web|apk|macos|ios|all]"; exit 1 ;;
esac
