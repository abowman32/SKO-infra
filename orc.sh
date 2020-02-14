#!/usr/bin/env bash

# REQUIRED VARIABLES
{
  CBUSER="corbolj" #Edit if you are not corbolj
  CLUSTER="skoflow" #
  FQDN="PUT_YOUR_FQDN_HERE"
}

# Step 0 - Cluster Provisioning
# TODO: This currently over-provisions.
# We need 4 x n1-standard-4 (zonal is OK for SKO)
{
  gcloud container clusters create $CLUSTER-$CBUSER \
    --machine-type=n1-standard-4 \
    --enable-autoscaling \
    --max-nodes '1' \
    --min-nodes '1' \
    --labels=owner=$CBUSER \
    --region us-east1

  kubectl create clusterrolebinding cluster-admin-binding --clusterrole cluster-admin --user $(gcloud config get-value account)
}

# Step 1 - MySQL
{
  MYSQLNS=mysql
  kubectl create namespace $MYSQLNS
  kubectl label  namespace $MYSQLNS name=$MYSQLNS
  kubectl config set-context $(kubectl config current-context) --namespace=$MYSQLNS
}

helm install flow-mysql stable/mysql \
  --namespace $MYSQLNS \
  -f mysql-values.yaml

kubectl run jumpbox sleep 30000 --image=ubuntu:16.04 --restart=Never --generator=run-pod/v1 --namespace $MYSQLNS

sleep 60

{
  MYSQL_ROOT_PASSWORD=$(kubectl get secret --namespace mysql flow-mysql -o jsonpath="{.data.mysql-root-password}" | base64 --decode; echo)
  MYSQL_PORT=3306
}

{
  kubectl exec jumpbox -- sh -c "apt-get update && apt-get install mysql-client -y"
  kubectl exec jumpbox -- sh -c "mysql -h flow-mysql -P${MYSQL_PORT} -u root -p${MYSQL_ROOT_PASSWORD} \
    -Bse \"CREATE USER 'flowuser'@'localhost' IDENTIFIED BY 'password'\""
  kubectl exec jumpbox -- sh -c "mysql -h flow-mysql -P${MYSQL_PORT} -u root -p${MYSQL_ROOT_PASSWORD} \
    -Bse \"GRANT ALL PRIVILEGES ON * . * TO 'flowuser'@'localhost'\""
  kubectl exec jumpbox -- sh -c "mysql -h flow-mysql -P${MYSQL_PORT} -u root -p${MYSQL_ROOT_PASSWORD} \
    -Bse \"FLUSH PRIVILEGES\""
  kubectl exec jumpbox -- sh -c "mysql -h flow-mysql -P${MYSQL_PORT} -u root -p${MYSQL_ROOT_PASSWORD} \
    -Bse \"SHOW VARIABLES LIKE '%character%';SHOW VARIABLES LIKE '%collation%';\""
  echo ""
  echo "All above character sets should be set to UTF8 (except for filesystem, which should be set to binary)"
    
}

# MySQL Outputs
{
  DB_Endpoint='flow-mysql.mysql.svc.cluster.local'
  #Dbname=
  Dbuser='flowuser'
  dbPassword='password'
}

# Step 2: FQDN 
# You need a FQDN, put it in the required variables in step 0

# Step 3: ElasticSearch
{
  ESNS=elasticsearch
  kubectl create namespace $ESNS
  kubectl label  namespace $ESNS name=$ESNS
  kubectl config set-context $(kubectl config current-context) --namespace=$ESNS
}
{
  helm repo add elastic https://helm.elastic.co
  helm install elasticsearch elastic/elasticsearch \
    --namespace $ESNS
}

# Verify
## kubectl get pods --namespace=elasticsearch -l app=elasticsearch-master -w
# this will take a second to complete successfully
# helm test elasticsearch

# ES Outputs
# TODO: Get the ES endpoint
echo elastic search service endpoint: 
kubectl get svc -n $ESNS

# Step 4: RWX storage (NFS for GKE)

# A single filestore needs to exist in the project. These are project-wide. 
# ps-dev already has one in us-central1-a
# if the this won't work, you'll need to install the gcloud beta tools and use the following:

# Create File Store
# FS=nfs
# gcloud beta filestore instances create ${FS} \
#     --project=${PROJECT} \
#     --zone=${ZONE} \
#     --tier=STANDARD \
#     --file-share=name="volumes",capacity=1TB \
#     --network=name="default"
# FSADDR=$(gcloud beta filestore instances describe ${FS} \
#      --project=${PROJECT} \
#      --zone=${ZONE} \
#      --format="value(networks.ipAddresses[0])")

# Change this to the correct FSADDR as needed 
FSADDR=10.89.48.58
kubectl config set-context $(kubectl config current-context) --namespace=kube-system
helm install nfs-cp stable/nfs-client-provisioner --set nfs.server=${FSADDR} --set nfs.path=/volumes

# Step 5: RWO storage

# TODO: Does anything need to be done here? Is standard type underperformant for flow or does it need ssd?
# Provision ssd storage if we do need it
# {
#   kubectl create -f ssd-storage.yaml
#   kubectl patch storageclass standard -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
#   kubectl patch storageclass ssd -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
# }

# Step 6: Core Modern

DOMAIN_NAME="core.$FQDN"   # change as desired

{
  CORENS='cloudbees-core'
  kubectl create namespace $CORENS
  kubectl label  namespace $CORENS name=$CORENS
  kubectl config set-context $(kubectl config current-context) --namespace=$CORENS
}

# Manual ingress creation. YMMV here. Remove the nginx-ingress.Enabled=true from the install command if you're deploying manually. 
# {
#   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.23.0/deploy/mandatory.yaml
#   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.23.0/deploy/provider/cloud-generic.yaml
# }
#
# sleep 120
#
# {
#   CLOUDBEES_CORE_IP=$(kubectl -n ingress-nginx get service ingress-nginx -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
#   DOMAIN_NAME="jenkins.$CLOUDBEES_CORE_IP.xip.io"
# }
#

helm install cloudbees-core \
  cloudbees/cloudbees-core \
  --set nginx-ingress.Enabled=true \
  --set OperationsCenter.Platform=gke \
  --set OperationsCenter.HostName=$DOMAIN_NAME \
  --namespace=$CORENS

# Output prereq values

# Teardown steps

#gcloud container clusters delete $CLUSTER-$CBUSER --region us-east1