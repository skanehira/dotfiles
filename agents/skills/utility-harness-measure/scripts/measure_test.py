import json
import subprocess
import sys
import unittest
from pathlib import Path

import measure


def result_event(model_usage, result="done", is_error=False):
    return {
        "type": "result",
        "is_error": is_error,
        "result": result,
        "modelUsage": {m: {} for m in model_usage},
        "total_cost_usd": 3.5,
    }


ALLOWED = {"claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"}


class CheckRunTest(unittest.TestCase):
    def test_run_on_pinned_model_with_haiku_subagent_is_valid(self):
        events = [result_event(["claude-opus-5-5", "claude-haiku-5-5"])]
        self.assertEqual(
            measure.check_run(events, "claude-opus-5-5", ALLOWED),
            (True, "ok"),
        )

    def test_one_m_context_suffix_is_treated_as_same_model(self):
        events = [result_event(["claude-opus-5-5[1m]"])]
        self.assertEqual(
            measure.check_run(events, "claude-opus-5-5", ALLOWED),
            (True, "ok"),
        )

    def test_run_where_alias_resolved_to_unexpected_model_is_invalid(self):
        events = [result_event(["claude-sonnet-4-6", "claude-sonnet-4-6[1m]"])]
        self.assertEqual(
            measure.check_run(events, "claude-opus-5-5", ALLOWED),
            (False, "想定外のモデル: claude-sonnet-4-6"),
        )

    def test_run_that_consulted_fable_advisor_is_invalid(self):
        events = [result_event(["claude-opus-5-5", "claude-fable-5-1"])]
        self.assertEqual(
            measure.check_run(events, "claude-opus-5-5", measure.allowed_models("claude-opus-5-5")),
            (False, "計測に使わないモデル: claude-fable-5-1"),
        )

    def test_run_executed_on_fable_is_invalid_even_if_it_was_the_requested_model(self):
        events = [result_event(["claude-fable-5-1[1m]"])]
        self.assertEqual(
            measure.check_run(events, "claude-fable-5-1", {"claude-fable-5-1"}),
            (False, "計測に使わないモデル: claude-fable-5-1"),
        )

    def test_run_that_used_mythos_is_invalid(self):
        events = [result_event(["claude-opus-5-5", "claude-mythos-5-1"])]
        self.assertEqual(
            measure.check_run(events, "claude-opus-5-5", measure.allowed_models("claude-opus-5-5")),
            (False, "計測に使わないモデル: claude-mythos-5-1"),
        )

    def test_run_that_never_used_executor_model_is_invalid(self):
        events = [result_event(["claude-haiku-5-5"])]
        self.assertEqual(
            measure.check_run(events, "claude-opus-5-5", ALLOWED),
            (False, "実行モデル claude-opus-5-5 が使われていない"),
        )

    def test_run_stopped_by_usage_limit_is_invalid(self):
        events = [
            result_event(
                ["claude-opus-5-5"],
                result="You've hit your session limit · resets 2:20pm (Asia/Tokyo)",
                is_error=True,
            )
        ]
        self.assertEqual(
            measure.check_run(events, "claude-opus-5-5", ALLOWED),
            (False, "使用量の上限で停止"),
        )

    def test_run_that_ended_in_error_is_invalid(self):
        events = [result_event(["claude-opus-5-5"], result="boom", is_error=True)]
        self.assertEqual(
            measure.check_run(events, "claude-opus-5-5", ALLOWED),
            (False, "エラーで終了: boom"),
        )

    def test_run_without_result_event_is_invalid(self):
        self.assertEqual(
            measure.check_run([{"type": "assistant"}], "claude-opus-5-5", ALLOWED),
            (False, "result イベントが無い (途中で止まった)"),
        )

    def test_unexpected_model_in_earlier_result_of_resumed_run_is_invalid(self):
        events = [result_event(["claude-sonnet-4-6"]), result_event(["claude-opus-5-5"])]
        self.assertEqual(
            measure.check_run(events, "claude-opus-5-5", ALLOWED),
            (False, "想定外のモデル: claude-sonnet-4-6"),
        )

    def test_resumed_run_whose_last_result_hit_usage_limit_is_invalid(self):
        events = [result_event(["claude-opus-5-5"]),
                  result_event(["claude-opus-5-5"], result="Claude usage limit reached",
                               is_error=True)]
        self.assertEqual(
            measure.check_run(events, "claude-opus-5-5", ALLOWED),
            (False, "使用量の上限で停止"),
        )

    def test_final_message_joins_every_result_event_in_order(self):
        # バックグラウンドタスクで再開した回は result が複数出る。読み手はその全部を読む
        events = [result_event(["claude-opus-5-5"], result="first"),
                  {"type": "assistant"},
                  result_event(["claude-opus-5-5"], result="second")]
        self.assertEqual(measure.final_message(events), "first\n\n---\n\nsecond")


