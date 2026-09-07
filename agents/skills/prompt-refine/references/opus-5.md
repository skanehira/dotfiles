<!--
取得元: https://platform.claude.com/docs/ja/build-with-claude/prompt-engineering/prompting-claude-opus-5.md
取得日: 2026-07-30
-->

# Claude Opus 5のプロンプティング

Claude Opus 5の動作の違いとプロンプティングパターン。応答の冗長性、エージェント的なナレーション、タスクのスコープ設定、サブエージェントへの委任、自己修正、思考が無効な場合の出力アーティファクトについて説明します。

---

このガイドでは、Claude Opus 5に固有のプロンプティングパターンについて説明します。モデルの機能とAPIの変更については、[Claude Opus 5の新機能](/docs/ja/about-claude/models/whats-new-opus-5)を参照してください。現行のすべてのClaudeモデルに適用されるテクニックについては、[プロンプティングのベストプラクティス](/docs/ja/build-with-claude/prompt-engineering/claude-prompting-best-practices)を参照してください。

Claude Opus 5は、複雑なエージェント的コーディングとエンタープライズ業務のために構築されており、特に長期的なエージェントタスクに強みがあります。既存のClaude Opus 4.8のプロンプトでも、そのまま良好に動作します。以下のパターンは、最も頻繁に調整が必要となる動作を扱っています。

