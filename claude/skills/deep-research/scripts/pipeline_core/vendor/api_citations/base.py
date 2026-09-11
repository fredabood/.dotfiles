#!/usr/bin/env python3
"""
ABOUTME: Base API client with error handling, retries, and rate limiting
ABOUTME: Provides production-grade HTTP request infrastructure for academic APIs

Local patch (see ../VENDORED.md, "request hygiene"): upstream rotated spoofed
browser User-Agents, forwarded a client IP in X-Forwarded-For, and rotated
through a PROXY_LIST to evade rate limits. All three are removed. Every request
identifies as this tool, with a mailto for the Crossref/OpenAlex polite pools
when OPENALEX_EMAIL is set, and a rate limit is met with backoff.
"""

import os
import re
import time
import logging
import requests
from typing import Optional, Dict, Any
from abc import ABC, abstractmethod

logger = logging.getLogger(__name__)

TOOL_NAME = "deep-research-skill/1.0 (+https://github.com/fredabood/.dotfiles)"


def user_agent() -> str:
    """Honest identification; the mailto opts into the APIs' polite pools."""
    email = os.getenv("OPENALEX_EMAIL", "").strip()
    return f"{TOOL_NAME} mailto:{email}" if email else TOOL_NAME


DEFAULT_HEADERS = {
    "Accept": "application/json",
    "Accept-Encoding": "gzip, deflate",
}

# =========================================================================
# Citation Quality Validation Functions (Fix 2 & Fix 5)
# =========================================================================

import datetime

CURRENT_YEAR = datetime.datetime.now().year

def validate_author_name(author_name: str) -> tuple:
    """
    Validate author name is academically acceptable.
    
    Args:
        author_name: Author name string
        
    Returns:
        Tuple of (is_valid, reason)
    """
    if not author_name:
        return (False, "empty")
    
    name = author_name.strip()
    
    # Reject single-character authors (e.g., "R et al.")
    if len(name) <= 2:
        return (False, "too_short")
    
    # Reject domain-like authors (e.g., "education.illinois.edu")
    domain_tlds = ['.com', '.org', '.net', '.edu', '.gov', '.io', '.ai', '.int']
    if '.' in name and any(tld in name.lower() for tld in domain_tlds):
        return (False, "domain_as_author")
    
    # Reject URLs as authors
    if name.startswith('http://') or name.startswith('https://'):
        return (False, "url_as_author")
    
    # Reject generic/institutional author names (metadata pollution)
    generic_terms = [
        'working paper', 'discussion paper', 'technical report', 'staff report',
        'research paper', 'policy brief', 'white paper', 'occasional paper',
        'series', 'anonymous', 'unknown', 'author', 'authors', 'editor', 'editors',
        'committee', 'commission', 'group', 'team', 'staff', 'admin', 'administrator'
    ]
    # Local patch: whole-word match. Upstream's substring test rejected real
    # surnames (Stafford ⊃ 'staff', Teamey ⊃ 'team', Groupe ⊃ 'group').
    name_lower = name.lower()
    if any(re.search(rf"\b{re.escape(term)}\b", name_lower) for term in generic_terms):
        return (False, "generic_author")
    
    return (True, "valid")

def validate_publication_year(year: int) -> tuple:
    """
    Validate publication year is reasonable.
    
    Args:
        year: Publication year
        
    Returns:
        Tuple of (is_valid, reason, is_recent)
    """
    if not year:
        return (False, "no_year", False)
    
    try:
        year_int = int(year)
    except (ValueError, TypeError):
        return (False, "invalid_year", False)
    
    # Future years are impossible
    if year_int > CURRENT_YEAR:
        return (False, "future_year", False)
    
    # Very old papers (pre-1900) are suspicious
    if year_int < 1900:
        return (False, "ancient_year", False)
    
    # Current year papers might be preprints
    is_recent = (year_int == CURRENT_YEAR)
    
    return (True, "valid", is_recent)


