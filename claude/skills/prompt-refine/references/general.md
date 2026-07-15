<!--
取得元: https://platform.claude.com/docs/ja/build-with-claude/prompt-engineering/claude-prompting-best-practices.md
取得日: 2026-07-15
-->

# プロンプト作成のベストプラクティス

Claudeの最新モデル向けのプロンプトエンジニアリング手法に関する包括的なガイド。明確さ、例示、XML構造化、思考、エージェントシステムについて解説します。

---

これは、Claude Fable 5、Claude Mythos 5、Claude Opus 4.8、Claude Opus 4.7、Claude Opus 4.6、Claude Sonnet 5、Claude Sonnet 4.6、Claude Haiku 4.5を含むClaudeの最新モデルを対象としたプロンプトエンジニアリングのリファレンスです。このページは3つのパートで構成されています。

* **モデル固有のガイダンス**（最初）：[Claude Fable 5](/docs/ja/build-with-claude/prompt-engineering/prompting-claude-fable-5)、[Claude Sonnet 5](/docs/ja/build-with-claude/prompt-engineering/prompting-claude-sonnet-5)、[Claude Opus 4.8](/docs/ja/build-with-claude/prompt-engineering/prompting-claude-opus-4-8)の挙動の違いと、それに応じて変更すべき点。
* **現行の全モデルに共通する手法**（その後）：一般原則、出力とフォーマット、ツール使用、思考、エージェントシステム。
* **移行に関する考慮事項**（最後）：以前の世代から移行するプロンプト向け。

<Tip>
  モデルの機能の概要については、[モデルの概要](/docs/ja/about-claude/models/overview)を参照してください。Claude Fable 5の機能とAPIの変更点については、[Claude Fable 5とClaude Mythos 5の紹介](/docs/ja/about-claude/models/introducing-claude-fable-5-and-claude-mythos-5)を参照してください。Claude Sonnet 5の新機能の詳細については、[Claude Sonnet 5の新機能](/docs/ja/about-claude/models/whats-new-sonnet-5)を参照してください。Claude Opus 4.8の新機能の詳細については、[Claude Opus 4.8の新機能](/docs/ja/about-claude/models/whats-new-claude-4-8)を参照してください。移行ガイダンスについては、[移行ガイド](/docs/ja/about-claude/models/migration-guide)を参照してください。
</Tip>

## Claude Fable 5

Claude Fable 5とClaude Mythos 5のプロンプト作成ガイダンスは専用ページにあります：[Claude Fable 5のプロンプト作成](/docs/ja/build-with-claude/prompt-engineering/prompting-claude-fable-5)。Claude Opus 4.8との挙動の違いと、それに応じて行うべきプロンプトおよびスキャフォールディングの変更について解説しており、effortレベル、指示への従順性、長時間実行時の進捗報告、メモリシステム、`reasoning_extraction`拒否カテゴリなどを扱っています。

## Claude Sonnet 5

Claude Sonnet 5のプロンプト作成ガイダンスは専用ページにあります：[Claude Sonnet 5のプロンプト作成](/docs/ja/build-with-claude/prompt-engineering/prompting-claude-sonnet-5)。Claude Sonnet 4.6との挙動の違いと、それに応じて行うべきプロンプトの変更について解説しており、応答の長さ、effortと思考の深さの調整、ツール使用のトリガー、指示の文字通りの解釈、デザインおよびフロントエンドのデフォルトなどを扱っています。

## Claude Opus 4.8のプロンプト作成

Claude Opus 4.8のプロンプト作成ガイダンスは専用ページにあります：[Claude Opus 4.8のプロンプト作成](/docs/ja/build-with-claude/prompt-engineering/prompting-claude-opus-4-8)。応答の長さ、effortと思考の深さの調整、ツール使用のトリガー、指示の文字通りの解釈、サブエージェントの制御、デザインおよびフロントエンドのデフォルトについて解説しています。

## 一般原則

このセクションおよび以降のセクションで紹介する手法は、Claude Fable 5とClaude Mythos 5を含む現行のすべてのClaudeモデルに適用されます。

### 明確かつ直接的に

Claudeは明確で具体的な指示によく反応します。望む出力について具体的に指定することで、結果を向上させることができます。「期待以上」の動作を望む場合は、曖昧なプロンプトからモデルに推測させるのではなく、明示的にリクエストしてください。

Claudeを、優秀だが新入社員で、あなたの規範やワークフローについての文脈を持っていない人だと考えてください。何を望んでいるかを正確に説明するほど、結果は良くなります。

**黄金律：** タスクについて最小限の文脈しか持たない同僚にプロンプトを見せて、それに従うよう依頼してみてください。その人が混乱するなら、Claudeも混乱します。

* 望む出力形式と制約について具体的に指定してください。
* ステップの順序や完全性が重要な場合は、番号付きリストや箇条書きを使って指示を順序立てたステップとして提供してください。

<Accordion title="例：分析ダッシュボードの作成">
  **効果が低い例：**

  ```text wrap
  Create an analytics dashboard
  ```

  **効果が高い例：**

  ```text wrap
  Create an analytics dashboard. Include as many relevant features and interactions as possible. Go beyond the basics to create a fully-featured implementation.
  ```
</Accordion>

### コンテキストを追加してパフォーマンスを向上させる

指示の背景にあるコンテキストや動機を提供すること、たとえばその動作がなぜ重要なのかをClaudeに説明することで、Claudeはあなたの目標をより深く理解し、より的を射た応答を提供できるようになります。

<Accordion title="例：フォーマットの好み">
  **効果が低い例：**

  ```text wrap
  NEVER use ellipses
  ```

  **効果が高い例：**

  ```text wrap
  Your response will be read aloud by a text-to-speech engine, so never use ellipses since the text-to-speech engine will not know how to pronounce them.
  ```
</Accordion>

Claudeは説明から一般化できるほど賢いです。

### 例を効果的に使用する

例は、Claudeの出力形式、トーン、構造を誘導する最も信頼性の高い方法の一つです。よく練られた数個の例（「few-shot」または「multishot」プロンプティングと呼ばれます）は、精度と一貫性を向上させます。

例を追加する際は、以下の点に注意してください。

* **関連性：** 実際のユースケースを忠実に反映させます。
* **多様性：** エッジケースをカバーし、Claudeが意図しないパターンを学習しないよう十分に変化をつけます。
* **構造化：** 例を`<example>`タグで囲み（複数の例は`<examples>`タグで囲み）、Claudeが指示と区別できるようにします。

<Tip>
  最良の結果を得るには3〜5個の例を含めてください。また、Claudeに例の関連性と多様性を評価させたり、最初のセットに基づいて追加の例を生成させたりすることもできます。
</Tip>

### XMLタグでプロンプトを構造化する

XMLタグは、特にプロンプトに指示、コンテキスト、例、変数入力が混在している場合に、Claudeが複雑なプロンプトを曖昧さなく解析するのに役立ちます。各種類のコンテンツを独自のタグ（例：`<instructions>`、`<context>`、`<input>`）で囲むことで、誤解釈を減らせます。

ベストプラクティス：

* プロンプト全体で一貫性のある、説明的なタグ名を使用します。
* コンテンツに自然な階層がある場合はタグをネストします（`<documents>`の中にドキュメントを入れ、それぞれを`<document index="n">`の中に入れるなど）。

### Claudeに役割を与える

