import unittest
from decimal import Decimal
from scripts.cost_gate import check_cost


class CostGateTests(unittest.TestCase):
    def test_pending_usage_counts_towards_total(self):
        with self.assertRaises(ValueError):
            check_cost('6', '1', '1.01')

    def test_exact_boundary_preserves_reserve(self):
        self.assertEqual(check_cost('5.10', '0.20', '2.70'), Decimal('0'))

    def test_small_initial_operation(self):
        self.assertEqual(check_cost('0', '0', '0.10'), Decimal('7.90'))

    def test_invalid_values_fail_closed(self):
        for value in ['NaN', 'Infinity', '-1', 'invalid', '-Infinity']:
            for position in range(3):
                values = ['0', '0', '0']
                values[position] = value
                with self.subTest(value=value, position=position):
                    with self.assertRaises(ValueError):
                        check_cost(*values)


if __name__ == '__main__':
    unittest.main()