class BaseAPIClient(ABC):
    """
    Base class for academic API clients.

    Provides:
    - Exponential backoff retries
    - Rate limiting
    - Error handling
    - Request logging
    """

    def __init__(
        self,
        base_url: str,
        api_key: Optional[str] = None,
        rate_limit_per_second: float = 10.0,
        timeout: int = 10,
        max_retries: int = 3,
        api_type: Optional[str] = None,
    ):
        """
        Initialize API client.

        Args:
            base_url: Base URL for API
            api_key: Optional API key for authenticated requests
            rate_limit_per_second: Maximum requests per second
            timeout: Request timeout in seconds
            max_retries: Maximum retry attempts for failed requests
        """
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key
        self.rate_limit_per_second = rate_limit_per_second
        self.timeout = timeout
        self.max_retries = max_retries
        self.api_type = api_type

        # Rate limiting state
        self.last_request_time: float = 0.0
        self.min_interval: float = 1.0 / rate_limit_per_second

        # Session for connection pooling
        self.session = requests.Session()
        self.session.headers.update({**DEFAULT_HEADERS, "User-Agent": user_agent()})

    def _rate_limit_wait(self) -> None:
        """Wait if necessary to respect rate limit."""
        current_time = time.time()
        time_since_last_request = current_time - self.last_request_time

        if time_since_last_request < self.min_interval:
            sleep_time = self.min_interval - time_since_last_request
            logger.debug(f"Rate limit: sleeping {sleep_time:.3f}s")
            time.sleep(sleep_time)

        self.last_request_time = time.time()

    @staticmethod
    def _retry_after(payload: Any) -> Optional[float]:
        """OpenAlex's anonymous limiter answers HTTP 200 with
        {"error": "Rate limit exceeded", "retryAfter": N}. Treat it as a 429."""
        if isinstance(payload, dict) and "error" in payload and "retryAfter" in payload:
            try:
                return float(payload["retryAfter"])
            except (TypeError, ValueError):
                return 1.0
        return None

    def _make_request(
        self,
        method: str,
        endpoint: str,
        params: Optional[Dict[str, Any]] = None,
        json_data: Optional[Dict[str, Any]] = None,
    ) -> Optional[Dict[str, Any]]:
        """
        Make HTTP request with retries and error handling.

        Args:
            method: HTTP method (GET, POST, etc.)
            endpoint: API endpoint (relative to base_url)
            params: Query parameters
            json_data: JSON request body

        Returns:
            Response JSON dict or None if all retries failed
        """
        url = f"{self.base_url}/{endpoint.lstrip('/')}"
        headers = {"x-api-key": self.api_key} if self.api_key else {}

        for attempt in range(self.max_retries):
            try:
                self._rate_limit_wait()
                logger.debug(f"Request: {method} {url} (attempt {attempt + 1}/{self.max_retries})")

                response = self.session.request(
                    method=method,
                    url=url,
                    params=params,
                    json=json_data,
                    headers=headers,
                    timeout=self.timeout,
                )

                if response.status_code == 200:
                    payload = response.json()
                    retry_after = self._retry_after(payload)
                    if retry_after is None:
                        return payload
                    wait_time = min(max(retry_after, 1.0), 60.0)
                    logger.debug(f"Rate limited (200 body), waiting {wait_time:.1f}s")
                    time.sleep(wait_time)
                    continue

                elif response.status_code == 404:
                    logger.debug(f"Resource not found: {url}")
                    return None  # Not found is not an error, just no result

                elif response.status_code == 429:
                    # Exponential backoff: 3s, 6s, 12s ... — the keyless tiers need real waits.
                    wait_time = 3 * (2 ** attempt)
                    logger.debug(f"Rate limited (429), waiting {wait_time:.1f}s before retry "
                                 f"(attempt {attempt + 1}/{self.max_retries})")
                    time.sleep(wait_time)
                    continue

                elif response.status_code >= 500:
                    wait_time = 2 ** attempt
                    logger.warning(f"Server error ({response.status_code}), waiting {wait_time}s before retry")
                    time.sleep(wait_time)
                    continue

                else:
                    logger.error(f"Client error: {response.status_code} - {response.text[:200]}")
                    return None

            except (requests.exceptions.Timeout, requests.exceptions.ConnectionError) as e:
                wait_time = 2 ** attempt
                logger.warning(f"Request failed ({type(e).__name__}), waiting {wait_time}s before retry")
                time.sleep(wait_time)
                continue

            except requests.exceptions.RequestException as e:
                logger.error(f"Request failed: {e}")
                return None

            except Exception as e:
                logger.error(f"Unexpected error: {e}")
                return None

        # All retries exhausted - normal; the next API in the chain is tried.
        logger.debug(f"API unavailable after {self.max_retries} retries: {url[:60]}...")
        return None

    @abstractmethod
    def search_paper(self, query: str) -> Optional[Dict[str, Any]]:
        """
        Search for a paper by query.

        Must be implemented by subclasses.

        Args:
            query: Search query (title, authors, keywords)

        Returns:
            Paper metadata dict or None if not found
        """
        pass

    def close(self) -> None:
        """Close the session."""
        self.session.close()

    def __enter__(self):
        """Context manager entry."""
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        self.close()
