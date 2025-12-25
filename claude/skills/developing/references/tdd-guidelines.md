# TDDガイドラインリファレンス

このドキュメントはテスト駆動開発のプラクティス、パターン、アンチパターンに関する詳細なガイダンスを提供する。

## 高度なテストパターン

### テスト整理戦略

#### 1. Arrange-Act-Assert (AAA) パターン
```javascript
test('shouldCalculateTotalWithTax', () => {
  // Arrange: テストデータと前提条件をセットアップ
  const cart = new ShoppingCart();
  cart.addItem({ price: 100, quantity: 2 });
  const taxRate = 0.1;

  // Act: テスト対象の動作を実行
  const total = cart.calculateTotal(taxRate);

  // Assert: 期待される結果を検証
  expect(total).toBe(220);
});
```

#### 2. テストフィクスチャとセットアップ
```javascript
describe('UserService', () => {
  let userService;
  let mockDatabase;

  beforeEach(() => {
    // すべてのテストに共通のセットアップ
    mockDatabase = new MockDatabase();
    userService = new UserService(mockDatabase);
  });

  afterEach(() => {
    // 各テスト後のクリーンアップ
    mockDatabase.clear();
  });

  test('shouldCreateNewUser', () => {
    // テストの実装
  });
});
```

### テストダブル

#### 1. スタブ - 事前に決められた応答を提供
```javascript
const emailStub = {
  send: () => true  // 常に成功を返す
};
```

#### 2. モック - インタラクションを検証
```javascript
const emailMock = {
  send: jest.fn()
};

userService.registerUser(user);
expect(emailMock.send).toHaveBeenCalledWith(user.email);
```

#### 3. フェイク - 動作する実装
```javascript
class FakeDatabase {
  constructor() {
    this.data = new Map();
  }

  save(key, value) {
    this.data.set(key, value);
  }

  find(key) {
    return this.data.get(key);
  }
}
```

## 言語別TDDの例

### JavaScript/TypeScript (Jest)
```javascript
// user.test.js
describe('User', () => {
  test('shouldHashPasswordOnCreation', () => {
    const user = new User('john@example.com', 'password123');
    expect(user.password).not.toBe('password123');
    expect(user.password.length).toBeGreaterThan(20);
  });
});
```

### Python (pytest)
```python
# test_user.py
def test_should_hash_password_on_creation():
    user = User('john@example.com', 'password123')
    assert user.password != 'password123'
    assert len(user.password) > 20
```

### Rust
```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn should_hash_password_on_creation() {
        let user = User::new("john@example.com", "password123");
        assert_ne!(user.password, "password123");
        assert!(user.password.len() > 20);
    }
}
```

### Go
```go
func TestShouldHashPasswordOnCreation(t *testing.T) {
    user := NewUser("john@example.com", "password123")
    if user.Password == "password123" {
        t.Error("パスワードはハッシュ化されるべき")
    }
    if len(user.Password) <= 20 {
        t.Error("ハッシュ化されたパスワードは20文字より長いべき")
    }
}
```

## 一般的なTDDアンチパターン

### 1. 動作ではなく実装をテストする
❌ **悪い例** - 実装に密結合:
```javascript
test('shouldCallValidateMethodThreeTimes', () => {
  const validator = new Validator();
  const spy = jest.spyOn(validator, 'validate');

  validator.processData(data);

  expect(spy).toHaveBeenCalledTimes(3);
});
```

✅ **良い例** - 動作をテスト:
```javascript
test('shouldRejectInvalidData', () => {
  const validator = new Validator();

  const result = validator.processData(invalidData);

  expect(result.isValid).toBe(false);
  expect(result.errors).toContain('Invalid email format');
});
```

### 2. 複雑すぎるテスト
❌ **悪い例** - テストロジックが複雑すぎる:
```javascript
test('shouldProcessOrders', () => {
  for (let i = 0; i < 10; i++) {
    const order = createOrder(i);
    if (order.total > 100) {
      expect(order.discount).toBeGreaterThan(0);
    } else {
      expect(order.discount).toBe(0);
    }
  }
});
```

✅ **良い例** - シンプルで焦点を絞ったテスト:
```javascript
test('shouldApplyDiscountForOrdersOver100', () => {
  const order = createOrder({ total: 150 });
  expect(order.discount).toBeGreaterThan(0);
});

test('shouldNotApplyDiscountForOrdersUnder100', () => {
  const order = createOrder({ total: 50 });
  expect(order.discount).toBe(0);
});
```

### 3. 脆弱なテスト（アサーションが多すぎる）
❌ **悪い例** - アサーションが多すぎてテストが脆弱:
```javascript
test('shouldCreateUser', () => {
  const user = createUser();

  expect(user.id).toBeDefined();
  expect(user.createdAt).toBeInstanceOf(Date);
  expect(user.updatedAt).toBeInstanceOf(Date);
  expect(user.roles).toEqual(['user']);
  expect(user.isActive).toBe(true);
  expect(user.emailVerified).toBe(false);
  // ... さらに10個のアサーション
});
```

