"""Unit tests for the categorize() logic - no database required.

These tests prove the categorization rules without touching PostgreSQL,
so they run fast in CI. The /summary endpoint is exercised separately
against the live database in the BUILD guide.
"""
from app import categorize


def test_auth_keyword():
    assert categorize("Cannot log in", "password reset") == "auth"


def test_billing_keyword():
    assert categorize("Invoice is wrong", "charged twice") == "billing"


def test_bug_keyword():
    assert categorize("App crashes on upload", None) == "bug"


def test_performance_keyword():
    assert categorize("Slow dashboard", "takes 30s") == "performance"


def test_unmatched_is_uncategorized():
    assert categorize("How do I add a user", "invite a teammate") == "uncategorized"
