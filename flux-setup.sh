#!/bin/bash

CLUSTER_TYPE=${1:-minikube}

#######################################
# Install flux cli and other tools    #
#######################################
brew bundle

#######################################
# Install a kubernetes cluster        #
#######################################

if [ "$CLUSTER_TYPE" == "minikube" ]; then
    minikube delete
    minikube start --driver=docker \
        --docker-opt="default-ulimit=nofile=65536:65536"

    # minikube addons enable ingress

    INGRESS_HOST=$(minikube ip)
    export INGRESS_HOST

elif [ "$CLUSTER_TYPE" == "k3s" ]; then
    ./create_k3s_cluster.sh
    INGRESS_HOST=$(hostname -I | awk '{ print $1 }').nip.io
    export INGRESS_HOST

elif [ "$CLUSTER_TYPE" == "kind" ]; then
    pf kind create flux-cluster
    pf kube switch flux-cluster
    INGRESS_HOST=$(hostname -I | awk '{ print $1 }').nip.io
    export INGRESS_HOST
fi

#################
# Bootstrapping #
#################
flux check --pre

flux bootstrap github \
    --token-auth \
    --owner $GITHUB_ORG \
    --repository gitops-flux-bootstrap \
    --branch main \
    --path clusters/staging/flux-cluster \
    --personal $GITHUB_PERSONAL
