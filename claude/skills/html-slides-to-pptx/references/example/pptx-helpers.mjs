// theme.css / 各デッキの HTML ヘルパー (hero/slide/term/cards/...) を
// pptxgenjs の図形・テキスト・表として再現するレンダラ群
import {
  BODY_BOTTOM,
  BODY_W,
  C,
  FONT_BODY,
  FONT_MONO,
  GAP_MD,
  GAP_SM,
  IN,
  PAD,
  RADIUS,
  SLIDE_H,
  SLIDE_W,
  estLines,
  mix,
  textUnits,
} from "./pptx-theme.mjs";

const stripTags = (html) => html.replace(/<[^>]+>/g, "");

// <em>/<b>/<span class="mono|accent"> を run 配列に変換する
export function parseInline(html, level, defOpts = {}) {
  const runs = [];
  const stack = [{ ...defOpts }];
  for (const tok of html.match(/<[^>]+>|[^<]+/g) ?? []) {
    if (tok.startsWith("<")) {
      const t = tok.toLowerCase();
      if (t.startsWith("</")) {
        if (stack.length > 1) stack.pop();
      } else if (t.startsWith("<em")) {
        stack.push({ ...stack.at(-1), color: level });
      } else if (t.startsWith("<b")) {
        stack.push({ ...stack.at(-1), bold: true, color: C.fg });
      } else if (t.includes('class="mono"')) {
        stack.push({ ...stack.at(-1), fontFace: FONT_MONO });
      } else if (t.includes('class="accent"')) {
        stack.push({ ...stack.at(-1), color: level });
      } else {
        stack.push({ ...stack.at(-1) });
      }
    } else {
      const text = tok.replace(/\s+/g, " ");
      if (text) runs.push({ text, options: { ...stack.at(-1) } });
    }
  }
  return runs;
}

// <p>...</p> 区切りで段落に分割 (無ければ 1 段落)
function splitParagraphs(html) {
  const ps = [...html.matchAll(/<p[^>]*>([\s\S]*?)<\/p>/g)].map((m) => m[1]);
  return ps.length ? ps : [html];
}

export function renderPromptLine(slide, deck, prompt, y, sizePt = 13) {
  slide.addText(
    [
      { text: "❯ ", options: { color: deck.level, bold: true } },
      { text: "claude", options: { color: C.claude, bold: true } },
      ...(prompt
        ? [{ text: ` ${prompt}`, options: { color: C.fgMuted } }]
        : []),
    ],
    {
      x: PAD,
      y,
      w: BODY_W,
      h: IN(44),
      fontFace: FONT_MONO,
      fontSize: sizePt,
      valign: "middle",
    },
  );
}

export function renderTitle(slide, deck, title, y) {
  const lines = estLines(stripTags(title), 64, BODY_W);
  const h = lines * IN(80);
  slide.addText(parseInline(title, deck.level, { color: C.fg }), {
    x: PAD,
    y,
    w: BODY_W,
    h,
    fontFace: FONT_BODY,
    fontSize: 32,
    bold: true,
    valign: "top",
    lineSpacingMultiple: 1.15,
  });
  return h;
}

export function renderBadge(slide, deck, badge, y) {
  const isHandsOn = badge === "hands-on";
  const text = isHandsOn ? "HANDS-ON ── 全員で手を動かす" : "DEMO ── 講師デモ";
  slide.addText(text, {
    x: PAD,
    y,
    w: textUnits(text) * 0.15 + 0.35,
    h: IN(44),
    fontFace: FONT_MONO,
    fontSize: 10,
    bold: true,
    charSpacing: 1,
    align: "center",
    valign: "middle",
    color: isHandsOn ? C.bg : C.cyan,
    fill: isHandsOn ? { color: deck.level } : { color: C.bg },
    line: isHandsOn ? undefined : { color: C.cyan, width: 1 },
    shape: "roundRect",
    rectRadius: 0.04,
  });
  return IN(44);
}

