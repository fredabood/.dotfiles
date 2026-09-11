---
name: discovery
description: Analyze a codebase — tech stack, structure, quality, security, and improvement roadmap
user_invocable: true
---

# /discovery

Perform a comprehensive codebase analysis to understand project structure, technology stack, code quality, and identify improvement opportunities.

## Usage

```
/discovery
/discovery <path>
```

## Steps

### Step 1: Project Structure

- Identify project type (web app, API, library, CLI, monorepo, etc.)
- Map directory structure and key entry points
- Identify build system and package manager
- Count files by type and size

### Step 2: Technology Stack

- Detect languages and their versions
- Identify frameworks and libraries (from dependency files)
- Note database, caching, and messaging technologies
- Identify CI/CD configuration
- Check for containerization (Docker, etc.)

### Step 3: Documentation Audit

- Check for README, CONTRIBUTING, CHANGELOG, LICENSE
- Check for API documentation (OpenAPI, etc.)
- Check for architecture decision records (ADRs)
- Assess inline documentation quality (sample files)

### Step 4: Security Scan

- Search for hardcoded secrets: `grep -rE "(api[_-]key|password|secret|token)=" --include="*.py" --include="*.js" --include="*.ts"`
- Check for `.env` files committed to git
- Check `.gitignore` for sensitive patterns
- Review dependency files for known vulnerable packages
- Check for SSL verification disabled

### Step 5: Test Coverage

- Identify test framework and configuration
- Count test files vs source files
- Run tests if possible and report results
- Identify untested areas

### Step 6: Code Quality

- Check for linter / formatter configuration
- Check for type checking configuration
- Identify code patterns (consistent naming, error handling)
- Note any anti-patterns (god classes, circular imports, etc.)

### Step 7: Git History Analysis (optional)

- Recent activity: `git log --oneline -20`
- Contributors: `git shortlog -sn --no-merges`
- Hot files: most frequently changed files
- Velocity: commits per week over last month

### Step 8: Generate Report

Output a structured analysis:

```markdown
## Codebase Discovery Report

### Project Overview
- **Type:** <project type>
- **Languages:** <languages with percentages>
- **Framework:** <primary framework>
- **Size:** <file count, LOC estimate>

### Tech Stack
| Component | Technology | Version |
|-----------|-----------|---------|
| Language  | ...       | ...     |
| Framework | ...       | ...     |
| Database  | ...       | ...     |
| CI/CD     | ...       | ...     |

### Quality Assessment
| Area | Score | Notes |
|------|-------|-------|
| Documentation | X/5 | ... |
| Test Coverage | X/5 | ... |
| Security | X/5 | ... |
| Code Quality | X/5 | ... |

### Key Findings
1. <finding>
2. <finding>

### Improvement Roadmap
1. **Quick wins** (< 1 day): ...
2. **Short-term** (1-5 days): ...
3. **Long-term** (1+ weeks): ...
```