<Note>
  Claude Opus 4.8から移行する際のAPIの変更（思考がデフォルトで有効になること、および思考の無効化が`high`エフォートまでに制限されること）については、[移行ガイド](/docs/ja/about-claude/models/migration-guide#migrating-from-claude-opus-4-8-to-claude-opus-5)を参照してください。
</Note>

## 機能の改善

Claude Opus 4.8と比較して、プロンプティングに最も関連する改善点は次のとおりです。

* **エージェント的コーディング:** Claude Opus 5は、複数ファイルにまたがる機能、大規模なリファクタリング、エンドツーエンドの機能開発といった難易度の高いコーディングタスクで最も力を発揮します。スタブやプレースホルダーを残すのではなくタスクを完全に完了し、最初に完全なタスク仕様を与えて実行に任せたときに最高のパフォーマンスを発揮します。また、単一ターンの編集のような簡単なタスクでも良好に動作しますが、従来のモデルとの差は小さくなります。
* **コードレビューとバグ発見:** Claude Opus 5は高い精度（precision）と再現率（recall）でコードをレビューします。1回のパスで高い割合で実際のバグを発見し、追加の指摘も誤検知ではなく実際の問題であることがほとんどです。精度は低いエフォート設定でも維持されるため、レビュー時に高速なパスを行い、後でより徹底的なパスを行うことができます。レビュープロンプトに「重大度の高い問題のみを報告する」や「保守的に」と書かれている場合、モデルはその指示を文字通りに従って報告を減らす可能性があります。代わりに、すべてを報告させて別のパスでフィルタリングするよう依頼してください。
* **低エフォートでの効率性:** `low`および`medium`の[エフォート](/docs/ja/build-with-claude/effort)は、より高い設定と比べてわずかなトークン数とレイテンシで高い品質を生み出します。デフォルト（`high`）から始めて、評価に基づいて調整してください。品質が維持される限り、トークンコストと応答時間の主要な制御手段として`low`と`medium`を積極的に使用し、要求の厳しいコーディングやエージェント作業には`xhigh`に引き上げてください。以前のモデルからエフォートのデフォルトを引き継いだ場合は、独自の評価でエフォートのスイープを再実行してください。完全な推奨事項については、[エフォート](/docs/ja/build-with-claude/effort#recommended-effort-levels-for-claude-opus-5)を参照してください。
* **ビジョン:** Claude Opus 5は、チャート、ドキュメント、図の理解、およびUIとフロントエンドの視覚的な再現に優れています。以前のモデル向けに調整したプロンプト側のビジョン回避策は再検証してください。もはや不要になっている可能性があります。ビジョンのパフォーマンスは、モデルが反復的に分析、切り抜き、視覚的に作業を検証するためのツールを持っている場合に最も高くなり、ツール使用は思考のみよりも費用対効果の高い手段です。
* **長いコンテキストでの作業:** Claude Opus 5は、デフォルトかつ最大値として[100万トークンのコンテキストウィンドウ](/docs/ja/build-with-claude/context-windows)を持ち、指示の遵守、ツール呼び出し、推論はウィンドウ全体を通して一貫性を保ちます。
* **オフィスおよびドキュメントタスク:** Claude Opus 5は、複雑な数式を含む複数シートのスプレッドシートを生成・操作し、よく構造化されたスライドデッキを作成します。従うべき特定のスタイルやテンプレートがあれば、プロンプトで指定してください。
* **マルチエージェントの調整:** Claude Opus 5は、サブエージェントのチームをうまく調整し、効果的なライター・ベリファイアーパターンを実現し、エージェント同士が互いの作業を上書きするケースはほとんどありません。コストに敏感なワークロードでは、委任に上限を設けてください。[サブエージェントの生成の制御](#controlling-subagent-spawning)を参照してください。

## 応答の長さと冗長性

Claude Opus 5のデフォルトのユーザー向け応答は、以前のOpusモデルよりも長くなります。[エフォートパラメータ](/docs/ja/build-with-claude/effort)は、モデルがどれだけ発言するかではなく、どれだけ[思考する](/docs/ja/build-with-claude/thinking-steering-and-cost)かを制御します。エフォートを下げると思考量は減りますが、目に見える応答を確実に短くすることはできません。応答の長さを制御するには、明示的にプロンプトで指示してください。

短い簡潔さの指示が効果的です。たとえば、ユーザー向けのマルチターン製品の場合：

```text wrap
Keep responses focused, brief, and concise. Keep disclaimers and caveats short, and spend most of the response on the main answer. When asked to explain something, give a high-level summary unless an in-depth explanation is specifically requested.
```

長いシステムプロンプトでは、プロンプトの終わり近くに短いリマインダーを添えて指示をペアにします：

```text wrap
<tone_preference>
Keep outputs reasonably concise.
</tone_preference>
```

## ユーザー向けの進捗更新

Claude Opus 5は、エージェント作業中に積極的にナレーションを行います。これから何をするかを宣言する傾向があり、エージェントセッションでのメッセージごとの出力は以前のモデルよりも長くなることがよくあります。タスク中にユーザーとどのようにコミュニケーションするかについて、明示的なガイダンスを与えると効果的です。ナレーションを抑えるには、望むペースと形式を記述してください：

```text wrap
Before your first tool call, say in one sentence what you're about to do. While working, give a brief update only when you find something important or change direction. When you finish, lead with the outcome: your first sentence should answer "what happened" or "what did you find," with supporting detail after it for readers who want it.
```

ナレーションを増やしたり、そのスタイルを変更したりするには、同じ手段を逆方向に適用します。更新がどのようなものであるべきかを明示的に記述し、例を提供してください。望むコミュニケーションスタイルの肯定的な例は、何をしないかについての指示よりも効果的である傾向があります。

## 成果物ドキュメントの長さ

会話の冗長性とは別に、Claude Opus 5がディスクに書き込むファイル（レポート、Markdownドキュメント、要約）は、以前のモデルよりも長くなることがよくあります。製品にClaudeが作成するドキュメントが含まれる場合は、明示的な長さの調整を追加してください：

```text wrap
Match the length of written documents to what the task needs: cover the substance, but do not pad with filler sections, redundant summaries, or boilerplate.
```

## タスクのスコープと過剰な検証

Claude Opus 5は、指示されなくても自身の作業を検証します。プロンプトに明示的な検証指示（「自明でないタスクには最終検証ステップを含める」「サブエージェントを使用して検証する」）が含まれている場合は、削除してください。このような指示はClaude Opus 5で過剰な検証を引き起こし、削除することで品質を損なうことなく無駄なトークンを削減できます。同じことが、別個の検証ステップを追加するレガシーなハーネスのスキャフォールディングにも当てはまります。

Claude Opus 5は、タスクのスコープを拡大し、要求されていないステップを追加したり、タスクがどうあるべきかについて独自の判断を適用したりすることもあります。狭いタスクの場合は、スコープを明示的に制約してください：

```text wrap
Deliver what was asked, at the scope intended. Make routine judgment calls yourself, and check in only when different readings of the request would lead to materially different work. If the request seems mistaken or a better approach exists, say so in a sentence and continue with the task as asked rather than quietly narrowing, widening, or transforming it. Finish the whole task, and stop short of actions that are clearly beyond what was asked.
```

## サブエージェントの生成の制御

Claude Opus 5は、以前のモデルよりも積極的にサブエージェントに委任します。委任は、真に独立した大規模な作業の流れでは効果を発揮しますが、小さなタスクに適用するとコストと時間が倍増します。ハーネスがサブエージェントをサポートしている場合は、どのシナリオで委任が妥当かについて明示的なガイダンスを与えるか、起動できるエージェント数に決定論的な上限を設定してください。例：

```text wrap
Delegate to a subagent only for large tasks that are genuinely independent and parallelizable, such as a wide multi-file investigation. Do not delegate work you can finish yourself in a handful of tool calls, and do not use subagents to verify or double-check your own work. If one subagent can complete the task, use one rather than several, and keep spawn counts low.
```

## 自己修正

Claude Opus 5は、プロンプトなしで自身のミスをうまく発見して修正します。すでに実行している再チェックを指示すること（「答えを再確認する」「応答前に再検証する」）は避けてください。検証指示と同様に、これらはモデル自身の動作と重複し、結果を改善することなくコストを増加させます。

また、このモデルは以前のモデルよりも、自身の以前の発言に対する修正をナレーションする傾向があり、これはユーザー向け製品では望ましくない場合があります。修正のナレーションを重要な修正のみに限定するには：

```text wrap
Only correct an earlier statement when the error would change the user's code, conclusions, or decisions. State corrections plainly and briefly, then continue the task. For slips that change nothing for the user, make the fix and move on without noting it.
```

## 思考を無効にして実行する

Claude Opus 5はデフォルトで[思考](/docs/ja/build-with-claude/thinking)が有効になっており、思考は[エフォート](/docs/ja/build-with-claude/effort)が`high`以下の場合にのみ無効にできます。[移行ガイド](/docs/ja/about-claude/models/migration-guide#migrating-from-claude-opus-4-8-to-claude-opus-5)を参照してください。思考を無効にすると、モデルの目に見える出力に2つのアーティファクトが時折現れることがあります。どちらに対しても主な緩和策は、思考を有効にしたまま、思考を無効にする代わりに低いエフォートレベルでトークンコストを制御することです。ほとんどのタスクでは、`low`エフォートで思考を有効にした方が、同程度のコストで思考を無効にするよりも優れたパフォーマンスを発揮します。

**テキストとしてのツール呼び出し。** 思考を無効にすると、モデルは構造化された`tool_use`ブロックを出力する代わりに、ユーザー向けテキストにツール呼び出しを書き込むことがあります。ターンは正常に完了し、呼び出しは実行されません。エージェントループでは、漏れたテキストが会話履歴に残るため、後のターンにも影響します。これは検索などのツールを多用するワークロードで最も一般的です。

**出力内の内部XMLタグ。** 思考を無効にすると、モデルは`<thinking>`タグやその他の内部XMLタグを目に見える応答に出力することがあります。システムプロンプトに、モデルに思考や推論をしないよう指示するルールが含まれている場合は、削除してください。そのような指示はタグの漏れを増加させます。

思考を無効にしたままにする必要がある統合の場合、1つの組み合わせた指示で両方のアーティファクトを緩和できます。これは、ツール呼び出しの前に発言する明示的な許可、適合するツールがない場合に呼び出しを強制する代わりの選択肢、および内部タグに対する一般的なルールをモデルに与えます：

```text wrap
When you use a tool, you may say a brief sentence first. If no tool can express what the user asked for, say so instead of guessing. Do not include internal or system XML tags in your response.
```

思考タグを名指しで指摘する指示は、一般的な形式よりも効果が低いため、具体的に名前を挙げることは避けてください。
