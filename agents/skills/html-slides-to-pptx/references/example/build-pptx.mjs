// ビルドエントリの例: デッキデータを pptx に書き出す
// (実際の変換では対象デッキ分の deck-*.mjs を作って並べる)
import PptxGenJS from "pptxgenjs";
import { buildDeck } from "./pptx-helpers.mjs";
import * as beginner from "./deck-beginner.mjs";

for (const { deck, slides } of [beginner]) {
  const pptx = new PptxGenJS();
  pptx.defineLayout({ name: "WIDE", width: 13.333, height: 7.5 });
  pptx.layout = "WIDE";
  pptx.title = deck.title;
  buildDeck(pptx, deck, slides);
  const out = `./claude-code-${deck.id}.pptx`;
  await pptx.writeFile({ fileName: out });
  console.log(`wrote ${out} (${slides.length} slides)`);
}
