# Lindorm to DynamoDB Import Solution

This project provides a solution for importing data from Alibaba Cloud Lindorm to AWS DynamoDB using Amazon EMR with Apache Flink.

## Requirements

- Import data from Lindorm to AWS DynamoDB
- Data volume: 100GB+
- Record size: 80 bytes per record (approximately 1.25 billion records)
- Filter data by timestamp range during import

## Solution Architecture

```
Alibaba Cloud Lindorm → Amazon EMR (Flink) → AWS DynamoDB
```

### Key Components

- **Source**: Alibaba Cloud Lindorm database
- **Processing**: Amazon EMR cluster running Apache Flink
- **Destination**: AWS DynamoDB
- **Storage**: Amazon S3 for checkpoints and state management

## Quick Start

1. **Set up AWS resources using CloudFormation**:
   ```bash
   aws cloudformation create-stack \
     --stack-name lindorm-to-dynamodb-import \
     --template-body file://cloudformation-template.yaml \
     --parameters ParameterKey=DynamoDBTableName,ParameterValue=my-target-table \
                  ParameterKey=S3BucketName,ParameterValue=my-import-bucket \
                  ParameterKey=DynamoDBWriteCapacity,ParameterValue=7000 \
     --capabilities CAPABILITY_IAM
   ```

2. **Deploy the solution**:
   ```bash
   # Make scripts executable
   chmod +x deploy.sh run.sh monitor.sh
   
   # Deploy to EMR
   ./deploy.sh my-import-bucket jdbc:lindorm://lindorm-host:port/database my_table \
     username password "2023-01-01 00:00:00" "2023-02-01 00:00:00" \
     us-west-2 my-target-table
   ```

3. **Monitor the import progress**:
   ```bash
   ./monitor.sh j-1K48XXXXXXXX my-target-table us-west-2
   ```

## Implementation Approach

### Data Filtering Strategy

We use SQL query filtering in the Lindorm connector (Approach 1) for optimal performance:

```java
// Example configuration for Lindorm source with timestamp filtering
Map<String, String> lindormConfig = new HashMap<>();
lindormConfig.put("connector", "lindorm");
lindormConfig.put("url", "your-lindorm-url");
lindormConfig.put("table-name", "your_table");
lindormConfig.put("username", "username");
lindormConfig.put("password", "password");
// Apply timestamp range filter in the query
lindormConfig.put("scan.query", "SELECT * FROM your_table WHERE timestamp_column >= '2023-01-01 00:00:00' AND timestamp_column < '2023-02-01 00:00:00'");
```

This approach provides:
- Push-down predicates (filtering at source)
- Reduced data transfer
- Lower memory usage
- Reduced serialization/deserialization overhead

### Project Structure

```
lindorm-to-dynamodb-import/
├── src/main/java/com/example/
│   └── LindormToDynamoDBImport.java  # Main Flink application
├── src/main/resources/
│   └── log4j.properties              # Logging configuration
├── cloudformation-template.yaml      # AWS resources template
├── deploy.sh                         # Deployment script
├── emr-config.json                   # EMR cluster configuration
├── monitor.sh                        # Import monitoring script
├── pom.xml                           # Maven dependencies
├── README.md                         # This file
└── run.sh                            # Local execution script
```

### EMR Cluster Configuration

For 100GB+ data volume:

- **Primary Node**: 1 × `m5.2xlarge` (8 vCPU, 32GB RAM)
- **Core Nodes**: 10-15 × `r5.2xlarge` (8 vCPU, 64GB RAM)

#### Flink Configuration Parameters

```
flink.taskmanager.numberOfTaskSlots: 4  # Per core node
flink.parallelism.default: 40-60        # (number of cores × number of nodes × slots per task)
taskmanager.memory.process.size: 52428mb
taskmanager.memory.managed.size: 32768mb
```

### Deployment Options

#### Option 1: Using CloudFormation (Recommended)

