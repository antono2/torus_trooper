"""Release safety checks reject untested or mismatched source commits."""
import unittest
from prepare_release import REQUIRED_JOBS, validate_run


class ReleaseChecks(unittest.TestCase):
    def fixture(self):
        return {'headSha': 'tested', 'headBranch': 'main', 'status': 'completed',
                'conclusion': 'success',
                'jobs': [{'name': name, 'conclusion': 'success'} for name in REQUIRED_JOBS]}

    def test_exact_successful_release_run(self):
        validate_run(self.fixture(), 'tested')

    def test_different_source_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'exact'):
            validate_run(self.fixture(), 'different')

    def test_missing_consumer_is_rejected(self):
        run = self.fixture()
        run['jobs'] = [job for job in run['jobs'] if job['name'] != 'Package consumer (windows)']
        with self.assertRaisesRegex(ValueError, 'missing'):
            validate_run(run, 'tested')

    def test_pending_or_failed_jobs_are_rejected(self):
        run = self.fixture()
        run['jobs'][0]['conclusion'] = 'cancelled'
        with self.assertRaisesRegex(ValueError, 'Every'):
            validate_run(run, 'tested')
        run = self.fixture()
        run['status'] = 'in_progress'
        with self.assertRaisesRegex(ValueError, 'complete'):
            validate_run(run, 'tested')


if __name__ == '__main__':
    unittest.main()
