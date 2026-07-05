#!/usr/bin/env bash
# One-shot installer for the RPi playback device. Run on the Raspberry Pi.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

echo "==> Installing system packages (mpv, python venv)"
sudo apt-get update
sudo apt-get install -y mpv python3-venv python3-pip

echo "==> Creating Python venv"
python3 -m venv venv
./venv/bin/pip install --upgrade pip
./venv/bin/pip install -r requirements.txt

if [ ! -f .env ]; then
  echo "==> Creating .env from template — EDIT IT before starting the service"
  cp .env.example .env
fi

echo "==> Ensuring current user is in the 'audio' group"
sudo usermod -aG audio "$USER" || true

echo
echo "Done. Next steps:"
echo "  1. Edit $HERE/.env  (SERVER_URL, credentials, ALSA_DEVICE)"
echo "  2. Find your USB DAC:   mpv --audio-device=help"
echo "  3. Test in foreground:  ./venv/bin/python player.py"
echo "  4. Install as a service (edit User/paths in the unit if needed):"
echo "       sudo cp musicplayer-rpi.service /etc/systemd/system/"
echo "       sudo systemctl daemon-reload"
echo "       sudo systemctl enable --now musicplayer-rpi"
