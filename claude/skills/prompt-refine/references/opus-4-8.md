<!--
取得元: https://platform.claude.com/docs/ja/build-with-claude/prompt-engineering/prompting-claude-opus-4-8.md
取得日: 2026-07-15
-->

# Claude Opus 4.8 のプロンプティング

Claude Opus 4.8 の動作の違いとプロンプティングパターンについて、冗長性、エフォートの調整、ツール使用、サブエージェント、フロントエンドのデフォルトを解説します。

---

このガイドでは、Claude Opus 4.8 に固有のプロンプティングパターンについて説明します。モデルの機能と API の変更点については、[Claude Opus 4.8 の新機能](/docs/ja/about-claude/models/whats-new-claude-4-8)を参照してください。現在のすべての Claude モデルに適用される手法については、[プロンプティングのベストプラクティス](/docs/ja/build-with-claude/prompt-engineering/claude-prompting-best-practices)を参照してください。

Claude Opus 4.8 は、長期的なエージェント作業、ナレッジワーク、ビジョン、メモリタスクにおいて特に優れた強みを持っています。既存の Claude Opus 4.7 向けプロンプトでもそのまま良好に動作します。以下のパターンでは、調整が必要になることが最も多い動作について説明します。

<Note>
  Claude Opus 4.7 から移行する際の API パラメータの変更点（サンプリングパラメータ、エフォートのデフォルト、100万トークンのコンテキストウィンドウのデフォルト、会話途中のシステムメッセージ、拒否時の停止詳細）については、[移行ガイド](/docs/ja/about-claude/models/migration-guide#migrating-from-claude-opus-47)を参照してください。
</Note>

## 応答の長さと冗長性

Claude Opus 4.8 は、固定の冗長性をデフォルトとするのではなく、タスクの複雑さをどう判断するかに基づいて応答の長さを調整します。これは通常、単純な検索では短い回答になり、オープンエンドな分析でははるかに長い回答になることを意味します。

プロダクトが特定のスタイルや出力の冗長性に依存している場合は、プロンプトの調整が必要になることがあります。例として、冗長性を減らすには、次のように追加できます。

```text wrap
Provide concise, focused responses. Skip non-essential context, and keep examples minimal.
```

特定の種類の冗長性（過剰な説明など）の具体例が見られる場合は、それを防ぐための追加の指示をプロンプトに加えることができます。適切な簡潔さで Claude がどのようにコミュニケーションできるかを示すポジティブな例は、モデルに何をしてはいけないかを伝えるネガティブな例や指示よりも効果的な傾向があります。

## エフォートと思考の深さの調整

[effort パラメータ](/docs/ja/build-with-claude/effort)を使用すると、Claude の知能とトークン消費のバランスを調整し、能力と引き換えに速度向上とコスト削減を実現できます。コーディングやエージェント的なユースケースでは `xhigh` エフォートレベルから始め、知能が重要なほとんどのユースケースでは最低でも `high` エフォートを使用してください。他のエフォートレベルも試して、トークン使用量と知能をさらに調整してください。

* **`max`：** max エフォートは一部のユースケースでパフォーマンス向上をもたらすことがありますが、トークン使用量の増加に対して収穫逓減が見られる場合があります。この設定は、過剰思考に陥りやすいこともあります。知能を要求するタスクで max エフォートをテストしてください。
* **`xhigh`：** extra high エフォートは、ほとんどのコーディングおよびエージェント的なユースケースに最適な設定です。
* **`high`：** この設定はトークン使用量と知能のバランスを取ります。知能が重要なほとんどのユースケースでは、最低でも `high` エフォートを使用してください。
* **`medium`：** 知能をある程度犠牲にしてトークン使用量を削減する必要がある、コスト重視のユースケースに適しています。
* **`low`：** 短く範囲が限定されたタスクや、知能をあまり必要としないレイテンシ重視のワークロード向けに確保してください。

Claude Opus 4.8 は、特に低いレベルにおいてエフォートレベルを厳密に尊重します。`low` および `medium` では、モデルは求められた以上のことをするのではなく、依頼された範囲に作業を限定します。これはレイテンシとコストの面で有利ですが、`low` エフォートで実行される中程度に複雑なタスクでは、思考不足のリスクがある程度あります。

複雑な問題で浅い推論が見られる場合は、プロンプトで回避しようとするのではなく、エフォートを `high` または `xhigh` に上げてください。レイテンシのためにエフォートを `low` に保つ必要がある場合は、的を絞ったガイダンスを追加してください。

```text wrap
This task involves multi-step reasoning. Think carefully through the problem before responding.
```

エフォートは、これまでのどの Opus よりもこのモデルにとって重要になる可能性が高いため、アップグレード時には積極的に試してください。

Claude Opus 4.8 では、`thinking: {type: "adaptive"}` を明示的に設定しない限り、思考はオフになっています。適応的思考のトリガー動作は誘導可能です。モデルが望む以上に頻繁に思考していることに気づいた場合（大規模または複雑なシステムプロンプトで発生することがあります）、ガイダンスを追加して誘導してください。いつものように、プロンプト変更がパフォーマンスに与える影響を測定してください。例：

```text wrap
Thinking adds latency and should only be used when it will meaningfully improve answer quality — typically for problems that require multi-step reasoning. When in doubt, respond directly.
```

逆に、`medium` で難しいワークロードを実行していて思考不足が見られる場合、最初のレバーはエフォートを上げることです。より細かい制御が必要な場合は、直接プロンプトで指示してください。

<Note>
  Claude Opus 4.8 を `max` または `xhigh` エフォートで実行する場合は、モデルがサブエージェントやツール呼び出し全体で思考し行動する余地を持てるように、大きな最大出力トークン予算を設定してください。64k トークンから始めて、そこから調整してください。
</Note>

## ツール使用のトリガー

Claude Opus 4.8 は、ツール呼び出しよりも推論を優先する傾向があります。これはほとんどの場合、より良い結果を生み出します。ただし、エフォート設定を上げることは、特にナレッジワークにおいてツール使用のレベルを高めるための有効なレバーです。`high` または `xhigh` のエフォート設定では、エージェント的な検索やコーディングにおいてツール使用が大幅に増加します。より多くのツール使用を望むシナリオでは、いつどのようにツールを適切に使用すべきかをモデルに明示的に指示するようにプロンプトを調整することもできます。たとえば、モデルがウェブ検索ツールを使用していないことに気づいた場合は、なぜ、どのように使用すべきかを明確に記述してください。

## ユーザー向けの進捗更新

Claude Opus 4.8 は、長いエージェント的なトレース全体を通じて、より定期的で高品質な更新をユーザーに提供します。中間ステータスメッセージを強制するスキャフォールディング（「ツール呼び出し3回ごとに進捗を要約する」など）を追加している場合は、それを削除してみてください。Claude Opus 4.8 のユーザー向け更新の長さや内容がユースケースに適切に調整されていないと感じる場合は、これらの更新がどのようなものであるべきかをプロンプトで明示的に記述し、例を提供してください。

## より文字通りの指示追従

Claude Opus 4.8 は、特に低いエフォートレベルにおいて、プロンプトを文字通りかつ明示的に解釈します。ある項目への指示を別の項目に暗黙的に一般化することはなく、明示されていないリクエストを推測することもありません。この文字通りの解釈の利点は精度の高さと無駄な試行錯誤の少なさであり、慎重に調整されたプロンプト、構造化抽出、予測可能な動作が求められるパイプラインを伴う API ユースケースでは一般的により良いパフォーマンスを発揮します。Claude に指示を広く適用させる必要がある場合は、範囲を明示的に述べてください（例：「このフォーマットを最初のセクションだけでなく、すべてのセクションに適用してください」）。

## トーンと文体

新しいモデルと同様に、長文執筆における文体は変化する可能性があります。Claude Opus 4.8 は、直接的で意見のはっきりしたスタイルを好む傾向があり、肯定を前面に出した言い回しは最小限で、絵文字の使用も控えめです。プロダクトが特定のボイスに依存している場合は、新しいベースラインに対してスタイルプロンプトを再評価してください。

たとえば、プロダクトのボイスがより温かみのある、または会話的なものである場合は、次のように追加します。

```text wrap
Use a warm, collaborative tone. Acknowledge the user's framing before answering.
```

## サブエージェント生成の制御

Claude Opus 4.8 は、デフォルトで生成するサブエージェントの数が少ない傾向があります。ただし、この動作はプロンプティングによって誘導可能です。サブエージェントが望ましい場合について、Claude Opus 4.8 に明示的なガイダンスを与えてください。コーディングユースケースの簡単な例：

```text wrap
Do not spawn a subagent for work you can complete directly in a single response (e.g. refactoring a function you can already see).

Spawn multiple subagents in the same turn when fanning out across items or reading multiple files.
```

## デザインとフロントエンドのデフォルト

Claude Opus 4.8 は優れたデザインセンスを持ち、一貫したデフォルトのハウススタイルがあります。温かみのあるクリーム/オフホワイトの背景（約 `#F4F1EA`）、セリフ体の見出しフォント（Georgia、Fraunces、Playfair）、イタリック体の単語アクセント、テラコッタ/アンバーのアクセントカラーです。これはエディトリアル、ホスピタリティ、ポートフォリオの案件には適していますが、ダッシュボード、開発ツール、フィンテック、ヘルスケア、エンタープライズアプリには違和感があります。このデフォルトはスライドデッキやウェブ UI に現れます。

このデフォルトは根強いものです。一般的な指示（「クリーム色を使わないで」「クリーンでミニマルにして」）は、多様性を生み出すのではなく、モデルを別の固定パレットに移行させる傾向があります。確実に機能するアプローチは2つあります。

**1. 具体的な代替案を指定する。** モデルは明示的な仕様に正確に従います。

```text wrap
Design a desktop landing page for a supplement brand called AEFRM.

The visual direction should come from a cold monochrome atmosphere using pale silver-gray tones that gradually deepen into blue-gray and near-black, similar to a misted metallic surface.

The page should feel sharp and controlled, with a strong sense of structure and restraint.

Use this tonal system across the full page instead of introducing bright accent colors.

Use the uploaded image on the hero design in black and white.

The layout should be built with clear horizontal sections and a centered max-width container. Use 4px corner radius consistently across cards, buttons, inputs, and media frames. Margins should feel generous, with enough empty space around each section so the page breathes.

Typography should use a square, angular sans-serif with wider letter spacing than usual, especially in headings and navigation, so the text feels more engineered and less compressed. Headline text can be large and uppercase, while supporting copy remains short and sparse. The sub texts should be written with Alumni Sans SC in 4-6px like tiny little texts on corners bottom centre like that.

For the structure, start with a hero section containing a strong product statement, one short supporting paragraph, and a clean product placeholder or packshot frame. Below that, add a benefit grid with three or four blocks, then a formulation or ingredients section, and finally a cta.

Buttons should be flat and precise, with subtle hover changes using transition: all 160ms ease out where brightness and border contrast shift slightly rather than using dramatic motion.

Color palette should stay within this range:
#E9ECEC, #C9D2D4, #8C9A9E, #44545B, #11171B.
```

**2. 構築前にモデルに選択肢を提案させる。** これによりデフォルトが打破され、ユーザーに制御権が与えられます。以前デザインの多様性のために `temperature` に依存していた場合は、このアプローチを使用してください。実行ごとに意味のある異なる方向性が生成されます。プロンプト例：

```text wrap
Before building, propose 4 distinct visual directions tailored to this brief (each as: bg hex / accent hex / typeface — one-line rationale). Ask the user to pick one, then implement only that direction.
```

さらに、Claude Opus 4.8 は、ユーザーが「AI slop」的な美学と呼ぶ汎用的なパターンを避けるために、以前のモデルよりも少ないフロントエンドデザインプロンプティングで済みます。以前のモデルでは、Anthropic は [frontend-design スキル](https://github.com/anthropics/claude-code/blob/main/plugins/frontend-design/skills/frontend-design/SKILL.md)でより長いプロンプトスニペットを推奨していました。しかし、Claude Opus 4.8 は、より最小限のプロンプティングガイダンスで独特で創造的なフロントエンドを生成します。このプロンプトスニペットは、前述の多様性のためのプロンプティングアドバイスと組み合わせるとうまく機能します。

```text wrap
<frontend_aesthetics>
NEVER use generic AI-generated aesthetics like overused font families (Inter, Roboto, Arial, system fonts), cliched color schemes (particularly purple gradients on white or dark backgrounds), predictable layouts and component patterns, and cookie-cutter design that lacks context-specific character. Use unique fonts, cohesive colors and themes, and animations for effects and micro-interactions.
</frontend_aesthetics>
```

## インタラクティブなコーディングプロダクト

Claude Opus 4.8 のトークン使用量と動作は、単一のユーザーターンを持つ自律的・非同期的なコーディングエージェントと、複数のユーザーターンを持つインタラクティブ・同期的なコーディングエージェントとで異なる場合があります。具体的には、インタラクティブな設定ではより多くのトークンを使用する傾向があり、これは主にユーザーターンの後により多く推論するためです。これにより、長いインタラクティブなコーディングセッションにおける長期的な一貫性、指示追従、コーディング能力が向上しますが、トークン使用量も増加します。コーディングプロダクトでパフォーマンスとトークン効率の両方を最大化するには、`xhigh` または `high` エフォートを使用し、オートモードなどの自律的な機能を追加し、ユーザーに必要な人間のインタラクション数を減らしてください。

もちろん、必要なユーザーインタラクション数を制限する場合は、最初の人間のターンでタスク、意図、関連する制約を事前に指定することが重要です。明確で正確なタスク記述を事前に提供することで、ユーザーターン後の余分なトークン使用を最小限に抑えながら、自律性と知能を最大化できます。Claude Opus 4.8 は以前のモデルよりも自律的であるため、この使用パターンはパフォーマンスを最大化するのに役立ちます。対照的に、複数のユーザーターンにわたって段階的に伝えられる曖昧または不十分に指定されたプロンプトは、相対的にトークン効率を低下させ、場合によってはパフォーマンスも低下させる傾向があります。

## コードレビューハーネス

Claude Opus 4.8 は、以前のモデルよりもバグの発見が大幅に優れており、内部評価では再現率と適合率の両方が高くなっています。ただし、コードレビューハーネスが以前のモデル向けに調整されていた場合、最初は再現率が低く見えることがあります。これはハーネスの影響である可能性が高く、能力の低下ではありません。レビュープロンプトに「重大度の高い問題のみを報告する」「保守的に」「細かい指摘はしない」などの記述がある場合、Claude Opus 4.8 は以前のモデルよりもその指示に忠実に従う可能性があります。コードを同じくらい徹底的に調査し、バグを特定しても、指定された基準を下回ると判断した発見を報告しないことがあります。これは、モデルが同じ深さの調査を行いながらも、特に重大度の低いバグについて、調査を報告された発見に変換する割合が少なくなるという形で現れることがあります。適合率は通常上昇しますが、モデルの根本的なバグ発見能力が向上しているにもかかわらず、測定される再現率は低下する可能性があります。

推奨されるプロンプト文言：

```text wrap
Report every issue you find, including ones you are uncertain about or consider low-severity. Do not filter for importance or confidence at this stage - a separate verification step will do that. Your goal here is coverage: it is better to surface a finding that later gets filtered out than to silently drop a real bug. For each finding, include your confidence level and an estimated severity so a downstream filter can rank them.
```

このプロンプトは実際の第2ステップがなくても使用できますが、信頼度フィルタリングを発見ステップから切り離すことが役立つことが多いです。ハーネスに別個の検証、重複排除、またはランキングステージがある場合は、発見ステージでのモデルの役割はフィルタリングではなくカバレッジであることを明示的に伝えてください。

モデルに単一パスで自己フィルタリングさせたい場合は、「重要」のような定性的な用語を使用するのではなく、基準がどこにあるかを具体的に示してください。例：「不正な動作、テストの失敗、または誤解を招く結果を引き起こす可能性のあるバグはすべて報告してください。純粋なスタイルや命名の好みなどの細かい指摘のみを省略してください。」

評価やテストケースのサブセットに対してプロンプトを反復し、再現率または F1 スコアの向上を検証してください。

## コンピュータ使用

[コンピュータ使用](/docs/ja/agents-and-tools/tool-use/computer-use-tool)機能は、最大解像度 2576px / 3.75MP までのさまざまな解像度で動作します。内部のコンピュータ使用テストでは、1080p で画像を送信することがパフォーマンスとコストの良いバランスを提供することが示されています。

特にコスト重視のワークロードでは、720p または 1366×768 が、優れたパフォーマンスを持つ低コストのオプションです。ユースケースに最適な設定を見つけるために独自のテストを実施してください。エフォート設定を試すことも、モデルの動作を調整するのに役立ちます。
