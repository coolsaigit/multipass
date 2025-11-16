# Simple Redpanda Setup

## Deploy
```bash
kubectl apply -f redpanda.yaml
```

## Access Redpanda

**1. Port-forward Kafka API:**
```bash
kubectl port-forward svc/redpanda -n redpanda 9092:9092
```

**2. Port-forward Redpanda Console (Web UI):**
```bash
# Port-forward directly to pod (more reliable)
kubectl port-forward -n redpanda $(kubectl get pod -n redpanda -l app=redpanda-console -o jsonpath='{.items[0].metadata.name}') 8080:8080

# Or via service (may need retry)
kubectl port-forward svc/redpanda-console -n redpanda 8080:8080
```

**3. Port-forward Schema Registry:**
```bash
kubectl port-forward svc/redpanda -n redpanda 8081:8081
```

**4. Port-forward Admin API:**
```bash
kubectl port-forward svc/redpanda -n redpanda 9644:9644
```

## Access Points

- **Redpanda Console (Web UI)**: http://localhost:8080
  - No authentication required
  - Browse topics, messages, schemas, etc.

- **Kafka API**: `localhost:9092`
  - Use with any Kafka client
  - Compatible with Kafka protocol

- **Schema Registry**: `http://localhost:8081`
  - For Avro/Protobuf schema management

- **Admin API**: `http://localhost:9644`
  - Redpanda admin operations

## Using Redpanda

**Option 1: Via Redpanda Console (Web UI)**
1. Open http://localhost:8080
2. Create topics, produce/consume messages
3. View schemas, monitor cluster

**Option 2: Via Kafka CLI tools**
```bash
# Create a topic
kubectl exec -it -n redpanda $(kubectl get pod -n redpanda -l app=redpanda -o jsonpath='{.items[0].metadata.name}') -- \
  rpk topic create my-topic

# List topics
kubectl exec -it -n redpanda $(kubectl get pod -n redpanda -l app=redpanda -o jsonpath='{.items[0].metadata.name}') -- \
  rpk topic list

# Produce messages
kubectl exec -it -n redpanda $(kubectl get pod -n redpanda -l app=redpanda -o jsonpath='{.items[0].metadata.name}') -- \
  rpk topic produce my-topic

# Consume messages
kubectl exec -it -n redpanda $(kubectl get pod -n redpanda -l app=redpanda -o jsonpath='{.items[0].metadata.name}') -- \
  rpk topic consume my-topic
```

**Option 3: Via Kafka clients (Python example)**
```python
from kafka import KafkaProducer, KafkaConsumer

# Producer
producer = KafkaProducer(bootstrap_servers='localhost:9092')
producer.send('my-topic', b'Hello Redpanda!')
producer.flush()

# Consumer
consumer = KafkaConsumer('my-topic', bootstrap_servers='localhost:9092')
for message in consumer:
    print(message.value)
```

**Option 4: Via rpk (Redpanda CLI)**
```bash
# Port-forward first, then use rpk locally if installed
rpk cluster info --brokers localhost:9092
```

## Components
- **Redpanda**: Kafka-compatible streaming platform (port 9092 for Kafka API)
- **Redpanda Console**: Web UI for managing topics and messages (port 8080)
- **Schema Registry**: Schema management (port 8081)

## Ports
- **9092**: Kafka API (internal)
- **19092**: Kafka API (external)
- **8080**: Redpanda Console Web UI
- **8081**: Schema Registry (internal)
- **18081**: Schema Registry (external)
- **8082**: Pandaproxy (internal)
- **18082**: Pandaproxy (external)
- **9644**: Admin API

## Check Status
```bash
# Check pods
kubectl get pods -n redpanda

# Check Redpanda logs
kubectl logs -n redpanda -l app=redpanda

# Check Console logs
kubectl logs -n redpanda -l app=redpanda-console
```

## Cleanup
```bash
kubectl delete -f redpanda.yaml
```