export function renderStatusBar(slide, deck, topic, time) {
  const y = SLIDE_H - IN(64);
  slide.addShape("rect", {
    x: 0,
    y,
    w: SLIDE_W,
    h: IN(64),
    fill: { color: C.bgInset },
    line: { color: C.border, width: 0.75 },
  });
  const tag = deck.levelTag;
  slide.addText(tag, {
    x: IN(48),
    y: y + IN(12),
    w: textUnits(tag) * 0.16 + 0.3,
    h: IN(40),
    fontFace: FONT_MONO,
    fontSize: 11,
    bold: true,
    align: "center",
    valign: "middle",
    color: C.bg,
    fill: { color: deck.level },
    shape: "roundRect",
    rectRadius: 0.03,
  });
  slide.addText(topic || deck.title, {
    x: SLIDE_W / 2 - 3.5,
    y,
    w: 7,
    h: IN(64),
    fontFace: FONT_MONO,
    fontSize: 11,
    align: "center",
    valign: "middle",
    color: C.fgMuted,
  });
  slide.addText(time || deck.duration, {
    x: SLIDE_W - IN(48) - 2.5,
    y,
    w: 2.5,
    h: IN(64),
    fontFace: FONT_MONO,
    fontSize: 11,
    align: "right",
    valign: "middle",
    color: C.fgFaint,
  });
}

/* ---- term (ターミナル窓) ---- */
const TERM_LINE_COLORS = {
  u: C.fg,
  a: C.fgMuted,
  ok: C.green,
  ng: C.red,
  warn: C.yellow,
  dim: C.fgFaint,
};

export function termHeight(block) {
  return IN(48) + IN(40) + block.lines.length * IN(42);
}

export function renderTerm(slide, deck, block, x, y, w, h) {
  const headH = IN(48);
  slide.addShape("roundRect", {
    x,
    y,
    w,
    h,
    rectRadius: RADIUS,
    fill: { color: C.bgInset },
    line: { color: C.border, width: 1 },
  });
  for (let i = 0; i < 3; i++) {
    slide.addShape("ellipse", {
      x: x + 0.14 + i * 0.16,
      y: y + headH / 2 - 0.045,
      w: 0.09,
      h: 0.09,
      fill: { color: C.border },
    });
  }
  slide.addText(block.title, {
    x: x + 0.62,
    y,
    w: w - 0.75,
    h: headH,
    fontFace: FONT_MONO,
    fontSize: 9,
    color: C.fgFaint,
    valign: "middle",
  });
  slide.addShape("line", {
    x,
    y: y + headH,
    w,
    h: 0,
    line: { color: C.border, width: 0.75 },
  });
  const paras = block.lines.map((l) => {
    const color = TERM_LINE_COLORS[l.t] ?? C.fgMuted;
    const opts = {
      color,
      bold: l.t === "u",
      breakLine: true,
    };
    if (l.t === "u") {
      return [
        { text: "❯ ", options: { color: deck.level, bold: true } },
        { text: l.s, options: opts },
      ];
    }
    return [{ text: l.s || " ", options: opts }];
  });
  slide.addText(paras.flat(), {
    x: x + 0.22,
    y: y + headH + IN(14),
    w: w - 0.44,
    h: h - headH - IN(28),
    fontFace: FONT_MONO,
    fontSize: 11.5,
    valign: "top",
    lineSpacingMultiple: 1.35,
  });
}

