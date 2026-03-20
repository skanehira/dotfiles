# スライドナビゲーション

## 機能

- キーボード操作（←→ / スペース / Home / End）
- プログレスバー（画面下部）
- スライド番号表示（現在/全体）
- ウィンドウリサイズ時の自動スケーリング

## JavaScript実装

以下のコードを生成するHTMLの `<script>` タグ内に配置する。

```javascript
(function() {
  'use strict';

  const slides = document.querySelectorAll('.slide');
  const totalSlides = slides.length;
  let currentSlide = 0;

  // ナビゲーションUI要素
  const nav = document.getElementById('slide-nav');
  const progressBar = document.getElementById('slide-progress-bar');
  const slideCounter = document.getElementById('slide-counter');

  // スライド表示
  function showSlide(index) {
    if (index < 0 || index >= totalSlides) return;
    slides[currentSlide].classList.remove('active');
    currentSlide = index;
    slides[currentSlide].classList.add('active');
    updateUI();
  }

  // UI更新
  function updateUI() {
    // プログレスバー
    const progress = ((currentSlide + 1) / totalSlides) * 100;
    progressBar.style.width = progress + '%';

    // スライド番号
    slideCounter.textContent = (currentSlide + 1) + ' / ' + totalSlides;

    // URLハッシュ更新
    history.replaceState(null, '', '#' + (currentSlide + 1));
  }

  // 次のスライド
  function nextSlide() {
    showSlide(currentSlide + 1);
  }

  // 前のスライド
  function prevSlide() {
    showSlide(currentSlide - 1);
  }

  // 特定のスライドへ移動（外部から呼び出し可能）
  window.navigateToSlide = function(n) {
    showSlide(n - 1); // 1-based index
  };

  // キーボードイベント
  document.addEventListener('keydown', function(e) {
    switch(e.key) {
      case 'ArrowRight':
      case ' ':
      case 'PageDown':
        e.preventDefault();
        nextSlide();
        break;
      case 'ArrowLeft':
      case 'PageUp':
        e.preventDefault();
        prevSlide();
        break;
      case 'Home':
        e.preventDefault();
        showSlide(0);
        break;
      case 'End':
        e.preventDefault();
        showSlide(totalSlides - 1);
        break;
    }
  });

  // クリックで次スライド（ナビ部分は除外）
  document.getElementById('slide-container').addEventListener('click', function(e) {
    if (!e.target.closest('#slide-nav')) {
      nextSlide();
    }
  });

  // ウィンドウリサイズ時のスケーリング
  function scaleSlides() {
    const container = document.getElementById('slide-container');
    const scaleX = window.innerWidth / 1920;
    const scaleY = window.innerHeight / 1080;
    const scale = Math.min(scaleX, scaleY);

    slides.forEach(function(slide) {
      slide.style.transform = 'translate(-50%, -50%) scale(' + scale + ')';
    });
  }

  window.addEventListener('resize', scaleSlides);

  // URLハッシュから初期スライドを取得
  function getInitialSlide() {
    const hash = window.location.hash;
    if (hash) {
      const num = parseInt(hash.substring(1), 10);
      if (num >= 1 && num <= totalSlides) {
        return num - 1;
      }
    }
    return 0;
  }

  // 初期化
  currentSlide = getInitialSlide();
  slides[currentSlide].classList.add('active');
  scaleSlides();
  updateUI();
})();
```

## ナビゲーションHTML

`<body>` の末尾、`</body>` の直前に配置する。

```html
<!-- ナビゲーションUI -->
<div id="slide-nav"
     class="fixed bottom-0 left-0 right-0 z-50 transition-opacity duration-300"
     style="opacity: 0.6;"
     onmouseenter="this.style.opacity='1'"
     onmouseleave="this.style.opacity='0.6'">
  <!-- プログレスバー -->
  <div class="w-full h-1" style="background: var(--color-border)">
    <div id="slide-progress-bar"
         class="h-full transition-all duration-300"
         style="background: var(--color-accent); width: 0%">
    </div>
  </div>
  <!-- スライド番号 -->
  <div class="flex justify-end px-6 py-2"
       style="background: rgba(0,0,0,0.03)">
    <span id="slide-counter"
          class="text-sm font-mono"
          style="color: var(--color-text-muted)">
      1 / 1
    </span>
  </div>
</div>
```

## キーボード操作一覧

| キー | 動作 |
|------|------|
| → / Space / PageDown | 次のスライド |
| ← / PageUp | 前のスライド |
| Home | 最初のスライド |
| End | 最後のスライド |

## 品質レビュー時のスライド移動

chrome-devtools MCPでの品質レビュー時は、`evaluate_script` で以下を実行してスライドを移動する：

```javascript
navigateToSlide(3); // 3枚目のスライドに移動
```
