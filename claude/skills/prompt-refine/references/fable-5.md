<!--
取得元: https://platform.claude.com/docs/ja/build-with-claude/prompt-engineering/prompting-claude-fable-5.md
取得日: 2026-07-15
-->

# Claude Fable 5 のプロンプティング

Claude Fable 5 と Claude Mythos 5 における動作の違いとプロンプティングパターンについて、エフォート、指示への追従、長時間実行、メモリ、スキャフォールディングの変更点を解説します。

---

このガイドでは、Claude Fable 5 と Claude Mythos 5 に固有のプロンプティングおよびスキャフォールディングのパターンについて説明します。モデルの機能、API の変更点、価格、提供状況については、[Claude Fable 5 と Claude Mythos 5 の紹介](/docs/ja/about-claude/models/introducing-claude-fable-5-and-claude-mythos-5)を参照してください。現行のすべての Claude モデルに適用できる手法については、[プロンプティングのベストプラクティス](/docs/ja/build-with-claude/prompt-engineering/claude-prompting-best-practices)を参照してください。

Claude Fable 5 は、従来のモデルでは複雑すぎたり、長時間かかりすぎたり、曖昧すぎたりした問題に取り組むことができ、人間が数時間、数日、あるいは数週間かけて完了するようなエンドツーエンドの作業において特に効果を発揮します。最良の成果を得ているチームは、Claude Fable 5 を最も困難な未解決の問題に適用しています。より単純なワークロードでのみテストすると、その能力範囲を過小評価しがちです。もちろん、より単純なタスクでも確実に機能します。

Claude Fable 5 には Claude Opus 4.8 とは異なる動作上の特徴がいくつかあり、プロンプトやスキャフォールディングの更新が必要になる場合があります。このレベルの能力向上は、どの指示、ツール、ガードレールがまだ必要かを再評価する良い機会でもあります。以下のパターンは、最も頻繁に調整が必要となる動作を扱っています。

<Note>
  Claude Fable 5 と Claude Mythos 5 に固有の API パラメータの変更点（適応的思考のみ、要約された思考出力のみ、拡張思考バジェットなし、`refusal` の stop reason とフォールバック処理）については、[Claude Fable 5 と Claude Mythos 5 の紹介](/docs/ja/about-claude/models/introducing-claude-fable-5-and-claude-mythos-5)を参照してください。

  Claude Fable 5 は、攻撃的なサイバーセキュリティ技術（エクスプロイト、マルウェア、攻撃ツールの構築など）、生物学・ライフサイエンス関連のコンテンツ（実験手法や分子メカニズムなど）、およびモデルの要約された思考の抽出を対象とした安全性分類器を実行します。無害なサイバーセキュリティ作業や有益なライフサイエンスのタスクでも、これらのセーフガードがトリガーされる場合があります。拒否されたリクエストを自動的に再ルーティングするには、Claude Opus 4.8 への[サーバーサイドまたはクライアントサイドのフォールバック](/docs/ja/build-with-claude/refusals-and-fallback)を設定してください。
</Note>

## 能力の向上

Claude Opus 4.8 と比較して、Claude Fable 5 は以下の点で向上しています。