システムプロンプトで役割を設定すると、ユースケースに合わせてClaudeの動作とトーンが焦点化されます。一文だけでも違いが生まれます。

<CodeGroup>
  ```bash cURL
  curl https://api.anthropic.com/v1/messages \
    -H "content-type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -d '{
      "model": "claude-opus-4-8",
      "max_tokens": 1024,
      "system": "You are a helpful coding assistant specializing in Python.",
      "messages": [
        {"role": "user", "content": "How do I sort a list of dictionaries by key?"}
      ]
    }'
  ```

  ```bash CLI
  ant messages create \
    --model claude-opus-4-8 \
    --max-tokens 1024 \
    --system "You are a helpful coding assistant specializing in Python." \
    --message '{role: user, content: "How do I sort a list of dictionaries by key?"}'
  ```

  ```python Python
  client = anthropic.Anthropic()

  message = client.messages.create(
      model="claude-opus-4-8",
      max_tokens=1024,
      system="You are a helpful coding assistant specializing in Python.",
      messages=[
          {"role": "user", "content": "How do I sort a list of dictionaries by key?"}
      ],
  )

  print(message.content)
  ```

  ```typescript TypeScript
  const client = new Anthropic();

  const message = await client.messages.create({
    model: "claude-opus-4-8",
    max_tokens: 1024,
    system: "You are a helpful coding assistant specializing in Python.",
    messages: [{ role: "user", content: "How do I sort a list of dictionaries by key?" }]
  });

  console.log(message.content);
  ```

  ```csharp C#
  AnthropicClient client = new();

  var parameters = new MessageCreateParams
  {
      Model = Model.ClaudeOpus4_8,
      MaxTokens = 1024,
      System = "You are a helpful coding assistant specializing in Python.",
      Messages =
      [
          new() { Role = Role.User, Content = "How do I sort a list of dictionaries by key?" }
      ]
  };

  var message = await client.Messages.Create(parameters);
  Console.WriteLine(message);
  ```

  ```go Go
  client := anthropic.NewClient()

  message, err := client.Messages.New(context.TODO(), anthropic.MessageNewParams{
  	Model:     anthropic.ModelClaudeOpus4_8,
  	MaxTokens: 1024,
  	System: []anthropic.TextBlockParam{
  		{Text: "You are a helpful coding assistant specializing in Python."},
  	},
  	Messages: []anthropic.MessageParam{
  		anthropic.NewUserMessage(anthropic.NewTextBlock("How do I sort a list of dictionaries by key?")),
  	},
  })
  if err != nil {
  	log.Fatal(err)
  }
  fmt.Println(message.Content)
  ```

  ```java Java
  AnthropicClient client = AnthropicOkHttpClient.fromEnv();

  MessageCreateParams params = MessageCreateParams.builder()
      .model(Model.CLAUDE_OPUS_4_8)
      .maxTokens(1024)
      .system("You are a helpful coding assistant specializing in Python.")
      .addUserMessage("How do I sort a list of dictionaries by key?")
      .build();

  Message message = client.messages().create(params);
  System.out.println(message.content());
  ```

  ```php PHP
  $client = new Client();

  $message = $client->messages->create(
      maxTokens: 1024,
      messages: [
          ['role' => 'user', 'content' => 'How do I sort a list of dictionaries by key?']
      ],
      model: 'claude-opus-4-8',
      system: 'You are a helpful coding assistant specializing in Python.',
  );

  echo $message->content[0]->text;
  ```

  ```ruby Ruby
  client = Anthropic::Client.new

  message = client.messages.create(
    model: "claude-opus-4-8",
    max_tokens: 1024,
    system: "You are a helpful coding assistant specializing in Python.",
    messages: [
      { role: "user", content: "How do I sort a list of dictionaries by key?" }
    ]
  )

  puts message.content
  ```
</CodeGroup>

### 長いコンテキストのプロンプト作成

大きなドキュメントやデータが豊富な入力（20,000トークン以上）を扱う場合は、最良の結果を得るためにプロンプトを慎重に構造化してください。

* **長文データを先頭に配置する：** 長いドキュメントや入力をプロンプトの上部、つまりクエリ、指示、例の上に配置します。これにより、すべてのモデルでパフォーマンスが向上します。

  <Note>
    クエリを末尾に配置すると、特に複雑な複数ドキュメントの入力において、テストで応答品質が最大30%向上することがあります。
  </Note>

* **ドキュメントの内容とメタデータをXMLタグで構造化する：** 複数のドキュメントを使用する場合は、明確にするために各ドキュメントを`<document>`タグで囲み、`<document_content>`と`<source>`（およびその他のメタデータ）のサブタグを付けます。

  <Accordion title="複数ドキュメント構造の例">
    ```xml
    <documents>
      <document index="1">
        <source>annual_report_2023.pdf</source>
        <document_content>
          {{ANNUAL_REPORT}}
        </document_content>
      </document>
      <document index="2">
        <source>competitor_analysis_q2.xlsx</source>
        <document_content>
          {{COMPETITOR_ANALYSIS}}
        </document_content>
      </document>
    </documents>

    Analyze the annual report and competitor analysis. Identify strategic advantages and recommend Q3 focus areas.
    ```
  </Accordion>

* **引用に基づいて応答を根拠づける：** 長いドキュメントのタスクでは、タスクを実行する前にまずドキュメントの関連部分を引用するようClaudeに依頼します。これにより、Claudeはドキュメントの残りの内容のノイズを排除できます。

  <Accordion title="引用抽出の例">
    ```xml
    You are an AI physician's assistant. Your task is to help doctors diagnose possible patient illnesses.

    <documents>
      <document index="1">
        <source>patient_symptoms.txt</source>
        <document_content>
          {{PATIENT_SYMPTOMS}}
        </document_content>
      </document>
      <document index="2">
        <source>patient_records.txt</source>
        <document_content>
          {{PATIENT_RECORDS}}
        </document_content>
      </document>
      <document index="3">
        <source>patient01_appt_history.txt</source>
        <document_content>
          {{PATIENT01_APPOINTMENT_HISTORY}}
        </document_content>
      </document>
    </documents>

    Find quotes from the patient records and appointment history that are relevant to diagnosing the patient's reported symptoms. Place these in <quotes> tags. Then, based on these quotes, list all information that would help the doctor diagnose the patient's symptoms. Place your diagnostic information in <info> tags.
    ```
  </Accordion>

### モデルの自己認識

アプリケーション内でClaudeに自身を正しく識別させたい場合や、特定のAPI文字列を使用させたい場合：

```text Sample prompt for model identity wrap
The assistant is Claude, created by Anthropic. The current model is Claude Opus 4.8.
```

モデル文字列を指定する必要があるLLM搭載アプリの場合：

```text Sample prompt for model string wrap
When an LLM is needed, please default to Claude Opus 4.8 unless the user requests
otherwise. The exact model string for Claude Opus 4.8 is claude-opus-4-8.
```

## 出力とフォーマット

### コミュニケーションスタイルと冗長性

Claudeの最新モデルは、以前のモデルと比較してより簡潔で自然なコミュニケーションスタイルを持っています。

* **より直接的で根拠に基づく：** 自己称賛的な更新ではなく、事実に基づいた進捗報告を提供します
* **より会話的：** やや流暢で口語的になり、機械的な印象が減っています
* **冗長性が低い：** 特に指示がない限り、効率のために詳細な要約を省略することがあります

