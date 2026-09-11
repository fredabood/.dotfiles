# Harvest — bibliographic API playbook

The pipeline's `harvest` command calls Crossref, OpenAlex and Semantic Scholar for you. This
file is for fetching **by hand**: the reader getting an abstract or full text for a harvested
record, or reaching Europe PMC and arXiv, which the automated harvest does not yet cover. It
never licenses adding a source the harvest did not return.

Everything here is keyless. Call these with web fetch; they return JSON that can be read
directly. The `select` / `fields` parameters are **not optional** — without them the
responses are large enough to be truncated mid-record, and a truncated record is a
fabrication risk.

## Query routing

Classify each query, then walk its chain until you have 3 usable records or the chain is
exhausted. Do not call every API for every query — that is how you burn the S2 rate limit.

| Query looks like | Chain |
| --- | --- |
| Academic — `peer-reviewed`, `systematic review`, `meta-analysis`, `empirical`, a method name, a discipline term | Crossref → OpenAlex → Semantic Scholar |
| Biomedical / clinical / life sciences | Europe PMC → Crossref → OpenAlex |
| CS / physics / math / stats, or anything where preprints lead | arXiv → Semantic Scholar → OpenAlex |
| Industry — a consultancy, regulator, standards body, think tank, vendor, or market term | skip the APIs; this query belongs to the step-4 scout |
| Mixed / unclear | OpenAlex → Crossref → Semantic Scholar |

## Endpoints

### Crossref — the DOI registry, best metadata quality

```text
https://api.crossref.org/works?query=<QUERY>&rows=5&sort=relevance&select=DOI,title,author,published,container-title,publisher,volume,issue,page,type&mailto=<EMAIL>
```

- `mailto` is optional but gets you the polite pool (faster, fewer 429s). Use the user's
  address only if they offer it; otherwise omit the parameter entirely.
- Map: `DOI` → doi, `title[0]` → title, `author[].family` → authors,
  `published.date-parts[0][0]` → year, `container-title[0]` → journal, `type` → source type.
- Crossref indexes journals, books, conference proceedings and preprints. It has no
  citation counts and no abstracts for most records.

### OpenAlex — broadest coverage, has citation counts

```text
https://api.openalex.org/works?search=<QUERY>&per-page=5&select=id,doi,title,authorships,publication_year,primary_location,type,cited_by_count&mailto=<EMAIL>
```

- Always set `per-page` (OpenAlex also accepts `per_page`). Without it you get 25 records
  back, which will truncate.
- **The anonymous rate limiter answers HTTP 200** with `{"error": "Rate limit exceeded",
  "retryAfter": N}`. That is not an empty result — wait `retryAfter` seconds and retry once.
- Map: `authorships[].author.display_name` → authors,
  `primary_location.source.display_name` → venue, `cited_by_count` → citation count.
- Add `abstract_inverted_index` to `select` only when you need the abstract; it arrives as a
  `{word: [positions]}` map that must be reconstructed by sorting words by position.
  Prefer Semantic Scholar or Europe PMC for abstracts when either has the record.

### Semantic Scholar — abstracts, citation graph

```text
https://api.semanticscholar.org/graph/v1/paper/search?query=<QUERY>&limit=5&fields=title,authors,year,venue,externalIds,url,citationCount,abstract,publicationTypes
```

- Unauthenticated access is **aggressively rate limited** (~1 request/second shared across
  all anonymous callers; 429s are routine). Treat it as a third choice, not a first, and
  when it 429s, move on rather than retrying — one retry at most.
- `externalIds.DOI` → doi, `externalIds.ArXiv` → arXiv id.

### Europe PMC — biomedical, generous limits, often full text

```text
https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=<QUERY>&format=json&pageSize=5&resultType=core
```

- `resultType=core` includes the abstract. `isOpenAccess: "Y"` with a `pmcid` means full
  text is fetchable at `https://www.ebi.ac.uk/europepmc/webservices/rest/<PMCID>/fullTextXML`.
- Map: `authorString` → authors, `journalTitle` → journal, `pubYear` → year, `doi` → doi.

### arXiv — preprints in CS/physics/math

```text
http://export.arxiv.org/api/query?search_query=all:%22<QUERY>%22&max_results=5&sortBy=relevance
```

- Returns Atom XML, not JSON. Map `entry/title`, `entry/author/name`, `entry/published`
  (year), `entry/id` (URL), `entry/summary` (abstract).
- **Preprints are not peer reviewed.** Tag them `[PREPRINT]` everywhere they appear and
  never present a preprint finding with the same confidence as a published one.

## Building the harvest table

One row per unique record:

```markdown
| #  | Authors (first + et al.) | Year | Title | Venue | DOI / URL | API | Query |
```

**Dedup key:** `(first author lowercased, year, title lowercased)`. On collision keep the
record with more populated fields — merging a Crossref record's DOI into an OpenAlex
record's citation count is fine and desirable.

**Quality gate — drop the record if:**

- no author, no year, or no title;
- year is in the future or before 1900;
- the first author is a URL, a bare domain (`example.edu`), a single character, or an
  institutional placeholder (`Working Paper`, `Anonymous`, `Editors`, `Committee`, `Staff`).

Track per-query yield. A query returning zero records is a **weak query** — it is the input
to step 4, and it is also a signal worth reporting ("no indexed work matches X").

## Stopping

Stop harvesting when you reach `2 × target` unique records or you have run every query,
whichever comes first. Over-harvesting costs fetches and buys nothing — step 5 is where the
budget should go.

## When an API fails

Per-source tolerance: a failed or empty call is not a failed harvest. Move to the next API
in the chain, record the failure, and report it once at the end
("Semantic Scholar rate-limited on 4 of 10 queries"). Never let a failure become an
invented record.