1. Deploy the CloudFormation stack:
   ```bash
   aws cloudformation create-stack \
     --stack-name lindorm-to-dynamodb-import \
     --template-body file://cloudformation-template.yaml \
     --parameters ParameterKey=DynamoDBTableName,ParameterValue=my-target-table \
                  ParameterKey=S3BucketName,ParameterValue=my-import-bucket \
                  ParameterKey=DynamoDBWriteCapacity,ParameterValue=7000 \
     --capabilities CAPABILITY_IAM
   ```

2. Wait for stack creation to complete:
   ```bash
   aws cloudformation wait stack-create-complete --stack-name lindorm-to-dynamodb-import
   ```

3. Get the outputs:
   ```bash
   aws cloudformation describe-stacks --stack-name lindorm-to-dynamodb-import --query 'Stacks[0].Outputs'
   ```

#### Option 2: Manual Deployment

1. Create DynamoDB table with appropriate capacity
2. Create S3 bucket for logs and JAR files
3. Set up IAM roles for EMR
4. Configure and deploy EMR cluster using `deploy.sh`

### DynamoDB Capacity Planning

#### WCU Calculation

- Record size: 80 bytes
- WCU capacity: 1 WCU = 1KB write/second
- Records per WCU: ~12.8 records per WCU

| Desired Import Time | Required WCUs |
|---------------------|---------------|
| 1 hour              | ~29,000 WCUs  |
| 4 hours             | ~7,200 WCUs   |
| 8 hours             | ~3,600 WCUs   |
| 24 hours            | ~1,200 WCUs   |

#### WCU Optimization Strategies

1. **On-Demand Capacity**: Recommended for one-time imports
2. **Provisioned Capacity with Auto-Scaling**:
   - Target utilization: 70-80%
   - Configure min/max capacity based on budget
3. **Batch Writing**:
   - Use BatchWriteItem (25 items per batch)
   - Set `dynamodb.sink.batch-size` to 25

## Performance Optimization

### Write Distribution

To avoid hot partitions in DynamoDB:
1. Ensure partition key has high cardinality
2. Add random suffix to keys if needed
3. Use Flink to shuffle records before writing:

```java
// Example optimization
yourDataStream
  .rebalance()  // Evenly distribute records across tasks
  .map(new DynamoDBBatchMapper(25))  // Batch records
  .addSink(new DynamoDBSink(...));
```

### Checkpointing Configuration

For large data volumes:
```
execution.checkpointing.interval: 60000             // 1 minute
execution.checkpointing.min-pause-between-checkpoints: 30000  // 30 seconds
execution.checkpointing.timeout: 600000            // 10 minutes
```

## Implementation Steps

1. Set up EMR cluster with Flink installed
2. Configure appropriate IAM roles for DynamoDB access
3. Develop Flink application with Lindorm source and DynamoDB sink
4. Configure timestamp filtering in Lindorm connector
5. Implement error handling and retry mechanisms
6. Set up monitoring with CloudWatch
7. Execute and monitor the import job

## Monitoring and Validation

### CloudWatch Dashboard

The CloudFormation template creates a CloudWatch dashboard that displays:
- DynamoDB Write Capacity Consumption
- Throttled Requests
- Import progress metrics

### Monitoring Script

The included `monitor.sh` script provides real-time monitoring of:
- EMR cluster status
- Items imported to DynamoDB
- WCU consumption
- Estimated completion time

```bash
./monitor.sh j-1K48XXXXXXXX my-target-table us-west-2
```

## Considerations and Limitations

- Network connectivity between Alibaba Cloud and AWS
- Data transfer costs between clouds
- DynamoDB partition key strategy
- Proper mapping of Lindorm data types to DynamoDB

## Troubleshooting

### Common Issues

1. **DynamoDB Throttling**
   - Symptom: Slow import progress, throttled requests in CloudWatch
   - Solution: Increase WCU or switch to on-demand capacity

2. **EMR Cluster Memory Issues**
   - Symptom: Task failures with OOM errors
   - Solution: Increase taskmanager.memory.process.size or use larger instance types

3. **Lindorm Connection Issues**
   - Symptom: Job fails at startup with connection errors
   - Solution: Verify network connectivity, credentials, and Lindorm endpoint

### Getting Support

For issues with this solution, please open an issue in the GitHub repository or contact your AWS representative.
