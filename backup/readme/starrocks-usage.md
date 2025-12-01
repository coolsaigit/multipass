# Simple StarRocks Setup

## Deploy
```bash
kubectl apply -f starrocks.yaml
```

## Access StarRocks

**1. Port-forward FE (Frontend) - Query port:**
```bash
kubectl port-forward svc/starrocks-fe -n starrocks 9030:9030
```

**2. Port-forward FE Web UI:**
```bash
kubectl port-forward svc/starrocks-fe -n starrocks 8030:8030
```

**3. Access:**
- **Web UI**: http://localhost:8030
  - When prompted for login, use:
    - Username: `root`
    - Password: **leave empty** (press Enter/OK without typing anything)
  - Note: Browser will show HTTP Basic Auth popup - just leave password blank
- **MySQL Client**: Connect to `localhost:9030` (password is empty)

## Using StarRocks

**Connect via MySQL client:**
```bash
mysql -h 127.0.0.1 -P 9030 -u root
```

**Example SQL:**
```sql
-- Show databases
SHOW DATABASES;

-- Create database
CREATE DATABASE test_db;
USE test_db;

-- Create table
CREATE TABLE test_table (
    id INT,
    name VARCHAR(50),
    created_at DATETIME
) ENGINE=OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 3;

-- Insert data
INSERT INTO test_table VALUES 
(1, 'test1', NOW()),
(2, 'test2', NOW());

-- Query
SELECT * FROM test_table;
```

**Connect via Python:**
```python
import pymysql

conn = pymysql.connect(
    host='127.0.0.1',
    port=9030,
    user='root',
    password='',
    database='test_db'
)

cursor = conn.cursor()
cursor.execute("SELECT * FROM test_table")
results = cursor.fetchall()
print(results)
```

## Components
- **FE (Frontend)**: Query coordination and metadata (ports 8030, 9020, 9030)
- **BE (Backend)**: Data storage and query execution (ports 8040, 8060, 9060)

## Ports
- **8030**: FE Web UI
- **9020**: FE RPC (internal)
- **9030**: MySQL protocol (query port)
- **8040**: BE Web UI
- **8060**: BE Heartbeat
- **9060**: BE Service

## Cleanup
```bash
kubectl delete -f starrocks.yaml
```

