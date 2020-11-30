VERSION=1.3.0
kubectl apply -f https://download.elastic.co/downloads/eck/${VERSION}/all-in-one.yaml

kubectl get all -n elastic-system
