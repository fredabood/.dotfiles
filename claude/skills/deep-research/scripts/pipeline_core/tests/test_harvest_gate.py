from pipeline_core.harvest import (
    TIER_ACCEPTABLE,
    TIER_EXCELLENT,
    TIER_FAILED,
    TIER_MINIMAL,
    tier_for,
)


def test_boundaries_at_target_100():
    assert tier_for(100, 100) == TIER_EXCELLENT
    assert tier_for(99, 100) == TIER_ACCEPTABLE
    assert tier_for(86, 100) == TIER_ACCEPTABLE   # exactly int(100*0.86)
    assert tier_for(85, 100) == TIER_MINIMAL
    assert tier_for(70, 100) == TIER_MINIMAL      # exactly int(100*0.70)
    assert tier_for(69, 100) == TIER_FAILED
    assert tier_for(0, 100) == TIER_FAILED


def test_small_targets_round_down():
    # target 10: ACCEPTABLE >= 8 (int(8.6)), MINIMAL >= 7
    assert tier_for(8, 10) == TIER_ACCEPTABLE
    assert tier_for(7, 10) == TIER_MINIMAL
    assert tier_for(6, 10) == TIER_FAILED
