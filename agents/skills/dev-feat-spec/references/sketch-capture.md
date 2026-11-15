# UI スケッチを直して画面のスクリーンショットを PR に載せる

- 種別: 手順書
- 読み手: 設計 PR を出す dev-feat-spec (設計モードの手順 4・6・7、直しのモードの手順 3〜5)
- 生成するもの: `docs/design/UI_SKETCH.html` の変更と、変更前・変更後の画面の png (`<SCRATCH>/issue-<N>/screens/`)
- 消費者: 設計 PR をレビューする人 (PR の本文「画面の変化」で画像を見る)、手順 6 の検査の subagent

設計で画面が変わるときは、`docs/design/UI_SKETCH.html` を設計どおりに直し、変わる画面の変更前と変更後をスクリーンショットにして PR の本文に貼る。レビューする人は、設計書を読まずに見た目の変化を画像でつかめる。テキストの図は全角と罫線の表示幅で崩れて読みにくいので使わない。画像の添付は `workflow-create-pr` と同じく `gh pr create --attach` で行う。

## 使えるか確かめる

```bash
ls docs/design/UI_SKETCH.html
gh --version | head -1
```

- `UI_SKETCH.html` が無い (cli モードのプロジェクトなど) ときは、スケッチを新しく作らない。PR の「画面の変化」は、どの画面のどこに何が増える・変わるかを、画面の表示語で文章に書く
- gh の版が 2.99.0 未満なら `--attach` が無い。スケッチは直すが、PR には画像を貼らず、「画面の変化」を文章で書いて、末尾に「スクリーンショットは gh <版> が添付に対応していないため載せていない」と書く。画像の参照をローカルのパスのまま本文に残さない (ローカルのパスが PR に載るため)
- Node.js と npm が要る。Playwright は撮影のスクリプトが初回にキャッシュへ入れる

## スケッチの口

撮影のスクリプト (`scripts/capture-sketch.sh`) は、スケッチに次の 2 つがあることを前提にする。

1. **`#screen=<画面 ID>` で開くと、その画面を描く。** 画面 ID はスケッチの画面一覧が持つ ID である (例: `admin-products`)
2. **描いた画面を包む要素に `data-sketch-screen="<描いた画面の ID>"` を付ける。** 知らない ID を渡されてスケッチが既定の画面に落ちたときは、渡された ID ではなく既定の画面の ID を出す。スクリプトは渡した ID の要素を待つので、知らない ID は時間切れで失敗し、別の画面を撮って成功したことにならない

React で画面を切り替えるスケッチ (`dev-spec` の `references/ui-sketch.md` の手順で作るもの) なら、次の 2 か所を直せば口ができる。

```jsx
const [screen, setScreen] = useState(
  () => new URLSearchParams(location.hash.slice(1)).get("screen") ?? "login",
);

<div data-sketch-screen={VIEWS[screen] ? screen : "login"}>
  <View />
</div>
```

`VIEWS` (画面 ID から画面のコンポーネントを引く表) と既定の画面 `login` は、そのスケッチの名前に合わせる。

**操作で出る状態は、別の画面 ID として持たせる。** モーダルを開いた状態、保存を拒否されてエラーが出た状態、一覧が 0 件の状態などは、`<画面 ID>--<状態>` (例: `admin-products--add-modal`) の画面としてスケッチの画面一覧に足し、その状態を最初から描く。撮影のスクリプトはボタンを押さない。スケッチのボタンには処理の無いものが多く、押しても状態が変わらないまま撮れてしまうためである。

## 手順

画像は `<SCRATCH>/issue-<N>/screens/` に置き、リポジトリの中には置かない (コミットに混ざるため)。ファイル名は `before-<slug>.png` / `after-<slug>.png` で、slug は英小文字・数字・`-` だけにする (日本語や括弧を入れると、本文の画像参照が壊れることがある)。撮るのは変わる画面と、変わる状態だけにする。

