# Stripe CLI/API対応表

- 種別: スキル補助手順書
- 仕様確認日: 2026-09-18。実行時にCLIのhelpと公式APIリファレンスを再確認する。

## コマンドの組み立て

Stripe CLIの`stripe get` / `stripe post`でAPIを呼ぶ。`-d`でネストしたパラメータ、`--idempotency`で再送用キー、`--project-name`でプロファイル、`--live`で本番を指定する。利用CLIの`--dry-run`は送信せず組み立て内容を確認する。

以下は**プレースホルダーを含むドライラン例**。`cus_EXAMPLE`等をそのまま実行用IDにしない。実行時にはSKILL.mdの合意・権限・重複確認を済ませ、jobに記録した値を使う。税率等の値は案件に従う。

```bash
stripe post /v1/checkout/sessions --dry-run \
  --project-name default \
  --idempotency job-UUID-setup-1 \
  -d mode=setup \
  -d currency=jpy \
  -d customer=cus_EXAMPLE \
  -d payment_method_configuration=pmc_EXAMPLE \
  -d 'metadata[billing_job_id]=UUID' \
  -d 'success_url=https://example.com/card-registration-complete'
```

この例はテストモード。実際のURLは顧客向けに利用できる承認済みのページへ置き換える。`success_url`の存在や到達はカード登録成功の証拠にしない。APIバージョンに応じた`integration_identifier`が要求・推奨される場合は、公式仕様で対応を確認して用途名＋ランダムな8英字を指定する。

## データの流れ

| 操作・API | 入力の要点 | 次で使う出力・検証 |
| --- | --- | --- |
| GET `/v1/account` | CLIプロファイル・環境 | `id`を請求元と照合。アカウント応答全文は出力しない |
| GET/POST `/v1/customers` | 正式名称・メール・契約の対応情報 | `cus_`をSessionとScheduleに渡す。メールの一致だけで別会社を統合しない |
| GET/POST `/v1/products` | 顧客に表示するサービス名 | `prod_`をPriceへ渡す |
| GET/POST `/v1/prices` | `product`、`currency`、`unit_amount`、`recurring[interval]=month`、`recurring[interval_count]=1`、`tax_behavior` | `price_`をScheduleへ渡す。JPYの48,000円は`48000`で、100倍しない |
| GET/POST `/v1/tax_rates` | 合意済み`percentage`、`inclusive`、表示名、国・地域 | `txr_`をphaseの`default_tax_rates`へ渡す。税抜価格の宣言だけでは加算されない |
| GET/POST `/v1/payment_method_configurations` | 専用設定の作成が許可された場合は`name`と`card[display_preference][preference]=on`。カード以外の方法は対応フィールドを公式仕様で列挙して`off` | `pmc_`。GETでactive・card.availableと実効表示値を確認。カードブランドはカードと別の支払手段として一括無効化しない |
| POST `/v1/checkout/sessions` | 上記ドライラン例＋案件の説明文 | `cs_`、`url`、`expires_at`。Customerと`mode=setup`を確認 |
| GET `/v1/checkout/sessions/{id}` | 保存した`cs_` | `status`、`customer`、`setup_intent`を検証。`payment_status`だけでsetup完了と判断しない |
| GET `/v1/setup_intents/{id}` | Sessionの`setup_intent` | `status=succeeded`、`usage=off_session`、`payment_method`、`customer`を検証 |
| GET `/v1/payment_methods/{id}` | SetupIntentの`payment_method` | `pm_`、`type=card`、`customer`、`livemode`を検証 |
| POST `/v1/checkout/sessions/{id}/expire` | 置換を依頼された有効Session | 旧URLの失効を確認。既にcompleteなら新URLを作らず登録内容を再照合 |
| GET `/v1/subscriptions` | `customer`、`status=all`、ページング | 同一契約の既存請求を確認 |
| GET `/v1/subscription_schedules` | `customer`、ページング | 未開始・有効な予約と`metadata[billing_job_id]`を照合 |
| GET `/v1/invoiceitems` | `customer`、`pending=true`、ページング | 次回請求に混ざり得る未請求項目を確認 |
| GET `/v1/customers/{id}` | 顧客ID。適用中APIの割引等を必要に応じexpand | 残高、税免除、割引等の金額への影響を確認 |
| POST `/v1/invoices/create_preview` | 初回見積りは作成前なら`customer`と`schedule_details`、作成後なら`schedule` | 請求書を確定せず期間・小計・税・税込額を取得。割引・残高等による請求額とカード決済額の差も照合 |
| POST/GET `/v1/subscription_schedules` | 下記の将来開始予約 | `sub_sched_`を保存・再取得。開始後の`sub_`は後から取得可能 |

