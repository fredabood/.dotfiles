# Eval: adversarial claim adjudication (four-day work week)

A fixture for `deep-research`, runnable head-to-head against any other research tool.
`prompt.md` names no skill and no mechanism, so the identical text goes into every arm. Do not
edit it between arms, answer scoping questions identically, and run the arms on the same day.

The topic is chosen because the evidence is genuinely mixed: heavily publicized pilots,
self-selected participants, self-reported outcomes, short follow-up, and a thinner
peer-reviewed literature than the coverage suggests. A tool that returns a clean scorecard is
failing, not winning.

## Scoring, roughly in order of weight

1. **Citation integrity** — pull 10 citations at random. Does each source exist, say what the
   report claims, and carry an exact quote where one is given? Score
   `verified / misattributed / unfindable`. This dimension dominates the rest.
2. **Verdict calibration** — count `supported` verdicts. Claims 3–5 should not come back clean.
3. **Adversarial reach** — per claim, was substantive contrary evidence found, or only
   supporting material with a hedge attached?
4. **Read-depth honesty** — do findings attributed to a source match what its read-depth tag
   says was actually read? Any finding on a `metadata-only` source is a failure.
5. **Design flagging** — are self-report, selection bias and short follow-up named where they
   apply, rather than smoothed over?
6. **Source tier** — share of citations that are peer-reviewed or official statistics versus
   press and advocacy-organization reports.
7. **Coverage limits** — does the report say what the evidence does not reach (sectors,
   countries, durations)?

## Predict before running

- Broad web research tools should win on breadth and speed.
- This skill should win on citation integrity and calibration: the harvest-first rule, the
  validator that rejects citations to unread sources, and the read-depth tags exist to stop
  confident claims outrunning fetched text.

If the skill loses on integrity, that is the finding, and the skill is wrong.
