{ lib, dotfilesRoot, ... }:

let
  # 生成器の呼び出しをランタイム別に組み立てる。activation の中で使う。
  #
  # 出力先が symlink や正本配下に解決する場合、生成器自身が例外で止まる。Home Manager の
  # activation は旧 symlink の撤去 (linkGeneration) が終わるまで待たないと、生成物を
  # 旧 symlink 越しに正本へ書き込んで agents/ を破壊しうるため、DAG でも後ろに置く。
  build = runtime: args: ''
    run "$HOME/.deno/bin/deno" run --allow-read --allow-write --allow-env \
      "${dotfilesRoot}/agents/scripts/build-harness.ts" \
      --runtime ${runtime} \
      --dotfiles-root "${dotfilesRoot}" \
      --vocabulary "${dotfilesRoot}/agents/vocabulary.json" \
      ${args}
  '';

  buildTree =
    runtime: source: out: extra:
    build runtime ''
      --base "${dotfilesRoot}/agents/${source}" \
        --overlay "${dotfilesRoot}/agents/bindings/${runtime}/overlay/${source}" \
        --out "${out}" ${extra}
    '';

  # deno は bootstrapDeno が入れる。無ければ生成をスキップして activation は成功させる
  # (生成物は前回のまま残る)。
  withDeno = body: ''
    if [ ! -x "$HOME/.deno/bin/deno" ]; then
      warnEcho "deno が無いのでハーネスの生成をスキップした"
    else
      ${body}
    fi
  '';

  after = lib.hm.dag.entryAfter [
    "linkGeneration"
    "bootstrapDeno"
  ];
in
{
  # ハーネス (ルール / スキル / subagent) を 3 ランタイム分コンパイルして配る。
  #
  # 正本 agents/ は 1 セットで、ランタイム別の差分は agents/bindings/<runtime>/overlay/ に
  # 節単位で置く。読み手はそれぞれ自分の語彙で書かれた完成品だけを読む。
  #
  # グローバル指示 (AGENTS.md) はまだ symlink のまま。3 者で中身が違い、overlay へ移すのは
  # 語彙の中立化と同じフェーズでまとめて行う。
  home.activation.buildHarness = after (withDeno ''
    ${buildTree "claude" "rules" "$HOME/.claude/rules" ""}
    ${buildTree "claude" "skills" "$HOME/.claude/skills" ""}
    ${buildTree "claude" "subagents" "$HOME/.claude/agents" ""}

    ${buildTree "opencode" "rules" "$HOME/.agents/rules/opencode" ""}
    ${buildTree "opencode" "skills" "$HOME/.config/opencode/skills" ""}
    ${buildTree "opencode" "subagents" "$HOME/.config/opencode/agents" "--subagent-format opencode"}
  '');

  # 旧方式は agents/skills/<name> を ~/.agents/skills/ へ個別 symlink していた。この
  # ディレクトリは Codex と OpenCode の両方が探索し、どちらも探索を止める手段が無いため
  # (OpenCode の skills.paths は追加専用、Codex の skip_host_skill_discovery は roots を
  # 変えない。いずれも実測)、ランタイム別の生成物を置けない。他ツールの領域として空ける。
  #
  # Home Manager は activation script が張った symlink を自動撤去しないので、ここで撤去する。
  # 対象は「target が dotfilesRoot 配下に解決する symlink」だけで、他ツールが置いた実体
  # ディレクトリには触れない。
  home.activation.removeLegacyAgentSkillLinks = after (withDeno ''
    run "$HOME/.deno/bin/deno" run --allow-read --allow-write --allow-env \
      "${dotfilesRoot}/agents/scripts/build-harness.ts" \
      --remove-dotfiles-links "$HOME/.agents/skills" \
      --dotfiles-root "${dotfilesRoot}"
  '');
}