一覧APIは`has_more`がfalseになるまで`starting_after`等の対応パラメータで取得する。名前や先頭ページだけで「存在しない」と判断しない。APIエラーの再試行は、同じ方式で2〜3回失敗したら仕様と入力を再確認し、新規IDの量産で回避しない。

GETには対象リソースの読取、作成・変更には書込権限を用意する。制限付きキーの権限名やリソース間の依存は最新の[制限付きキー](https://docs.stripe.com/keys/restricted-api-keys)で確認する。請求プレビューのPOSTも必要権限を確認する。権限不足なら対象APIと段階を報告し、キーの全権化や秘密値の提示を要求しない。

`schedule_details`はSchedule作成パラメータの丸ごとコピーではない。対応する開始日時・カード・税等をphase内のフィールドへ写す。継続額を`preview_mode=recurring`で別途見積もる場合は、schedule系パラメータを渡さず、同じ料金・税等を指定した`subscription_details.items`または開始後の`subscription`を使う。この継続額見積りは次回請求の厳密な期間・一時項目を保証しない。確定していない項目を検証済みと報告しない。

PaymentMethodConfigurationの`display_preference.preference`は希望値、`display_preference.value`は実効値、`available`は利用可否。継承設定や未指定の方法が残り得るため、作成パラメータだけでカード専用と判定せず、GET応答と対象Checkoutの条件を確認する。設定だけで判定できなければURLを顧客へ渡す前に登録画面で表示方法を確認する。

## 将来開始予約の形

以下の`START_UNIX_SECONDS`は、合意したタイムゾーン付き開始日時をUnix秒に変換した整数へ置換する。`UUID`はjob ID、`pm_`はそのjobで成功確認したカード、`price_`・`txr_`は照合済みの月額料金と手動税率。無税・Stripe Taxの案件はこの手動税率の例をそのまま使わない。

```bash
stripe post /v1/subscription_schedules --dry-run \
  --project-name default \
  --idempotency job-UUID-schedule-1 \
  -d customer=cus_EXAMPLE \
  -d start_date=START_UNIX_SECONDS \
  -d end_behavior=release \
  -d 'metadata[billing_job_id]=UUID' \
  -d 'default_settings[collection_method]=charge_automatically' \
  -d 'default_settings[default_payment_method]=pm_EXAMPLE' \
  -d 'default_settings[automatic_tax][enabled]=false' \
  -d 'phases[0][metadata][billing_job_id]=UUID' \
  -d 'phases[0][items][0][price]=price_EXAMPLE' \
  -d 'phases[0][items][0][quantity]=1' \
  -d 'phases[0][default_tax_rates][0]=txr_EXAMPLE' \
  -d 'phases[0][duration][interval]=month' \
  -d 'phases[0][duration][interval_count]=1'
```

`duration`は予約管理のphaseの長さ。契約終了日ではない。`release`でphase終了後のSubscriptionを継続させる。開始前の`subscription=null`を理由に別Subscriptionを作らない。将来開始直前・直後の実行は日時を再確認し、開始が過去になっていたら停止する。

## 検証シナリオ

文書レビュー・ドライランで検証できる範囲と、明示的に許可されたテストアカウントでのみ確認できる範囲を分ける。

| シナリオ | 期待する行動・結果 |
| --- | --- |
| 別顧客の新規案件 | 顧客名、50,000円等の別料金、別の開始日を入力から採用。前の案件の値を使わない |
| URL発行までを依頼 | `awaiting_card`で終了。カード登録・予約・決済を完了したと報告しない |
| URL失効 | 同じCustomerで新Sessionを作成。顧客・Price・Scheduleを重複作成しない |
| 有効URL・登録済みURLの再発行依頼 | 有効なら再利用。登録済みならAPIで検証してactivateの許可範囲を判断 |
| setup未完了・別顧客・別環境 | 予約しない。成功ページだけで成功扱いしない |
| POST応答の消失・再実行 | jobとStripeを再取得し既存IDを回収。同じ契約の予約は1件 |
| POST成功直後中断し開始後に再開 | active/releasedのScheduleとSubscriptionを回収。開始日超過を理由に再作成しない |
| 登録期限が2時間後・数か月後 | 業務期限を記録。短いURL期限はAPI許容範囲で設定し、長期の業務期限とURL失効を区別 |
| 7/7まで前払い済み、8/8開始を指定 | 7/8〜8/7の扱いを確認。1か月分を無断で免除・追加請求しない |
| 10%外税・48,000円の案件 | 請求プレビューの小計48,000円・税4,800円・合計52,800円を照合 |
| 割引やクレジットがある既存顧客 | 想定額との差を検知して扱いを確認。他契約の設定を削除しない |
| 将来開始と無期限継続 | 開始前に料金請求なし、開始日に初回分、1か月後にも同額の更新。テストクロック等で確認する場合はテスト環境のみ |
| 開始日超過・不明な本番権限 | 即時課金や`--live`の無断追加を行わない |
| 通常解約の日割りなし＋提供者責任の返金条項 | 通常解約条件と例外返金を別々に保持する |

## 依拠する外部事実

2026-09-18時点で公式仕様とローカルCLIのhelpを確認。helpの存在・ドライラン成功はAPI受理の証明ではない。

- [CLI](https://docs.stripe.com/cli)：コマンドと対象環境。認証情報は出力しない。
- [カードを保存して後日決済](https://docs.stripe.com/payments/checkout/save-and-reuse)：setupモード、Customer指定、SetupIntentからPaymentMethodを取得する流れ。
- [Checkout Session作成](https://docs.stripe.com/api/checkout/sessions/create)：`expires_at`は作成後30分〜24時間、標準24時間。`success_url`・`payment_method_configuration`を確認する。
- [支払い方法設定の作成](https://docs.stripe.com/api/payment_method_configurations/create)・[設定オブジェクト](https://docs.stripe.com/api/payment_method_configurations/object)：カード用設定と実効表示値。
- [請求プレビュー](https://docs.stripe.com/api/invoices/create_preview)・[未請求項目](https://docs.stripe.com/api/invoiceitems/list)：想定額に影響する項目と将来の請求額の照合。
- [将来決済の同意](https://docs.stripe.com/payments/setup-intents)：支払い方法の保存とoff-session利用の同意。
- [手動税率](https://docs.stripe.com/billing/taxes/tax-rates)：内税・外税とSubscriptionへの適用。税率変更は手動更新が必要。
- [Schedule作成](https://docs.stripe.com/api/subscription_schedules/create)：将来の`start_date`、phaseの`duration`、既定のカード・税率。
- [Scheduleの継続](https://docs.stripe.com/billing/subscriptions/subscription-schedules)：`release`はSubscriptionを継続し、`cancel`は終了させる。
- [冪等リクエスト](https://docs.stripe.com/api/idempotent_requests)：同じキーの再試行と、保存期限経過後の再実行の区別。
