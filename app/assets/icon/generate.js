// App icon source + generator. Edit the SVG below, then regenerate:
//   npm i --prefix /tmp/iconkit @resvg/resvg-js@2.6.2
//   NODE_PATH=/tmp/iconkit/node_modules node app/assets/icon/generate.js
// Writes the SVG sources next to this file and every platform PNG.
const fs = require('fs');
const path = require('path');

const C = 512; // center of the 1024 canvas

// "Record classic · R1": flat fills only — no gradients, shadows or textures.
const COLORS = {
  bg: '#EFE9DD',     // cream
  disc: '#1B1B1D',   // record
  groove: '#2E2E31', // the single ring on the record
  label: '#E2533B',  // red label
  play: '#FFFFFF',
};

// The record motif, scaled by s around the center. s=1 → disc radius 330.
function disc(s) {
  const R = 330 * s, G = 236 * s, L = 122 * s;
  // Rounded play triangle centered optically (shifted right a touch).
  const t = 58 * s, ox = C + 10 * s;
  const tri = `M ${ox - t * 0.75} ${C - t} L ${ox + t * 0.95} ${C} L ${ox - t * 0.75} ${C + t} Z`;
  return `
  <circle cx="${C}" cy="${C}" r="${R}" fill="${COLORS.disc}"/>
  <circle cx="${C}" cy="${C}" r="${G}" fill="none" stroke="${COLORS.groove}" stroke-width="${10 * s}"/>
  <circle cx="${C}" cy="${C}" r="${L}" fill="${COLORS.label}"/>
  <path d="${tri}" fill="${COLORS.play}" stroke="${COLORS.play}" stroke-width="${22 * s}" stroke-linejoin="round"/>`;
}

const svg = (body) => `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">${body}\n</svg>\n`;
const bgRect = `<rect width="1024" height="1024" fill="${COLORS.bg}"/>`;

const variants = {
  // iOS / Android legacy / web: full-bleed square (the OS applies its mask).
  'icon.svg': svg(`${bgRect}${disc(1)}`),
  // macOS: Big Sur grid — 824px rounded square on a transparent 1024 canvas.
  'icon_macos.svg': svg(`
  <rect x="100" y="100" width="824" height="824" rx="185" fill="${COLORS.bg}"/>${disc(0.8)}`),
  // Android adaptive: background layer and a foreground kept inside the
  // 66% safe zone (masks crop up to ~18% per side).
  'icon_adaptive_bg.svg': svg(bgRect),
  'icon_adaptive_fg.svg': svg(disc(0.62)),
};
// Android 13+ themed icon: single-color silhouette (disc with play cut out).
{
  const s = 0.62, R = 330 * s, t = 58 * s, ox = C + 10 * s, L = 122 * s;
  variants['icon_adaptive_mono.svg'] = svg(`
  <path fill-rule="evenodd" fill="#FFFFFF" d="
    M ${C - R} ${C} a ${R} ${R} 0 1 0 ${2 * R} 0 a ${R} ${R} 0 1 0 ${-2 * R} 0 Z
    M ${C - L} ${C} a ${L} ${L} 0 1 0 ${2 * L} 0 a ${L} ${L} 0 1 0 ${-2 * L} 0 Z"/>
  <path fill="#FFFFFF" stroke="#FFFFFF" stroke-width="${22 * s}" stroke-linejoin="round"
    d="M ${ox - t * 0.75} ${C - t} L ${ox + t * 0.95} ${C} L ${ox - t * 0.75} ${C + t} Z"/>`);
}

const { Resvg } = require('@resvg/resvg-js');
const zlib = require('zlib');
const here = __dirname;
const app = path.resolve(here, '../..');
for (const [n, s] of Object.entries(variants)) fs.writeFileSync(path.join(here, n), s);

// Render an SVG at `size` px. opaque=true drops the alpha channel (App Store
// rejects icons with alpha), so we encode the PNG ourselves as RGB.
function render(name, size, dst, { opaque = false } = {}) {
  const img = new Resvg(variants[name], { fitTo: { mode: 'width', value: size } }).render();
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  if (!opaque) return fs.writeFileSync(dst, img.asPng());
  const w = img.width, h = img.height, px = img.pixels;
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 3 + 1)] = 0;
    for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 4, o = y * (w * 3 + 1) + 1 + x * 3;
      raw[o] = px[i]; raw[o + 1] = px[i + 1]; raw[o + 2] = px[i + 2];
    }
  }
  const crcTable = Array.from({ length: 256 }, (_, n) => {
    let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0;
  });
  const crc = (b) => { let c = 0xffffffff; for (const v of b) c = crcTable[(c ^ v) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type), data]);
    const c = Buffer.alloc(4); c.writeUInt32BE(crc(td));
    return Buffer.concat([len, td, c]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2; // 8-bit RGB
  fs.writeFileSync(dst, Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0)),
  ]));
}

// iOS — sizes read from the asset catalog.
const iosDir = path.join(app, 'ios/Runner/Assets.xcassets/AppIcon.appiconset');
for (const im of JSON.parse(fs.readFileSync(path.join(iosDir, 'Contents.json'))).images) {
  if (!im.filename) continue;
  const px = Math.round(parseFloat(im.size) * parseFloat(im.scale));
  render('icon.svg', px, path.join(iosDir, im.filename), { opaque: true });
}

// macOS
const macDir = path.join(app, 'macos/Runner/Assets.xcassets/AppIcon.appiconset');
for (const px of [16, 32, 64, 128, 256, 512, 1024]) {
  render('icon_macos.svg', px, path.join(macDir, `app_icon_${px}.png`));
}

// Android — legacy (rounded square) + adaptive layers (108dp canvas).
const res = path.join(app, 'android/app/src/main/res');
const dens = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };
for (const [d, k] of Object.entries(dens)) {
  const dir = path.join(res, `mipmap-${d}`);
  render('icon_macos.svg', 48 * k, path.join(dir, 'ic_launcher.png'));
  render('icon_adaptive_fg.svg', 108 * k, path.join(dir, 'ic_launcher_foreground.png'));
  render('icon_adaptive_bg.svg', 108 * k, path.join(dir, 'ic_launcher_background.png'));
  render('icon_adaptive_mono.svg', 108 * k, path.join(dir, 'ic_launcher_monochrome.png'));
}
fs.mkdirSync(path.join(res, 'mipmap-anydpi-v26'), { recursive: true });
fs.writeFileSync(path.join(res, 'mipmap-anydpi-v26/ic_launcher.xml'), `<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by app/assets/icon/generate.js -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
`);
console.log('icons generated');
