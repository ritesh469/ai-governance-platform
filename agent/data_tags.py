"""Layer 3 column tags and masking — deliberately dependency-light.

Split out of governance_middleware so this logic can be imported and tested
without pulling in mlflow, guardrails, agent_os and a running stack. That
matters: when these functions lived in governance_middleware, the only way
to exercise them was inside the full agent image, so CI either skipped them
entirely (a green build proving nothing) or had to install the whole runtime
to test pure string handling.

Only the tag SOURCE lives here. The masking DECISION is always OPA's --
see get_mask_columns() in governance_middleware and the
governance/data_access rule in policy/policies/data_access.rego.
"""
import os

import yaml

# Where column tags come from when OpenMetadata isn't running (lite profile).
LOCAL_TAGS_FILE = os.environ.get("LOCAL_COLUMN_TAGS_FILE", "/app/data-governance/column_tags.yaml")

# What Layer 3 does when NO tag source can be reached at all. "open" serves
# the row unmasked (convenient for a demo); "closed" masks every column
# rather than risk leaking PII the catalog would have flagged. A real
# high-risk deployment wants "closed" -- an unreachable catalog is not
# evidence that a column is safe.
DATA_LAYER_FAIL_MODE = os.environ.get("DATA_LAYER_FAIL_MODE", "open").lower()

# Returned instead of a column list when no tag source could be reached and
# the fail mode is "closed". mask_record() expands it to every column.
MASK_ALL = "*"


def local_column_tags(table_name: str, path: str | None = None) -> list[dict] | None:
    """Reads per-column tags from the local YAML tag source. Same shape
    OpenMetadata returns, so OPA sees an identical input either way."""
    try:
        with open(path or LOCAL_TAGS_FILE, encoding="utf-8") as fh:
            doc = yaml.safe_load(fh) or {}
        columns = (doc.get("tables") or {}).get(table_name)
        if not columns:
            return None
        return [{"name": c["name"], "tags": list(c.get("tags") or [])} for c in columns]
    except (OSError, yaml.YAMLError) as e:
        print(f"[governance] local tag source unavailable ({e})")
        return None


def mask_record(record: dict, mask_columns: list[str]) -> dict:
    """Applies OPA's masking verdict to one row. Never mutates the input."""
    masked = dict(record)
    if MASK_ALL in mask_columns:  # fail-closed: no tag source was reachable
        return {col: f"***MASKED ({col}, no tag source)***" for col in masked}
    for col in mask_columns:
        if col in masked:
            masked[col] = f"***MASKED ({col}, PII.Sensitive)***"
    return masked
