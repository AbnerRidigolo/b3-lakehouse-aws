"""Offline cost gate. All amounts are gross USD, before promotional credits."""
import argparse
from decimal import Decimal, InvalidOperation

CAP = Decimal('10.00')
RESERVE = Decimal('2.00')


def check_cost(spent: str, pending: str, estimate: str) -> Decimal:
    try:
        amounts = [Decimal(x) for x in (spent, pending, estimate)]
    except InvalidOperation as exc:
        raise ValueError('Amounts must be decimal numbers') from exc
    if any(not x.is_finite() or x < 0 for x in amounts):
        raise ValueError('Amounts must be finite and nonnegative')
    projected = sum(amounts) + RESERVE
    if projected > CAP:
        raise ValueError('Blocked: projected use plus USD 2 reserve exceeds USD 10')
    return CAP - projected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--spent', required=True)
    parser.add_argument('--pending', required=True, help='Usage not yet reflected in billing')
    parser.add_argument('--estimate', required=True, help='Upper estimate for proposed operation')
    args = parser.parse_args()
    try:
        remaining = check_cost(args.spent, args.pending, args.estimate)
    except ValueError as exc:
        parser.exit(1, str(exc) + '\n')
    print(f'Within planning cap; remaining outside reserve: USD {remaining:.2f}')
    print('This calculation is not approval and does not enforce an AWS spending cap.')


if __name__ == '__main__':
    main()
