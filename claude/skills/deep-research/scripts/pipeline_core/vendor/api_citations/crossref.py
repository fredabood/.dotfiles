#!/usr/bin/env python3
"""
ABOUTME: Crossref API client for academic paper lookup via DOI and title search
ABOUTME: Primary citation source with 50M+ papers and guaranteed metadata quality
"""

import logging
from typing import Optional, Dict, Any, List
from .base import BaseAPIClient, validate_author_name

logger = logging.getLogger(__name__)


class CrossrefClient(BaseAPIClient):
    """
    Crossref API client for academic paper search.

    Crossref is the official DOI registration agency for academic publishing.
    Provides high-quality metadata for 50M+ papers.

    API Documentation: https://api.crossref.org/swagger-ui/index.html
    """

    def __init__(
        self,
        rate_limit_per_second: float = 10.0,
        timeout: int = 10,
        max_retries: int = 3,
    ):
        """
        Initialize Crossref API client.

        Args:
            rate_limit_per_second: Maximum requests per second (Crossref allows 50, we use 10)
            timeout: Request timeout in seconds
            max_retries: Maximum retry attempts
        """
        super().__init__(
            base_url="https://api.crossref.org",
            rate_limit_per_second=rate_limit_per_second,
            timeout=timeout,
            max_retries=max_retries,
        )

    def search_paper(self, query: str) -> Optional[Dict[str, Any]]:
        """Most relevant usable record for the query, or None.

        Local patch: delegates to search_papers(); upstream parsed only items[0],
        so one incomplete top hit discarded the whole response.
        """
        papers = self.search_papers(query, limit=5)
        return papers[0] if papers else None

    def search_papers(self, query: str, limit: int = 5) -> List[Dict[str, Any]]:
        """Every usable record among the top ``limit`` results (local patch)."""
        response = self._make_request(
            method="GET",
            endpoint="/works",
            params={
                "query": query,
                "rows": limit,
                "sort": "relevance",
                "select": "DOI,title,author,published,container-title,publisher,volume,issue,page,type,abstract",
            },
        )
        if not response:
            logger.debug(f"Crossref: No results for query '{query[:50]}...'")
            return []
        try:
            items = response.get("message", {}).get("items", []) or []
        except Exception as e:
            logger.error(f"Crossref: Error parsing response: {e}")
            return []
        papers = []
        for item in items:
            metadata = self._extract_metadata(item)
            if metadata:
                papers.append(metadata)
        return papers

    def _extract_metadata(self, paper: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """
        Extract and normalize paper metadata from Crossref response.

        Args:
            paper: Crossref paper object

        Returns:
            Normalized metadata dict or None if required fields missing
        """
        try:
            # Title (required)
            title = paper.get("title", [])
            if not title or not isinstance(title, list):
                return None
            title_str = title[0] if title else ""
            if not title_str:
                return None

            # Authors (required)
            authors_raw = paper.get("author", [])
            authors = []
            for author in authors_raw:
                if isinstance(author, dict):
                    family = author.get("family", "")
                    given = author.get("given", "")
                    if family:
                        # Validate author name (Fix 2 - reject single-letter authors)
                        is_valid, reason = validate_author_name(family)
                        if not is_valid:
                            logger.debug(f"Invalid author name '{family}': {reason}")
                            continue  # Skip invalid author, try next
                        # Store as "Family" only (consistent with existing format)
                        authors.append(family)

            if not authors:
                logger.debug(f"No authors found for '{title_str[:50]}...'")
                return None

            # Year (required)
            published = paper.get("published", {})
            date_parts = published.get("date-parts", [[]])
            year = 0
            if date_parts and date_parts[0]:
                year = date_parts[0][0] if date_parts[0] else 0

            if year == 0:
                # Try alternative date field
                published_online = paper.get("published-online", {})
                date_parts = published_online.get("date-parts", [[]])
                if date_parts and date_parts[0]:
                    year = date_parts[0][0] if date_parts[0] else 0

            if year == 0:
                logger.debug(f"No publication year for '{title_str[:50]}...'")
                return None

            # DOI (highly preferred)
            doi = paper.get("DOI", "")

            # URL (construct from DOI if available)
            url = f"https://doi.org/{doi}" if doi else ""

            # Journal/Container (optional)
            container_title = paper.get("container-title", [])
            journal = container_title[0] if container_title else ""

            # Publisher (optional)
            publisher = paper.get("publisher", "")

            # Volume, Issue, Pages (optional)
            volume = paper.get("volume", "")
            issue = paper.get("issue", "")
            page = paper.get("page", "")

            # Abstract (optional) - Crossref sometimes returns JATS XML, extract text
            abstract = paper.get("abstract", "")
            if abstract:
                # Strip JATS XML tags if present (<jats:p>, <jats:italic>, etc.)
                import re
                abstract = re.sub(r'<[^>]+>', '', abstract)
                abstract = abstract.strip()

            # Source type
            crossref_type = paper.get("type", "")
            source_type = self._map_source_type(crossref_type)

            # Calculate confidence score
            confidence = self._calculate_confidence(
                has_doi=bool(doi), has_journal=bool(journal), has_publisher=bool(publisher), author_count=len(authors)
            )

            return {
                "title": title_str,
                "authors": authors,
                "year": year,
                "doi": doi,
                "url": url,
                "journal": journal,
                "publisher": publisher,
                "volume": volume,
                "issue": issue,
                "pages": page,
                "source_type": source_type,
                "confidence": confidence,
                "abstract": abstract if abstract else None,
            }

        except Exception as e:
            logger.error(f"Error extracting metadata: {e}")
            return None

    def _map_source_type(self, crossref_type: str) -> str:
        """
        Map Crossref type to our source_type enum.

        Args:
            crossref_type: Crossref work type

        Returns:
            source_type: One of: journal, conference, book, report, website
        """
        type_mapping = {
            "journal-article": "journal",
            "proceedings-article": "conference",
            "book": "book",
            "book-chapter": "book",
            "report": "report",
            "posted-content": "report",
            "dataset": "report",
        }

        return type_mapping.get(crossref_type, "journal")  # Default to journal

    def _calculate_confidence(self, has_doi: bool, has_journal: bool, has_publisher: bool, author_count: int) -> float:
        """
        Calculate confidence score for paper metadata.

        Args:
            has_doi: Whether DOI is present
            has_journal: Whether journal name is present
            has_publisher: Whether publisher is present
            author_count: Number of authors

        Returns:
            Confidence score (0.0 to 1.0)
        """
        score = 0.5  # Base score

        if has_doi:
            score += 0.3  # DOI is strong signal of quality
        if has_journal:
            score += 0.1
        if has_publisher:
            score += 0.05
        if author_count > 0:
            score += 0.05

        return min(score, 1.0)  # Cap at 1.0
