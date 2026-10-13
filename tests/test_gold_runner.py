import importlib.util
import os
from pathlib import Path
from types import SimpleNamespace
from unittest import TestCase
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('gold_runner', Path(__file__).resolve().parents[1] / 'dbt' / 'run.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
ENV = {key: 'offline-test' for key in ['GOLD_DATABASE', 'ATHENA_RESULTS_URI', 'GOLD_DATA_URI', 'ATHENA_WORKGROUP']}


class GoldRunnerTests(TestCase):
    @patch.dict(os.environ, ENV)
    def test_failed_source_contract_prevents_gold_build(self):
        with patch.object(runner.subprocess, 'run', return_value=SimpleNamespace(returncode=1)) as execute:
            self.assertEqual(runner.main(), 1)
        execute.assert_called_once()
        command = execute.call_args.args[0]
        self.assertEqual(command[:3], ['dbt', '--no-use-colors', 'test'])
        self.assertIn('tag:source_contract', command)

    @patch.dict(os.environ, ENV)
    def test_build_follows_validation_and_has_time_limit(self):
        with patch.object(runner.subprocess, 'run', return_value=SimpleNamespace(returncode=0)) as execute:
            self.assertEqual(runner.main(), 0)
        self.assertEqual(execute.call_count, 2)
        command = execute.call_args.args[0]
        self.assertEqual(command[:3], ['dbt', '--no-use-colors', 'build'])
        self.assertIn('--fail-fast', command)
        self.assertLessEqual(execute.call_args.kwargs['timeout'], 1200)

    @patch.dict(os.environ, {}, clear=True)
    def test_missing_config_stops_before_launch(self):
        with patch.object(runner.subprocess, 'run') as execute:
            with self.assertRaises(ValueError):
                runner.main()
        execute.assert_not_called()
