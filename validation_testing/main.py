import subprocess
import os
import sys

TESTABLE_CONNECTORS = ['mysql', 'dynamodb']


def run_single_connector_release_tests(connector_name, results_location):
    shell_command = f'sh run_release_tests.sh {connector_name} "{results_location}"'
    # check=True means we will throw an Exception if the subprocess exits with a non-zero response code.
    subprocess.run(shell_command, shell=True, check=True)

def run_all_connector_release_tests(results_location):
    for connector in TESTABLE_CONNECTORS:
        run_single_connector_release_tests(connector, results_location)

def assert_required_env_vars_set():
    has_results_location = os.environ.get('RESULTS_LOCATION') is not None
    has_repo_root = os.environ.get('REPOSITORY_ROOT') is not None
    has_db_password = os.environ.get('DATABASE_PASSWORD') is not None
    return has_results_location and has_repo_root and has_db_password

if __name__ == '__main__':
    has_env_vars = assert_required_env_vars_set()
    if not has_env_vars:
        sys.exit(1)
    results_location = os.environ.get('RESULTS_LOCATION')
    run_all_connector_release_tests(results_location) 
