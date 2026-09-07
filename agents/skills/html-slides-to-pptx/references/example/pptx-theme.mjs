// theme.css の配色・寸法を pptxgenjs 用に写した定数
export const C = {
  bg: "14151F",
  bgPanel: "1D1F2E",
  bgInset: "10111A",
  border: "33364D",
  fg: "E6E9F5",
  fgMuted: "9AA1C0",
  fgFaint: "666D8F",
  claude: "D97757",
  green: "9ECE6A",
  red: "F7768E",
  yellow: "E0AF68",
  blue: "7AA2F7",
  cyan: "7DCFFF",
  magenta: "BB9AF7",
};

export const FONT_MONO = "Consolas";
export const FONT_BODY = "Yu Gothic";

// 1920x1080px → 13.333x7.5in
export const IN = (px) => px / 144;
// フォント px → pt
export const PT = (px) => px / 2;

export const SLIDE_W = 13.333;
export const SLIDE_H = 7.5;
export const PAD = IN(96); // --pad-slide
export const BODY_BOTTOM = IN(1080 - 140); // slide-inner の下端 (status bar + 余白)
export const BODY_W = SLIDE_W - PAD * 2;
export const GAP_LG = IN(48);
export const GAP_MD = IN(24);
export const GAP_SM = IN(12);
export const RADIUS = 0.07; // 10px 相当の角丸

// 色 8%/12% を地色に混ぜる (color-mix 相当)
export function mix(base, tint, ratio) {
  const b = [0, 2, 4].map((i) => parseInt(base.slice(i, i + 2), 16));
  const t = [0, 2, 4].map((i) => parseInt(tint.slice(i, i + 2), 16));
  return b
    .map((v, i) =>
      Math.round(v * (1 - ratio) + t[i] * ratio)
        .toString(16)
        .padStart(2, "0"),
    )
    .join("")
    .toUpperCase();
}

// 全角=1, 半角=0.55 で概算した「全角換算幅」
export function textUnits(s) {
  let u = 0;
  for (const ch of s) u += /[\x20-\x7e]/.test(ch) ? 0.55 : 1;
  return u;
}

// 幅 w(in) に fontPx の文字を折り返したときの行数を概算
export function estLines(text, fontPx, w) {
  const perLine = Math.floor((w * 144) / fontPx);
  return Math.max(1, Math.ceil(textUnits(text) / perLine));
}
