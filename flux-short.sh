# Source: https://gist.github.com/0431989df4836eb82bdac0cc53c7f3d6

# Used in https://youtu.be/R6OeIgb7lUI

##############################
# Flux 2 With GitOps Toolkit #
##############################

# What Is GitOps And Why Do We Want It?: https://youtu.be/HKkhD6nokC8
# Argo CD: Applying GitOps Principles To Manage Production Environment In Kubernetes: https://youtu.be/vpWQeoaiRM4

#########
# Setup #
#########

minikube start

minikube addons enable ingress

export INGRESS_HOST=$(minikube ip)


##############################
# Creating environment repos #
##############################

mkdir -p flux-production/apps

cd flux-production

git init

gh repo create --public

echo "# Production" | tee README.md

git add .

git commit -m "Initial commit"

git push --set-upstream origin master

kubectl create namespace production

cd ..

mkdir -p flux-staging/apps

cd flux-staging

git init

gh repo create --public

echo "# Staging" | tee README.md

git add .

git commit -m "Initial commit"

git push --set-upstream origin master

kubectl create namespace staging

cd ..

#################
# Bootstrapping #
#################

flux bootstrap github \
    --owner $GITHUB_ORG \
    --repository flux-fleet \
    --branch main \
    --path apps \
    --personal $GITHUB_PERSONAL

kubectl --namespace flux-system \
    get pods

git clone \
    https://github.com/$GITHUB_ORG/flux-fleet.git

cd flux-fleet

ls -1 apps

ls -1 apps/flux-system

####################
# Creating sources #
####################

flux create source git staging \
    --url https://github.com/$GITHUB_ORG/flux-staging \
    --branch master \
    --interval 30s \
    --export \
    | tee apps/staging.yaml

flux create kustomization staging \
    --source staging \
    --path "./" \
    --prune true \
    --validation client \
    --interval 10m \
    --export \
    | tee -a apps/staging.yaml

flux create source git production \
    --url https://github.com/$GITHUB_ORG/flux-production \
    --branch master \
    --interval 30s \
    --export \
    | tee apps/production.yaml

flux create kustomization production \
    --source production \
    --path "./" \
    --prune true \
    --validation client \
    --interval 10m \
    --export \
    | tee -a apps/production.yaml

flux create source git \
    devops-toolkit \
    --url https://github.com/vfarcic/devops-toolkit \
    --branch master \
    --interval 30s \
    --export \
    | tee apps/devops-toolkit.yaml

git add .

git commit -m "Added environments"

git push

watch flux get sources git

watch flux get kustomizations

cd ..

###############################
# Deploying the first release #
###############################

cd flux-staging

echo "image:
    tag: 2.9.9
ingress:
    host: staging.devops-toolkit.$INGRESS_HOST.nip.io" \
    | tee values.yaml

flux create helmrelease \
    devops-toolkit-staging \
    --source GitRepository/devops-toolkit \
    --values values.yaml \
    --chart "helm" \
    --target-namespace staging \
    --interval 30s \
    --export \
    | tee apps/devops-toolkit.yaml

rm values.yaml

git add .

git commit -m "Initial commit"

git push

watch flux get helmreleases

kubectl --namespace staging \
    get pods

##########################
# Deploying new releases #
##########################

cat apps/devops-toolkit.yaml \
    | sed -e "s@tag: 2.9.9@tag: 2.9.17@g" \
    | tee apps/devops-toolkit.yaml

git add .

git commit -m "Upgrade to 2.9.17"

git push

watch kubectl --namespace staging \
    get pods

watch kubectl --namespace staging \
    get deployment \
    staging-devops-toolkit-devops-toolkit \
    --output jsonpath="{.spec.template.spec.containers[0].image}"

cd ..

###########################
# Promoting to production #
###########################

cd flux-production

echo "image:
    tag: 2.9.17
ingress:
    host: devops-toolkit.$INGRESS_HOST.nip.io" \
    | tee values.yaml

flux create helmrelease \
    devops-toolkit-production \
    --source GitRepository/devops-toolkit \
    --values values.yaml \
    --chart "helm" \
    --target-namespace production \
    --interval 30s \
    --export \
    | tee apps/devops-toolkit.yaml

rm values.yaml

git add .

git commit -m "Initial commit"

git push

watch flux get helmreleases

kubectl --namespace production \
    get pods

#########################
# Destroying Everything #
#########################

minikube delete

cd ..

cd flux-fleet

gh repo view --web

# Delete the repo

cd ..

rm -rf flux-fleet

cd flux-staging

gh repo view --web

# Delete the repo

cd ..

rm -rf flux-staging

cd flux-production

gh repo view --web

# Delete the repo

cd ..

rm -rf flux-production
