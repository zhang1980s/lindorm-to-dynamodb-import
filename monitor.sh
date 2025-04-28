#!/bin/bash

# Script to monitor the Lindorm to DynamoDB import job

# Check if required arguments are provided
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <cluster-id> <dynamodb-table> [dynamodb-region]"
    echo "Example: $0 j-1K48XXXXXXXX my-dynamodb-table us-west-2"
    exit 1
fi

CLUSTER_ID=$1
DYNAMODB_TABLE=$2
DYNAMODB_REGION=${3:-us-east-1}

# Function to get EMR cluster status
get_cluster_status() {
    aws emr describe-cluster --cluster-id $CLUSTER_ID --query 'Cluster.Status.State' --output text
}

# Function to get DynamoDB consumed write capacity
get_dynamodb_wcu() {
    local end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local start_time=$(date -u -d "5 minutes ago" +"%Y-%m-%dT%H:%M:%SZ")
    
    aws cloudwatch get-metric-statistics \
        --namespace AWS/DynamoDB \
        --metric-name ConsumedWriteCapacityUnits \
        --dimensions Name=TableName,Value=$DYNAMODB_TABLE \
        --start-time $start_time \
        --end-time $end_time \
        --period 300 \
        --statistics Sum \
        --region $DYNAMODB_REGION \
        --output json \
        --query 'Datapoints[0].Sum'
}

# Function to get DynamoDB item count
get_dynamodb_item_count() {
    aws dynamodb describe-table \
        --table-name $DYNAMODB_TABLE \
        --region $DYNAMODB_REGION \
        --query 'Table.ItemCount' \
        --output text
}

# Main monitoring loop
echo "Starting monitoring for Lindorm to DynamoDB import job..."
echo "Cluster ID: $CLUSTER_ID"
echo "DynamoDB Table: $DYNAMODB_TABLE"
echo "Region: $DYNAMODB_REGION"
echo ""

echo "Time                 | Cluster Status | Items Imported | WCU Consumed (5min) | Est. Completion"
echo "--------------------|--------------|--------------|--------------------|----------------"

start_time=$(date +%s)
previous_count=0

while true; do
    current_time=$(date +"%Y-%m-%d %H:%M:%S")
    cluster_status=$(get_cluster_status)
    
    # If cluster is terminated or failed, exit the loop
    if [[ "$cluster_status" == "TERMINATED" || "$cluster_status" == "TERMINATED_WITH_ERRORS" ]]; then
        echo "$current_time | $cluster_status | Monitoring stopped - cluster is no longer running."
        break
    fi
    
    # Get DynamoDB metrics
    item_count=$(get_dynamodb_item_count)
    wcu_consumed=$(get_dynamodb_wcu)
    
    # Calculate import rate and estimated completion
    elapsed_seconds=$(($(date +%s) - start_time))
    
    if [[ $elapsed_seconds -gt 300 && $item_count -gt $previous_count ]]; then
        import_rate=$(( (item_count - previous_count) / (elapsed_seconds / 60) ))
        
        # Assuming 1.25 billion records total (from README)
        remaining_items=$((1250000000 - item_count))
        
        if [[ $import_rate -gt 0 ]]; then
            minutes_remaining=$((remaining_items / import_rate))
            hours_remaining=$((minutes_remaining / 60))
            minutes_remainder=$((minutes_remaining % 60))
            
            est_completion="${hours_remaining}h ${minutes_remainder}m"
        else
            est_completion="Calculating..."
        fi
    else
        est_completion="Calculating..."
    fi
    
    # Print status line
    printf "%-20s | %-12s | %-12s | %-18s | %-15s\n" \
        "$current_time" "$cluster_status" "$item_count" "$wcu_consumed" "$est_completion"
    
    # Store current count for next iteration
    previous_count=$item_count
    
    # Wait before next check
    sleep 60
done

echo ""
echo "Monitoring complete."
