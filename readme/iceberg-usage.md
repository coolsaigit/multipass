# Simple Iceberg Setup

## Prerequisites
Make sure MinIO is running first (for storage):
```bash
kubectl apply -f minio.yaml
```

## Deploy Iceberg REST Catalog
```bash
kubectl apply -f iceberg-simple.yaml
```

This deploys the Iceberg REST Catalog which manages table metadata. **This is the recommended catalog for Iceberg tables** - it works perfectly on ARM architectures and provides all the functionality you need to register and manage Iceberg tables. This is a working alternative to both Nessie and Hive Metastore.

## Access REST Catalog
```bash
kubectl port-forward svc/rest-catalog -n iceberg 8181:8181
```

## Using Iceberg

**Option 1: Use with Spark/PySpark (recommended for simplicity)**
```python
from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .appName("Iceberg") \
    .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
    .config("spark.sql.catalog.iceberg", "org.apache.iceberg.spark.SparkCatalog") \
    .config("spark.sql.catalog.iceberg.type", "rest") \
    .config("spark.sql.catalog.iceberg.uri", "http://localhost:8181") \
    .config("spark.sql.catalog.iceberg.warehouse", "s3://iceberg-warehouse/") \
    .config("spark.sql.catalog.iceberg.s3.endpoint", "http://localhost:9000") \
    .getOrCreate()

# Create table
spark.sql("CREATE TABLE iceberg.default.test (id bigint, name string)")

# Insert data
spark.sql("INSERT INTO iceberg.default.test VALUES (1, 'test')")

# Query
spark.sql("SELECT * FROM iceberg.default.test").show()
```

**Option 2: Use REST API directly**
```bash
# List namespaces
curl http://localhost:8181/v1/namespaces

# Create table (via REST API)
curl -X POST http://localhost:8181/v1/namespaces/default/tables \
  -H "Content-Type: application/json" \
  -d '{"name": "test_table", "schema": {...}}'
```

## Components
- **REST Catalog**: Manages Iceberg table metadata (port 8181)
- **Storage**: Uses MinIO (S3-compatible) for actual data storage

## Cleanup
```bash
kubectl delete -f iceberg-simple.yaml
```