* **長期的な自律性。** Claude Fable 5 は長期間にわたって生産的な出力を維持し、長く複雑なタスク全体で高い指示保持力を保ちながら、数日にわたる目標指向の実行を完了します。
* **複雑で明確に仕様化された問題に対する初回の正確性。** 初期テスターからは、以前は数日の反復作業を要したシステムをシングルパスで実装できたという報告がありました。
* **ビジョン。** Claude Fable 5 は、密度の高い技術画像、Web アプリケーション、詳細なスクリーンショットを大幅に高い精度で解釈し、多くの場合より少ない出力トークンで処理します。また、反転した画像、ぼやけた画像、ノイズの多い画像を処理するために bash ツールや crop ツールを使用するようトレーニングされています。
* **エンタープライズワークフロー。** Claude Fable 5 は指示に従い、スコープ内にとどまり、財務分析、スプレッドシート、スライド、ドキュメントにおいてプロフェッショナルレベルの出力を生成します。
* **コードレビューとデバッグ。** バグ発見の再現率（安全性分類器が対象とするサイバーセキュリティ領域を除く）は Claude Opus 4.8 よりも顕著に高く、コードベースやリポジトリ履歴全体の検索も含まれます。
* **曖昧さへの対処。** Claude Fable 5 は、複雑で複数のスレッドにまたがるリクエストを与えられ、次のステップを判断するよう求められた場合に優れたパフォーマンスを発揮します。
* **委任と協調。** Claude Fable 5 は、並列サブエージェントのディスパッチと維持において大幅に信頼性が向上しており、長時間実行されるサブエージェントやピアエージェントとの継続的なコミュニケーションを確実に管理します。

これらの具体的な改善点に加えて、Claude Fable 5 はほぼすべてのタスクにおいて従来のモデルよりも全般的に高い能力を持っています。Claude Fable 5 は攻撃的なサイバーセキュリティや生物学・ライフサイエンスの作業を目的としていません。これらの領域のリクエストは [`stop_reason: "refusal"`](/docs/ja/build-with-claude/refusals-and-fallback) を返す場合があります。

## デフォルトでより長いターン

難しいタスクに対する個々のリクエストは、より高い [effort](/docs/ja/build-with-claude/effort)（エフォート）設定では何分も実行されることがあります。特にタスクがコンテキストの収集、構築、自己検証を必要とする場合はその傾向が強く、自律実行は数時間に及ぶこともあります。これは、チームが Claude Fable 5 に適応する際に直面する最も大きな変化の一つです。移行前にクライアントのタイムアウト、ストリーミング、ユーザー向けの進捗インジケーターを調整し、ブロッキングではなくスケジュールされたジョブなどを通じて非同期的に実行状況を確認するようにハーネスを再構築することを検討してください。タスクが曖昧な場合に Claude Fable 5 が過剰に計画を立てないようにするには、次のように指示します。

```text wrap
When you have enough information to act, act. Do not re-derive facts already established in the conversation, re-litigate a decision the user has already made, or narrate options you will not pursue in user-facing messages. If you are weighing a choice, give a recommendation, not an exhaustive survey. This does not apply to thinking blocks.
```

## すべてのエフォートレベルを検討する

[Effort](/docs/ja/build-with-claude/effort)（エフォート）は、Claude Fable 5 における知能、レイテンシ、コストのトレードオフを制御する主要な手段です。ほとんどのタスクではデフォルトとして `high` を使用し、最も能力が重視されるワークロードには `xhigh` を、日常的な作業には `medium` または `low` を使用してください。Claude Fable 5 の低いエフォート設定でも良好なパフォーマンスを発揮し、多くの場合、従来のモデルの `xhigh` のパフォーマンスを上回ります。タスクは完了するものの必要以上に時間がかかる場合や、より迅速でインタラクティブな作業スタイルを望む場合は、エフォートを下げてください。

高いエフォートで日常的な作業を行う場合、Claude Fable 5 はタスクに必要な範囲を超えてコンテキストを収集し、熟考することがあります。同時に、高いエフォートは優れた検証動作、洗練された推論、最も厳密な出力を生み出すことが多くあります。高いエフォートで要求されていない整理やリファクタリングを防ぐには、次のように指示します。

```text wrap
Don't add features, refactor, or introduce abstractions beyond what the task requires. A bug fix doesn't need surrounding cleanup and a one-shot operation usually doesn't need a helper. Don't design for hypothetical future requirements: do the simplest thing that works well. Avoid premature abstraction and half-finished implementations. Don't add error handling, fallbacks, or validation for scenarios that cannot happen. Trust internal code and framework guarantees. Only validate at system boundaries (user input, external APIs). Don't use feature flags or backwards-compatibility shims when you can just change the code.
```