✅ **良い例** - 1つのテストに1つのコンセプト:
```javascript
test('shouldAssignDefaultRoleOnCreation', () => {
  const user = createUser();
  expect(user.roles).toEqual(['user']);
});

test('shouldStartAsActiveUser', () => {
  const user = createUser();
  expect(user.isActive).toBe(true);
});
```

## TDDによる統合テスト

### データベース統合テスト
```javascript
describe('UserRepository Integration', () => {
  let database;
  let repository;

  beforeAll(async () => {
    database = await createTestDatabase();
    repository = new UserRepository(database);
  });

  afterAll(async () => {
    await database.close();
  });

  beforeEach(async () => {
    await database.clear();
  });

  test('shouldPersistUserToDatabase', async () => {
    const user = new User('john@example.com');

    await repository.save(user);
    const retrieved = await repository.findByEmail('john@example.com');

    expect(retrieved.email).toBe('john@example.com');
  });
});
```

### API統合テスト
```javascript
describe('POST /api/users', () => {
  test('shouldCreateNewUser', async () => {
    const response = await request(app)
      .post('/api/users')
      .send({
        email: 'john@example.com',
        password: 'password123'
      });

    expect(response.status).toBe(201);
    expect(response.body).toHaveProperty('id');
    expect(response.body.email).toBe('john@example.com');
  });

  test('shouldReturn400ForInvalidEmail', async () => {
    const response = await request(app)
      .post('/api/users')
      .send({
        email: 'invalid-email',
        password: 'password123'
      });

    expect(response.status).toBe(400);
    expect(response.body.error).toContain('Invalid email');
  });
});
```

## TDDによるE2Eテスト

### ブラウザベースのE2Eテスト
```javascript
describe('User Registration Flow', () => {
  test('shouldCompleteRegistrationSuccessfully', async () => {
    // 登録ページに移動
    await page.goto('http://localhost:3000/register');

    // フォームに入力
    await page.fill('[name="email"]', 'john@example.com');
    await page.fill('[name="password"]', 'password123');
    await page.fill('[name="confirmPassword"]', 'password123');

    // フォームを送信
    await page.click('button[type="submit"]');

    // 成功ページへのリダイレクトを検証
    await expect(page).toHaveURL('http://localhost:3000/registration-success');
    await expect(page.locator('h1')).toContainText('Welcome!');
  });
});
```

## テストカバレッジガイドライン

### 測定すべき指標
- **行カバレッジ**: 実行されたコード行の割合
- **ブランチカバレッジ**: 取られた分岐の割合
- **関数カバレッジ**: 呼び出された関数の割合
- **ステートメントカバレッジ**: 実行された文の割合

### カバレッジ目標
- **ユニットテスト**: 80-90%のカバレッジを目指す
- **統合テスト**: クリティカルパスに焦点
- **E2Eテスト**: 主要なユーザージャーニーをカバー

### カバレッジ ≠ 品質
```javascript
// 100%カバレッジだがテスト品質が低い
test('shouldRunAllCode', () => {
  const result = complexFunction(input);
  expect(result).toBeDefined();  // 弱いアサーション
});

// より良いアプローチ
test('shouldCalculateCorrectResult', () => {
  const result = complexFunction({ x: 5, y: 10 });
  expect(result.total).toBe(15);
  expect(result.status).toBe('success');
});
```

## 継続的テストワークフロー

### ウォッチモード開発
```bash
# 開発中にウォッチモードでテストを実行
npm test -- --watch

# 変更されたファイルに関連するテストのみ実行
npm test -- --watch --onlyChanged
```

### プリコミットフック
```json
{
  "husky": {
    "hooks": {
      "pre-commit": "npm test",
      "pre-push": "npm test && npm run lint"
    }
  }
}
```

### CI/CD統合
```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Run tests
        run: |
          npm install
          npm test
          npm run test:coverage
```

## 異なるコンテキストでのTDD

### レガシーコード
レガシーコードに機能を追加する場合：
1. 特性テストを書く（現在の動作を文書化）
2. テストのセーフティネットでリファクタリング
3. TDDを使用して新機能を追加

### スパイクソリューション
新技術を探索する場合：
1. TDDなしで時間制限付きスパイクを作成
2. スパイクコードを破棄
3. 学んだことを使用してTDDで本番バージョンを実装

### パフォーマンスクリティカルなコード
1. まず機能テストを書く（正確性）
2. パフォーマンスベンチマークをテストとして追加
3. テストをグリーンに保ちながら最適化

## リソースと参考文献

### 書籍
- "Test-Driven Development: By Example" - Kent Beck
- "Growing Object-Oriented Software, Guided by Tests" - Freeman & Pryce
- "Working Effectively with Legacy Code" - Michael Feathers

### オンラインリソース
- Test-driven-development.com
- Martin Fowlerのテストに関する記事
- Uncle BobのClean Codeブログ

### 言語別ツール
- **JavaScript/TypeScript**: Jest, Mocha, Vitest
- **Python**: pytest, unittest
- **Java**: JUnit, TestNG
- **C#**: NUnit, xUnit
- **Ruby**: RSpec, Minitest
- **Go**: testingパッケージ
- **Rust**: 組み込みテストフレームワーク
