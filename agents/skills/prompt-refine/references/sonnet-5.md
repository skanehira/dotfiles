<!--
取得元: https://platform.claude.com/docs/ja/build-with-claude/prompt-engineering/prompting-claude-sonnet-5.md
取得日: 2026-07-15
-->

# Claude Sonnet 5のプロンプティング

Claude Sonnet 5の動作の違いとプロンプティングパターン。effort、適応的思考のデフォルト、ツール使用、Claude Sonnet 4.6からの移行について説明します。

---

このガイドでは、Claude Sonnet 5に固有のプロンプティングパターンについて説明します。モデルの機能とAPIの変更については、[Claude Sonnet 5の新機能](/docs/ja/about-claude/models/whats-new-sonnet-5)を参照してください。現行のすべてのClaudeモデルに適用されるテクニックについては、[プロンプティングのベストプラクティス](/docs/ja/build-with-claude/prompt-engineering/claude-prompting-best-practices)を参照してください。

Claude Sonnet 5は、コーディングとエージェント的なタスクに特に強みがあります。既存のClaude Sonnet 4.6のプロンプトでもそのまま良好に動作します。このガイドのパターンは、最も頻繁に調整が必要となる動作をカバーしています。

<Note>
  Claude Sonnet 4.6から移行する際のAPIパラメータの変更（適応的思考がデフォルトで有効、サンプリングパラメータが受け付けられない、手動の拡張思考の削除、新しいトークナイザー）については、[移行ガイド](/docs/ja/about-claude/models/migration-guide#migrating-from-claude-sonnet-4-6-to-claude-sonnet-5)を参照してください。
</Note>

## 応答の長さと冗長性

Claude Sonnet 5は、固定された冗長性をデフォルトとするのではなく、タスクの複雑さに応じて応答の長さを調整します。これは通常、単純な検索では短い回答、自由度の高い分析では長い回答になることを意味します。

プロダクトが特定のスタイルや出力の冗長性に依存している場合は、プロンプトの調整が必要になることがあります。例として、冗長性を減らすには、次のように追加できます。

```text wrap
Provide concise, focused responses. Skip non-essential context, and keep examples minimal.
```

特定の種類の冗長性（過剰な説明など）が見られる場合は、それを防ぐための追加の指示をプロンプトに加えることができます。Claudeが適切なレベルの簡潔さでコミュニケーションする方法を示すポジティブな例は、モデルに何をしてはいけないかを伝えるネガティブな例や指示よりも効果的である傾向があります。

## effortと思考の深さの調整

[effortパラメータ](/docs/ja/build-with-claude/effort)を使用すると、Claudeの知能とトークン消費のバランスを調整し、能力と引き換えに速度の向上とコストの削減を図ることができます。Claude Sonnet 5では、effortはClaude Sonnet 4.6と同じく`high`がデフォルトです。最も難しいコーディングやエージェント的なタスクでは、effortを`xhigh`に上げてください。トークン使用量と知能をさらに調整するには、他のeffortレベルを試してみてください。

* **`max`:** トークン消費に制約のない、絶対的な最大能力。
* **`xhigh`:** 特に高いeffortは、最も難しいコーディングおよびエージェント的なユースケースに推奨される設定です。
* **`high`:** デフォルト。この設定は、ほとんどのユースケースでトークン使用量と知能のバランスを取ります。
* **`medium`:** 知能とのトレードオフでトークン使用量を削減する必要がある、コスト重視のユースケースに適しています。
* **`low`:** 知能への要求が高くない、短くスコープが限定されたタスクやレイテンシ重視のワークロード向けに確保してください。

移行時の大まかなモデル間の対応としては、Claude Sonnet 5のmediumはClaude Sonnet 4.6のhighと同程度の知能であり、Claude Sonnet 5のhighはClaude Sonnet 4.6のmaxと同程度です。ベンチマークを行う際は、effortの名前ではなく、観測された思考の長さで対応付けてください。

Claude Sonnet 5は、特に低い側でeffortレベルを厳密に守ります。`low`と`medium`では、モデルは求められた以上のことをするのではなく、求められた範囲に作業をスコープします。これはレイテンシとコストには良いことですが、`low` effortで実行される中程度に複雑なタスクでは、思考が不足するリスクがいくらかあります。

複雑な問題で浅い推論が観察される場合は、プロンプトで回避しようとするのではなく、effortを`high`または`xhigh`に上げてください。レイテンシのためにeffortを`low`に保つ必要がある場合は、的を絞ったガイダンスを追加してください。

```text wrap
This task involves multi-step reasoning. Think carefully through the problem before responding.
```

Claude Sonnet 5では、[適応的思考](/docs/ja/build-with-claude/adaptive-thinking)がデフォルトで有効です。`thinking`フィールドのないリクエストは適応的思考で実行されます。これは、同じリクエストが思考なしで実行されていたClaude Sonnet 4.6からの変更点です。思考を完全にオフにするには、`thinking: {type: "disabled"}`を渡してください。`max_tokens`は合計出力（思考と応答テキスト）に対するハードリミットであるため、Claude Sonnet 4.6で思考なしで実行していたワークロードについては見直してください。以前Claude Sonnet 4.6で思考をオフにして使用していた場合は、Claude Sonnet 5では思考をオンにして、より低いeffortレベルを試してみてください。

適応的思考のトリガー動作は制御可能です。大規模または複雑なシステムプロンプトで起こり得ることですが、モデルが思考ブロックを望むより頻繁に出力していると感じた場合は、それを制御するためのガイダンスを追加してください。いつものように、プロンプトの変更がパフォーマンスに与える影響を測定してください。例：

```text wrap
Thinking adds latency and should only be used when it will meaningfully improve answer quality, typically for problems that require multi-step reasoning. When in doubt, respond directly.
```

逆に、難しいワークロードを`medium`で実行していて思考不足が見られる場合、最初のレバーはeffortを上げることです。より細かい制御が必要な場合は、直接プロンプトで指示してください。

手動の拡張思考（`thinking: {type: "enabled", budget_tokens: N}`）はClaude Sonnet 5ではサポートされておらず、400エラーを返します。これはClaude Sonnet 4.6で非推奨となり、現在は削除されています。代わりにeffortパラメータを使った適応的思考を使用してください。

<Note>
  Claude Sonnet 5を`high`、`xhigh`、または`max` effortで実行している場合は、モデルが思考とツール呼び出しを行う余地を持てるように、`max_tokens`に余裕を持たせてください。長いタスクでは、適応的思考が予算の大部分を使用することがあります。予算が厳しい場合、ほぼ全体が思考で、その後に切り詰められた回答と`stop_reason: "max_tokens"`が続く応答が見られることがあります。`max_tokens`を上げるか、`medium` effortに下げることでこれは解決します。Claude Sonnet 5は同じテキストに対して約30%多くのトークンを生成する[新しいトークナイザー](/docs/ja/about-claude/models/whats-new-sonnet-5#new-tokenizer)を使用しているため、Claude Sonnet 4.6向けに調整された`max_tokens`の制限では、同等の出力が切り詰められる可能性があります。正確な増加量は、コンテンツとワークロードの形状によって異なります。
</Note>

## ツール使用のトリガー

Claude Sonnet 5はデフォルトでClaude Sonnet 4.6よりもエージェント的であり、ツールに手を伸ばしたり、自己検証ループを実行したりすることがより積極的です。思考を無効にすると、モデルはツールに手を伸ばしたり検索を検討したりする可能性が低くなります。思考をオフにした状態でツール呼び出しに依存している場合は、システムプロンプトに明示的な後押しを追加してください。effortもツール使用のレバーです。`high`または`xhigh`のeffort設定では、エージェント的な検索やコーディングにおいてツール使用が大幅に増加します。より多くのツール使用を望むシナリオでは、いつどのようにツールを適切に使用すべきかをモデルに明示的に指示するようにプロンプトを調整することもできます。たとえば、モデルがウェブ検索ツールを使用していないことに気づいた場合は、なぜ、どのように使用すべきかを明確に説明してください。

## ユーザー向けの進捗更新

Claude Sonnet 5は、長いエージェント的なトレース全体を通して、定期的でより高品質な更新をユーザーに提供します。中間ステータスメッセージを強制するためのスキャフォールディング（「3回のツール呼び出しごとに進捗を要約する」）を追加している場合は、それを削除してみてください。Claude Sonnet 5のユーザー向け更新の長さや内容がユースケースに適切に調整されていないと感じた場合は、これらの更新がどのようなものであるべきかをプロンプトで明示的に説明し、例を提供してください。

## より文字通りの指示追従

Claude Sonnet 5は、特に低いeffortレベルにおいて、プロンプトを文字通りかつ明示的に解釈します。ある項目への指示を別の項目に暗黙的に一般化することはなく、あなたが行っていない要求を推測することもありません。この文字通りの解釈の利点は精度であり、慎重に調整されたプロンプト、構造化された抽出、予測可能な動作を求めるパイプラインを持つAPIユースケースでは一般的により良いパフォーマンスを発揮します。Claudeに指示を広く適用させる必要がある場合は、スコープを明示的に述べてください（たとえば、「このフォーマットを最初のセクションだけでなく、すべてのセクションに適用してください」）。

## トーンと文体

新しいモデルの常として、長文の文章における散文のスタイルは変化する可能性があります。プロダクトが特定のボイスに依存している場合は、新しいベースラインに対してスタイルプロンプトを再評価してください。

たとえば、プロダクトのボイスがより温かみのある、または会話的なものである場合は、次のように追加してください。

```text wrap
Use a warm, collaborative tone. Acknowledge the user's framing before answering.
```

以前にスタイルの多様性のために`temperature`に依存していた場合、Claude Sonnet 5では`temperature`、`top_p`、または`top_k`をデフォルト以外の値に設定すると400エラーが返されることに注意してください。この制約はSonnetクラスのモデルでは新しいものです。移行時にはこれらのパラメータを削除し、代わりにシステムプロンプトの指示を使用してトーンと多様性を導いてください。

## デザインとフロントエンドのデフォルト

Claude Sonnet 5は、自由度の高いフロントエンドやデザインのブリーフに対して、一貫したデフォルトのビジュアルスタイルに落ち着くことがあります。デフォルトのハウススタイルは一部のブリーフでは良く見えるかもしれませんが、ダッシュボード、開発ツール、フィンテック、ヘルスケア、エンタープライズアプリでは違和感を与える可能性があります。

一般的な指示（「その色を使わないで」「クリーンでミニマルにして」）は、多様性を生み出すのではなく、モデルを別の固定パレットに移行させる傾向があります。確実に機能するアプローチが2つあります。

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

**2. 構築前にモデルに選択肢を提案させる。** これによりデフォルトが打破され、ユーザーに制御権が与えられます。Claude Sonnet 5では`temperature`が受け付けられないため、このアプローチは実行ごとに意味のある異なるデザインの方向性を生み出すための推奨される方法です。プロンプトの例：

```text wrap
Before building, propose 4 distinct visual directions tailored to this brief (each as: bg hex / accent hex / typeface, plus a one-line rationale). Ask the user to pick one, then implement only that direction.
```

ユーザーが「AIスロップ」の美学と呼ぶ一般的なパターンから離れるように導くには、システムプロンプトに短い指示を含めることができます。[frontend-designスキル](https://github.com/anthropics/claude-code/blob/main/plugins/frontend-design/skills/frontend-design/SKILL.md)ではより詳しく扱っていますが、このスニペットは前述の多様性のアプローチと併用するとうまく機能します。

```text wrap
<frontend_aesthetics>
NEVER use generic AI-generated aesthetics like overused font families (Inter, Roboto, Arial, system fonts), cliched color schemes (particularly purple gradients on white or dark backgrounds), predictable layouts and component patterns, and cookie-cutter design that lacks context-specific character. Use unique fonts, cohesive colors and themes, and animations for effects and micro-interactions.
</frontend_aesthetics>
```

## インタラクティブなコーディングプロダクト

トークン使用量と動作は、単一のユーザーターンを持つ自律的で非同期のコーディングエージェントと、複数のユーザーターンを持つインタラクティブで同期的なコーディングエージェントとで異なる場合があります。コーディングプロダクトでパフォーマンスとトークン効率の両方を最大化するには、`xhigh`または`high` effortを使用し、自動モードのような自律的な機能を追加し、ユーザーに求められる人間の操作の回数を減らしてください。

必要なユーザー操作の回数を制限する場合、最初の人間のターンでタスク、意図、関連する制約を前もって指定することが重要です。十分に仕様化された、明確で正確なタスクの説明を前もって提供することで、ユーザーターン後の余分なトークン使用を最小限に抑えながら、自律性と知能を最大化できます。対照的に、複数のユーザーターンにわたって段階的に伝えられる曖昧または仕様不足のプロンプトは、トークン効率を相対的に低下させ、場合によってはパフォーマンスも低下させる傾向があります。

## コードレビューハーネス

コードレビューハーネスが以前のモデル向けに調整されていた場合、Claude Sonnet 5では最初は再現率（recall）が低く見えることがあります。これはハーネスの影響である可能性が高く、能力の後退ではありません。レビュープロンプトに「重大度の高い問題のみを報告する」「保守的に」「細かいことを指摘しない」などと書かれている場合、Claude Sonnet 5は以前のモデルよりもその指示に忠実に従う可能性があります。つまり、コードを同じように徹底的に調査し、バグを特定した上で、指定された基準を下回ると判断した発見を報告しないことがあります。これは、モデルが同じ深さの調査を行いながらも、特に重大度の低いバグについて、調査結果を報告される発見に変換する割合が減るという形で現れることがあります。精度（precision）は通常上昇しますが、モデルの根本的なバグ発見能力が向上しているにもかかわらず、測定される再現率は低下することがあります。

推奨されるプロンプトの文言：

```text wrap
Report every issue you find, including ones you are uncertain about or consider low-severity. Do not filter for importance or confidence at this stage - a separate verification step will do that. Your goal here is coverage: it is better to surface a finding that later gets filtered out than to silently drop a real bug. For each finding, include your confidence level and an estimated severity so a downstream filter can rank them.
```

このプロンプトは実際の第2ステップがなくても使用できますが、信頼度によるフィルタリングを発見ステップから切り離すことはしばしば有効です。ハーネスに別個の検証、重複排除、またはランキングのステージがある場合は、発見ステージでのモデルの仕事はフィルタリングではなくカバレッジであることを明示的に伝えてください。

単一のパスでモデルに自己フィルタリングをさせたい場合は、「重要な」のような定性的な用語を使うのではなく、基準がどこにあるかを具体的に示してください。たとえば、「不正な動作、テストの失敗、または誤解を招く結果を引き起こす可能性のあるバグはすべて報告してください。純粋なスタイルや命名の好みのような細かい指摘のみを省略してください」のようにします。

評価やテストケースのサブセットに対してプロンプトを反復し、再現率またはF1スコアの向上を検証してください。

## コンピュータ使用

Claude Sonnet 5は`computer_20251124`ツールバージョンをサポートしています。[コンピュータ使用](/docs/ja/agents-and-tools/tool-use/computer-use-tool)機能は、最大解像度2576px / 3.75MPまでのさまざまな解像度で動作します。社内のコンピュータ使用テストでは、1080pで画像を送信するとパフォーマンスとコストのバランスが良いことが示されています。

特にコストに敏感なワークロードでは、720pまたは1366×768が、優れたパフォーマンスを持つ低コストの選択肢です。ユースケースに最適な設定を見つけるために独自のテストを実施してください。effort設定を試すことも、モデルの動作を調整するのに役立ちます。
