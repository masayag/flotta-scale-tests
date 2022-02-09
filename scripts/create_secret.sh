#!/bin/bash

# Create a service account
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flotta-scale
EOF

# Attach the service account to a privileged role
kubectl create clusterrolebinding flotta-scale-cluster-admin --clusterrole=cluster-admin --serviceaccount=default:flotta-scale

# Get the token
K8S_BEARER_TOKEN=$(kubectl get secret $(kubectl get serviceaccount flotta-scale -o json | jq -r '.secrets[].name') -o yaml | grep " token:" | awk {'print $2'} |  base64 -d)

export K8S_BEARER_TOKEN
