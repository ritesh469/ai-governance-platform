"""Tests for Layer 3 (data governance) column tagging and masking.

These import agent.data_tags, which depends only on PyYAML — so they run in
CI in seconds without mlflow, guardrails, or a running stack. That is the
point of the split: pure logic should be testable without the whole runtime.
"""
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO))

from agent.data_tags import MASK_ALL, local_column_tags, mask_record  # noqa: E402

TAGS_FILE = REPO / "data-governance" / "column_tags.yaml"


class TestMaskRecord:
    def test_masks_only_the_named_columns(self):
        record = {"customer_id": 1, "name": "Ada", "email": "ada@example.com"}
        out = mask_record(record, ["email"])
        assert "MASKED" in out["email"]
        assert "ada@example.com" not in out["email"]
        assert out["name"] == "Ada", "untagged column must pass through untouched"
        assert out["customer_id"] == 1

    def test_unknown_column_is_ignored(self):
        assert mask_record({"name": "Ada"}, ["nonexistent"]) == {"name": "Ada"}

    def test_empty_mask_list_changes_nothing(self):
        record = {"name": "Ada", "email": "ada@example.com"}
        assert mask_record(record, []) == record

    def test_does_not_mutate_the_input(self):
        record = {"email": "ada@example.com"}
        mask_record(record, ["email"])
        assert record["email"] == "ada@example.com"

    def test_wildcard_masks_every_column(self):
        """The fail-closed path returns [MASK_ALL] when no tag source is
        reachable — nothing may leak, including untagged columns."""
        record = {"customer_id": 1, "name": "Ada", "email": "ada@example.com"}
        out = mask_record(record, [MASK_ALL])
        assert set(out) == set(record), "column names are kept, values are not"
        assert all("MASKED" in v for v in out.values())
        assert "ada@example.com" not in out.values()
        assert "Ada" not in out.values()


class TestLocalColumnTags:
    def test_reads_tags_from_the_local_source(self):
        cols = local_column_tags("customers", path=str(TAGS_FILE))
        assert cols is not None, "lite-profile tag source must resolve 'customers'"
        by_name = {c["name"]: c["tags"] for c in cols}
        assert "PII.Sensitive" in by_name["email"]
        assert by_name["name"] == [], "only email is tagged PII in this dataset"

    def test_unknown_table_returns_none(self):
        assert local_column_tags("no_such_table", path=str(TAGS_FILE)) is None

    def test_missing_file_returns_none_rather_than_raising(self):
        assert local_column_tags("customers", path=str(REPO / "nope.yaml")) is None

    def test_tags_match_the_ingest_scripts_pii_list(self):
        """Guards against drift: the lite tag source and the OpenMetadata
        ingest script must agree on which columns are PII, or the two
        profiles would enforce different things."""
        import ast
        import re

        src = (REPO / "data-governance" / "ingest_and_tag_pii.py").read_text(encoding="utf-8")
        m = re.search(r"PII_COLUMNS\s*=\s*(\{.*?\})", src, re.S)
        assert m, "PII_COLUMNS not found in ingest_and_tag_pii.py"
        expected = ast.literal_eval(m.group(1))

        for table, pii_cols in expected.items():
            cols = local_column_tags(table, path=str(TAGS_FILE))
            assert cols is not None, f"local tag source is missing table '{table}'"
            tagged = {c["name"] for c in cols if "PII.Sensitive" in c["tags"]}
            assert tagged == set(pii_cols), (
                f"{table}: lite source tags {tagged}, ingest script tags {set(pii_cols)}"
            )

    def test_tag_source_matches_the_real_table_schema(self):
        """Every column in the tag file must exist in the database schema —
        a tag on a column that was renamed or dropped silently protects
        nothing."""
        import re

        ddl = (REPO / "data-governance" / "init_db.sh").read_text(encoding="utf-8")
        m = re.search(r"CREATE TABLE customers \((.*?)\);", ddl, re.S)
        assert m, "customers DDL not found"
        real = {
            line.strip().split()[0]
            for line in m.group(1).strip().splitlines()
            if line.strip() and not line.strip().startswith(")")
        }
        tagged = {c["name"] for c in local_column_tags("customers", path=str(TAGS_FILE))}
        assert tagged <= real, f"tag file names columns not in the schema: {tagged - real}"
