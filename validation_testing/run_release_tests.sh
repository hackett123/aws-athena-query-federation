# Script just handles calling other scripts in the right order and will exit if any of them fail.
# Performs the following steps:
#   - Build and deploy CDK stacks for each of the connectors we are testing against
#   - Once the stacks finish deploying, start and wait for each glue job to finish
#   - Once those are done, invoke Athena queries against our test data
#   - Once those are done, exit successfully.

# To keep things simple to start, we'll only involve DynamoDB in this process. The other stacks will come later.


# PREREQS. need env var $REPOSITORY_ROOT and aws credentials exported.
# Expects input arg of a connector name and where query results should go
CONNECTOR_NAME=$1
RESULTS_LOCATION=$2
VALIDATION_TESTING_ROOT=$REPOSITORY_ROOT/validation_testing

# upload connector jar to s3 and update yaml to s3 uri
aws s3 cp $REPOSITORY_ROOT/athena-$CONNECTOR_NAME/target/athena-$CONNECTOR_NAME-2022.47.1.jar s3://athena-federation-validation-testing-jars
sed -i "s#CodeUri: \"./target/athena-$CONNECTOR_NAME-2022.47.1.jar\"#CodeUri: \"s3://athena-federation-validation-testing-jars/athena-$CONNECTOR_NAME-2022.47.1.jar\"#" $REPOSITORY_ROOT/athena-$CONNECTOR_NAME/athena-$CONNECTOR_NAME.yaml

# then we can deploy the stack - start our node/cdk docker container, build, deploy
cd $(dirname $(find . -name ATHENA_INFRA_SPINUP_ROOT))/app;
echo "DATABASE_PASSWORD=$DATABASE_PASSWORD" > .env
npm install;
npm run build;
npm run cdk synth;
npm run cdk deploy ${CONNECTOR_NAME}CdkStack;

echo "FINISHED DEPLOYING INFRA FOR ${CONNECTOR_NAME}."

# cd back to validation root
cd $VALIDATION_TESTING_ROOT

# now we run the glue jobs that the CDK stack created
# If there is any output to glue_job_synchronous_execution.py, we will exit this script with a failure code.
# The 2>&1 lets us pipe both stdout and stderr to grep, as opposed to just the stdout. https://stackoverflow.com/questions/818255/what-does-21-mean
echo "Starting glue jobs..."
aws glue list-jobs --max-results 100 \
| jq ".JobNames[] | select(startswith(\"${CONNECTOR_NAME}gluejob\"))" \
| xargs -I{} python3 scripts/glue_job_synchronous_execution.py {} 2>&1 \
| grep -q '.' && exit 1

echo "FINISHED RUNNING GLUE JOBS FOR ${CONNECTOR_NAME}."

# if we are here, it means the above succeeded and we can continue by running our validation tests.

CONNECTOR_LAMBDA_ARN=$(aws lambda get-function --function-name $CONNECTOR_NAME-cdk-deployed | jq ".Configuration.FunctionArn" | tr -d '"') # trim quotes from the json string output
python3 scripts/exec_release_test_queries.py $CONNECTOR_NAME $RESULTS_LOCATION $CONNECTOR_LAMBDA_ARN
RELEASE_TESTS_EXIT_CODE=$?
echo "FINISHED RUNNING TESTS FOR ${CONNECTOR_NAME}, exit code was $RELEASE_TESTS_EXIT_CODE."

# once that is done, we can delete our CDK stack.
# IMAGE=federation-cdk-dev ~/docker_images/gh_env.sh '\
#   source env_vars.sh;
#   cd $(dirname $(find . -name ATHENA_INFRA_SPINUP_ROOT))/app;
#   # cannot use --force because npm is stripping the flags, so pipe yes through
#   yes | npm run cdk destroy ${CONNECTOR_NAME}CdkStack;
# '

echo "FINISHED CLEANING UP RESOURCES FOR ${CONNECTOR_NAME}."


echo "FINISHED RELEASE TESTS FOR ${CONNECTOR_NAME}."

exit $RELEASE_TESTS_EXIT_CODE
