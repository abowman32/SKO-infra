#!/usr/bin/env bash

{
  CBUSER="corbolj" #Edit if you are not corbolj
  CLUSTER="skoflow"
}

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

{
  MYSQLNS=mysql
  kubectl create namespace $MYSQLNS
  kubectl label  namespace $MYSQLNS name=$MYSQLNS
  kubectl config set-context $(kubectl config current-context) --namespace=$MYSQLNS
}

helm install flow-mysql stable/mysql \
  --namespace $MYSQLNS

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
}

{
  DB_Endpoint='flow-mysql.mysql.svc.cluster.local'
  #Dbname=
  Dbuser='flowuser'
  dbPassword='password'
}

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

{
  CORENS='cloudbees-core'
  kubectl create namespace $CORENS
  kubectl label  namespace $CORENS name=$CORENS
  kubectl config set-context $(kubectl config current-context) --namespace=$CORENS
}

{
  kubectl create -f ssd-storage.yaml
  kubectl patch storageclass standard -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
  kubectl patch storageclass ssd -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
  kubectl create clusterrolebinding cluster-admin-binding --clusterrole cluster-admin --user $(gcloud config get-value account)
}

{
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.23.0/deploy/mandatory.yaml
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.23.0/deploy/provider/cloud-generic.yaml
}

sleep 120

{
  CLOUDBEES_CORE_IP=$(kubectl -n ingress-nginx get service ingress-nginx -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
  DOMAIN_NAME="jenkins.$CLOUDBEES_CORE_IP.xip.io"
}

{
  helm install cloudbees-core \
    cloudbees/cloudbees-core \
    --set OperationsCenter.HostName=$DOMAIN_NAME \
    --set OperationsCenter.ServiceType='ClusterIP' \
    --namespace=$CORENS \
    --values=sko.yml
}

# Verify
# kubectl get pods --namespace=elasticsearch -l app=elasticsearch-master -w
# helm test elasticsearch
#gcloud container clusters delete $CLUSTER-$CBUSER --region us-east1