## 強力な指示追従

指示追従が十分に改善されているため、各動作を名前で列挙するのではなく、簡潔な指示でほとんどの動作を制御できます。たとえば、特に指示がない場合、Claude Fable 5 は特に高いエフォート設定において、タスクに必要な範囲を超えて詳述することがあります。採用しない選択肢を調査したり、根本原因を長々と説明したり、過度に構造化された PR の説明を生成したり、次の行が何をするかを説明するコメントを書いたりします。短い簡潔さの指示は、各パターンを列挙するのと同じくらい効果的です。

```text wrap
Lead with the outcome. Your first sentence after finishing should answer "what happened" or "what did you find": the thing the user would ask for if they said "just give me the TLDR." Supporting detail and reasoning come after. Being readable and being concise are different things, and readability matters more.

The way to keep output short is to be selective about what you include (drop details that don't change what the reader would do next), not to compress the writing into fragments, abbreviations, arrow chains like A → B → fails, or jargon.
```

長時間実行されるワークフローにおけるチェックポイント動作にも同じことが当てはまります。Claude Fable 5 が本当にユーザーを必要とする箇所でのみ停止するようにするには、すべてのケースを列挙する必要はありません。

```text wrap
Pause for the user only when the work genuinely requires them: a destructive or irreversible action, a real scope change, or input that only they can provide. If you hit one of these, ask and end the turn, rather than ending on a promise.
```

## 長時間実行中の進捗報告を裏付ける

長時間の自律実行では、実際のツール結果に照らして進捗を監査するよう Claude Fable 5 に指示してください。Anthropic のテストでは、これにより、捏造を誘発するように設計されたタスクであっても、捏造されたステータスレポートがほぼ排除されました。

```text wrap
Before reporting progress, audit each claim against a tool result from this session. Only report work you can point to evidence for; if something is not yet verified, say so explicitly. Report outcomes faithfully: if tests fail, say so with the output; if a step was skipped, say that; when something is done and verified, state it plainly without hedging.
```

## 境界を明示する

Claude Fable 5 は、要求されていないアクション（依頼されていないメールの下書き作成、防御的な git ブランチのバックアップ作成など）を実行することがあります。Claude Fable 5 がすべきこととすべきでないことについて、明示的な制約を定義してください。

```text wrap
When the user is describing a problem, asking a question, or thinking out loud rather than requesting a change, the deliverable is your assessment. Report your findings and stop. Don't apply a fix until they ask for one. Before running a command that changes system state (restarts, deletes, config edits), check that the evidence actually supports that specific action. A signal that pattern-matches to a known failure may have a different cause.
```

## 並列サブエージェント

Claude Fable 5 は従来のモデルよりも積極的に並列サブエージェントをディスパッチします。サブエージェントを頻繁に使用し、委任が適切なタイミングについて明示的なガイダンスを提供し、各サブエージェントが返るまでブロックするのではなく、オーケストレーターとサブエージェント間の非同期通信を優先してください。サブタスク間でコンテキストを保持する長寿命のサブエージェントは、キャッシュ読み取りによって時間とコストを節約し、最も遅いサブエージェントがボトルネックになることを回避します。

```text wrap
Delegate independent subtasks to subagents and keep working while they run. Intervene if a subagent goes off track or is missing relevant context.
```

## メモリシステムを構築する

Claude Fable 5 は、以前の実行から得た教訓を記録し、それを参照できる場合に特に優れたパフォーマンスを発揮します。Markdown ファイルのようなシンプルなものでよいので、メモを書き込む場所を提供してください。

```text wrap
Store one lesson per file with a one-line summary at the top. Record corrections and confirmed approaches alike, including why they mattered. Don't save what the repo or chat history already records; update an existing note rather than creating a duplicate; delete notes that turn out to be wrong.
```