/* ---- card ---- */
export function renderCard(slide, deck, item, x, y, w, h) {
  const highlight = item.highlight;
  slide.addShape("roundRect", {
    x,
    y,
    w,
    h,
    rectRadius: RADIUS,
    fill: { color: C.bgPanel },
    line: highlight
      ? { color: deck.level, width: 2 }
      : { color: C.border, width: 1 },
  });
  const paras = [];
  if (item.num) {
    paras.push([
      {
        text: item.num,
        options: {
          fontFace: FONT_MONO,
          fontSize: 11,
          bold: true,
          color: item.numColor ?? deck.level,
          breakLine: true,
          paraSpaceAfter: 6,
        },
      },
    ]);
  }
  if (item.title) {
    const runs = parseInline(item.title, deck.level, {
      color: C.fg,
    });
    runs.forEach((r) => {
      r.options.fontSize = 15;
      r.options.bold = true;
    });
    runs.at(-1).options.breakLine = true;
    runs.at(-1).options.paraSpaceAfter = 8;
    paras.push(runs);
  }
  // HTML と同じ出現順: 本文段落 → 箇条書き (→ note は常に最後)
  for (const p of item.body ? splitParagraphs(item.body) : []) {
    const runs = parseInline(p, deck.level, { color: C.fgMuted });
    runs.at(-1).options.breakLine = true;
    runs.at(-1).options.paraSpaceAfter = 8;
    paras.push(runs);
  }
  for (const li of item.list ?? []) {
    const runs = [
      { text: "· ", options: { color: deck.level, bold: true } },
      ...parseInline(li, deck.level, { color: C.fgMuted }),
    ];
    runs.at(-1).options.breakLine = true;
    runs.at(-1).options.paraSpaceAfter = 4;
    paras.push(runs);
  }
  if (item.note) {
    const runs = parseInline(item.note, deck.level, { color: C.fgMuted });
    runs.forEach((r) => (r.options.paraSpaceBefore = 12));
    paras.push(runs);
  }
  slide.addText(paras.flat(), {
    x: x + 0.2,
    y: y + 0.16,
    w: w - 0.4,
    h: h - 0.32,
    fontFace: FONT_BODY,
    fontSize: 12,
    valign: "top",
    lineSpacingMultiple: 1.25,
  });
}

export function renderCards(slide, deck, block, x, y, w, h) {
  const n = block.cols;
  const rows = Math.ceil(block.items.length / n);
  const cardW = (w - (n - 1) * GAP_MD) / n;
  const cardH = (h - (rows - 1) * GAP_MD) / rows;
  block.items.forEach((item, i) => {
    const cx = x + (i % n) * (cardW + GAP_MD);
    const cy = y + Math.floor(i / n) * (cardH + GAP_MD);
    renderCard(slide, deck, item, cx, cy, cardW, cardH);
  });
}

/* ---- timetable / 汎用 table ---- */
const noBorder = { type: "none" };
const rowBorder = [
  noBorder,
  noBorder,
  { type: "solid", color: C.border, pt: 0.5 },
  noBorder,
];

export function timetableHeight(block) {
  return IN(46) + block.rows.length * IN(52);
}

export function renderTimetable(slide, deck, block, x, y, w) {
  const head = ["TIME", "#", "トピック", "やること"].map((t) => ({
    text: t,
    options: {
      fontFace: FONT_MONO,
      fontSize: 10,
      bold: true,
      color: C.fgFaint,
      border: rowBorder,
    },
  }));
  const rows = block.rows.map((r) => {
    const italic = !!r.break;
    const base = { border: rowBorder, italic };
    return [
      {
        text: r.time,
        options: { ...base, fontFace: FONT_MONO, fontSize: 11, color: C.fgFaint },
      },
      {
        text: r.no ?? "—",
        options: {
          ...base,
          fontFace: FONT_MONO,
          fontSize: 12,
          bold: !!r.no,
          color: r.no ? deck.level : C.fgFaint,
        },
      },
      {
        text: r.topic,
        options: {
          ...base,
          fontSize: 12.5,
          color: italic ? C.fgFaint : C.fg,
        },
      },
      {
        text: r.desc ?? "",
        options: { ...base, fontSize: 12.5, color: italic ? C.fgFaint : C.fgMuted },
      },
    ];
  });
  slide.addTable([head, ...rows], {
    x,
    y,
    w,
    colW: [1.55, 0.7, 4.35, w - 1.55 - 0.7 - 4.35],
    fontFace: FONT_BODY,
    valign: "middle",
    margin: [4, 8, 4, 8],
    rowH: IN(52),
  });
}

export function tableHeight(block) {
  return IN(46) + block.rows.length * IN(88);
}

