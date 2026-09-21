{
  config,
  lib,
  pkgs,
  ...
}:

# ComfyUI (Qwen-Image-2.1 の GUI) を rev 固定で導入し、.app から起動できるようにする (mac only)。
#
# nixpkgs の comfyui は meta.platforms が linux のみで、かつ Qwen-Image-2.1 対応の
# v0.37.0 に追いついていない (2026-09-21 時点で nixpkgs master は 0.35.0)。
# サードパーティの utensils/comfyui-nix も 0.34.0 で、aarch64-darwin のビルドが
# torch 2.5.1 pin のせいで失敗中 (issue #105 が open)。
# よって deno.nix / rustup.nix / vite-plus-bootstrap.nix と同じ bootstrap パターンで、
# commit を本ファイルに固定して drs が冪等に導入する形にする。
# nixpkgs か上流 flake が 0.37 以降 + darwin に追いついたら本モジュールは捨てられる。
let
  # ComfyUI v0.37.0 (2026-09-21)。`feat: Qwen-image 2.1 support (#16400)` を収録する最初のリリース
  rev = "73c9bad4d21e7addbe1d13bc92eee0f1431b017d";

  root = "${config.home.homeDirectory}/.local/share/comfyui";
  venvPython = "${root}/venv/bin/python";
  mainPy = "${root}/ComfyUI/main.py";
  port = "8188";

  # 生成画像だけは ~/.local/share の下だと Finder から探しにくいので Pictures に出す。
  # models / custom_nodes / input / temp / user は --base-directory 側 (clone の外) に残る
  outputDir = "${config.home.homeDirectory}/Pictures/ComfyUI";

  # .app の本体。サーバが起きていなければ起こし、ブラウザを開く。
  # 常駐させない方針なので launchd は使わない (sleepctl.nix のような user agent は作らない)
  launcher = pkgs.writeShellScript "comfyui-launch" ''
    set -u
    url="http://127.0.0.1:${port}/"

    alive() {
      ${pkgs.curl}/bin/curl -fsS -m 2 -o /dev/null "$url"
    }

    fail() {
      /usr/bin/osascript -e "display alert \"ComfyUI を起動できませんでした\" message \"$1\"" >/dev/null 2>&1
      exit 1
    }

    if ! alive; then
      if [ ! -x "${venvPython}" ]; then
        fail "venv がありません。drs を実行してください: ${venvPython}"
      fi

      cd "${root}/ComfyUI" || fail "ComfyUI のディレクトリがありません: ${root}/ComfyUI"
      /usr/bin/nohup "${venvPython}" "${mainPy}" \
        --listen 127.0.0.1 --port ${port} --disable-auto-launch \
        --base-directory "${root}" \
        --output-directory "${outputDir}" \
        >> "${root}/comfyui.log" 2>&1 &

      # 起動には重み無しでも十数秒かかる。120 秒まで待つ
      for _ in $(seq 1 240); do
        alive && break
        /bin/sleep 0.5
      done
      alive || fail "120 秒待っても応答がありません。ログ: ${root}/comfyui.log"
    fi

    /usr/bin/open "$url"
  '';

  # mac-app-util (flake.nix で input 済み) が home.packages 内の .app を
  # ~/Applications/Home Manager Trampolines/ へ trampoline 化し、
  # mac-app-util-icons.nix がアイコンを整える。Spotlight からはこの trampoline が引ける
  comfyuiApp = pkgs.runCommand "comfyui-app" { } ''
    app="$out/Applications/ComfyUI.app"
    mkdir -p "$app/Contents/MacOS"

    cat > "$app/Contents/Info.plist" <<'PLIST'
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleName</key><string>ComfyUI</string>
      <key>CFBundleDisplayName</key><string>ComfyUI</string>
      <key>CFBundleExecutable</key><string>ComfyUI</string>
      <key>CFBundleIdentifier</key><string>org.comfy.ComfyUI-launcher</string>
      <key>CFBundlePackageType</key><string>APPL</string>
      <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
      <key>CFBundleShortVersionString</key><string>0.37.0</string>
      <key>CFBundleVersion</key><string>0.37.0</string>
      <key>LSMinimumSystemVersion</key><string>13.0</string>
      <key>LSUIElement</key><true/>
      <key>NSHighResolutionCapable</key><true/>
    </dict>
    </plist>
    PLIST

    # ヒアドキュメントのインデントを剥がす (<<- はタブしか扱えないため sed で落とす)
    sed -i -e 's/^    //' "$app/Contents/Info.plist"

    # trampoline は CFBundleExecutable を実行するので、symlink ではなく実体を置く
    cp ${launcher} "$app/Contents/MacOS/ComfyUI"
    chmod +x "$app/Contents/MacOS/ComfyUI"
  '';
in
{
  home.packages = [ comfyuiApp ];

  # clone 先 (${root}/ComfyUI) には home.file を一切置かない。
  # HM の linkGeneration は writeBoundary より先に走るため、そこにファイルを宣言すると
  # 新規マシンで先にディレクトリが作られ git clone が「空でないディレクトリ」を拒否する。
  # 設定は launcher が --base-directory / --output-directory で渡す。
  #
  # activation の PATH は最小なので git / uv は絶対 store path で呼ぶ (deno.nix と同じ理由)。
  home.activation.bootstrapComfyui = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    comfyRoot="${root}"
    repo="$comfyRoot/ComfyUI"
    stamp="$comfyRoot/.rev-stamp"

    run mkdir -p "$comfyRoot/models/diffusion_models" "$comfyRoot/models/text_encoders" \
      "$comfyRoot/models/vae" "${outputDir}"

    if [ ! -d "$repo/.git" ]; then
      echo "Bootstrapping ComfyUI (${rev})..." >&2
      run ${pkgs.git}/bin/git clone --filter=blob:none \
        https://github.com/comfyanonymous/ComfyUI.git "$repo" || true
    fi

    if [ -d "$repo/.git" ]; then
      if [ "$(${pkgs.git}/bin/git -C "$repo" rev-parse HEAD 2>/dev/null)" != "${rev}" ]; then
        run ${pkgs.git}/bin/git -C "$repo" fetch origin || true
        run ${pkgs.git}/bin/git -C "$repo" checkout --detach ${rev} || true
      fi
    fi

    # rev が変わった (または初回) ときだけ venv を作り直す。
    # stamp は uv pip install が成功したときにだけ書くので、途中で失敗すれば次回やり直す
    if [ "$(cat "$stamp" 2>/dev/null)" != "${rev}" ] && [ -f "$repo/requirements.txt" ]; then
      echo "Installing ComfyUI dependencies (${rev})..." >&2
      if ${pkgs.uv}/bin/uv venv --python 3.12 "$comfyRoot/venv" \
        && ${pkgs.uv}/bin/uv pip install --python "$comfyRoot/venv/bin/python" \
             -r "$repo/requirements.txt"; then
        echo "${rev}" > "$stamp"
      else
        echo "warning: ComfyUI の依存インストールに失敗した。次回の drs で再試行する" >&2
      fi
    fi

    if [ ! -e "$comfyRoot/models/diffusion_models/qwen_image_2.1_bf16.safetensors" ]; then
      echo "note: Qwen-Image-2.1 の重みが未配置。comfyui/merge-weights.py を 1 回実行する" >&2
    fi
  '';
}
