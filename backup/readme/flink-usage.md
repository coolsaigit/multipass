# Simple Flink Setup

## Deploy
```bash
kubectl apply -f flink.yaml
```

## Access Flink

**1. Port-forward JobManager Web UI:**
```bash
kubectl port-forward svc/flink-jobmanager -n flink 8081:8081
```

**2. Access Flink Web UI:**
- Open: http://localhost:8081
- No authentication required

## Using Flink

**Submit a Job:**

**Option 1: Via Web UI**
1. Go to http://localhost:8081
2. Click "Submit New Job"
3. Upload your JAR file
4. Configure main class and parameters
5. Submit

**Option 2: Via Flink CLI**
```bash
# Port-forward for job submission
kubectl port-forward svc/flink-jobmanager -n flink 8081:8081

# Submit job (from your local machine with Flink installed)
flink run -m localhost:8081 your-job.jar
```

**Option 3: Via kubectl exec**
```bash
# Copy your JAR to the pod
kubectl cp your-job.jar flink/<jobmanager-pod-name>:/tmp/your-job.jar

# Submit from inside the pod
kubectl exec -it -n flink <jobmanager-pod-name> -- \
  /opt/flink/bin/flink run /tmp/your-job.jar
```

**Example: Run WordCount (if available in image)**
```bash
kubectl exec -it -n flink $(kubectl get pod -n flink -l component=jobmanager -o jsonpath='{.items[0].metadata.name}') -- \
  /opt/flink/bin/flink run /opt/flink/examples/streaming/WordCount.jar
```

## Components
- **JobManager**: Coordinates jobs and manages cluster (port 8081 for Web UI, 6123 for RPC)
- **TaskManager**: Executes tasks (port 6122 for data)

## Ports
- **8081**: JobManager Web UI
- **6123**: JobManager RPC
- **6122**: TaskManager data port

## Check Status
```bash
# Check pods
kubectl get pods -n flink

# Check JobManager logs
kubectl logs -n flink -l component=jobmanager

# Check TaskManager logs
kubectl logs -n flink -l component=taskmanager
```

## Cleanup
```bash
kubectl delete -f flink.yaml
```

