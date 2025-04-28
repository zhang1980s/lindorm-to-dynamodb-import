#!/bin/bash

# Script to validate the setup for Lindorm to DynamoDB import solution

echo "Validating setup for Lindorm to DynamoDB import solution..."

# Check Java installation
echo -n "Checking Java installation... "
if command -v java &> /dev/null; then
    java_version=$(java -version 2>&1 | head -1 | cut -d'"' -f2)
    echo "Found Java $java_version"
else
    echo "Not found. Please install Java 11 or later."
    exit 1
fi

# Check Maven installation
echo -n "Checking Maven installation... "
if command -v mvn &> /dev/null; then
    mvn_version=$(mvn --version | head -1 | cut -d' ' -f3)
    echo "Found Maven $mvn_version"
else
    echo "Not found. Please install Maven."
    exit 1
fi

# Check AWS CLI installation
echo -n "Checking AWS CLI installation... "
if command -v aws &> /dev/null; then
    aws_version=$(aws --version 2>&1 | cut -d' ' -f1 | cut -d'/' -f2)
    echo "Found AWS CLI $aws_version"
else
    echo "Not found. Please install AWS CLI."
    exit 1
fi

# Check if AWS credentials are configured
echo -n "Checking AWS credentials... "
if aws sts get-caller-identity &> /dev/null; then
    account_id=$(aws sts get-caller-identity --query "Account" --output text)
    echo "Valid credentials found for account $account_id"
else
    echo "Not configured. Please run 'aws configure' to set up your credentials."
    exit 1
fi

# Validate project structure
echo -n "Checking project structure... "
if [ -f "pom.xml" ] && [ -d "src/main/java/com/example" ]; then
    echo "Valid"
else
    echo "Invalid. Please ensure you're in the project root directory."
    exit 1
fi

# Try to compile the project
echo "Compiling project..."
if mvn clean compile; then
    echo "Compilation successful."
else
    echo "Compilation failed. Please check the error messages above."
    exit 1
fi

echo ""
echo "Setup validation complete. Your environment is ready for the Lindorm to DynamoDB import solution."
echo ""
echo "Next steps:"
echo "1. Configure your AWS resources using CloudFormation:"
echo "   aws cloudformation create-stack --stack-name lindorm-to-dynamodb-import --template-body file://cloudformation-template.yaml --parameters ParameterKey=DynamoDBTableName,ParameterValue=my-target-table ParameterKey=S3BucketName,ParameterValue=my-import-bucket --capabilities CAPABILITY_IAM"
echo ""
echo "2. Deploy the solution:"
echo "   ./deploy.sh my-import-bucket jdbc:lindorm://lindorm-host:port/database my_table username password \"2023-01-01 00:00:00\" \"2023-02-01 00:00:00\" us-west-2 my-target-table"
echo ""
echo "3. Monitor the import progress:"
echo "   ./monitor.sh j-1K48XXXXXXXX my-target-table us-west-2"
