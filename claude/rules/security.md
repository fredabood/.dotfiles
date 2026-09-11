---
description: Security standards for authentication, credential, and token-related code
globs:
  - "**/auth/**"
  - "**/*password*"
  - "**/*token*"
  - "**/*secret*"
  - "**/*credential*"
  - "**/.env*"
---

# Security Rules

When working with authentication, credentials, or token-related code:

1. **Never hardcode secrets** — use environment variables or a secrets manager
2. **Never log credentials** — mask sensitive values if debugging is needed (show first/last 4 chars only)
3. **Use parameterized queries** — never construct SQL with string interpolation
4. **Validate all inputs** — sanitize user input at system boundaries
5. **Use HTTPS everywhere** — never disable SSL verification
6. **Don't leak info in errors** — error messages must not reveal system internals, credentials, or stack traces to end users
7. **Use short-lived tokens** — prefer JWTs with expiry over long-lived API keys
8. **Check dependencies** — flag known CVEs in imported packages
9. **Test credentials must be clearly fake** — use patterns like `test_key_fake_for_testing_only`, never real-looking keys
