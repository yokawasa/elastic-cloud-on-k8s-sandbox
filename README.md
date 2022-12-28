# elastic-cloud-on-k8s-sandbox

This is a sandbox repository where I play around with [Elastic Cloud on Kubernetes](https://github.com/elastic/cloud-on-k8s) (ECK) by running sample configurations, testing their behaviors, and so on

<!-- TOC -->

- [elastic-cloud-on-k8s-sandbox](#elastic-cloud-on-k8s-sandbox)
  - [Installation](#installation)
    - [Install ECK](#install-eck)
    - [Deploy Elasticsearch](#deploy-elasticsearch)
    - [Access Elasticsearch](#access-elasticsearch)
    - [Deploy Kibana](#deploy-kibana)
    - [Access Kibana](#access-kibana)
  - [Configurations](#configurations)
    - [Volume Claim Template](#volume-claim-template)
      - [Update PersistentVolumeClaims](#update-persistentvolumeclaims)
      - [gp2 storage class can NOT expand online](#gp2-storage-class-can-not-expand-online)
      - [emptyDir](#emptydir)
  - [REFERENCES](#references)

<!-- /TOC -->

## Installation

### Install ECK

Download and install
```bash
VERSION=1.3.0
kubectl apply -f https://download.elastic.co/downloads/eck/${VERSION}/all-in-one.yaml
```

Check if all elastic cloud pods running

```bash
kubectl get all -n elastic-system

NAME                     READY   STATUS    RESTARTS   AGE
pod/elastic-operator-0   1/1     Running   0          14m

NAME                             TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
service/elastic-webhook-server   ClusterIP   10.100.111.185   <none>        443/TCP   14m

NAME                                READY   AGE
statefulset.apps/elastic-operator   1/1     14m
```

Check operator logs

```bash
kubectl -n elastic-system logs -f statefulset.apps/elastic-operator
```

### Deploy Elasticsearch

First of all create a namespace, `testns` for test

```
kubectl create namespace testns
```

Deploy a simple Elasticsearch cluster

```yaml
# kubectl apply -f manifests/elasticsearch-quickstart.yaml -n testns

cat <<EOF | kubectl apply -n testns -f -
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: quickstart
spec:
  version: 7.10.0
  nodeSets:
  - name: default
    count: 3
    config:
      node.store.allow_mmap: false
EOF
```

Check if elasticsearch is running

```bash
kubectl get elasticsearch -n testns

NAME         HEALTH   NODES   VERSION   PHASE   AGE
quickstart   green    3       7.10.0    Ready   5m6s
```

Check elasticsearch service

```bash
kubectl get svc -n testns

NAME                      TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
quickstart-es-default     ClusterIP   None           <none>        9200/TCP   5m27s
quickstart-es-http        ClusterIP   10.100.249.9   <none>        9200/TCP   5m28s
quickstart-es-transport   ClusterIP   None           <none>        9300/TCP   5m28s
```

### Access Elasticsearch

Get ES password that is automatically created with the password stored in a secret.

```bsah
NAMESPACE=testns
PASSWORD=$(kubectl get secret quickstart-es-elastic-user -n ${NAMESPACE} -o go-template='{{.data.elastic | base64decode}}')
```

Use `kubectl port-forward` to access Kibana from your local machine: 

```bash
kubectl port-forward service/quickstart-es-http 9200 -n testns
curl -u "elastic:$PASSWORD" -k "https://localhost:9200"

{
  "name" : "quickstart-es-default-0",
  "cluster_name" : "quickstart",
  "cluster_uuid" : "yRZmQpplQ0udcq3k1_1j2w",
  "version" : {
    "number" : "7.10.0",
    "build_flavor" : "default",
    "build_type" : "docker",
    "build_hash" : "51e9d6f22758d0374a0f3f5c6e8f3a7997850f96",
    "build_date" : "2020-11-09T21:30:33.964949Z",
    "build_snapshot" : false,
    "lucene_version" : "8.7.0",
    "minimum_wire_compatibility_version" : "6.8.0",
    "minimum_index_compatibility_version" : "6.0.0-beta1"
  },
  "tagline" : "You Know, for Search"
}
```


### Deploy Kibana

Deploy a simple Kibana

```yaml
# kubectl apply -f manifests/kibana-quickstart.yaml -n testns

cat <<EOF | kubectl apply -n testns -f -
apiVersion: kibana.k8s.elastic.co/v1
kind: Kibana
metadata:
  name: quickstart
spec:
  version: 7.10.0
  count: 1
  elasticsearchRef:
    name: quickstart
EOF
```

### Access Kibana

Access Kibana

```bash
kubectl get svc -n testns

NAME                      TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
quickstart-es-default     ClusterIP   None            <none>        9200/TCP   34m
quickstart-es-http        ClusterIP   10.100.249.9    <none>        9200/TCP   34m
quickstart-es-transport   ClusterIP   None            <none>        9300/TCP   34m
quickstart-kb-http        ClusterIP   10.100.93.112   <none>        5601/TCP   24m
```

Get Kibana password that is automatically created with the password stored in a secret.

```bash
export NAMESPACE=testns
PASSWORD=$(kubectl get secret quickstart-es-elastic-user -n ${NAMESPACE} -o=jsonpath='{.data.elastic}' | base64 --decode;)
```

Use `kubectl port-forward` to access Kibana from your local workstation:

```bash
kubectl port-forward service/quickstart-kb-http 5601 -n testns
open https://localhost:5601
```

The Kibana login page comes up and you'll be able to login by giving the password for `elastic` user.


## Configurations

-  ECK rely on StatefulSets to manage PersistentVolumes.


### Volume Claim Template

You configure [VolumeClaimTemplates](https://www.elastic.co/guide/en/cloud-on-k8s/master/k8s-volume-claim-templates.html) section of the Elasticsearch resource to use PersistentVolume to store Elasticsearch data.

First of all, let's take a look at storage classes we have. As you can see we have `gp2` storage class by default (in this case, it's in EKS)

```bash
kubectl get storageclass

NAME            PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
gp2 (default)   kubernetes.io/aws-ebs   Delete          WaitForFirstConsumer   false                  8h
```

By default, the operator creates a `PersistentVolumeClaim` (PVC) with a capacity of `1Gi` for each pod in an Elasticsearch cluster.

> NOTE: ECK automatically deletes `PersistentVolumeClaim` resources if they are not required for any Elasticsearch node, but you can change this behavior with [storage class reclaim policy](https://kubernetes.io/docs/concepts/storage/storage-classes/#reclaim-policy) (`reclaimPolicy`: Delete or Retain).

```bash
 kubectl get pvc -n testns

NAME                                         STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
elasticsearch-data-quickstart-es-default-0   Bound    pvc-afbdd454-e331-4691-82f0-9f639970dd92   1Gi        RWO            gp2            72m
elasticsearch-data-quickstart-es-default-1   Bound    pvc-b67d4346-46b1-4fda-9b5e-48d9b5dccf4f   1Gi        RWO            gp2            72m
elasticsearch-data-quickstart-es-default-2   Bound    pvc-67182316-8fc1-4a0a-9c0a-d87b5c0a01bb   1Gi        RWO            gp2            72m
```

You can see 1Gi of PVC is allocated for each pod
```yaml
kubectl get pvc elasticsearch-data-quickstart-es-default-0 -n testns -o yaml

apiVersion: v1
kind: PersistentVolumeClaim
metadata:
...
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: gp2
  volumeMode: Filesystem
  volumeName: pvc-afbdd454-e331-4691-82f0-9f639970dd92
status:
  accessModes:
  - ReadWriteOnce
  capacity:
    storage: 1Gi
  phase: Bound
```

#### Update PersistentVolumeClaims

You can define your own volume claim template with the desired storage capacity with `VolumeClaimTempalte`. Also if the storage class allows volume expansion, you can increase the storage requests size in the `volumeClaimTemplates`. ECK will update the existing PersistentVolumeClaims accordingly, and recreate the StatefulSet automatically.

See also: https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-volume-claim-templates.html


```yaml
# kubectl apply -f manifests/elasticsearch-volumeclaim-gp2.yaml -n testns

cat <<EOF | kubectl apply -n testns -f -
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: quickstart
spec:
  version: 7.10.0
  nodeSets:
  - name: default
    count: 3
    config:
      node.store.allow_mmap: false
    # request 2Gi of persistent data storage for pods in this topology element
    volumeClaimTemplates:
    - metadata:
        name: elasticsearch-data
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 2Gi
        storageClassName: gp2
EOF
```

> [NOTE] **ExpandInUsePersistentVolumes = Enable expanding in-use PVC** 
> - If the volume driver supports ExpandInUsePersistentVolumes:
>   - the filesystem is resized online, without the need of restarting the Elasticsearch process, or re-creating the Pods. 
> - If the volume driver does not support ExpandInUsePersistentVolumes
>   - Pods must be manually deleted after the resize, to be recreated automatically with the expanded filesystem.
> 
> ExpandInUsePersistentVolumes is supported by the in-tree volume plugins GCE-PD, AWS-EBS, Cinder, and Ceph RBD.
> - https://kubernetes.io/blog/2018/07/12/resizing-persistent-volumes-using-kubernetes/#online-file-system-expansion
> - https://kubernetes.io/docs/concepts/storage/persistent-volumes/#resizing-an-in-use-persistentvolumeclaim


#### gp2 storage class can NOT expand online

Unfortunately, default gp2 storage class does not support online storage volume expansion (see ALLOWVOLUMEEXPANSION `false` below)

```bash
kubectl get storageclass

NAME            PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
gp2 (default)   kubernetes.io/aws-ebs   Delete          WaitForFirstConsumer   false                  10h
```

See also [Storage class gp2](https://docs.aws.amazon.com/eks/latest/userguide/storage-classes.html)

#### emptyDir

If you don't care about data persistency, you can use an `emptyDir` volume for Elasticsearch data:

```yaml
spec:
  nodeSets:
  - name: data
    count: 10
    podTemplate:
      spec:
        volumes:
        - name: elasticsearch-data
          emptyDir: {}
```

See also https://www.elastic.co/guide/en/cloud-on-k8s/1.3/k8s-volume-claim-templates.html#k8s_emptydir




## REFERENCES

- https://github.com/elastic/cloud-on-k8s
- https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html
- https://github.com/elastic/cloud-on-k8s/tree/master/config
- [Kubernetes feature gates](https://kubernetes.io/docs/reference/command-line-tools-reference/feature-gates/) 
