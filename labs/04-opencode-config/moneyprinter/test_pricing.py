import pricing


def test_price_default_margin():
    assert pricing.price(10) == 13.0


def test_bulk_discount_applies_at_threshold():
    # The policy says "at or above 100 units", does the code agree?
    assert pricing.bulk_price(10, 100) < pricing.price(10) * 100


def test_margin_roundtrip():
    assert pricing.margin_for_target(10, 13) == 0.3