export function renderTable(slide, _deck, block, x, y, w) {
  const colW = block.colW ?? block.head.map(() => w / block.head.length);
  const head = block.head.map((t) => ({
    text: t,
    options: {
      fontFace: FONT_MONO,
      fontSize: 10,
      bold: true,
      color: C.fgFaint,
      border: rowBorder,
    },
  }));
  const rows = block.rows.map((cells) =>
    cells.map((cell, i) => ({
      text: cell,
      options: {
        border: rowBorder,
        fontSize: 12.5,
        color: i === 0 ? C.fg : C.fgMuted,
      },
    })),
  );
  slide.addTable([head, ...rows], {
    x,
    y,
    w,
    colW,
    fontFace: FONT_BODY,
    valign: "middle",
    margin: [6, 8, 6, 8],
  });
}

/* ---- panel ---- */
export function panelHeight(block, w) {
  const fontPx = block.fontPx ?? 26;
  const lines = estLines(stripTags(block.text), fontPx, w - 0.66);
  return lines * IN(fontPx * 1.8) + IN(48);
}

export function renderPanel(slide, _deck, block, x, y, w, h) {
  slide.addShape("roundRect", {
    x,
    y,
    w,
    h,
    rectRadius: RADIUS,
    fill: { color: C.bgPanel },
    line: { color: C.border, width: 1 },
  });
  slide.addText(parseInline(block.text, _deck.level, { color: C.fgMuted }), {
    x: x + 0.33,
    y: y + 0.1,
    w: w - 0.66,
    h: h - 0.2,
    fontFace: FONT_BODY,
    fontSize: (block.fontPx ?? 26) / 2,
    valign: "middle",
    lineSpacingMultiple: 1.4,
  });
}

/* ---- pass chip ---- */
export function passHeight() {
  return IN(60);
}

export function renderPass(slide, _deck, text, x, y) {
  const badgeW = 0.85;
  const w = Math.min(badgeW + textUnits(text) * 0.19 + 0.6, BODY_W);
  slide.addShape("roundRect", {
    x,
    y,
    w,
    h: IN(56),
    rectRadius: 0.05,
    fill: { color: mix(C.bg, C.green, 0.12) },
    line: { color: mix(C.bg, C.green, 0.45), width: 1 },
  });
  slide.addText("✓ PASS", {
    x: x + 0.14,
    y: y + IN(13),
    w: badgeW,
    h: IN(30),
    fontFace: FONT_MONO,
    fontSize: 10,
    bold: true,
    align: "center",
    valign: "middle",
    color: C.bg,
    fill: { color: C.green },
    shape: "roundRect",
    rectRadius: 0.03,
  });
  slide.addText(text, {
    x: x + badgeW + 0.24,
    y,
    w: w - badgeW - 0.3,
    h: IN(56),
    fontFace: FONT_MONO,
    fontSize: 12,
    bold: true,
    color: C.green,
    valign: "middle",
  });
}

/* ---- before / after ---- */
export function renderBeforeAfter(slide, _deck, pairs, x, y, w, h) {
  const arrowW = IN(60);
  const colW = (w - arrowW) / 2;
  const headH = 0.32;
  const n = pairs.length;
  const rowH = (h - headH - n * GAP_SM) / n;
  const heads = [
    { text: "BEFORE ── 受講前", color: C.red, cx: x },
    { text: "AFTER ── 受講後", color: C.green, cx: x + colW + arrowW },
  ];
  for (const hd of heads) {
    slide.addText(hd.text, {
      x: hd.cx,
      y,
      w: colW,
      h: headH,
      fontFace: FONT_MONO,
      fontSize: 12,
      bold: true,
      color: hd.color,
    });
  }
  pairs.forEach(([before, after], i) => {
    const ry = y + headH + GAP_SM + i * (rowH + GAP_SM);
    slide.addText(before, {
      x,
      y: ry,
      w: colW,
      h: rowH,
      shape: "roundRect",
      rectRadius: RADIUS,
      fill: { color: mix(C.bgPanel, C.red, 0.08) },
      line: { color: mix(C.bg, C.red, 0.25), width: 1 },
      fontFace: FONT_BODY,
      fontSize: 11.5,
      color: C.fgMuted,
      valign: "middle",
      margin: [4, 12, 4, 12],
      lineSpacingMultiple: 1.2,
    });
    slide.addText("→", {
      x: x + colW,
      y: ry,
      w: arrowW,
      h: rowH,
      fontFace: FONT_MONO,
      fontSize: 13,
      color: C.fgFaint,
      align: "center",
      valign: "middle",
    });
    slide.addText(after, {
      x: x + colW + arrowW,
      y: ry,
      w: colW,
      h: rowH,
      shape: "roundRect",
      rectRadius: RADIUS,
      fill: { color: mix(C.bgPanel, C.green, 0.08) },
      line: { color: mix(C.bg, C.green, 0.25), width: 1 },
      fontFace: FONT_BODY,
      fontSize: 11.5,
      color: C.fg,
      valign: "middle",
      margin: [4, 12, 4, 12],
      lineSpacingMultiple: 1.2,
    });
  });
}

