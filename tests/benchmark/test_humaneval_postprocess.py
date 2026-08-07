# Copyright (c) Alibaba, Inc. and its affiliates.

from evalscope.benchmarks.humaneval.humaneval_adapter import HumanevalAdapter


class TestHumanevalPostprocess:
    def test_standard_fenced_block(self) -> None:
        text = "```python\ndef f():\n    return 1\n```"
        assert HumanevalAdapter._postprocess(text) == "def f():\n    return 1\n"

    def test_trailing_space_after_language(self) -> None:
        text = "```python \ndef f():\n    return 1\n```"
        out = HumanevalAdapter._postprocess(text)
        assert "```" not in out
        assert "def f():" in out

    def test_space_before_language(self) -> None:
        text = "``` python\ndef f():\n    return 1\n```"
        out = HumanevalAdapter._postprocess(text)
        assert "```" not in out
        assert "def f():" in out

    def test_truncated_no_closing_fence(self) -> None:
        text = "```python\ndef f():\n    return 1"
        out = HumanevalAdapter._postprocess(text)
        assert "```" not in out
        assert out == "def f():\n    return 1"

    def test_prose_then_code_block(self) -> None:
        text = "Here is the solution:\n```python\ndef f():\n    return 1\n```"
        assert HumanevalAdapter._postprocess(text) == "def f():\n    return 1\n"

    def test_raw_code_no_fence(self) -> None:
        text = "def f():\n    return 1"
        assert HumanevalAdapter._postprocess(text) == "def f():\n    return 1"

    def test_other_language_tag(self) -> None:
        text = "```py\ndef f():\n    return 1\n```"
        assert HumanevalAdapter._postprocess(text) == "def f():\n    return 1\n"

    def test_empty_text(self) -> None:
        assert HumanevalAdapter._postprocess("") == ""