class ForbiddenModelCliTest(unittest.TestCase):
    def test_run_and_grade_refuse_fable_and_mythos_before_launching_claude(self):
        cases = [
            (["run", "--topic", "t", "--label", "l"], "claude-fable-5-1"),
            (["run", "--topic", "t", "--label", "l"], "claude-mythos-5-1[1m]"),
            (["grade", "--topic", "t", "--labels", "l"], "claude-fable-5-1"),
        ]
        for argv, model in cases:
            with self.subTest(cmd=argv[0], model=model):
                # PATH を空にして claude を見つけられなくする。起動前に拒否していれば、
                # claude が無いことのエラーより先に禁止のエラーで止まる
                proc = subprocess.run(
                    [sys.executable, "-B", str(Path(measure.__file__)), *argv, "--model", model],
                    capture_output=True, text=True, env={"PATH": ""})
                self.assertEqual(
                    (proc.returncode, proc.stdout, proc.stderr),
                    (1, "", f"{model} は計測に使わない (Fable と Mythos のモデルは実行・採点とも禁止)\n"),
                )


class ChildEnvTest(unittest.TestCase):
    def test_child_env_keeps_only_what_claude_needs_and_drops_credentials(self):
        parent = {"PATH": "/bin", "HOME": "/h", "USER": "u", "LANG": "ja_JP.UTF-8",
                  "GH_TOKEN": "secret", "AWS_SECRET_ACCESS_KEY": "secret",
                  "CLAUDE_CODE_MESSAGING_TOKEN": "secret", "ANTHROPIC_MODEL": "opusplan"}
        self.assertEqual(
            measure.child_env(parent),
            {"PATH": "/bin", "HOME": "/h", "USER": "u", "LANG": "ja_JP.UTF-8"},
        )


class ParseGraderOutputTest(unittest.TestCase):
    def test_reads_result_from_event_array_and_strips_code_fence(self):
        raw = json.dumps([
            {"type": "system"},
            {"type": "result", "result": '```json\n{"X01": {"S1": 2}}\n```',
             "modelUsage": {"claude-opus-5-5": {}}},
        ])
        self.assertEqual(
            measure.parse_grader_output(raw),
            ({"X01": {"S1": 2}}, ["claude-opus-5-5"]),
        )

    def test_output_that_is_not_json_raises_readable_error(self):
        with self.assertRaises(ValueError) as ctx:
            measure.parse_grader_output("Not logged in · Please run /login\n")
        self.assertEqual(
            str(ctx.exception),
            "採点の出力が読めない: Not logged in · Please run /login",
        )

    def test_grader_answer_that_is_not_json_raises_readable_error(self):
        raw = json.dumps({"type": "result", "result": "採点できませんでした",
                          "modelUsage": {"claude-opus-5-5": {}}})
        with self.assertRaises(ValueError) as ctx:
            measure.parse_grader_output(raw)
        self.assertEqual(
            str(ctx.exception),
            "採点の出力が読めない: 採点できませんでした",
        )

    def test_output_without_result_event_raises_readable_error(self):
        with self.assertRaises(ValueError) as ctx:
            measure.parse_grader_output(json.dumps([{"type": "system"}]))
        self.assertEqual(str(ctx.exception), "採点の出力に result イベントが無い")

    def test_reads_last_result_when_grader_output_has_several(self):
        raw = json.dumps([
            {"type": "result", "result": '{"X01": {"S1": 0}}', "modelUsage": {"claude-fable-5-1": {}}},
            {"type": "result", "result": '{"X01": {"S1": 2}}', "modelUsage": {"claude-opus-5-5": {}}},
        ])
        self.assertEqual(
            measure.parse_grader_output(raw),
            ({"X01": {"S1": 2}}, ["claude-opus-5-5"]),
        )

    def test_reads_result_from_single_object(self):
        raw = json.dumps({"type": "result", "result": '{"X01": {"S1": 0}}',
                          "modelUsage": {"claude-opus-5-5[1m]": {}}})
        self.assertEqual(
            measure.parse_grader_output(raw),
            ({"X01": {"S1": 0}}, ["claude-opus-5-5"]),
        )


EXPECTED = {
    "items": ["S1", "S2"],
    "max": 2,
    "controls": {"pos": {"S1": 2, "S2": 2}, "neg": {"S1": 0, "S2": 0}},
}


