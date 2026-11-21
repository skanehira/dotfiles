import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import doc_check  # noqa: E402

SCRIPT = Path(__file__).parent / "doc_check.py"


def kinds(text, name="doc.md"):
    return [f.kind for f in doc_check.check_text(text, name)]


class ProcessTest(unittest.TestCase):
    def test_process_phrases_are_reported(self):
        for s in [
            "以前は生成方式で配っていたが、symlink に変更した。",
            "当初は 3 本の agent を使う設計だった。",
            "旧方式 (Home Manager が生成) を使っていたマシンでは、キーを手で削除する。",
            "配布方式を生成方式から symlink へ切り替えた。",
            "この案は撤回した。",
            "TDD ゲートはやめた。",
            "rules を guidelines に改名した。",
            "経緯は DESIGN_NOTES.md にある。",
            "- 旧実装は fetch を直接呼んでいた",
        ]:
            with self.subTest(s=s):
                self.assertEqual(kinds(s), ["process"])

    def test_dated_observation_is_reported(self):
        self.assertEqual(kinds("2026-10-03 のこのマシンでは 6 本とも installed だった。"), ["process"])

    def test_verification_narrative_is_reported(self):
        for s in ["反映は確かめていない。", "これは未実測の推測である。", "Linux では確認していない。",
                  "ループからの推論で、clone の無いマシンは見ていない。"]:
            with self.subTest(s=s):
                self.assertEqual(kinds(s), ["verification"])

    def test_ordinary_sentences_are_not_reported(self):
        for s in [
            "スキルは 3 ランタイムへ配られる。",
            "`以前は` という語を grep する。",
            "スキルを追加・削除したら drs を流す。",
            "設定を変えたときは再起動する。",
            "再送したら以前のコードを失効させる。",
            "旧版の結果で最新を上書きしない。",
            "申請を差し戻した場合は再申請できる。",
            "過程の記録（「以前は〜だったが」）を残さず、最終状態のみを書く。",
            "決定: symlink で配る。理由: 編集が即反映されるため。",
            "その点は本文に推測で補わない。",
        ]:
            with self.subTest(s=s):
                self.assertEqual(kinds(s), [])

    def test_code_blocks_are_ignored_but_list_continuations_are_checked(self):
        text = "# 見出し\n\n```text\n以前は X だったが Y に変更した\n```\n\n    以前は indented code だったが\n\n- 箇条書き\n    以前は箇条書きの続きだったが\n"
        self.assertEqual([(f.line, f.kind) for f in doc_check.check_text(text, "doc.md")], [(10, "process")])

    def test_facts_and_history_sections_are_exempt(self):
        text = "# 設計\n\n## 依拠する外部事実\n\n| 事実 | 確認日 |\n| --- | --- |\n| 2026-10-03 に実測した。反映は確かめていない | 2026-10-03 |\n\n## 本文\n\n以前は X だった。\n"
        self.assertEqual([(f.line, f.kind) for f in doc_check.check_text(text, "doc.md")], [(11, "process")])

    def test_quoted_examples_are_not_reported(self):
        for s in ["「Linux では確かめていない」のような文は本文に書かない。",
                  "例: 「2026-10-03 のこのマシンでは〜だった」は表へ移す。"]:
            with self.subTest(s=s):
                self.assertEqual(kinds(s), [])

    def test_skip_marker_disables_only_process_and_verification(self):
        text = "<!-- doc-check: skip-process -->\n# 規範\n\n撤回した案は台帳に置く。\n\n" + "あ" * 101 + "。\n"
        self.assertEqual([(f.line, f.kind) for f in doc_check.check_text(text, "rule.md")], [(6, "long")])

    def test_record_documents_are_exempt_from_process_checks(self):
        for name in ["docs/DESIGN_NOTES.md", "CHANGELOG.md", "docs/adr/0001-x.md"]:
            with self.subTest(name=name):
                self.assertEqual(kinds("以前は X だったが Y に変更した。", name), [])


class LongSentenceTest(unittest.TestCase):
    def test_sentence_over_100_chars_is_reported(self):
        s = "あ" * 101 + "。"
        self.assertEqual(kinds(s), ["long"])

    def test_sentence_of_100_chars_is_not_reported(self):
        s = "あ" * 99 + "。"
        self.assertEqual(kinds(s), [])

    def test_table_rows_are_not_checked_for_length(self):
        self.assertEqual(kinds("| " + "あ" * 120 + "。 | x |"), [])


class DuplicateTest(unittest.TestCase):
    def test_same_sentence_in_two_sections_is_warned(self):
        s = "OpenCode の常駐サービスは設定とプラグインの変更を検知して読み直す。"
        text = f"## A\n\n{s}\n\n## B\n\n{s}\n"
        self.assertEqual([(f.line, f.kind) for f in doc_check.check_text(text, "doc.md")], [(7, "duplicate")])

    def test_same_sentence_in_one_section_is_not_warned(self):
        s = "OpenCode の常駐サービスは設定とプラグインの変更を検知して読み直す。"
        self.assertEqual(kinds(f"## A\n\n{s}\n\n{s}\n"), [])


class CliTest(unittest.TestCase):
    def run_cli(self, *args, cwd=None):
        return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True, cwd=cwd)

    def test_exit_1_and_location_when_error_found(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "a.md"
            p.write_text("# T\n\n以前は X だった。\n")
            r = self.run_cli(str(p))
            self.assertEqual(r.returncode, 1)
            self.assertEqual(r.stdout.splitlines()[0], f"{p}:3: [process] 過程の記述: 以前は X だった。")

    def test_exit_0_when_only_duplicates(self):
        s = "OpenCode の常駐サービスは設定とプラグインの変更を検知して読み直す。"
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "a.md"
            p.write_text(f"## A\n\n{s}\n\n## B\n\n{s}\n")
            self.assertEqual(self.run_cli(str(p)).returncode, 0)

    def test_base_option_checks_only_added_lines(self):
        with tempfile.TemporaryDirectory() as d:
            git = ["git", "-C", d, "-c", "user.name=t", "-c", "user.email=t@example.invalid"]
            subprocess.run(["git", "init", "-q", d], check=True)
            p = Path(d) / "a.md"
            p.write_text("# T\n\n以前は X だった。\n")
            subprocess.run(git + ["add", "-A"], check=True)
            subprocess.run(git + ["commit", "-qm", "init"], check=True)
            p.write_text("# T\n\n以前は X だった。\n\n当初は Y だった。\n")
            r = self.run_cli("--base", "HEAD", str(p), cwd=d)
            self.assertEqual(r.returncode, 1)
            self.assertEqual([l for l in r.stdout.splitlines() if "[process]" in l],
                             [f"{p}:5: [process] 過程の記述: 当初は Y だった。"])


if __name__ == "__main__":
    unittest.main()
