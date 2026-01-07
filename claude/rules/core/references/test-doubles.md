# テストダブル

## スタブ（Stub）

事前に決められた応答を提供：

```javascript
const emailStub = {
  send: () => true  // 常に成功を返す
};
```

## モック（Mock）

インタラクションを検証：

```javascript
const emailMock = {
  send: jest.fn()
};
userService.registerUser(user);
expect(emailMock.send).toHaveBeenCalledWith(user.email);
```

## フェイク（Fake）

動作する簡易実装：

```javascript
class FakeDatabase {
  constructor() { this.data = new Map(); }
  save(key, value) { this.data.set(key, value); }
  find(key) { return this.data.get(key); }
}
```

## 使い分け

| 種類 | 用途 | 検証対象 |
|------|------|----------|
| スタブ | 依存を置換して制御された応答を返す | 状態 |
| モック | 呼び出しの検証 | インタラクション |
| フェイク | 軽量な実装で動作確認 | 振る舞い |
