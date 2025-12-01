# Simple MinIO Storage

## Deploy
```bash
kubectl apply -f minio.yaml
```

## Access Storage

**1. Port-forward to access:**
```bash
# S3 API (port 9000)
kubectl port-forward svc/minio -n minio 9000:9000

# Web Console (port 9001)  
kubectl port-forward svc/minio -n minio 9001:9001
```

**2. Open in browser:**
- Console: http://localhost:9001
- API: http://localhost:9000

**3. Login:**
- Username: `minioadmin`
- Password: `minioadmin`

## That's it. Simple and reusable.

## Cleanup
```bash
kubectl delete -f minio.yaml
```

