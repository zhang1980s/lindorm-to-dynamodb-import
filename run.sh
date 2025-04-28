#!/bin/bash

# Script to run the Lindorm to DynamoDB import job on EMR

# Check if all required arguments are provided
if [ "$#" -lt 7 ]; then
    echo "Usage: $0 <lindorm-url> <lindorm-table> <lindorm-username> <lindorm-password> <start-timestamp> <end-timestamp> <dynamodb-region> <dynamodb-table> [dynamodb-endpoint]"
    echo "Example: $0 jdbc:lindorm://lindorm-host:port/database my_table user password \"2023-01-01 00:00:00\" \"2023-02-01 00:00:00\" us-west-2 my-dynamodb-table"
    exit 1
fi

# Build the project
echo "Building the project..."
mvn clean package

# Run the Flink job
echo "Submitting Flink job to EMR cluster..."
flink run \
    --parallelism 40 \
    --detached \
    --name "Lindorm to DynamoDB Import" \
    ./target/lindorm-to-dynamodb-import-1.0-SNAPSHOT.jar \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"

echo "Job submitted. Check the Flink dashboard for status."
