brew install --cask multipass
brew install kubectl

multipass launch --name node1 jammy
multipass launch --name node2 jammy
multipass launch --name node3 jammy

multipass list

multipass stop node1
multipass delete node1
multipass delete --purge node1

multipass launch --name node1 jammy --cpus 4 --memory 8G --disk 40G

multipass shell node1
curl -sfL https://get.k3s.io | sh -s - server --write-kubeconfig-mode 644

multipass exec node1 -- sudo cat /var/lib/rancher/k3s/server/node-token
multipass exec node1 -- sudo cat /etc/rancher/k3s/k3s.yaml > ~/.kube/multipass-k3s.yaml
multipass exec node1 -- sudo systemctl status k3s
multipass exec node2 -- sudo systemctl status k3s-agent
multipass exec node3 -- sudo systemctl status k3s-agent

multipass info node1 | grep -E 'CPUs|Memory|Disk'

curl -sfL https://get.k3s.io | K3S_URL=https://192.168.64.2:6443 K3S_TOKEN=K10fc94e4580aec25c51242534694ea97c398f7f46c6fd67ee53c8cd0096a1aeafe::server:5f6fd9c43c39efc0ad0e3fa716a295c4 sh -

curl -sfL https://get.k3s.io | K3S_URL=https://192.168.64.2:6443 K3S_TOKEN=K10a04aab3dde1329836994b4ba69d5dc2269105a8a88bdb1d33fa09971c8a407c5::server:b84a490cdd8cbb29bf5a819d3c48f899 sh - 

multipass delete --purge node1
multipass delete --purge node1 node2 node3
multipass delete --purge $(multipass list --format csv | tail -n +2 | cut -d, -f1)

TOKEN=$(multipass exec node1 -- sudo cat /var/lib/rancher/k3s/server/node-token)

sed -i '' 's/127.0.0.1/192.168.64.2/g' ~/.kube/multipass-k3s.yaml
sed -i '' 's/127.0.0.1/192.168.64.5/g' ~/.kube/multipass-k3s.yaml

export KUBECONFIG=~/.kube/multipass-k3s.yaml
kubectl config use-context default  
# Or just run commands with KUBECONFIG=...

kubectl config current-context

kubectl config get-contexts

kubectl get nodes

K10fc94e4580aec25c51242534694ea97c398f7f46c6fd67ee53c8cd0096a1aeafe::server:5f6fd9c43c39efc0ad0e3fa716a295c4