### 1. 口と、いまの画面をスケッチに足す (無いときだけ)

スケッチに口が無いか、変わる画面がスケッチに無いときは、設計の変更を入れる前に足す。

- 口が無ければ、上の「スケッチの口」の 2 か所を足す
- 変わる画面が無ければ、いまの実装 (画面のコンポーネント) を読み、いまの見た目と文言のとおりにスケッチへ足す。クラスと部品の名前は実装の UI の語彙からそのまま写す (`dev-spec` の `references/ui-sketch.md`「5.0 既存の UI 語彙の取り込み」)。設計で足す要素はまだ入れない

足したら、設計の変更とは別のコミットにする (`📝 docs: [STRUCTURAL] UI スケッチに <画面名> を足す` など)。いまの画面を写しただけで、設計の判断を含まないためである。このコミットは手順 7 の push で設計の変更と一緒に出る。

### 2. 変更前を撮る

設計の変更を入れる前のスケッチで、変わる画面と状態を撮る。

```bash
~/.claude/skills/dev-feat-spec/scripts/capture-sketch.sh docs/design/UI_SKETCH.html <画面 ID> <SCRATCH>/issue-<N>/screens/before-<slug>.png
```

新しく作る画面には変更前が無いので撮らない。

### 3. スケッチを設計どおりに直す

機能設計書の「入出力と振る舞い」に書いた操作と画面に起きることを、スケッチに写す。

- 変わる画面を直す。ボタン・見出し・入力欄の名前と、案内・エラーの文言は、機能設計書に書いたものと同じにする
- 機能設計書の表に書いた状態のうち、レビューで見てほしいもの (モーダル・エラーの表示など) を `<画面 ID>--<状態>` の画面として足す
- スケッチの冒頭に変更履歴のコメントを書くプロジェクトでは、同じ形で 1 行足す

### 4. 変更後を撮る

```bash
~/.claude/skills/dev-feat-spec/scripts/capture-sketch.sh docs/design/UI_SKETCH.html <画面 ID> <SCRATCH>/issue-<N>/screens/after-<slug>.png
```

スクリプトは画面を包む要素だけを撮る。幅は 1280 px で、スマートフォン向けの画面は第 4 引数に `390` を渡す。終了コードが 0 でなければ、出力の 1 行目で原因を見る。

| 出力 | 原因 | 直し方 |
| --- | --- | --- |
| `TimeoutError: locator.waitFor` | 画面 ID がスケッチに無い、口が無い、またはスケッチが描画の前に壊れた | 画面 ID と口を確かめる。ブラウザで `#screen=<ID>` を付けて開くと、どこで止まるかが見える |
| `page error: ...` | スケッチの JavaScript が例外を投げた | スケッチを直す。エラーの出たまま撮った画像は使わない |
| `Executable doesn't exist` | Chromium が無い | `npx playwright@1.65.1 install chromium` |

### 5. 画像を開いて確かめる

撮った png をすべて Read で開き、次を確かめる。

- 変更前と変更後で、設計で変えた箇所が見て分かる (足したボタン、開いたモーダル、出したエラーなど)
- 文言が機能設計書と同じである
- 表示が崩れていない (文字の重なり、はみ出し、読み込みの途中の画面)

確かめられなければ、スケッチを直して撮り直す。

## PR の本文に載せる

「画面の変化」の節に、変わる画面ごとに小見出しを立て、変更前と変更後の画像を縦に並べる。表のセルには画像を入れない (gh が表の中の画像参照も書き換えるかは確かめていない)。画像参照のパスは png の絶対パスをそのまま書く。PR を作るときに同じパスを `--attach` に渡すと、gh がアップロード先の URL に書き換える。alt には画面名と状態を書き、`|` と `]` は全角にする。

