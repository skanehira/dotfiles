{ lib, ... }:

# mac-app-util が生成する trampoline のアイコンを本体アプリのものに揃える (mac only)。
#
# 上流 (hraban/mac-app-util の main.lisp) は trampoline を osacompile で作った
# AppleScript applet として生成し、本体の *.icns をコピーしたうえで Info.plist の
# 一部キー (*copyable-app-props*) を移植する。しかし applet テンプレート由来の
# Contents/Resources/Assets.car (汎用スクリプトアイコン "applet" のみを含む) はそのまま残る。
#
# macOS 26 (Tahoe) のアイコンパイプラインは、バンドルに Assets.car があると
# Info.plist の CFBundleIconFile / CFBundleIconName の指定に関わらず
# その asset catalog を優先して描画する。そのため plist を書き換えるだけでは足りず、
# applet の Assets.car 自体を捨てないと Spotlight / Finder で汎用アイコンのままになる。
#
# 対処は上流 PR #44 (hraban/mac-app-util、issue #36 に対する未マージの修正) と同じ:
# applet の Assets.car を必ず捨て、本体が asset catalog を持つならそれを CFBundleIconName
# ごと移植し、持たないなら CFBundleIconName を消して icns にフォールバックさせる。
# 上流がマージされたら本モジュールごと削除できる。
{
  home.activation.fixTrampolineIcons = lib.hm.dag.entryAfter [ "trampolineApps" ] ''
    trampolineDir="$HOME/Applications/Home Manager Trampolines"
    sourceDir="$HOME/Applications/Home Manager Apps"

    for app in "$trampolineDir"/*.app; do
      [ -d "$app" ] || continue
      plist="$app/Contents/Info.plist"
      resources="$app/Contents/Resources"

      srcApp="$sourceDir/$(basename "$app")"
      srcPlist="$srcApp/Contents/Info.plist"
      srcCatalog="$srcApp/Contents/Resources/Assets.car"

      # 本体が asset catalog でアイコンを持つか (Assets.car + それを指す CFBundleIconName)
      srcIconName=""
      if [ -f "$srcCatalog" ] && [ -f "$srcPlist" ]; then
        srcIconName=$(/usr/bin/plutil -extract CFBundleIconName raw "$srcPlist" 2>/dev/null) || srcIconName=""
      fi

      # 本体から複製済みの icns が trampoline にあるか (catalog が無いときの受け皿)
      hasIcns=false
      iconFile=$(/usr/bin/plutil -extract CFBundleIconFile raw "$plist" 2>/dev/null) || iconFile=""
      if [ -n "$iconFile" ]; then
        if [ -e "$resources/$iconFile" ] || [ -e "$resources/$iconFile.icns" ]; then
          hasIcns=true
        fi
      fi

      if [ -n "$srcIconName" ]; then
        # 本体の asset catalog をそのまま移植する (Tahoe ネイティブのアイコン描画になる)
        run rm -f "$resources/Assets.car"
        run cp -f "$srcCatalog" "$resources/Assets.car"
        run /usr/bin/plutil -replace CFBundleIconName -string "$srcIconName" "$plist"
      elif [ "$hasIcns" = true ]; then
        # applet の catalog を捨てて CFBundleIconFile (= 複製済みの本体 icns) に解決させる
        run rm -f "$resources/Assets.car"
        run /usr/bin/plutil -remove CFBundleIconName "$plist" >/dev/null 2>&1 || true
      else
        # 代わりのアイコンが無い。applet の catalog を消すとアイコンが消えるだけなので触らない
        continue
      fi

      # mac-app-util 自身の Info.plist 書き換えで署名は既に invalid になっているが、
      # ad-hoc で署名し直して整合させる (失敗しても activation は止めない)
      run /usr/bin/codesign --force --sign - "$app" 2>/dev/null || true
      # アイコンキャッシュを無効化して再読み込みさせる (上流も同じ理由で touch している)
      run touch "$app"
    done
  '';
}