つまり、Claudeはツール呼び出し後の口頭での要約を省略し、次のアクションに直接進むことがあります。推論の可視性を高めたい場合：

```text Sample prompt wrap
After completing a task that involves tool use, provide a quick summary of the work you've done.
```

### 応答のフォーマットを制御する

出力フォーマットを誘導するのに特に効果的な方法がいくつかあります。

1. **何をしないかではなく、何をすべきかをClaudeに伝える**

   * 「応答にマークダウンを使用しないでください」の代わりに
   * 「応答は滑らかに流れる散文の段落で構成してください」を試してください。

2. **XMLフォーマット指示子を使用する**

   * 「応答の散文セクションを\<smoothly\_flowing\_prose\_paragraphs>タグ内に記述してください」を試してください。

3. **プロンプトのスタイルを望む出力に合わせる**

   プロンプトで使用されるフォーマットスタイルは、Claudeの応答スタイルに影響を与える可能性があります。出力フォーマットの制御性にまだ問題がある場合は、プロンプトのスタイルを望む出力スタイルにできるだけ近づけてみてください。たとえば、プロンプトからマークダウンを削除すると、出力内のマークダウンの量を減らせます。

4. **特定のフォーマット設定には詳細なプロンプトを使用する**

   マークダウンやフォーマットの使用をより細かく制御するには、明示的なガイダンスを提供します。

````text Sample prompt to minimize markdown wrap
<avoid_excessive_markdown_and_bullet_points>
When writing reports, documents, technical explanations, analyses, or any long-form
content, write in clear, flowing prose using complete paragraphs and sentences. Use
standard paragraph breaks for organization and reserve markdown primarily for `inline
code`, code blocks (```...```), and simple headings (## and ###). Avoid using **bold**
and *italics*.

DO NOT use ordered lists (1. ...) or unordered lists (*) unless: a) you're presenting
truly discrete items where a list format is the best option, or b) the user explicitly
requests a list or ranking

Instead of listing items with bullets or numbers, incorporate them naturally into
sentences. This guidance applies especially to technical writing. Using prose instead of
excessive formatting will improve user satisfaction. NEVER output a series of overly
short bullet points.

Your goal is readable, flowing text that guides the reader naturally through ideas
rather than fragmenting information into isolated points.
</avoid_excessive_markdown_and_bullet_points>
````

### LaTeX出力

Claudeの最新モデルは、数式、方程式、技術的な説明にデフォルトでLaTeXを使用します。プレーンテキストを希望する場合は、プロンプトに以下の指示を追加してください。

```text Sample prompt wrap
Format your response in plain text only. Do not use LaTeX, MathJax, or any markup
notation such as \( \), $, or rac{}{}. Write all math expressions using standard text
characters (e.g., "/" for division, "*" for multiplication, and "^" for exponents).
```

### ドキュメント作成

Claudeの最新モデルは、優れた指示追従能力でプレゼンテーション、アニメーション、ビジュアルドキュメントを作成し、通常は最初の試行で使用可能な出力を生成します。

ドキュメント作成で最良の結果を得るには：

```text Sample prompt wrap
Create a professional presentation on [topic]. Include thoughtful design elements,
visual hierarchy, and engaging animations where appropriate.
```

### プリフィル応答からの移行