既存の履歴からメモリシステムをブートストラップするには、Claude Fable 5 に過去のセッションをレビューさせます。

```text wrap
Reflect on the previous sessions we've had together. Use subagents to identify core themes and lessons, and store them in [X]. Make sure you know to reference [X] for future use.
```

## まれに発生する早期停止

長いセッションの深い段階で、Claude Fable 5 は対応するツール呼び出しを発行せずに、意図を示すテキストのみの文（「これから X を実行します」）でターンを終了したり、続行するのに十分な情報があるにもかかわらず許可を求めて一時停止したりすることがあります。「続けてください」または「最後まで実行してください」と伝えれば十分です。一時停止が適切なタイミングを定義するには、これを[強力な指示追従](#strong-instruction-following)のチェックポイント指示と組み合わせてください。自律パイプラインの場合は、システムリマインダーを追加します。

```text wrap
You are operating autonomously. The user is not watching in real time and cannot answer questions mid-task, so asking "Want me to…?" or "Shall I…?" will block the work. For reversible actions that follow from the original request, proceed without asking. Offering follow-ups after the task is done is fine; asking permission after already discussing with the user before doing the work is not. Before ending your turn, check your last paragraph. If it is a plan, an analysis, a question, a list of next steps, or a promise about work you have not done ("I'll…", "let me know when…"), do that work now with tool calls. End your turn only when the task is complete or you are blocked on input only the user can provide.
```

## まれに発生するコンテキストバジェットへの懸念

非常に長いセッションでは、Claude Fable 5 が新しいセッションを提案したり、要約して引き継ぐことを申し出たり、自身の作業を削減したりすることがあります。これは、ハーネスがモデルに残りトークンのカウントダウンを表示している場合に最も頻繁にトリガーされます。可能な限り、明示的なコンテキストバジェットのカウントを表示しないようにしてください。ハーネスがそれらを表示する必要がある場合は、安心させる指示が役立ちます。

```text wrap
You have ample context remaining. Do not stop, summarize, or suggest a new session on account of context limits. Continue the work.
```

## リクエストだけでなく理由を伝える

Claude Fable 5 は、リクエストの背後にある意図を理解している場合により良いパフォーマンスを発揮する傾向があります。コンテキストがあることで、自ら意図を推測するのではなく、タスクを関連情報に結びつけることができます。特に複数のワークストリームを活用する長時間実行エージェントの場合は、なぜそれを依頼しているのかについてのコンテキストを提供してください。

```text wrap
I'm working on [the larger task] for [who it's for]. They need [what the output enables]. With that in mind: [request].
```

## ユーザーとのコミュニケーションにおける読みやすさ

長時間またはエージェント的な会話（多数のツール呼び出し、大規模な作業コンテキスト）では、Claude Fable 5 は理解しにくいテキストを生成することがあります。密な矢印チェーンの省略表記、深い実装の詳細、ユーザーが見ていない思考への言及、過度に技術的な表現などです。コミュニケーションスタイルに関する補足指示でこれを軽減できます。

```text wrap
Terse shorthand is fine between tool calls (that's you thinking out loud, and brevity there is good). Your final summary is different: it's for a reader who didn't see any of that.

If you've been working for a while without the user watching (overnight, across many tool calls, since they last spoke), your final message is their first look at any of it. Write it as a re-grounding, not a continuation of your working thread: the outcome first, then the one or two things you need from them, each explained as if new. The vocabulary you built up while working is yours, not theirs; leave it behind unless you re-introduce it.

When you write the summary at the end, drop the working shorthand. Write complete sentences. Spell out terms. Don't use arrow chains, hyphen-stacked compounds, or labels you made up earlier. When you mention files, commits, flags, or other identifiers, give each one its own plain-language clause. Open with the outcome: one sentence on what happened or what you found. Then the supporting detail. If you have to choose between short and clear, choose clear.
```

## send-to-user ツールを作成する

長時間の非同期エージェントを実行する場合、エージェントがターンを終了せずに、ユーザーが書かれたとおりに正確に見る必要があるメッセージを表示する手段を提供してください。成果物（生成されたコードスニペットや下書きされたメッセージ）、具体的な数値を含む進捗更新、またはループの途中でユーザーが尋ねた質問への直接の返答などです。ツールの入力は表示するメッセージです。Claude がこれを呼び出したら、入力を UI に直接レンダリングし、ツール結果としてシンプルな確認応答を返します。ツール入力は決して要約されないため、コンテンツはそのまま届きます。

```json
{
  "name": "send_to_user",
  "description": "Display a message directly to the user. Use this for progress updates, partial results, or content the user must see exactly as written before the task finishes.",
  "input_schema": {
    "type": "object",
    "properties": {
      "message": {
        "type": "string",
        "description": "The content to display to the user."
      }
    },
    "required": ["message"]
  }
}
```

UX がタスクの途中でコンテンツや直接的なユーザーインタラクションをそのまま届けることに依存している場合は、常にこのツールを追加してください。日常的な進捗を説明するだけのエージェントの場合、通常はモデル自身の要約で十分です。ツールを定義するだけでは不十分です。システムプロンプトに指示がなければ、Claude Fable 5 がこれを呼び出すことはほとんどありません。ツールを次のような誘導文と組み合わせてください。

```text wrap
Between tool calls, when you have content the user must read verbatim (a partial deliverable, a direct answer to their question), call the send_to_user tool with that content. Use send_to_user only for user-facing content, not for narration or reasoning.
```

ナレーションや内部推論を `send_to_user` 経由でルーティングしないでください。ユーザー向けでないコンテンツに対して過剰に呼び出すと、本来の目的が損なわれます。

## 推奨されるスキャフォールディングの変更

* **難易度範囲の上限から始める。** 従来のモデルに割り当てるよりも難しいタスクを選び、Claude Fable 5 にスコープを定義させ、明確化のための質問をさせ、実行させてください。
* **長時間実行のプロンプトで自己検証を明示する。** 新しいコンテキストを持つ独立した検証サブエージェントは、自己批評よりも優れた結果を出す傾向があります。長時間実行タスクの場合は、次のように指示します。`Establish a method for checking your own work at an interval of [X] as you build. Run this every [X interval], verifying your work with subagents against the specification.`
* **既存のプロンプトとスキルをリファクタリングする。** 従来のモデル向けに開発されたスキルは、Claude Fable 5 には指示が細かすぎることが多く、出力品質を低下させる可能性があります。デフォルトのパフォーマンスの方が優れている場合は、古い指示を見直し、削除を検討してください。Claude Fable 5 は、目の前のタスクから学んだことに基づいてスキルをその場で更新することも得意です。
* **Claude に推論を応答内で再現するよう指示しない。** モデルに内部推論を応答テキストとしてエコー、書き起こし、または説明するよう指示するプロンプト、スキル、またはハーネス指示は、Claude Fable 5 で [`reasoning_extraction` 拒否カテゴリ](/docs/ja/build-with-claude/refusals-and-fallback#refusal-response)をトリガーし、Claude Opus 4.8 へのフォールバックが増加する可能性があります。移行時には、既存のスキルとシステムプロンプトに内省や思考過程を示す指示がないか監査してください。アプリケーションで推論の可視性が必要な場合は、代わりに[適応的思考](/docs/ja/build-with-claude/adaptive-thinking)から構造化された `thinking` ブロックを読み取り、長時間実行中の進捗を表示するには [send-to-user ツール](#create-a-send-to-user-tool)を使用してください。
* **send-to-user ツールを作成する。** 長時間の非同期エージェントの場合、クライアントサイドのツールがターンを終了せずにメッセージをそのままユーザーに届けます。[send-to-user ツールを作成する](#create-a-send-to-user-tool)を参照してください。