/* ---- course map ---- */
const STAGES = [
  { key: "beginner", lv: "BEGINNER", color: C.green, name: "初級", desc: "基本ワークフローを一人で回す" },
  { key: "intermediate", lv: "INTERMEDIATE", color: C.cyan, name: "中級", desc: "Subagent / Skill / Hook / MCP を自作する" },
  { key: "advanced", lv: "ADVANCED", color: C.magenta, name: "上級", desc: "プロジェクトのハーネスとして統合設計する" },
];

export function courseMapHeight() {
  return 1.55;
}

export function renderCourseMap(slide, deck, current, x, y, w) {
  const arrowW = 0.4;
  const cardW = (w - 2 * arrowW - 2 * GAP_SM) / 3;
  const h = courseMapHeight();
  STAGES.forEach((s, i) => {
    const cx = x + i * (cardW + arrowW + GAP_SM);
    if (i > 0) {
      slide.addText("→", {
        x: cx - arrowW - GAP_SM / 2,
        y,
        w: arrowW,
        h,
        fontFace: FONT_MONO,
        fontSize: 17,
        color: C.fgFaint,
        align: "center",
        valign: "middle",
      });
    }
    const isCurrent = s.key === current;
    slide.addShape("roundRect", {
      x: cx,
      y,
      w: cardW,
      h,
      rectRadius: RADIUS,
      fill: { color: C.bgPanel },
      line: isCurrent
        ? { color: deck.level, width: 2 }
        : { color: C.border, width: 1 },
    });
    slide.addText(
      [
        {
          text: s.lv,
          options: {
            fontFace: FONT_MONO,
            fontSize: 10,
            bold: true,
            charSpacing: 1.5,
            color: s.color,
            breakLine: true,
            paraSpaceAfter: 6,
          },
        },
        {
          text: s.name,
          options: {
            fontSize: 15,
            bold: true,
            color: C.fg,
            breakLine: true,
            paraSpaceAfter: 6,
          },
        },
        { text: s.desc, options: { fontSize: 11.5, color: C.fgMuted } },
      ],
      {
        x: cx + 0.2,
        y: y + 0.14,
        w: cardW - 0.4,
        h: h - 0.28,
        fontFace: FONT_BODY,
        valign: "top",
        lineSpacingMultiple: 1.25,
      },
    );
  });
  return h;
}

/* ---- hero ---- */
export function renderHero(slide, deck, data) {
  slide.background = { color: C.bg };
  const titleLines = estLines(stripTags(data.title), 110, BODY_W);
  const subLines = estLines(data.sub, 36, BODY_W);
  const promptH = IN(56);
  const titleH = titleLines * IN(130);
  const subH = subLines * IN(58);
  const metaH = IN(56);
  const total = promptH + IN(24) + titleH + IN(24) + subH + IN(48) + metaH;
  let y = (SLIDE_H - IN(64) - total) / 2;

  slide.addText(
    [
      { text: "❯ ", options: { color: deck.level } },
      { text: "claude", options: { color: C.claude, bold: true } },
      { text: " █", options: { color: deck.level } },
    ],
    {
      x: PAD,
      y,
      w: BODY_W,
      h: promptH,
      fontFace: FONT_MONO,
      fontSize: 20,
      color: C.fgFaint,
      valign: "middle",
    },
  );
  y += promptH + IN(24);
  slide.addText(parseInline(data.title, deck.level, { color: C.fg }), {
    x: PAD,
    y,
    w: BODY_W,
    h: titleH,
    fontFace: FONT_BODY,
    fontSize: 55,
    bold: true,
    valign: "top",
    lineSpacingMultiple: 1.1,
  });
  y += titleH + IN(24);
  slide.addText(data.sub, {
    x: PAD,
    y,
    w: BODY_W,
    h: subH,
    fontFace: FONT_BODY,
    fontSize: 18,
    color: C.fgMuted,
    valign: "top",
    lineSpacingMultiple: 1.4,
  });
  y += subH + IN(48);
  let cx = PAD;
  for (const m of data.meta) {
    const w = textUnits(m) * 0.16 + 0.5;
    slide.addText(m, {
      x: cx,
      y,
      w,
      h: metaH,
      shape: "roundRect",
      rectRadius: IN(28),
      line: { color: C.border, width: 1 },
      fill: { color: C.bg },
      fontFace: FONT_MONO,
      fontSize: 11,
      color: C.fgMuted,
      align: "center",
      valign: "middle",
    });
    cx += w + GAP_SM;
  }
  renderStatusBar(slide, deck, "", "");
}