class ValidateControlsTest(unittest.TestCase):
    def test_controls_scored_as_expected_produce_no_errors(self):
        key = {"X01": "control:pos", "X02": "control:neg"}
        scores = {"X01": {"S1": 2, "S2": 2}, "X02": {"S1": 0, "S2": 0}}
        self.assertEqual(measure.validate_controls(scores, key, EXPECTED), [])

    def test_control_scored_differently_is_reported(self):
        key = {"X01": "control:pos", "X02": "control:neg"}
        scores = {"X01": {"S1": 2, "S2": 1}, "X02": {"S1": 0, "S2": 0}}
        self.assertEqual(
            measure.validate_controls(scores, key, EXPECTED),
            ["対照 pos の S2: 期待 2 / 実際 1"],
        )

    def test_run_entries_are_not_checked_against_control_expectations(self):
        key = {"X01": "before/a-1", "X02": "control:pos", "X03": "control:neg"}
        scores = {"X01": {"S1": 1, "S2": 1}, "X02": {"S1": 2, "S2": 2},
                  "X03": {"S1": 0, "S2": 0}}
        self.assertEqual(measure.validate_controls(scores, key, EXPECTED), [])

    def test_control_score_missing_an_item_is_reported(self):
        key = {"X01": "control:pos", "X02": "control:neg"}
        scores = {"X01": {"S1": 2}, "X02": {"S1": 0, "S2": 0}}
        self.assertEqual(
            measure.validate_controls(scores, key, EXPECTED),
            ["対照 pos の S2: 期待 2 / 実際 None"],
        )

    def test_missing_control_score_is_reported(self):
        key = {"X01": "control:pos", "X02": "control:neg"}
        scores = {"X01": {"S1": 2, "S2": 2}}
        self.assertEqual(
            measure.validate_controls(scores, key, EXPECTED),
            ["対照 neg の採点が無い"],
        )


class BlindAssignTest(unittest.TestCase):
    def test_assignment_is_deterministic_for_seed_and_covers_every_item(self):
        items = ["before/a-1", "before/a-2", "after/a-1", "control:pos"]
        first = measure.blind_assign(items, seed=7)
        self.assertEqual(first, measure.blind_assign(items, seed=7))
        self.assertEqual(sorted(first.values()), sorted(items))
        self.assertEqual(sorted(first.keys()), ["X01", "X02", "X03", "X04"])


    def test_order_is_shuffled_and_depends_on_seed(self):
        # 改訂前後が入力順のまま並ぶと、採点器が順序から条件を推測できてしまう
        items = [f"before/a-{i}" for i in range(1, 5)] + [f"after/a-{i}" for i in range(1, 5)]
        by_seed = {seed: [measure.blind_assign(items, seed)[f"X{i:02d}"] for i in range(1, 9)]
                   for seed in (1, 2, 3)}
        self.assertTrue(all(order != items for order in by_seed.values()))
        self.assertEqual(len({tuple(o) for o in by_seed.values()}), 3)


class AggregateTest(unittest.TestCase):
    def test_summarizes_full_scores_and_per_item_max_counts_by_label_and_scenario(self):
        key = {"X01": "before/a-1", "X02": "before/a-2", "X03": "after/a-1",
               "X04": "control:pos"}
        scores = {
            "X01": {"has_decision": True, "S1": 0, "S2": 2},
            "X02": {"has_decision": True, "S1": 2, "S2": 2},
            "X03": {"has_decision": True, "S1": 2, "S2": 2},
            "X04": {"has_decision": True, "S1": 2, "S2": 2},
        }
        self.assertEqual(
            measure.aggregate(scores, key, EXPECTED),
            [
                {"label": "after", "scenario": "a", "runs": 1, "full": 1,
                 "mean": 4.0, "max_counts": {"S1": 1, "S2": 1}},
                {"label": "before", "scenario": "a", "runs": 2, "full": 1,
                 "mean": 3.0, "max_counts": {"S1": 1, "S2": 2}},
            ],
        )

    def test_groups_by_hyphenated_scenario_name_and_rounds_mean_to_one_decimal(self):
        key = {"X01": "after/completion-decision-1", "X02": "after/completion-decision-2",
               "X03": "after/completion-decision-3", "X04": "after/escalation-force-push-1"}
        scores = {
            "X01": {"has_decision": True, "S1": 2, "S2": 2},
            "X02": {"has_decision": True, "S1": 2, "S2": 2},
            "X03": {"has_decision": True, "S1": 1, "S2": 2},
            "X04": {"has_decision": True, "S1": 0, "S2": 0},
        }
        self.assertEqual(
            measure.aggregate(scores, key, EXPECTED),
            [
                {"label": "after", "scenario": "completion-decision", "runs": 3, "full": 2,
                 "mean": 3.7, "max_counts": {"S1": 2, "S2": 3}},
                {"label": "after", "scenario": "escalation-force-push", "runs": 1, "full": 0,
                 "mean": 0.0, "max_counts": {"S1": 0, "S2": 0}},
            ],
        )

    def test_scores_of_run_marked_without_decision_are_ignored(self):
        key = {"X01": "before/a-1"}
        scores = {"X01": {"has_decision": False, "S1": 2, "S2": 2}}
        self.assertEqual(
            measure.aggregate(scores, key, EXPECTED),
            [{"label": "before", "scenario": "a", "runs": 1, "full": 0,
              "mean": 0.0, "max_counts": {"S1": 0, "S2": 0}}],
        )

    def test_run_without_decision_request_counts_as_zero(self):
        key = {"X01": "before/a-1"}
        scores = {"X01": {"has_decision": False, "S1": None, "S2": None}}
        self.assertEqual(
            measure.aggregate(scores, key, EXPECTED),
            [{"label": "before", "scenario": "a", "runs": 1, "full": 0,
              "mean": 0.0, "max_counts": {"S1": 0, "S2": 0}}],
        )


if __name__ == "__main__":
    unittest.main()
