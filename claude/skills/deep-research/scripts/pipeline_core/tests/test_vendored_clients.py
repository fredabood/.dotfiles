"""Vendored-client tests against recorded fixtures (offline)."""

from __future__ import annotations

import pytest

from pipeline_core.vendor.api_citations import (
    CrossrefClient,
    OpenAlexClient,
    QueryRouter,
    SemanticScholarClient,
)
from pipeline_core.vendor.api_citations import base


def _patch_response(monkeypatch, client, payload):
    monkeypatch.setattr(
        type(client), "_make_request", lambda self, **kwargs: payload, raising=True
    )


class FakeResponse:
    def __init__(self, status, payload):
        self.status_code, self._payload, self.text = status, payload, str(payload)

    def json(self):
        return self._payload


class TestRequestHygiene:
    """Local patch: honest identification, no header spoofing, no proxy rotation."""

    def _capture(self, monkeypatch, client, responses):
        sent = []

        def fake_request(**kwargs):
            sent.append({**kwargs, "headers": {**client.session.headers,
                                               **(kwargs.get("headers") or {})}})
            return responses.pop(0)

        monkeypatch.setattr(client.session, "request", fake_request)
        monkeypatch.setattr(base.time, "sleep", lambda s: None)
        return sent

    def test_identifies_honestly_without_forwarding_or_proxies(self, monkeypatch):
        monkeypatch.setenv("OPENALEX_EMAIL", "someone@example.org")
        client = CrossrefClient()
        sent = self._capture(monkeypatch, client, [FakeResponse(200, {"message": {}})])
        client._make_request(method="GET", endpoint="/works", params={})
        headers = sent[0]["headers"]
        assert "Mozilla" not in headers["User-Agent"]
        assert "deep-research" in headers["User-Agent"]
        assert "mailto:someone@example.org" in headers["User-Agent"]
        assert "X-Forwarded-For" not in headers
        assert sent[0].get("proxies") is None
        assert not hasattr(base, "PROXY_LIST")
        assert not hasattr(base, "USER_AGENTS")

    def test_rate_limit_reported_in_a_200_body_is_retried(self, monkeypatch):
        client = OpenAlexClient()
        limited = FakeResponse(200, {"error": "Rate limit exceeded", "retryAfter": 1})
        ok = FakeResponse(200, {"results": [{"id": "W1"}]})
        sent = self._capture(monkeypatch, client, [limited, ok])
        payload = client._make_request(method="GET", endpoint="/works", params={})
        assert payload == {"results": [{"id": "W1"}]}
        assert len(sent) == 2


class TestCrossref:
    def test_parses_recorded_response(self, monkeypatch, load_fixture):
        client = CrossrefClient()
        _patch_response(monkeypatch, client, load_fixture("crossref_works.json"))
        md = client.search_paper("CRDT overview")
        assert md["title"].startswith("Conflict-free Replicated Data Types")
        assert md["authors"] == ["Preguica", "Baquero", "Shapiro"]
        assert md["year"] == 2018
        assert md["doi"] == "10.1145/3316482"
        assert md["url"] == "https://doi.org/10.1145/3316482"
        assert md["journal"] == "ACM Computing Surveys"

    def test_search_papers_returns_every_usable_record(self, monkeypatch, load_fixture):
        payload = load_fixture("crossref_works.json")
        item = payload["message"]["items"][0]
        payload["message"]["items"] = [item, dict(item, DOI="10.1145/2"), dict(item, author=[])]
        client = CrossrefClient()
        _patch_response(monkeypatch, client, payload)
        papers = client.search_papers("CRDT overview", limit=5)
        assert [p["doi"] for p in papers] == ["10.1145/3316482", "10.1145/2"]

    def test_empty_items_returns_none(self, monkeypatch):
        client = CrossrefClient()
        _patch_response(monkeypatch, client, {"message": {"items": []}})
        assert client.search_paper("nothing") is None
        assert client.search_papers("nothing", limit=5) == []

    def test_no_response_returns_none(self, monkeypatch):
        client = CrossrefClient()
        _patch_response(monkeypatch, client, None)
        assert client.search_paper("nothing") is None


class TestOpenAlex:
    def test_parses_recorded_response(self, monkeypatch, load_fixture):
        client = OpenAlexClient()
        _patch_response(monkeypatch, client, load_fixture("openalex_works.json"))
        md = client.search_paper("local-first software")
        assert md["title"].startswith("Local-First Software")
        assert md["authors"] == ["Kleppmann", "Wiggins"]
        assert md["year"] == 2019
        assert md["doi"] == "10.1109/TPDS.2019.2900000"
        assert md["journal"].startswith("IEEE Transactions")

    def test_missing_authors_rejected(self, monkeypatch, load_fixture):
        payload = load_fixture("openalex_works.json")
        payload["results"][0]["authorships"] = []
        client = OpenAlexClient()
        _patch_response(monkeypatch, client, payload)
        assert client.search_paper("q") is None


class TestSemanticScholar:
    def test_parses_recorded_response(self, monkeypatch, load_fixture):
        client = SemanticScholarClient()
        _patch_response(monkeypatch, client, load_fixture("s2_search.json"))
        md = client.search_paper("CRDT collaborative editing")
        assert md["title"].startswith("A Comprehensive Study")
        assert md["authors"] == ["Attiya", "Burckhardt"]
        assert md["year"] == 2021
        assert md["doi"] == "10.1145/3465084.3467900"

    def test_search_papers_returns_a_list(self, monkeypatch, load_fixture):
        client = SemanticScholarClient()
        _patch_response(monkeypatch, client, load_fixture("s2_search.json"))
        papers = client.search_papers("CRDT collaborative editing", limit=5)
        assert papers and papers[0]["doi"] == "10.1145/3465084.3467900"

    def test_keyless_rate_limit_is_conservative(self):
        client = SemanticScholarClient(api_key=None)
        assert client.rate_limit_per_second <= 0.5

    def test_missing_year_rejected(self, monkeypatch, load_fixture):
        payload = load_fixture("s2_search.json")
        payload["data"][0]["year"] = 0
        client = SemanticScholarClient()
        _patch_response(monkeypatch, client, payload)
        assert client.search_paper("q") is None


class TestQueryRouterPatch:
    """Local vendor patch: keyless chains, openalex routed, no gemini."""

    @pytest.mark.parametrize("qtype", ["academic", "industry", "mixed"])
    def test_chains_are_keyless_and_include_openalex(self, qtype):
        chain = QueryRouter().get_api_chain(qtype)
        assert "gemini_grounded" not in chain
        assert "openalex" in chain
        assert set(chain) == {"crossref", "semantic_scholar", "openalex"}

    def test_classify_and_route_end_to_end(self):
        result = QueryRouter().classify_and_route(
            "distributed consensus algorithms peer-reviewed evaluation"
        )
        assert result.query_type in ("academic", "industry", "mixed")
        assert len(result.api_chain) == 3
        assert "openalex" in result.api_chain
