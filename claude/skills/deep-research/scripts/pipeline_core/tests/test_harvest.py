"""Harvester behaviour with stub API clients (offline)."""

from __future__ import annotations

from pipeline_core.harvest import Harvester


def _rec(api, i, year=2020):
    return {"title": f"{api} paper {i}", "authors": [f"Author{api}{i}"], "year": year,
            "doi": f"10.1/{api}{i}", "url": f"https://doi.org/10.1/{api}{i}"}


class StubClient:
    def __init__(self, api, n):
        self.api, self.n, self.calls = api, n, 0

    def search_papers(self, query, limit):
        self.calls += 1
        return [_rec(self.api, i) for i in range(min(self.n, limit))]


def _harvester(tmp_path, **clients):
    h = Harvester(cache_dir=tmp_path / "cache")
    h.clients = clients
    h.router.classify_and_route = lambda q: type("R", (), {
        "api_chain": ["crossref", "openalex", "semantic_scholar"]})()
    return h


def test_keeps_up_to_five_records_per_query_from_one_api(tmp_path):
    cr = StubClient("crossref", 5)
    oa = StubClient("openalex", 5)
    h = _harvester(tmp_path, crossref=cr, openalex=oa, semantic_scholar=StubClient("s2", 5))
    result = h.harvest(["one query"], target=10)
    assert result["report"]["per_query"] == {"one query": 5}
    assert len(result["citations"]) == 5
    assert oa.calls == 0  # chain stops once the per-query quota is met


def test_walks_the_chain_until_the_quota_is_met(tmp_path):
    cr = StubClient("crossref", 2)
    oa = StubClient("openalex", 5)
    s2 = StubClient("s2", 5)
    h = _harvester(tmp_path, crossref=cr, openalex=oa, semantic_scholar=s2)
    result = h.harvest(["q"], target=10)
    assert result["report"]["per_query"] == {"q": 5}
    assert [c["api_source"] for c in result["citations"]] == ["crossref"] * 2 + ["openalex"] * 3
    assert s2.calls == 0


def test_cap_draws_round_robin_so_every_query_contributes(tmp_path):
    import random
    import time as _time

    class PerQuery:
        def search_papers(self, query, limit):
            _time.sleep(random.random() / 200)  # scramble completion order
            return [dict(_rec("crossref", i), title=f"{query} #{i}", authors=[f"Smith{query}{i}"])
                    for i in range(limit)]

    queries = [f"q{i}" for i in range(10)]
    h = _harvester(tmp_path, crossref=PerQuery(), openalex=StubClient("openalex", 0),
                   semantic_scholar=StubClient("s2", 0))
    result = h.harvest(queries, target=10)  # cap = max(2*10, 20) = 20 of 50 candidates
    titles = [c["title"] for c in result["citations"]]
    assert len(titles) == 20
    assert {t.split(" #")[0] for t in titles} == set(queries)  # the last query is not starved
    assert titles[:10] == [f"q{i} #0" for i in range(10)]     # plan order, not completion order
    assert result["report"]["per_query"] == {q: 5 for q in queries}


def test_quality_gate_applies_to_every_api(tmp_path):
    class Mixed:
        def search_papers(self, query, limit):
            good = _rec("s2", 1)
            return [good,
                    dict(_rec("s2", 7), authors=["Stafford", "Teamey"]),  # real surnames
                    dict(_rec("s2", 2), year=2999),                    # future
                    dict(_rec("s2", 3), year=1850),                    # pre-1900
                    dict(_rec("s2", 4), authors=["Working Paper"]),    # institutional
                    dict(_rec("s2", 5), authors=["example.edu"]),      # domain as author
                    dict(_rec("s2", 6), authors=[])]                   # no author

    h = _harvester(tmp_path, crossref=StubClient("crossref", 0), openalex=StubClient("openalex", 0),
                   semantic_scholar=Mixed())
    result = h.harvest(["q"], target=5)
    assert [c["title"] for c in result["citations"]] == ["s2 paper 1", "s2 paper 7"]
    assert result["report"]["dropped_quality"] == 5


def test_failing_api_is_tolerated_and_weak_queries_reported(tmp_path):
    class Boom:
        def search_papers(self, query, limit):
            raise RuntimeError("down")

    h = _harvester(tmp_path, crossref=Boom(), openalex=StubClient("openalex", 0),
                   semantic_scholar=StubClient("s2", 0))
    result = h.harvest(["nothing matches"], target=5)
    assert result["citations"] == []
    assert result["report"]["weak_queries"] == ["nothing matches"]
