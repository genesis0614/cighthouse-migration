#!/bin/bash

# CloudFormation Export 값을 각 변수명에 지정
PriSub3Id=$(aws cloudformation list-exports --query "Exports[?Name=='PriSub3Id'].Value" --output text)
PriSub4Id=$(aws cloudformation list-exports --query "Exports[?Name=='PriSub4Id'].Value" --output text)
PubSub1Id=$(aws cloudformation list-exports --query "Exports[?Name=='PubSub1Id'].Value" --output text)
PubSub2Id=$(aws cloudformation list-exports --query "Exports[?Name=='PubSub2Id'].Value" --output text)
MyVpc=$(aws cloudformation list-exports --query "Exports[?Name=='MyVpc'].Value" --output text)

# cluster-config.yaml 생성
cat > cluster-config.yaml <<EOL
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: my-cluster
  region: ap-southeast-1
  version: "1.27"

vpc:
  id: $MyVpc
  subnets:
    private:
      ap-southeast-1a:
        id: $PriSub3Id
      ap-southeast-1c:
        id: $PriSub4Id
    public:
      ap-southeast-1a:
        id: $PubSub1Id
      ap-southeast-1c:
        id: $PubSub2Id

managedNodeGroups:
  - name: worker-nodes
    instanceType: t3.medium
    desiredCapacity: 2
    minSize: 2
    maxSize: 3
    volumeSize: 20
    privateNetworking: true
    volumetype: gp3
    ssh:
      allow: true
      publicKeyName: singapore-key
    iam:
      withAddonPolicies:
        autoScaler: true
        cloudWatch: true
        ebs: true
        awsLoadBalancerController: true

addons:
  - name: vpc-cni
    version: latest
    attachPolicyARNs:
      - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

cloudWatch:
  clusterLogging:
    enableTypes: ["audit", "authenticator"]

iam:
  withOIDC: true
EOL

# eksctl 클러스터 생성
eksctl create cluster -f cluster-config.yaml
