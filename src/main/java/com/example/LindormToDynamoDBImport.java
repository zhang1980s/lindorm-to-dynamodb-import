package com.example;

import org.apache.flink.api.common.functions.MapFunction;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.functions.sink.SinkFunction;
import org.apache.flink.table.api.EnvironmentSettings;
import org.apache.flink.table.api.Table;
import org.apache.flink.table.api.TableEnvironment;
import org.apache.flink.table.api.bridge.java.StreamTableEnvironment;
import org.apache.flink.types.Row;

import java.util.HashMap;
import java.util.Map;
import java.util.Properties;

/**
 * Flink application to import data from Alibaba Cloud Lindorm to AWS DynamoDB
 * with timestamp-based filtering.
 */
public class LindormToDynamoDBImport {

    public static void main(String[] args) throws Exception {
        // Parse command line arguments
        final String lindormUrl = args[0];
        final String lindormTable = args[1];
        final String lindormUsername = args[2];
        final String lindormPassword = args[3];
        final String startTimestamp = args[4];
        final String endTimestamp = args[5];
        final String dynamodbRegion = args[6];
        final String dynamodbTable = args[7];
        final String dynamodbEndpoint = args.length > 8 ? args[8] : null;

        // Set up the streaming execution environment
        final StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        
        // Configure checkpointing for exactly-once processing
        env.enableCheckpointing(60000); // Checkpoint every minute
        env.getCheckpointConfig().setMinPauseBetweenCheckpoints(30000); // 30 seconds
        env.getCheckpointConfig().setCheckpointTimeout(600000); // 10 minutes
        
        // Create the table environment
        final StreamTableEnvironment tableEnv = StreamTableEnvironment.create(env);

        // Configure Lindorm source with timestamp filtering
        Map<String, String> lindormConfig = new HashMap<>();
        lindormConfig.put("connector", "lindorm");
        lindormConfig.put("url", lindormUrl);
        lindormConfig.put("table-name", lindormTable);
        lindormConfig.put("username", lindormUsername);
        lindormConfig.put("password", lindormPassword);
        
        // Apply timestamp range filter in the query
        String query = String.format(
            "SELECT * FROM %s WHERE timestamp_column >= '%s' AND timestamp_column < '%s'",
            lindormTable, startTimestamp, endTimestamp
        );
        lindormConfig.put("scan.query", query);
        
        // Optional: Configure batch size for reading from Lindorm
        lindormConfig.put("scan.fetch-size", "1000");
        
        // Register Lindorm table
        tableEnv.executeSql(String.format(
            "CREATE TABLE lindorm_source (" +
            "   id STRING, " +
            "   timestamp_column TIMESTAMP(3), " +
            "   data STRING, " +
            "   PRIMARY KEY (id) NOT ENFORCED" +
            ") WITH (" +
            "   'connector' = 'lindorm', " +
            "   'url' = '%s', " +
            "   'table-name' = '%s', " +
            "   'username' = '%s', " +
            "   'password' = '%s', " +
            "   'scan.query' = '%s', " +
            "   'scan.fetch-size' = '1000'" +
            ")",
            lindormUrl, lindormTable, lindormUsername, lindormPassword, query
        ));
        
        // Register DynamoDB table
        String dynamodbConnectorConfig = String.format(
            "CREATE TABLE dynamodb_sink (" +
            "   id STRING, " +
            "   timestamp_column TIMESTAMP(3), " +
            "   data STRING, " +
            "   PRIMARY KEY (id) NOT ENFORCED" +
            ") WITH (" +
            "   'connector' = 'dynamodb', " +
            "   'table-name' = '%s', " +
            "   'aws.region' = '%s', " +
            "   'aws.batch-size' = '25'",
            dynamodbTable, dynamodbRegion
        );
        
        // Add endpoint if provided (useful for testing with DynamoDB Local)
        if (dynamodbEndpoint != null && !dynamodbEndpoint.isEmpty()) {
            dynamodbConnectorConfig += String.format(", 'aws.endpoint' = '%s'", dynamodbEndpoint);
        }
        
        dynamodbConnectorConfig += ")";
        tableEnv.executeSql(dynamodbConnectorConfig);
        
        // Execute the import using SQL
        tableEnv.executeSql("INSERT INTO dynamodb_sink SELECT * FROM lindorm_source");
        
        // Alternative approach using DataStream API for more control
        /*
        // Convert table to stream
        Table sourceTable = tableEnv.sqlQuery("SELECT * FROM lindorm_source");
        DataStream<Row> dataStream = tableEnv.toDataStream(sourceTable);
        
        // Apply additional transformations if needed
        dataStream = dataStream
            .rebalance()  // Evenly distribute records across tasks
            .map(new EnrichmentFunction());  // Apply any transformations
        
        // Convert back to table and write to DynamoDB
        Table resultTable = tableEnv.fromDataStream(dataStream);
        tableEnv.createTemporaryView("processed_data", resultTable);
        tableEnv.executeSql("INSERT INTO dynamodb_sink SELECT * FROM processed_data");
        */
        
        // Execute the Flink job
        env.execute("Lindorm to DynamoDB Import");
    }
    
    /**
     * Example function to enrich or transform data if needed
     */
    public static class EnrichmentFunction implements MapFunction<Row, Row> {
        @Override
        public Row map(Row value) throws Exception {
            // Apply transformations if needed
            // For example, add a random suffix to the ID to avoid hot partitions
            // String id = value.getFieldAs("id") + "-" + (int)(Math.random() * 100);
            // value.setField("id", id);
            return value;
        }
    }
}