Claude 4.6モデルおよび[Claude Mythos Preview](https://anthropic.com/glasswing)以降、最後のアシスタントターンでのプリフィル応答（Claudeが続きを生成するための部分的なアシスタントメッセージを提供すること）はサポートされなくなりました。これらのモデルにプリフィルされたアシスタントメッセージを含むリクエストを送信すると、400エラーが返されます。モデルの知能と指示追従能力が向上したため、プリフィルのほとんどのユースケースではもはやプリフィルが不要です。以前のモデルは引き続きプリフィルをサポートしており、会話の他の場所にアシスタントメッセージを追加することは影響を受けません。

以下は一般的なプリフィルのシナリオと、それらからの移行方法です。

<Accordion title="出力フォーマットの制御">
  プリフィルは、JSON/YAML、分類など、プリフィルによってClaudeを特定の構造に制約するパターンで、特定の出力形式を強制するために使用されてきました。

  **移行方法：** [Structured Outputs](/docs/ja/build-with-claude/structured-outputs)機能は、Claudeの応答を指定されたスキーマに従うよう制約するために特別に設計されています。まずモデルに出力構造に従うよう依頼してみてください。新しいモデルは、特にリトライを実装している場合、指示されれば複雑なスキーマに確実に一致させることができます。分類タスクには、有効なラベルを含むenumフィールドを持つツール、またはStructured Outputsのいずれかを使用してください。
</Accordion>

<Accordion title="前置きの排除">
  `Here is the requested summary:
`のようなプリフィルは、導入テキストをスキップするために使用されていました。

  **移行方法：** システムプロンプトで直接指示を使用します：「前置きなしで直接応答してください。『Here is...』『Based on...』などのフレーズで始めないでください。」あるいは、モデルにXMLタグ内で出力するよう指示する、Structured Outputsを使用する、またはツール呼び出しを使用します。時折前置きが紛れ込む場合は、後処理で削除してください。
</Accordion>

<Accordion title="不適切な拒否の回避">
  プリフィルは、不必要な拒否を回避するために使用されていました。

  **移行方法：** Claudeは現在、適切な拒否の判断がはるかに向上しています。プリフィルなしで`user`メッセージ内に明確なプロンプトを記述すれば十分なはずです。
</Accordion>

<Accordion title="継続">
  プリフィルは、部分的な生成を継続したり、中断された応答を再開したり、前回の生成が終わったところから続けたりするために使用されていました。

  **移行方法：** 継続をユーザーメッセージに移動し、中断された応答の最後のテキストを含めます：「前回の応答は中断され、\`\[previous\_response]\`で終わりました。中断したところから続けてください。」これがエラー処理や不完全な応答の処理の一部であり、UXへの影響がない場合は、リクエストをリトライしてください。
</Accordion>

<Accordion title="コンテキストの注入と役割の一貫性">
  プリフィルは、更新または注入されたコンテキストを定期的に確保するために使用されていました。

  **移行方法：** 非常に長い会話では、以前プリフィルされたアシスタントのリマインダーだったものをユーザーターンに注入します。コンテキストの注入がより複雑なエージェントシステムの一部である場合は、ツール経由での注入（ターン数などのヒューリスティックに基づいてコンテキストを含むツールを公開または使用を促す）や、[コンテキスト圧縮](/docs/ja/build-with-claude/compaction)中の注入を検討してください。
</Accordion>

## ツール使用

### ツールの使用

Claudeの最新モデルは正確な指示追従のために訓練されており、特定のツールを使用するための明示的な指示から恩恵を受けます。「いくつか変更を提案してもらえますか」と言うと、変更を加えることがあなたの意図であったとしても、Claudeは実装するのではなく提案を提供することがあります。ツールの定義方法とツールトリガーのトラブルシューティングについては、[Claudeでのツール使用](/docs/ja/agents-and-tools/tool-use/overview)を参照してください。

Claudeにアクションを実行させるには、より明示的にしてください。

<Accordion title="例：明示的な指示">
  **効果が低い例（Claudeは提案のみを行います）：**

  ```text wrap
  Can you suggest some changes to improve this function?
  ```

  **効果が高い例（Claudeは変更を加えます）：**

  ```text wrap
  Change this function to improve its performance.
  ```

  または：

  ```text wrap
  Make these edits to the authentication flow.
  ```
</Accordion>

Claudeがデフォルトでより積極的にアクションを実行するようにするには、システムプロンプトに以下を追加できます。

```text Sample prompt for proactive action wrap
<default_to_action>
By default, implement changes rather than only suggesting them. If the user's intent is
unclear, infer the most useful likely action and proceed, using tools to discover any
missing details instead of guessing. Try to infer the user's intent about whether a tool
call (e.g., file edit or read) is intended or not, and act accordingly.
</default_to_action>
```

一方、モデルがデフォルトでより慎重になり、すぐに実装に飛び込まず、リクエストされた場合にのみアクションを実行するようにしたい場合は、以下のようなプロンプトでこの動作を誘導できます。

```text Sample prompt for conservative action wrap
<do_not_act_before_instructions>
Do not jump into implementation or change files unless clearly instructed to make
changes. When the user's intent is ambiguous, default to providing information, doing
research, and providing recommendations rather than taking action. Only proceed with
edits, modifications, or implementations when the user explicitly requests them.
</do_not_act_before_instructions>
```

Claude Opus 4.5とClaude Opus 4.6は、以前のモデルよりもシステムプロンプトに敏感に反応します。ツールやスキルのアンダートリガーを減らすように設計されたプロンプトを使用している場合、これらのモデルではオーバートリガーする可能性があります。修正方法は、強い表現を控えめにすることです。「CRITICAL: You MUST use this tool when...」と書いていた箇所は、「Use this tool when...」のような通常のプロンプトに変更できます。

### 並列ツール呼び出しの最適化

Claudeの最新モデルは、独立したツール呼び出しを並列で実行します。これらのモデルは以下を行います。

* リサーチ中に複数の投機的検索を実行する
* 複数のファイルを一度に読み込んでコンテキストをより速く構築する
* bashコマンドを並列で実行する（システムパフォーマンスのボトルネックになることさえあります）

この動作は制御可能です。プロンプトなしでもモデルは並列ツール呼び出しで高い成功率を示しますが、これを約100%まで高めたり、積極性のレベルを調整したりできます。

```text Sample prompt for maximum parallel efficiency wrap
<use_parallel_tool_calls>
If you intend to call multiple tools and there are no dependencies between the tool
calls, make all of the independent tool calls in parallel. Prioritize calling tools
simultaneously whenever the actions can be done in parallel rather than sequentially.
For example, when reading 3 files, run 3 tool calls in parallel to read all 3 files into
context at the same time. Maximize use of parallel tool calls where possible to increase
speed and efficiency. However, if some tool calls depend on previous calls to inform
dependent values like the parameters, do NOT call these tools in parallel and instead
call them sequentially. Never use placeholders or guess missing parameters in tool
calls.
</use_parallel_tool_calls>
```

```text Sample prompt to reduce parallel execution wrap
Execute operations sequentially with brief pauses between each step to ensure stability.
```

## 思考と推論

### 過剰な思考と過度な徹底性

Claude Opus 4.6は、特に高い[`effort`](/docs/ja/build-with-claude/effort)設定において、以前のモデルよりも事前の探索を多く行います。この初期作業は最終結果の最適化に役立つことが多いですが、モデルはプロンプトされなくても広範なコンテキストを収集したり、複数のリサーチの糸口を追求したりすることがあります。以前のプロンプトでモデルにより徹底的になるよう促していた場合は、Claude Opus 4.6向けにそのガイダンスを調整する必要があります。

* **一律のデフォルトをより的を絞った指示に置き換える。** 「デフォルトで\[tool]を使用する」の代わりに、「問題の理解を深めるのに役立つ場合に\[tool]を使用する」のようなガイダンスを追加します。
* **過剰なプロンプトを削除する。** 以前のモデルでアンダートリガーしていたツールは、現在は適切にトリガーされる可能性が高いです。「迷ったら\[tool]を使用する」のような指示はオーバートリガーを引き起こします。
* **フォールバックとしてeffortを使用する。** Claudeが引き続き過度に積極的な場合は、`effort`の設定を低くしてください。

場合によっては、Claude Opus 4.6が広範に思考することがあり、思考トークンが膨らんで応答が遅くなることがあります。この動作が望ましくない場合は、推論を制約する明示的な指示を追加するか、`effort`設定を下げて全体的な思考とトークン使用量を減らすことができます。

```text Sample prompt wrap
When you're deciding how to approach a problem, choose an approach and commit to it.
Avoid revisiting decisions unless you encounter new information that directly
contradicts your reasoning. If you're weighing two approaches, pick one and see it
through. You can always course-correct later if the chosen approach fails.
```

思考コストに厳密な上限が必要な場合、`budget_tokens`上限付きの拡張思考はOpus 4.6とSonnet 4.6でまだ機能しますが、非推奨です。Claude Opus 4.7以降のモデル、およびClaude Fable 5とClaude Mythos 5では、`budget_tokens`を設定すると400エラーが返されます。[effort](/docs/ja/build-with-claude/effort)設定を下げるか、[適応型思考](/docs/ja/build-with-claude/adaptive-thinking)で`max_tokens`を厳密な上限として使用することを推奨します。

### 思考とインターリーブ思考機能の活用

Claudeの最新モデルは、ツール使用後の振り返りや複雑な多段階推論を伴うタスクに特に役立つ思考機能を提供します。初期思考やインターリーブ思考を誘導することで、より良い結果を得られます。

Claude Opus 4.6、Claude Opus 4.7、Claude Opus 4.8、Claude Sonnet 4.6は[適応型思考](/docs/ja/build-with-claude/adaptive-thinking)（`thinking: {type: "adaptive"}`）を使用し、Claudeがいつ、どれだけ思考するかを動的に決定します。Claude Fable 5とClaude Mythos 5では、思考は常にオンであり、適応型思考が唯一のモードです。Claudeは2つの要因に基づいて思考を調整します：`effort`パラメータとクエリの複雑さです。effortが高いほど思考が多くなり、より複雑なクエリでも同様です。思考を必要としない簡単なクエリでは、モデルは直接応答します。内部評価では、適応型思考は拡張思考よりも確実に優れたパフォーマンスを発揮します。最も知的な応答を得るために、適応型思考への移行を検討してください。

多段階のツール使用、複雑なコーディングタスク、長期的なエージェントループなど、エージェント的な動作を必要とするワークロードには適応型思考を使用してください。古いモデルは`budget_tokens`を使用した手動の[拡張思考](/docs/ja/build-with-claude/extended-thinking)を使用します。各モデルがどのモードを受け付けるかについては、[サポートされているモデルの表](/docs/ja/build-with-claude/extended-thinking#supported-models)を参照してください。

Claudeの思考動作を誘導できます。

```text Example prompt wrap
After receiving tool results, carefully reflect on their quality and determine optimal
next steps before proceeding. Use your thinking to plan and iterate based on this new
information, and then take the best next action.
```

適応型思考のトリガー動作はプロンプトで制御可能です。大規模または複雑なシステムプロンプトで発生しがちですが、モデルが望むよりも頻繁に思考している場合は、ガイダンスを追加して誘導してください。

```text Sample prompt wrap
Extended thinking adds latency and should only be used when it will meaningfully improve
answer quality - typically for problems that require multi-step reasoning. When in
doubt, respond directly.
```

`budget_tokens`を使用した[拡張思考](/docs/ja/build-with-claude/extended-thinking)から移行する場合は、思考の設定を置き換え、予算制御を`effort`に移動してください。以下の例は、移行前後の同じリクエストを示しています（利用可能なレベルとモデルごとの利用可能性については[effort](/docs/ja/build-with-claude/effort)を参照してください）。

<CodeGroup>
  ```bash cURL
  # 変更前：手動バジェットによる拡張思考（旧モデル）
  curl https://api.anthropic.com/v1/messages \
    -H "content-type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -d '{
      "model": "claude-sonnet-4-5-20250929",
      "max_tokens": 16000,
      "thinking": {"type": "enabled", "budget_tokens": 10000},
      "messages": [
        {"role": "user", "content": "..."}
      ]
    }'

  # 変更後：エフォートによる適応型思考（現行モデル）
  curl https://api.anthropic.com/v1/messages \
    -H "content-type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -d '{
      "model": "claude-opus-4-8",
      "max_tokens": 16000,
      "thinking": {"type": "adaptive"},
      "output_config": {"effort": "high"},
      "messages": [
        {"role": "user", "content": "..."}
      ]
    }'
  ```

  ```bash CLI
  # 変更前：手動バジェットによる拡張思考（旧モデル）
  ant messages create <<'YAML'
  model: claude-sonnet-4-5-20250929
  max_tokens: 16000
  thinking:
    type: enabled
    budget_tokens: 10000
  messages:
    - role: user
      content: "..."
  YAML

  # 変更後：effortによる適応的思考（現行モデル）
  ant messages create <<'YAML'
  model: claude-opus-4-8
  max_tokens: 16000
  thinking:
    type: adaptive
  output_config:
    effort: high
  messages:
    - role: user
      content: "..."
  YAML
  ```

  ```python Python
  # 変更前：手動でバジェットを指定する拡張思考（旧モデル）
  client.messages.create(
      model="claude-sonnet-4-5-20250929",
      max_tokens=16000,
      thinking={"type": "enabled", "budget_tokens": 10000},
      messages=[{"role": "user", "content": "..."}],
  )

  # 変更後：effortを指定する適応型思考（現行モデル）
  client.messages.create(
      model="claude-opus-4-8",
      max_tokens=16000,
      thinking={"type": "adaptive"},
      output_config={"effort": "high"},
      messages=[{"role": "user", "content": "..."}],
  )
  ```

  ```typescript TypeScript
  // 変更前：手動バジェットによる拡張思考（旧モデル）
  await client.messages.create({
    model: "claude-sonnet-4-5-20250929",
    max_tokens: 16000,
    thinking: { type: "enabled", budget_tokens: 10000 },
    messages: [{ role: "user", content: "..." }]
  });

  // 変更後：effortによる適応的思考（現行モデル）
  await client.messages.create({
    model: "claude-opus-4-8",
    max_tokens: 16000,
    thinking: { type: "adaptive" },
    output_config: { effort: "high" },
    messages: [{ role: "user", content: "..." }]
  });
  ```

  ```csharp C#
  // 変更前：手動バジェットによる拡張思考（旧モデル）
  await client.Messages.Create(new MessageCreateParams
  {
      Model = "claude-sonnet-4-5-20250929",
      MaxTokens = 16000,
      Thinking = new ThinkingConfigEnabled(budgetTokens: 10000),
      Messages = [new() { Role = Role.User, Content = "..." }]
  });

  // 変更後：effortによる適応的思考（現行モデル）
  await client.Messages.Create(new MessageCreateParams
  {
      Model = Model.ClaudeOpus4_8,
      MaxTokens = 16000,
      Thinking = new ThinkingConfigAdaptive(),
      OutputConfig = new OutputConfig { Effort = Effort.High },
      Messages = [new() { Role = Role.User, Content = "..." }]
  });
  ```

  ```go Go
  // 変更前：手動バジェットによる拡張思考（旧モデル）
  client.Messages.New(ctx, anthropic.MessageNewParams{
  	Model:     "claude-sonnet-4-5-20250929",
  	MaxTokens: 16000,
  	Thinking: anthropic.ThinkingConfigParamUnion{
  		OfEnabled: &anthropic.ThinkingConfigEnabledParam{BudgetTokens: 10000},
  	},
  	Messages: []anthropic.MessageParam{
  		anthropic.NewUserMessage(anthropic.NewTextBlock("...")),
  	},
  })

  // 変更後：effortによる適応的思考（現行モデル）
  client.Messages.New(ctx, anthropic.MessageNewParams{
  	Model:     anthropic.ModelClaudeOpus4_8,
  	MaxTokens: 16000,
  	Thinking: anthropic.ThinkingConfigParamUnion{
  		OfAdaptive: &anthropic.ThinkingConfigAdaptiveParam{},
  	},
  	OutputConfig: anthropic.OutputConfigParam{
  		Effort: anthropic.OutputConfigEffortHigh,
  	},
  	Messages: []anthropic.MessageParam{
  		anthropic.NewUserMessage(anthropic.NewTextBlock("...")),
  	},
  })
  ```

  ```java Java
  // 変更前：手動バジェットによる拡張思考（旧モデル）
  client.messages().create(MessageCreateParams.builder()
      .model("claude-sonnet-4-5-20250929")
      .maxTokens(16000L)
      .thinking(ThinkingConfigEnabled.builder().budgetTokens(10000L).build())
      .addUserMessage("...")
      .build());

  // 変更後：effortによる適応的思考（現行モデル）
  client.messages().create(MessageCreateParams.builder()
      .model(Model.CLAUDE_OPUS_4_8)
      .maxTokens(16000L)
      .thinking(ThinkingConfigAdaptive.builder().build())
      .outputConfig(OutputConfig.builder()
          .effort(OutputConfig.Effort.HIGH)
          .build())
      .addUserMessage("...")
      .build());
  ```

  ```php PHP
  // 変更前：手動バジェットによる拡張思考（旧モデル）
  $client->messages->create(
      model: 'claude-sonnet-4-5-20250929',
      maxTokens: 16000,
      thinking: ['type' => 'enabled', 'budget_tokens' => 10000],
      messages: [['role' => 'user', 'content' => '...']],
  );

  // 変更後：エフォートによる適応的思考（現行モデル）
  $client->messages->create(
      model: 'claude-opus-4-8',
      maxTokens: 16000,
      thinking: ['type' => 'adaptive'],
      outputConfig: ['effort' => 'high'],
      messages: [['role' => 'user', 'content' => '...']],
  );
  ```

  ```ruby Ruby
  # 変更前：手動でバジェットを指定する拡張思考（旧モデル）
  client.messages.create(
    model: "claude-sonnet-4-5-20250929",
    max_tokens: 16000,
    thinking: { type: "enabled", budget_tokens: 10000 },
    messages: [{ role: "user", content: "..." }]
  )

  # 変更後：effortを指定する適応型思考（現行モデル）
  client.messages.create(
    model: "claude-opus-4-8",
    max_tokens: 16000,
    thinking: { type: "adaptive" },
    output_config: { effort: "high" },
    messages: [{ role: "user", content: "..." }]
  )
  ```
</CodeGroup>

拡張思考を使用していない場合、変更は不要です。Claude Opus 4.6からClaude Opus 4.8まで、およびClaude Sonnet 4.6では、`thinking`パラメータを省略すると思考はオフになります。Claude Fable 5とClaude Mythos 5では、`thinking`パラメータを設定するかどうかにかかわらず、思考は常にオンです。

* **規定的なステップよりも一般的な指示を優先する。** 「徹底的に考えてください」のようなプロンプトは、手書きのステップバイステップの計画よりも優れた推論を生み出すことがよくあります。Claudeの推論は、人間が規定するものを上回ることが頻繁にあります。
* **マルチショット例は思考と併用できる。** few-shot例の中で`<thinking>`タグを使用して、Claudeに推論パターンを示します。Claudeはそのスタイルを自身の拡張思考ブロックに一般化します。
* **フォールバックとしての手動の「chain-of-thought」（思考の連鎖）、すなわちCoTプロンプティング。** 思考がオフの場合でも、Claudeに問題を段階的に考えるよう依頼することで、ステップバイステップの推論を促すことができます。`<thinking>`や`<answer>`のような構造化タグを使用して、推論と最終出力を明確に分離します。
* **Claudeに自己チェックを依頼する。** 「終了する前に、\[テスト基準]に照らして回答を検証してください」のような文を追加します。これは特にコーディングや数学において、エラーを確実に検出します。

<Note>
  拡張思考が無効になっている場合、Claude Opus 4.5は「think」という単語とその派生語に特に敏感です。そのような場合は、「consider」「evaluate」「reason through」などの代替表現の使用を検討してください。
</Note>

<Info>
  思考機能の詳細については、[拡張思考](/docs/ja/build-with-claude/extended-thinking)と[適応型思考](/docs/ja/build-with-claude/adaptive-thinking)を参照してください。
</Info>

## エージェントシステム

### 長期的な推論と状態追跡

Claudeの最新モデルは、優れた状態追跡能力で長期的な推論タスクを処理します。Claudeは、一度にすべてを試みるのではなく、少数のことに着実に進展を重ねる段階的な進捗に焦点を当てることで、長時間のセッション全体で方向性を維持します。この能力は、複数のコンテキストウィンドウやタスクの反復にわたって特に発揮され、Claudeは複雑なタスクに取り組み、状態を保存し、新しいコンテキストウィンドウで続行できます。

#### コンテキスト認識とマルチウィンドウワークフロー

Claude Sonnet 5、Claude Sonnet 4.6、Claude Sonnet 4.5、Claude Haiku 4.5は[コンテキスト認識](/docs/ja/build-with-claude/context-windows#context-awareness)機能を備えており、モデルは会話全体を通じて残りのコンテキストウィンドウ（つまり「トークン予算」）を追跡できます。これにより、Claudeは作業に使えるスペースを理解することで、タスクの実行とコンテキストの管理をより効果的に行えます。

**コンテキスト制限の管理：**

コンテキストを圧縮したり、外部ファイルへのコンテキスト保存を許可したりするエージェントハーネス（Claude Codeなど）でClaudeを使用している場合は、Claudeが適切に動作できるよう、この情報をプロンプトに追加することを検討してください。そうしないと、Claudeはコンテキスト制限に近づくにつれて自然に作業を終わらせようとすることがあります。以下はプロンプトの例です。

```text Sample prompt wrap
Your context window will be automatically compacted as it approaches its limit, allowing
you to continue working indefinitely from where you left off. Therefore, do not stop
tasks early due to token budget concerns. As you approach your token budget limit, save
your current progress and state to memory before the context window refreshes. Always be
as persistent and autonomous as possible and complete tasks fully, even if the end of
your budget is approaching. Never artificially stop any task early regardless of the
context remaining.
```

[メモリツール](/docs/ja/agents-and-tools/tool-use/memory-tool)は、コンテキストの移行を管理するためにコンテキスト認識と相性が良いです。

#### マルチコンテキストウィンドウワークフロー

複数のコンテキストウィンドウにまたがるタスクの場合：

1. **最初のコンテキストウィンドウには異なるプロンプトを使用する：** 最初のコンテキストウィンドウを使用してフレームワークをセットアップし（テストの作成、セットアップスクリプトの作成）、その後のコンテキストウィンドウでTODOリストを反復処理します。

2. **モデルに構造化された形式でテストを書かせる：** 作業を開始する前にテストを作成し、構造化された形式（例：`tests.json`）で追跡するようClaudeに依頼します。これにより、長期的な反復能力が向上します。テストの重要性をClaudeに思い出させてください：「テストを削除または編集することは、機能の欠落やバグにつながる可能性があるため、許容されません。」

3. **QOL（作業効率化）ツールをセットアップする：** サーバーの起動、テストスイートの実行、リンターの実行を円滑に行うためのセットアップスクリプト（例：`init.sh`）を作成するようClaudeに促します。これにより、新しいコンテキストウィンドウから続行する際の繰り返し作業を防げます。

4. **新規開始と圧縮の比較：** コンテキストウィンドウがクリアされた場合、圧縮を使用するのではなく、まったく新しいコンテキストウィンドウから開始することを検討してください。Claudeの最新モデルは、ローカルファイルシステムから状態を発見するのに非常に効果的です。場合によっては、圧縮よりもこれを活用したいことがあります。どのように開始すべきかを具体的に指示してください。

   * 「pwdを呼び出してください。このディレクトリ内のファイルのみ読み書きできます。」
   * 「progress.txt、tests.json、gitログを確認してください。」
   * 「新機能の実装に進む前に、基本的な統合テストを手動で実行してください。」

5. **検証ツールを提供する：** 自律的なタスクの長さが増すにつれて、Claudeは継続的な人間のフィードバックなしで正確性を検証する必要があります。UIのテストにはPlaywright MCPサーバーやコンピュータ使用機能などのツールが役立ちます。

6. **コンテキストの完全な使用を促す：** 次に進む前にコンポーネントを効率的に完成させるようClaudeにプロンプトします。

```text Sample prompt wrap
This is a very long task, so it may be beneficial to plan out your work clearly. It's
encouraged to spend your entire output context working on the task - just make sure you
don't run out of context with significant uncommitted work. Continue working
systematically until you have completed this task.
```

#### 状態管理のベストプラクティス

* **状態データには構造化された形式を使用する：** 構造化された情報（テスト結果やタスクステータスなど）を追跡する場合は、JSONやその他の構造化された形式を使用して、Claudeがスキーマ要件を理解できるようにします
* **進捗メモには非構造化テキストを使用する：** 自由形式の進捗メモは、一般的な進捗とコンテキストの追跡に適しています
* **状態追跡にgitを使用する：** gitは、何が行われたかのログと復元可能なチェックポイントを提供します。Claudeの最新モデルは、複数のセッションにわたって状態を追跡するためにgitを使用するのに特に優れています。
* **段階的な進捗を強調する：** 進捗を追跡し、段階的な作業に焦点を当てるようClaudeに明示的に依頼します

<Accordion title="例：状態追跡">
  ```json
  // Structured state file (tests.json)
  {
    "tests": [
      { "id": 1, "name": "authentication_flow", "status": "passing" },
      { "id": 2, "name": "user_management", "status": "failing" },
      { "id": 3, "name": "api_endpoints", "status": "not_started" }
    ],
    "total": 200,
    "passing": 150,
    "failing": 25,
    "not_started": 25
  }
  ```

  ```text wrap
  // Progress notes (progress.txt)
  Session 3 progress:
  - Fixed authentication token validation
  - Updated user model to handle edge cases
  - Next: investigate user_management test failures (test #2)
  - Note: Do not remove tests as this could lead to missing functionality
  ```
</Accordion>

### 自律性と安全性のバランス

ガイダンスがない場合、Claude Opus 4.6は、ファイルの削除、強制プッシュ、外部サービスへの投稿など、元に戻すのが困難なアクションや共有システムに影響を与えるアクションを実行することがあります。潜在的にリスクのあるアクションを実行する前にClaude Opus 4.6に確認させたい場合は、プロンプトにガイダンスを追加してください。

```text Sample prompt wrap
Consider the reversibility and potential impact of your actions. You are encouraged to
take local, reversible actions like editing files or running tests, but for actions that
are hard to reverse, affect shared systems, or could be destructive, ask the user before
proceeding.

Examples of actions that warrant confirmation:
- Destructive operations: deleting files or branches, dropping database tables, rm -rf
- Hard to reverse operations: git push --force, git reset --hard, amending published commits
- Operations visible to others: pushing code, commenting on PRs/issues, sending
messages, modifying shared infrastructure

When encountering obstacles, do not use destructive actions as a shortcut. For example,
don't bypass safety checks (e.g. --no-verify) or discard unfamiliar files that may be
in-progress work.
```

### リサーチと情報収集

Claudeの最新モデルは、複数のソースから情報を効果的に見つけて統合できます。最適なリサーチ結果を得るには：

1. **明確な成功基準を提供する：** リサーチの質問に対する成功した回答とは何かを定義します

2. **ソースの検証を促す：** 複数のソースにわたって情報を検証するようClaudeに依頼します

3. **複雑なリサーチタスクには構造化されたアプローチを使用する：**

```text Sample prompt for complex research wrap
Search for this information in a structured way. As you gather data, develop several
competing hypotheses. Track your confidence levels in your progress notes to improve
calibration. Regularly self-critique your approach and plan. Update a hypothesis tree or
research notes file to persist information and provide transparency. Break down this
complex research task systematically.
```

この構造化されたアプローチは、Claudeが大規模なコーパスを体系的に処理し、発見を反復的に批評するのに役立ちます。

### サブエージェントのオーケストレーション

Claudeの最新モデルは、サブエージェントをネイティブにオーケストレーションします。これらのモデルは、タスクが専門的なサブエージェントへの作業委譲から恩恵を受ける場合を認識し、明示的な指示を必要とせずに積極的にそれを行います。

この動作を活用するには：

1. **明確に定義されたサブエージェントツールを用意する：** サブエージェントツールを利用可能にし、ツール定義で説明します
2. **Claudeに自然にオーケストレーションさせる：** Claudeは明示的な指示なしで適切に委譲します
3. **過剰使用に注意する：** Claude Opus 4.6はサブエージェントを強く好む傾向があり、よりシンプルで直接的なアプローチで十分な状況でもサブエージェントを生成することがあります。たとえば、直接のgrep呼び出しの方が速くて十分な場合でも、モデルはコード探索のためにサブエージェントを生成することがあります。

サブエージェントの過剰使用が見られる場合は、サブエージェントが適切な場合とそうでない場合について明示的なガイダンスを追加してください。

```text Sample prompt for subagent usage wrap
Use subagents when tasks can run in parallel, require isolated context, or involve
independent workstreams that don't need to share state. For simple tasks, sequential
operations, single-file edits, or tasks where you need to maintain context across steps,
work directly rather than delegating.
```

### 複雑なプロンプトの連鎖

適応型思考とサブエージェントのオーケストレーションにより、Claudeはほとんどの多段階推論を内部で処理します。明示的なプロンプトチェーン（タスクを連続したAPI呼び出しに分割すること）は、中間出力を検査したり、特定のパイプライン構造を強制したりする必要がある場合に依然として有用です。

最も一般的なチェーンパターンは**自己修正**です：ドラフトを生成 → Claudeに基準に照らしてレビューさせる → レビューに基づいてClaudeに改良させる。各ステップは個別のAPI呼び出しなので、任意の時点でログ記録、評価、分岐が可能です。

### エージェント的コーディングでのファイル作成を減らす

Claudeの最新モデルは、特にコードを扱う際に、テストと反復の目的で新しいファイルを作成することがあります。このアプローチにより、Claudeは最終出力を保存する前に、ファイル（特にPythonスクリプト）を「一時的なメモ帳」として使用できます。一時ファイルの使用は、特にエージェント的コーディングのユースケースで結果を改善できます。

新規ファイルの作成を最小限に抑えたい場合は、Claudeに後片付けをするよう指示できます。

```text Sample prompt wrap
If you create any temporary new files, scripts, or helper files for iteration, clean up
these files by removing them at the end of the task.
```

### 過剰な積極性

Claude Opus 4.5とClaude Opus 4.6は、余分なファイルを作成したり、不要な抽象化を追加したり、リクエストされていない柔軟性を組み込んだりすることで、過剰設計する傾向があります。この望ましくない動作が見られる場合は、ソリューションを最小限に保つための具体的なガイダンスを追加してください。

例：

```text Sample prompt to minimize overengineering wrap
Avoid over-engineering. Only make changes that are directly requested or clearly
necessary. Keep solutions simple and focused:

- Scope: Don't add features, refactor code, or make "improvements" beyond what was
asked. A bug fix doesn't need surrounding code cleaned up. A simple feature doesn't need
extra configurability.

- Documentation: Don't add docstrings, comments, or type annotations to code you didn't
change. Only add comments where the logic isn't self-evident.

- Defensive coding: Don't add error handling, fallbacks, or validation for scenarios
that can't happen. Trust internal code and framework guarantees. Only validate at system
boundaries (user input, external APIs).

- Abstractions: Don't create helpers, utilities, or abstractions for one-time
operations. Don't design for hypothetical future requirements. The right amount of
complexity is the minimum needed for the current task.
```

### テスト合格への固執とハードコーディングを避ける

Claudeは、より一般的なソリューションを犠牲にしてテストを合格させることに過度に集中したり、標準ツールを直接使用する代わりに複雑なリファクタリングにヘルパースクリプトなどの回避策を使用したりすることがあります。この動作を防ぎ、一般化できるソリューションを得るには：

```text Sample prompt wrap
Please write a high-quality, general-purpose solution using the standard tools
available. Do not create helper scripts or workarounds to accomplish the task more
efficiently. Implement a solution that works correctly for all valid inputs, not just
the test cases. Do not hard-code values or create solutions that only work for specific
test inputs. Instead, implement the actual logic that solves the problem generally.

Focus on understanding the problem requirements and implementing the correct algorithm.
Tests are there to verify correctness, not to define the solution. Provide a principled
implementation that follows best practices and software design principles.

If the task is unreasonable or infeasible, or if any of the tests are incorrect, please
inform me rather than working around them. The solution should be robust, maintainable,
and extendable.
```

### エージェント的コーディングでのハルシネーションの最小化

Claudeの最新モデルはハルシネーションが少なく、コードに基づいたより正確で根拠のある知的な回答を提供します。この動作をさらに促進し、ハルシネーションを最小限に抑えるには：

```text Sample prompt wrap
<investigate_before_answering>
Never speculate about code you have not opened. If the user references a specific file,
you MUST read the file before answering. Make sure to investigate and read relevant
files BEFORE answering questions about the codebase. Never make any claims about code
before investigating unless you are certain of the correct answer - give grounded and
hallucination-free answers.
</investigate_before_answering>
```

## 機能別のヒント

### 改善されたビジョン機能

Claude Opus 4.5とClaude Opus 4.6は、以前のClaudeモデルと比較してビジョン機能が改善されています。画像処理とデータ抽出タスク、特にコンテキストに複数の画像が存在する場合により優れたパフォーマンスを発揮します。これらの改善はコンピュータ使用にも引き継がれており、モデルはスクリーンショットやUI要素をより確実に解釈できます。また、動画をフレームに分割することで、これらのモデルを使用して動画を分析することもできます。

パフォーマンスをさらに向上させるのに効果的であることが証明されている手法の一つは、Claudeにクロップツールまたは[スキル](/docs/ja/agents-and-tools/agent-skills/overview)を与えることです。テストでは、Claudeが画像の関連領域に「ズームイン」できる場合、画像評価で一貫した向上が見られました。Anthropicは[クロップツールのクックブック](https://platform.claude.com/cookbook/multimodal-crop-tool)を作成しています。

### フロントエンドデザイン

Claude Opus 4.5とClaude Opus 4.6は、優れたフロントエンドデザインで複雑な実世界のWebアプリケーションを構築します。ただし、ガイダンスがない場合、モデルはユーザーが「AIスロップ」美学と呼ぶものを生み出す汎用的なパターンにデフォルトで従うことがあります。驚きと喜びを与える独特で創造的なフロントエンドを作成するには：

<Tip>
  フロントエンドデザインの改善に関する詳細なガイドについては、[スキルによるフロントエンドデザインの改善](https://www.claude.com/blog/improving-frontend-design-through-skills)に関するブログ記事を参照してください。
</Tip>

API以外でのフロントエンドデザイン作業には、[Claude Design](https://support.claude.com/en/articles/14604416-get-started-with-claude-design)がキャンバスとデザインツールを提供し、Claudeがインタラクティブにデザインを生成・反復します。

より良いフロントエンドデザインを促すために使用できるシステムプロンプトのスニペットを以下に示します。

```text Sample prompt for frontend aesthetics wrap
<frontend_aesthetics>
You tend to converge toward generic, "on distribution" outputs. In frontend design, this
creates what users call the "AI slop" aesthetic. Avoid this: make creative, distinctive
frontends that surprise and delight.

Focus on:
- Typography: Choose fonts that are beautiful, unique, and interesting. Avoid generic
fonts like Arial and Inter; opt instead for distinctive choices that elevate the
frontend's aesthetics.
- Color & Theme: Commit to a cohesive aesthetic. Use CSS variables for consistency.
Dominant colors with sharp accents outperform timid, evenly-distributed palettes. Draw
from IDE themes and cultural aesthetics for inspiration.
- Motion: Use animations for effects and micro-interactions. Prioritize CSS-only
solutions for HTML. Use Motion library for React when available. Focus on high-impact
moments: one well-orchestrated page load with staggered reveals (animation-delay)
creates more delight than scattered micro-interactions.
- Backgrounds: Create atmosphere and depth rather than defaulting to solid colors. Layer
CSS gradients, use geometric patterns, or add contextual effects that match the overall
aesthetic.

Avoid generic AI-generated aesthetics:
- Overused font families (Inter, Roboto, Arial, system fonts)
- Clichéd color schemes (particularly purple gradients on white backgrounds)
- Predictable layouts and component patterns
- Cookie-cutter design that lacks context-specific character

Interpret creatively and make unexpected choices that feel genuinely designed for the
context. Vary between light and dark themes, different fonts, different aesthetics. You
still tend to converge on common choices (Space Grotesk, for example) across
generations. Avoid this: it is critical that you think outside the box!
</frontend_aesthetics>
```

[完全なスキル定義](https://github.com/anthropics/claude-code/blob/main/plugins/frontend-design/skills/frontend-design/SKILL.md)も参照できます。

## 移行に関する考慮事項

以前の世代からClaude 4.6モデルに移行する場合：

1. **望む動作について具体的にする：** 出力で見たいものを正確に記述することを検討してください。

2. **修飾語で指示を組み立てる：** Claudeに出力の品質と詳細を高めるよう促す修飾語を追加すると、Claudeのパフォーマンスをより良く形成できます。たとえば、「分析ダッシュボードを作成してください」の代わりに、「分析ダッシュボードを作成してください。できるだけ多くの関連機能とインタラクションを含めてください。基本を超えて、完全な機能を備えた実装を作成してください」を使用します。

3. **特定の機能を明示的にリクエストする：** アニメーションやインタラクティブな要素は、必要な場合に明示的にリクエストする必要があります。

4. **思考の設定を更新する：** Claude 4.6モデルは、`budget_tokens`を使用した手動思考の代わりに[適応型思考](/docs/ja/build-with-claude/adaptive-thinking)（`thinking: {type: "adaptive"}`）を使用します。思考の深さを制御するには[effortパラメータ](/docs/ja/build-with-claude/effort)を使用してください。

5. **プリフィル応答から移行する：** 最後のアシスタントターンでのプリフィル応答は、Claude 4.6モデル以降サポートされなくなりました。代替手段の詳細なガイダンスについては、[プリフィル応答からの移行](#migrating-away-from-prefilled-responses)を参照してください。

6. **怠惰防止プロンプトを調整する：** 以前のプロンプトでモデルにより徹底的になるよう、またはツールをより積極的に使用するよう促していた場合は、そのガイダンスを控えめにしてください。Claude 4.6モデルはより積極的であり、以前のモデルで必要だった指示に対してオーバートリガーする可能性があります。

詳細な移行手順については、[移行ガイド](/docs/ja/about-claude/models/migration-guide)を参照してください。

### Claude Sonnet 4.5からClaude Sonnet 4.6への移行

移行ガイドの[Sonnet 4.5からの移行](/docs/ja/about-claude/models/migration-guide#migrating-from-sonnet-45)を参照してください。effortのデフォルト変更と、拡張思考の両方の移行パスについて解説しています。

## 次のステップ

<CardGroup cols={2}>
  <Card title="Claude Fable 5のプロンプト作成" icon="terminal" href="/docs/ja/build-with-claude/prompt-engineering/prompting-claude-fable-5">
    Claude Fable 5とClaude Mythos 5の挙動の違いとプロンプトパターン。effort、指示への従順性、長時間実行、メモリ、スキャフォールディングの変更について解説します。
  </Card>

  <Card title="Claude Sonnet 5のプロンプト作成" icon="terminal" href="/docs/ja/build-with-claude/prompt-engineering/prompting-claude-sonnet-5">
    Claude Sonnet 5の挙動の違いとプロンプトパターン。effort、適応型思考のデフォルト、ツール使用、Claude Sonnet 4.6からの移行について解説します。
  </Card>

  <Card title="プロンプトエンジニアリングの概要" icon="edit" href="/docs/ja/build-with-claude/prompt-engineering/overview">
    プロンプトエンジニアリングを使用すべきタイミングと、プロンプトを調整する前のアプローチの計画方法。
  </Card>
</CardGroup>
