#!/bin/bash

# Script to deploy the Lindorm to DynamoDB import solution on EMR

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if required arguments are provided
if [ "$#" -lt 9 ]; then
    echo "Usage: $0 <s3-bucket> <lindorm-url> <lindorm-table> <lindorm-username> <lindorm-password> <start-timestamp> <end-timestamp> <dynamodb-region> <dynamodb-table> [dynamodb-endpoint]"
    echo "Example: $0 my-s3-bucket jdbc:lindorm://lindorm-host:port/database my_table user password \"2023-01-01 00:00:00\" \"2023-02-01 00:00:00\" us-west-2 my-dynamodb-table"
    exit 1
fi

S3_BUCKET=$1
LINDORM_URL=$2
LINDORM_TABLE=$3
LINDORM_USERNAME=$4
LINDORM_PASSWORD=$5
START_TIMESTAMP=$6
END_TIMESTAMP=$7
DYNAMODB_REGION=$8
DYNAMODB_TABLE=$9
DYNAMODB_ENDPOINT=${10}

# Build the project
echo "Building the project..."
mvn clean package

# Upload the JAR to S3
echo "Uploading JAR to S3..."
aws s3 cp ./target/lindorm-to-dynamodb-import-1.0-SNAPSHOT.jar s3://$S3_BUCKET/jars/

# Update the EMR configuration with the correct S3 bucket
sed -i "s|s3://your-bucket|s3://$S3_BUCKET|g" emr-config.json

# Create the EMR cluster
echo "Creating EMR cluster..."
CLUSTER_ID=$(aws emr create-cluster --cli-input-json file://emr-config.json --output text --query 'ClusterId')

echo "EMR cluster $CLUSTER_ID is being created..."
echo "Waiting for the cluster to be ready..."

# Wait for the cluster to be ready
aws emr wait cluster-running --cluster-id $CLUSTER_ID

echo "Cluster is ready. Adding step to run the Flink job..."

# Create a step to run the Flink job
aws emr add-steps \
    --cluster-id $CLUSTER_ID \
    --steps Type=CUSTOM_JAR,Name="Lindorm to DynamoDB Import",Jar="command-runner.jar",Args=["flink","run","-m","yarn-cluster","-p","48","--detached","s3://$S3_BUCKET/jars/lindorm-to-dynamodb-import-1.0-SNAPSHOT.jar","$LINDORM_URL","$LINDORM_TABLE","$LINDORM_USERNAME","$LINDORM_PASSWORD","$START_TIMESTAMP","$END_TIMESTAMP","$DYNAMODB_REGION","$DYNAMODB_TABLE","$DYNAMODB_ENDPOINT"]

echo "Job submitted to the EMR cluster."
echo "You can monitor the job status in the EMR console or using the AWS CLI."
echo "Cluster ID: $CLUSTER_ID"

# Instructions for accessing the Flink dashboard
echo ""
echo "To access the Flink dashboard:"
echo "1. Set up an SSH tunnel to the EMR cluster:"
echo "   aws emr ssh --cluster-id $CLUSTER_ID --key-pair-file your-key-pair.pem --setup-tunnel"
echo "2. Open your browser and navigate to:"
echo "   http://localhost:8081"
echo ""
echo "To terminate the cluster when the job is complete:"
echo "   aws emr terminate-clusters --cluster-ids $CLUSTER_ID"
