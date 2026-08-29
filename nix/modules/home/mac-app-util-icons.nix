{ lib, ... }:

# mac-app-util が生成する trampoline のアイコンを本体アプリのものに揃える (mac only)。
#
# 上流 (hraban/mac-app-util の main.lisp) は trampoline を osacompile で作った
# AppleScript applet として生成し、本体の *.icns をコピーしたうえで Info.plist の
# 一部キー (*copyable-app-props*) を移植する。このリストに CFBundleIconName が
# 含まれないため、applet テンプレート由来の CFBundleIconName = "applet" が残る。
# macOS は CFBundleIconFile より CFBundleIconName (asset catalog 参照) を優先するので、
# applet 同梱の Assets.car にある汎用スクリプトアイコンが表示されてしまう。
#
# CFBundleIconName を削除して CFBundleIconFile (= コピー済みの本体アイコン) に
# 解決させる。上流が修正されたら本モジュールごと削除できる。
{
  home.activation.fixTrampolineIcons = lib.hm.dag.entryAfter [ "trampolineApps" ] ''
    trampolineDir="$HOME/Applications/Home Manager Trampolines"

    for app in "$trampolineDir"/*.app; do
      [ -d "$app" ] || continue
      plist="$app/Contents/Info.plist"

      /usr/bin/plutil -extract CFBundleIconName raw "$plist" >/dev/null 2>&1 || continue

      # CFBundleIconName を消すと CFBundleIconFile にフォールバックするので、その実体が
      # 無いアプリ (アイコンを asset catalog だけで持つもの) では逆にアイコンが消える。
      # 実体を確認できたものだけ処理する。
      iconFile=$(/usr/bin/plutil -extract CFBundleIconFile raw "$plist" 2>/dev/null) || continue
      resources="$app/Contents/Resources"
      [ -e "$resources/$iconFile" ] || [ -e "$resources/$iconFile.icns" ] || continue

      run /usr/bin/plutil -remove CFBundleIconName "$plist"
      # mac-app-util 自身の Info.plist 書き換えで署名は既に invalid になっているが、
      # ad-hoc で署名し直して整合させる (失敗しても activation は止めない)
      run /usr/bin/codesign --force --sign - "$app" 2>/dev/null || true
      # アイコンキャッシュを無効化して再読み込みさせる (上流も同じ理由で touch している)
      run touch "$app"
    done
  '';
}