/* ---- スライド全体の組み立て ---- */
function blockFixedHeight(block, w) {
  switch (block.k) {
    case "term":
      return termHeight(block);
    case "timetable":
      return timetableHeight(block);
    case "table":
      return tableHeight(block);
    case "panel":
      return panelHeight(block, w);
    case "pass":
      return passHeight();
    case "courseMap":
      return courseMapHeight();
    default:
      return null; // flex: cards / cols / beforeAfter
  }
}

function renderBlock(slide, deck, block, x, y, w, h) {
  switch (block.k) {
    case "term":
      renderTerm(slide, deck, block, x, y, w, h);
      break;
    case "timetable":
      renderTimetable(slide, deck, block, x, y, w);
      break;
    case "table":
      renderTable(slide, deck, block, x, y, w);
      break;
    case "panel":
      renderPanel(slide, deck, block, x, y, w, h);
      break;
    case "pass":
      renderPass(slide, deck, block.text, x, y);
      break;
    case "courseMap":
      renderCourseMap(slide, deck, block.current, x, y, w);
      break;
    case "cards":
      renderCards(slide, deck, block, x, y, w, h);
      break;
    case "card":
      renderCard(slide, deck, block, x, y, w, h);
      break;
    case "beforeAfter":
      renderBeforeAfter(slide, deck, block.pairs, x, y, w, h);
      break;
    case "cols": {
      const n = block.items.length;
      const colW = (w - (n - 1) * GAP_MD) / n;
      block.items.forEach((item, i) => {
        renderBlock(slide, deck, item, x + i * (colW + GAP_MD), y, colW, h);
      });
      break;
    }
    default:
      throw new Error(`unknown block: ${block.k}`);
  }
}

export function renderSlide(pptx, deck, def) {
  const slide = pptx.addSlide();
  if (def.type === "hero") {
    renderHero(slide, deck, def);
    return;
  }
  slide.background = { color: C.bg };
  renderPromptLine(slide, deck, def.prompt, IN(88));
  let y = IN(150);
  y += renderTitle(slide, deck, def.title, y) + IN(64);
  if (def.badge) {
    y += renderBadge(slide, deck, def.badge, y) + GAP_MD;
  }
  const bodyH = BODY_BOTTOM - y;
  const blocks = def.body;
  const gaps = (blocks.length - 1) * GAP_MD;
  const fixed = blocks.map((b) => blockFixedHeight(b, BODY_W));
  const flexCount = fixed.filter((h) => h === null).length;
  const flexH =
    flexCount > 0
      ? (bodyH - gaps - fixed.reduce((a, h) => a + (h ?? 0), 0)) / flexCount
      : 0;
  blocks.forEach((block, i) => {
    const h = fixed[i] ?? flexH;
    renderBlock(slide, deck, block, PAD, y, BODY_W, h);
    y += h + GAP_MD;
  });
  renderStatusBar(slide, deck, def.topic, def.time);
}

export function buildDeck(pptx, deck, slides) {
  for (const def of slides) renderSlide(pptx, deck, def);
}
