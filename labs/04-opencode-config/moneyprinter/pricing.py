"""Pricing maths for moneyprinter."""

DEFAULT_MARGIN = 0.30
BULK_THRESHOLD = 100


def price(cost, margin=DEFAULT_MARGIN):
    """Sale price for a unit cost at a given margin."""
    return cost * (1 + margin)


def bulk_price(cost, quantity, margin=DEFAULT_MARGIN):
    """Total for a quantity, with a 10% discount at or above the bulk threshold."""
    total = price(cost, margin) * quantity
    if quantity > BULK_THRESHOLD:
        total = total * 0.9
    return round(total, 2)


def margin_for_target(cost, target_price):
    """What margin gets us from cost to target_price?"""
    return (target_price - cost) / cost
