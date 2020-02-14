# SKO CloudeBees Core and Flow Workshop -- GKE Cluster Creation and Configuration (*ROUGH DRAFT*)

The purpose of this script is to help automate the provisioning of a GKE cluster using the Google Cloud SDK and will install MySQL, Elasticsearch, and CloudBees Core in the cluster using Helm 3.

Flow will be installed during the workshop.

## Prerequisites

* **Google Cloud SDK** (gcloud) (<https://cloud.google.com/sdk/docs/downloads-interactive>)

  * Initialize and login to Google <https://cloud.google.com/sdk/docs/initializing>  
    * You will need to verify which project under the CloudBees org you need to create this cluster within

* **Helm 3** (<https://github.com/helm/helm#install>)
  * *WILL NOT WORK WITH HELM 2*
  * If you have not already setup the CloudBees and Stable chart repos, run the following commands once helm is installed:
    * helm repo add cloudbees https://charts.cloudbees.com/public/cloudbees
    * helm repo add stable https://kubernetes-charts.storage.googleapis.com
    * helm repo update

* **Required Variables in Script**

  * `CBUSER` -- update this variable with your desired username (eg, abowman, corbolj, etc). It doesn't have to be correlated to anything and just is to make your cluster name unique and will be used tag your cluster.

  * `CLUSTER` -- doesn't need to change.

  * `FSADDR` -- used to identify the NFS server for the RWX and ROX. Don't change unless advised to do so.

  * `FQDN` -- unique and will be used further when installing Flow.