#!/usr/bin/env bash
# musicplayer 클라이언트 빌드/배포
# ---------------------------------------------------------------------------
# 서버는 publix 가 private repo oe2n/musicplayer 의 push 로 자동 배포한다
# (프로젝트 musicplayer, 프로젝트 ID c258d2fb). 이 스크립트는 클라이언트
# 아티팩트(web/APK/DMG/IPA)만 publix 호스트의 볼륨에 올린다.
#
#   web(작은 파일 다수) → ssd 공유 볼륨의 web/          (컨테이너 WEB_DIR=/data/web)
#   APK/DMG/IPA        → /mnt/data-hdd/c258d2fb/downloads (컨테이너 DOWNLOADS_DIR)
#                         data-hdd 는 TrueNAS hdd-4tb NFS(SMR → --bwlimit)
#
# - web, APK 는 이 머신에서 직접 빌드한다(flutter + ANDROID_HOME 필요).
# - DMG, IPA 는 macOS 가 필요하므로 GitHub Release(v* 태그로
#   .github/workflows/release-apple.yml 이 만든 것)에서 받아 올린다.
#   기본은 최신 릴리스, RELEASE_TAG=v0.2.0 처럼 지정 가능.
# - 덮어쓰기 전에 기존 web 은 web.bak-<날짜-시각>, 다운로드는 *.prev 로 남긴다.
#
# 볼륨 디렉터리는 root 소유라 publix 쪽 rsync 는 sudo 로 실행하고, 파일은
# 컨테이너 사용자(3000:staff) 소유로 맞춘다.
#
# 앱 기본 서버 URL 은 app/lib/config/server_url.dart(gitignore)에서 읽는다.
#
# 사용: ./scripts/deploy.sh [web|apk|apple|all]
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/app"
STAGE="${TMPDIR:-/tmp}/musicplayer-deploy"
mkdir -p "$STAGE"

FLUTTER="${FLUTTER:-$(command -v flutter || echo /opt/flutter/bin/flutter)}"
export ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
GH_REPO="${GH_REPO:-Oein/music-streaming}"

PUBLIX_HOST="${PUBLIX_HOST:-publix}"
# web 볼륨(publix-nfs-data-ssd-*, TrueNAS /mnt/ssd16/data-ssd/c258d2fb 의 NFS)
PUBLIX_WEB=/var/lib/docker/volumes/publix-nfs-data-ssd-5912683cd7f6/_data/web
PUBLIX_DL=/mnt/data-hdd/c258d2fb/downloads
TODAY="$(date +%Y%m%d-%H%M)"

remote() { ssh -o BatchMode=yes "$PUBLIX_HOST" "$@"; }

push_web() {
  remote "sudo test -d $PUBLIX_WEB && sudo rm -rf $PUBLIX_WEB.bak-$TODAY && sudo cp -a $PUBLIX_WEB $PUBLIX_WEB.bak-$TODAY"
  rsync -a --delete --chown=3000:staff --rsync-path="sudo rsync" "$1/" "$PUBLIX_HOST:$PUBLIX_WEB/"
}

push_dl() {
  local names=() f
  for f in "$@"; do names+=("$(basename "$f")"); done
  remote "cd $PUBLIX_DL && for f in ${names[*]}; do if sudo test -f \$f; then sudo cp -a \$f \$f.prev; fi; done"
  rsync -a --bwlimit=8000 --chown=3000:staff --rsync-path="sudo rsync" "$@" "$PUBLIX_HOST:$PUBLIX_DL/"
}

need_server_url() {
  if [[ ! -f "$APP_DIR/lib/config/server_url.dart" ]]; then
    echo "app/lib/config/server_url.dart 가 없습니다 (server_url.template.dart 를 복사해 URL 설정)" >&2
    exit 1
  fi
}

build_web() {
  echo "== web =="
  need_server_url
  # base-href=/app/ 필수 (서버가 /app/ prefix 로 서빙)
  ( cd "$APP_DIR" && "$FLUTTER" build web --release --base-href=/app/ )
  push_web "$APP_DIR/build/web"
  echo "web → publix 배포 완료 (이전 버전: $PUBLIX_WEB.bak-$TODAY)"
}

build_apk() {
  echo "== APK =="
  need_server_url
  # R8(minify/shrink) 는 android/ 설정에서 OFF 유지해야 audio_service 정상 (앱 설정에 이미 반영)
  ( cd "$APP_DIR" && "$FLUTTER" build apk --release )
  cp "$APP_DIR/build/app/outputs/flutter-apk/app-release.apk" "$STAGE/music.apk"
  push_dl "$STAGE/music.apk"
  echo "APK → publix downloads 배포 완료"
}

fetch_apple() {
  echo "== DMG/IPA (GitHub Release ${RELEASE_TAG:-latest}) =="
  rm -f "$STAGE/MusicPlayer.dmg" "$STAGE/MusicPlayer.ipa"
  gh release download ${RELEASE_TAG:+"$RELEASE_TAG"} -R "$GH_REPO" -D "$STAGE" \
    -p MusicPlayer.dmg -p MusicPlayer.ipa
  push_dl "$STAGE/MusicPlayer.dmg" "$STAGE/MusicPlayer.ipa"
  echo "DMG/IPA → publix downloads 배포 완료"
}

case "${1:-all}" in
  web)               build_web ;;
  apk)               build_apk ;;
  apple|macos|dmg|ios|ipa) fetch_apple ;;
  all)               build_web; build_apk; fetch_apple ;;
  *) echo "usage: $0 [web|apk|apple|all]"; exit 1 ;;
esac