```markdown
## 画面の変化

### 商品一覧 (管理者)

変更前:

![商品一覧 (変更前)](/abs/scratch/issue-12/screens/before-admin-products.png)

変更後: 「商品を追加」のボタンが増える。

![商品一覧 (変更後)](/abs/scratch/issue-12/screens/after-admin-products.png)

### 商品を追加 (新しいモーダル)

![商品を追加のモーダル](/abs/scratch/issue-12/screens/after-admin-products-add-modal.png)
```

各画像の前に、何が変わったかを 1 文で書く。画像だけでは、どこを見ればよいかが伝わらないためである。

## 添付して PR を作る

本文を書き出したら、本文の画像参照と添付するファイルが一致することを確かめる。一致しないと、添付されなかったローカルのパスが PR に残る。

```bash
rg -o '!\[[^]]*\]\(([^)]+)\)' -r '$1' <PR の本文のファイル> | sort
ls <SCRATCH>/issue-<N>/screens/*.png | sort
# 2 つの出力が同じであること
```

PR は撮った png を全件、1 つずつ `--attach` に渡して作る。

```bash
gh pr create --repo "$REPO_SLUG" --base "$DEFAULT" --head design/issue-<N> \
  --title "<タイトル>" --body-file <PR の本文のファイル> \
  --attach <before-...png> --attach <after-...png>
```

作ったら本文を読み直し、ローカルのパスが残っていないことを確かめる。

```bash
gh pr view <PR 番号> --repo "$REPO_SLUG" --json body -q .body | rg -n '!\[[^]]*\]\(/'
# 何も出なければよい
```

何か出たら、添付に失敗した画像がある。`gh pr edit <PR 番号> --repo "$REPO_SLUG" --body-file <PR の本文のファイル> --attach <png>...` で 1 回だけやり直す。それでも残れば、残った画像参照を「(スクリーンショットの添付に失敗した: <画面名>)」の 1 行に置き換えて `gh pr edit --body-file` で書き戻し、最終報告に書く。ローカルのパスを PR に残したままにしない。

## 直しのモード

指摘でスケッチを直したときは、手順 3〜5 をやり直して変更後を撮り直す (変更前は撮り直さない)。PR の本文の画像参照を新しい png の絶対パスに書き換え、`gh pr edit <PR 番号> --repo "$REPO_SLUG" --body-file <PR の本文のファイル> --attach <png>...` で更新する。更新した後も、上と同じコマンドでローカルのパスが残っていないことを確かめる。直しのモードのセッションには設計時の `<SCRATCH>` が無いので、変更前の画像は撮り直さず、本文に貼られている画像 (アップロード先の URL) をそのまま残す。

## 依拠する外部事実

| 事実 | 確認元 | 確認日 |
| --- | --- | --- |
| `gh pr create --attach` は 2.99.0 から使え、本文の `![alt](<path>)` のうち添付と同じファイルを指す参照をアップロード先の URL に書き換える | `workflow-create-pr` の SKILL.md「添付できる gh か」「gh pr create の実行」 | 2026-11-16 に同書を読んだ |
| `gh pr edit --attach` も本文の画像参照をアップロード先の URL (`https://github.com/user-attachments/assets/...`) に書き換える | gh 2.103.3 で、既存の設計 PR の本文を 3 枚の画像つきで差し替え、本文にローカルのパスが残らないことを `gh pr view --json body` で確かめた | 2026-11-16 |
| 撮影のスクリプトは、口のあるスケッチの既知の画面 ID で exit 0 になり、知らない画面 ID・口の無いスケッチ・ページの例外で exit 1 になる | 業務アプリのスケッチ (React 19 + Tailwind の CDN 版、約 210 KB) の写しで実行 (既知の ID は約 4 秒で撮影) | 2026-11-16 |
| Playwright 1.65.1 は、`utility-nvim-ui-capture` と同じ版で、ダウンロード済みの Chromium を共有する | `utility-nvim-ui-capture/scripts/nvim-ui-capture.sh` の `playwright@1.65.1` | 2026-11-16 |
