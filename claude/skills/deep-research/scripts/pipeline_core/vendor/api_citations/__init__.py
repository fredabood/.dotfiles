"""Keyless academic citation clients (vendored from opendraft 1.7.4, MIT).

Local patch: the upstream package __init__ imported the Gemini-entangled
CitationResearcher orchestrator — not vendored; pipeline_core.harvest is
the replacement orchestrator. Only the keyless clients are exported.
"""

from .base import BaseAPIClient, validate_author_name  # noqa: F401
from .crossref import CrossrefClient  # noqa: F401
from .openalex import OpenAlexClient  # noqa: F401
from .query_router import QueryRouter  # noqa: F401
from .semantic_scholar import SemanticScholarClient  # noqa: F401
