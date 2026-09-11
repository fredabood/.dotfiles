"""deep-research deterministic pipeline core.

Nothing here calls an LLM: LLM steps surface as dispatch instructions for the
orchestrating agent (see ../pipeline.py and ../../SKILL.md); this package owns
sequencing, validation, corrective-retry bookkeeping, citation harvesting, and
artifact generation. Vendored opendraft 1.7.4 modules live in ./vendor
(see vendor/VENDORED.md).
"""
