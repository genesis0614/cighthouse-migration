# Cighthouse: AWS Multi-Region Data Migration & Blue-Green Deployment

## 📋 프로젝트 개요

**Cighthouse**는 기존 AWS EC2 모놀리식 서비스를 EKS 기반 마이크로서비스로 마이그레이션하는 프로젝트입니다.
두 개의 AWS 리전(Seoul, Singapore)을 활용하여 리전 간 데이터 마이그레이션, Blue-Green 배포, 고가용성 아키텍처를 구현합니다.

---

## 🏗️ 아키텍처 개요

### **Seoul 리전 (기존 모놀리식 서비스)**
```
┌─────────────────────────────────────────────┐
│          Seoul VPC (10.1.0.0/16)             │
├─────────────────────────────────────────────┤
│  Public Subnet 1,2 (10.1.1.0/24, 10.1.2.0/24)
│  ├─ ALB (Application Load Balancer)
│  └─ NAT Instance (Bastion Host 겸용)
│
│  Private Subnet 3,4 (10.1.3.0/24, 10.1.4.0/24)
│  └─ Web Instances (Auto Scaling Group: min 2, max 4)
│      ├─ Apache HTTP Server
│      ├─ PHP
│      ├─ MySQL Client
│      └─ Static Files (HTML)
│
│  RDS MySQL (Managed)
│  └─ Database for Seoul service
└─────────────────────────────────────────────┘
         ↓ (VPC Peering)
       DMS ← 데이터 마이그레이션
         ↓
```

### **Singapore 리전 (마이크로서비스)**
```
┌─────────────────────────────────────────────┐
│       Singapore VPC (10.2.0.0/16)            │
├─────────────────────────────────────────────┤
│  EKS Cluster
│  ├─ Worker Nodes (t3.medium × 2)
│  ├─ Pods (Containerized Services)
│  └─ AWS Load Balancer Controller
│
│  RDS MySQL (Managed)
│  └─ Database for Singapore service
│      (Seoul에서 DMS로 마이그레이션된 데이터)
└─────────────────────────────────────────────┘
```

### **Route53 Blue-Green 배포**
```
도메인: saintlee.life
├─ Weighted Routing Policy
│  ├─ Seoul ALB (가중치: X%)  → Record 1
│  └─ Singapore EKS LB (가중치: Y%)  → Record 2
└─ 트래픽 분산 및 자동 Failover
```

---

## 📂 프로젝트 구조

```
cighthouse/
├── p1-infra/
│   ├── Infra-Seoul.yaml              # Seoul 리전 인프라 (VPC, EC2, ALB, ASG)
│   ├── infra-Singapor.yaml           # Singapore 리전 인프라 (VPC, RDS, NAT Gateway)
│   └── infra-Singapor-eks.sh         # Singapore EKS 클러스터 자동 배포
├── p2-service/
│   ├── index.html                    # 메인 페이지
│   ├── login.html, login.php         # 로그인 페이지
│   ├── signup.html, signup.php       # 회원가입 페이지
│   └── logout.php                    # 로그아웃 처리
├── ignore-presentation/              # 프로젝트 문서 (PDF, PPTX, 이미지)
├── ignore-keypair/                   # SSH 키페어 (Git 무시)
├── ignore-infra/                     # 추가 인프라 설정 (Git 무시)
└── README.md                         # 이 파일
```

---

## 🚀 배포 단계별 가이드

### **1단계: 사전 준비**

#### 필수 도구 설치
```bash
# AWS CLI 설치 (v2)
https://aws.amazon.com/cli/

# eksctl 설치 (EKS 클러스터 관리)
https://eksctl.io/

# kubectl 설치 (Kubernetes CLI)
https://kubernetes.io/docs/tasks/tools/

# AWS IAM 자격증명 설정
aws configure
# 액세스 키, 비밀 액세스 키 입력
```

#### SSH 키페어 생성
```bash
# Seoul 리전용 키페어 생성
aws ec2 create-key-pair \
  --key-name seoul-key \
  --region ap-northeast-2 \
  --query 'KeyMaterial' \
  --output text > seoul-key.pem
chmod 400 seoul-key.pem

# Singapore 리전용 키페어 생성
aws ec2 create-key-pair \
  --key-name singapore-key \
  --region ap-southeast-1 \
  --query 'KeyMaterial' \
  --output text > singapore-key.pem
chmod 400 singapore-key.pem

# (Optional) PuTTY 형식으로 변환 (Windows PuTTY 사용 시)
# PuTTYgen을 사용하여 .pem → .ppk로 변환
```

---

### **2단계: Seoul 리전 배포**

#### 2-1. CloudFormation 스택 생성
```bash
# Seoul 인프라 배포
aws cloudformation create-stack \
  --stack-name seoul-stack \
  --template-body file://p1-infra/Infra-Seoul.yaml \
  --region ap-northeast-2 \
  --parameters \
    ParameterKey=KeyName,ParameterValue=seoul-key

# 스택 생성 완료 대기
aws cloudformation wait stack-create-complete \
  --stack-name seoul-stack \
  --region ap-northeast-2

# 생성된 리소스 확인
aws cloudformation describe-stack-resources \
  --stack-name seoul-stack \
  --region ap-northeast-2
```

#### 2-2. 배포된 리소스 확인
```bash
# ALB DNS 이름 조회
aws elbv2 describe-load-balancers \
  --region ap-northeast-2 \
  --query 'LoadBalancers[0].DNSName' \
  --output text

# Auto Scaling Group 인스턴스 확인
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names seoul-web-asg \
  --region ap-northeast-2
```

#### 2-3. NAT Instance (Bastion Host) 접속
```bash
# NAT Instance의 공개 IP 조회
NAT_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=seoul-nat-instance" \
  --region ap-northeast-2 \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

# SSH 접속 (Linux/Mac)
ssh -i seoul-key.pem ec2-user@$NAT_IP

# PuTTY 접속 (Windows)
# 1. PuTTY 열기
# 2. Host name: $NAT_IP
# 3. Connection → SSH → Auth → Private key file: seoul-key.ppk
# 4. Open
```

#### 2-4. Private 인스턴스(Web) 접속 (NAT 경유)
```bash
# NAT에서 Private 인스턴스로 접속
# Private 인스턴스의 프라이빗 IP 조회
PRIVATE_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=seoul-web-asg" \
  --region ap-northeast-2 \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text)

# NAT 인스턴스에 접속한 상태에서
ssh -i seoul-key.pem ec2-user@$PRIVATE_IP
```

---

### **3단계: Singapore 리전 배포**

#### 3-1. Singapore 인프라 배포 (CloudFormation)
```bash
# Singapore 인프라 배포 (VPC, Subnets, RDS, NAT Gateway)
aws cloudformation create-stack \
  --stack-name singapore-stack \
  --template-body file://p1-infra/infra-Singapor.yaml \
  --region ap-southeast-1 \
  --parameters \
    ParameterKey=ProjectName,ParameterValue=sungju

# 스택 생성 완료 대기
aws cloudformation wait stack-create-complete \
  --stack-name singapore-stack \
  --region ap-southeast-1

# CloudFormation Export 값 확인
aws cloudformation list-exports \
  --region ap-southeast-1 \
  --query "Exports[*].[Name,Value]" \
  --output table
```

#### 3-2. EKS 클러스터 자동 배포
```bash
# 1. 필요한 도구 설치 확인
eksctl version
kubectl version --client

# 2. EKS 배포 스크립트 실행
# 주의: 사전에 eksctl, kubectl 설치 필수
bash p1-infra/infra-Singapor-eks.sh

# 스크립트 내부 작동:
# - CloudFormation Export 값으로 VPC/Subnet ID 조회
# - eksctl을 사용하여 EKS 클러스터 생성
# - 클러스터 설정: Kubernetes 1.27, t3.medium × 2 worker nodes
# - AWS Load Balancer Controller 자동 추가
```

#### 3-3. EKS 클러스터 접속 확인
```bash
# kubeconfig 업데이트
aws eks update-kubeconfig \
  --name my-cluster \
  --region ap-southeast-1

# 클러스터 상태 확인
kubectl cluster-info
kubectl get nodes
kubectl get pods --all-namespaces
```

---

### **4단계: VPC 피어링 설정**

#### 4-1. VPC 피어링 요청 (AWS CLI)
```bash
# Seoul VPC ID 조회
SEOUL_VPC=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=seoul-vpc" \
  --region ap-northeast-2 \
  --query 'Vpcs[0].VpcId' \
  --output text)

# Singapore VPC ID 조회
SG_VPC=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=sungju-vpc" \
  --region ap-southeast-1 \
  --query 'Vpcs[0].VpcId' \
  --output text)

# Seoul에서 Singapore로 피어링 요청
PEERING_ID=$(aws ec2 create-vpc-peering-connection \
  --vpc-id $SEOUL_VPC \
  --peer-vpc-id $SG_VPC \
  --peer-region ap-southeast-1 \
  --region ap-northeast-2 \
  --query 'VpcPeeringConnection.VpcPeeringConnectionId' \
  --output text)

echo "Peering Connection ID: $PEERING_ID"
```

#### 4-2. 피어링 연결 수락 (Singapore 리전)
```bash
# 피어링 연결 수락
aws ec2 accept-vpc-peering-connection \
  --vpc-peering-connection-id $PEERING_ID \
  --region ap-southeast-1
```

#### 4-3. 라우팅 테이블 수정

**Seoul 리전:**
```bash
# Seoul Private Route Table에 Singapore VPC 대역 추가
SEOUL_PRI_RT=$(aws ec2 describe-route-tables \
  --filters "Name=tag:Name,Values=seoul-pri-rt34" \
  --region ap-northeast-2 \
  --query 'RouteTables[0].RouteTableId' \
  --output text)

aws ec2 create-route \
  --route-table-id $SEOUL_PRI_RT \
  --destination-cidr-block 10.2.0.0/16 \
  --vpc-peering-connection-id $PEERING_ID \
  --region ap-northeast-2
```

**Singapore 리전:**
```bash
# Singapore Private Route Table에 Seoul VPC 대역 추가
SG_PRI_RT=$(aws ec2 describe-route-tables \
  --filters "Name=tag:Name,Values=sungju-pri-rt34" \
  --region ap-southeast-1 \
  --query 'RouteTables[0].RouteTableId' \
  --output text)

aws ec2 create-route \
  --route-table-id $SG_PRI_RT \
  --destination-cidr-block 10.1.0.0/16 \
  --vpc-peering-connection-id $PEERING_ID \
  --region ap-southeast-1
```

#### 4-4. 보안 그룹 수정 (선택사항)
```bash
# 양쪽 리전의 보안 그룹에서 상호 접근 허용 필요시
# 예: RDS, 애플리케이션 서버 간 통신

# Seoul RDS SG → Singapore 접근 허용
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxx \
  --protocol tcp \
  --port 3306 \
  --cidr 10.2.0.0/16 \
  --region ap-northeast-2
```

---

### **5단계: 데이터베이스 마이그레이션 (DMS)**

#### 5-1. DMS Replication Instance 생성
```bash
# DMS Replication Instance 생성
aws dms create-replication-instance \
  --replication-instance-identifier seoul-to-sg-replication \
  --replication-instance-class dms.t3.small \
  --allocated-storage 20 \
  --engine-version 3.4.6 \
  --region ap-northeast-2
```

#### 5-2. 소스 DB 엔드포인트 (Seoul RDS)
```bash
# Seoul RDS 엔드포인트 조회
SEOUL_RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier mydb \
  --region ap-northeast-2 \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

# DMS 소스 엔드포인트 생성
aws dms create-endpoint \
  --endpoint-identifier seoul-rds-source \
  --endpoint-type source \
  --engine-name mysql \
  --server-name $SEOUL_RDS_ENDPOINT \
  --port 3306 \
  --username admin \
  --password admin123 \
  --database-name mydb \
  --region ap-northeast-2
```

#### 5-3. 대상 DB 엔드포인트 (Singapore RDS)
```bash
# Singapore RDS 엔드포인트 조회
SG_RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier mydb \
  --region ap-southeast-1 \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

# DMS 대상 엔드포인트 생성
aws dms create-endpoint \
  --endpoint-identifier sg-rds-target \
  --endpoint-type target \
  --engine-name mysql \
  --server-name $SG_RDS_ENDPOINT \
  --port 3306 \
  --username admin \
  --password admin123 \
  --database-name mydb \
  --region ap-northeast-2
```

#### 5-4. 마이그레이션 작업 (Task) 생성
```bash
# DMS 마이그레이션 작업 생성
aws dms create-replication-task \
  --replication-task-identifier seoul-to-sg-migration \
  --source-endpoint-arn arn:aws:dms:ap-northeast-2:ACCOUNT_ID:endpoint/seoul-rds-source \
  --target-endpoint-arn arn:aws:dms:ap-northeast-2:ACCOUNT_ID:endpoint/sg-rds-target \
  --replication-instance-arn arn:aws:dms:ap-northeast-2:ACCOUNT_ID:rep/seoul-to-sg-replication \
  --migration-type cdc \
  --table-mappings '{"rules":[{"rule-type":"selection","rule-id":"1","rule-name":"include-all-tables","object-locator":{"schema-name":"%","table-name":"%"},"rule-action":"include"}]}' \
  --region ap-northeast-2

# 마이그레이션 작업 시작
aws dms start-replication-task \
  --replication-task-arn arn:aws:dms:ap-northeast-2:ACCOUNT_ID:task/seoul-to-sg-migration \
  --start-replication-task-type start-replication \
  --region ap-northeast-2
```

#### 5-5. 마이그레이션 진행 상황 확인
```bash
# 마이그레이션 작업 상태 확인
aws dms describe-replication-tasks \
  --filters "Name=replication-task-id,Values=seoul-to-sg-migration" \
  --region ap-northeast-2 \
  --query 'ReplicationTasks[0].[Status,ReplicationTaskStats]'
```

---

### **6단계: Route53 Blue-Green 배포 설정**

#### 6-1. Route53 호스팅 영역 확인
```bash
# 호스팅 영역 조회 (saintlee.life)
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --query "HostedZones[?Name=='saintlee.life.'].Id" \
  --output text | cut -d'/' -f3)

echo "Hosted Zone ID: $HOSTED_ZONE_ID"
```

#### 6-2. Seoul ALB 대상 레코드 생성
```bash
# Seoul ALB DNS 이름 조회
SEOUL_ALB=$(aws elbv2 describe-load-balancers \
  --region ap-northeast-2 \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

# Seoul 가중치 기반 레코드 생성
cat > seoul-record.json <<EOF
{
  "Action": "CREATE",
  "ResourceRecordSet": {
    "Name": "saintlee.life",
    "Type": "A",
    "SetIdentifier": "Seoul-ALB",
    "Weight": 50,
    "AliasTarget": {
      "HostedZoneId": "Z1LMS91P8CMLE5",
      "DNSName": "$SEOUL_ALB",
      "EvaluateTargetHealth": true
    }
  }
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch file://seoul-record.json
```

#### 6-3. Singapore EKS LB 대상 레코드 생성
```bash
# Singapore EKS Load Balancer DNS 조회
SG_LB=$(kubectl get service -n kube-system \
  -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].hostname}')

# Singapore 가중치 기반 레코드 생성
cat > sg-record.json <<EOF
{
  "Action": "CREATE",
  "ResourceRecordSet": {
    "Name": "saintlee.life",
    "Type": "A",
    "SetIdentifier": "Singapore-EKS",
    "Weight": 50,
    "AliasTarget": {
      "HostedZoneId": "Z1LMS91P8CMLE5",
      "DNSName": "$SG_LB",
      "EvaluateTargetHealth": true
    }
  }
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch file://sg-record.json
```

#### 6-4. Blue-Green 배포 검증
```bash
# DNS 가중치 기반 라우팅 확인
nslookup saintlee.life

# 여러 번 조회하면 Seoul ALB와 Singapore EKS 모두 응답
# 가중치 50:50이므로 약 50%씩 분산
```

---

## 🔐 보안 주의사항

### **1. SSH 키페어 관리**
- ⚠️ **프라이빗 키는 절대 Git에 커밋하지 마세요**
- `.gitignore`에 `*.pem`, `*.ppk` 추가됨
- 키페어는 안전한 위치에 별도 보관

### **2. RDS 비밀번호**
- ⚠️ 현재 테스트용으로 평문 비밀번호 사용 중
- **운영 환경에서는 AWS Secrets Manager 사용 권장**

```bash
# AWS Secrets Manager 사용 예시
aws secretsmanager create-secret \
  --name rds-credentials \
  --secret-string '{"username":"admin","password":"your-secure-password"}'
```

### **3. NAT Instance 보안 그룹**
- 현재: SSH 포트(22) 모든 IP에서 허용 (Bastion 역할)
- 프로덕션: 특정 IP 범위로 제한 권장

```bash
# 특정 IP만 허용하도록 수정
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxx \
  --protocol tcp \
  --port 22 \
  --cidr YOUR_IP/32 \
  --region ap-northeast-2
```

### **4. PublicKeyMaterial**
- CloudFormation 템플릿의 `PublicKeyMaterial`은 더미값
- 실제 배포 시 실제 공개키로 교체 필수

### **5. 데이터 보호**
- DMS 마이그레이션 중 암호화 전송 권장
- RDS 암호화 활성화 (기본값: 비활성화)

```bash
# RDS 암호화 활성화
aws rds modify-db-instance \
  --db-instance-identifier mydb \
  --storage-encrypted \
  --apply-immediately \
  --region ap-northeast-2
```

---

## 📊 모니터링 및 로깅

### **CloudWatch 로그 확인**
```bash
# EKS 클러스터 로그 조회
aws eks describe-cluster \
  --name my-cluster \
  --region ap-southeast-1 \
  --query 'cluster.logging.clusterLogging'

# EKS 로그 그룹 확인
aws logs describe-log-groups \
  --log-group-name-prefix /aws/eks/my-cluster \
  --region ap-southeast-1
```

### **ALB 헬스체크**
```bash
# Target Group 헬스 상태 확인
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:ap-northeast-2:ACCOUNT_ID:targetgroup/seoul-web-tg/xxxxx \
  --region ap-northeast-2
```

---

## 🧹 리소스 정리 (삭제)

### **주의: 완전 삭제 (복구 불가)**

```bash
# 1. EKS 클러스터 삭제 (Singapore)
eksctl delete cluster --name my-cluster --region ap-southeast-1

# 2. DMS 작업 삭제
aws dms delete-replication-task \
  --replication-task-arn arn:aws:dms:ap-northeast-2:ACCOUNT_ID:task/seoul-to-sg-migration \
  --region ap-northeast-2

# 3. VPC 피어링 삭제
aws ec2 delete-vpc-peering-connection \
  --vpc-peering-connection-id pcx-xxxxxxxx \
  --region ap-northeast-2

# 4. CloudFormation 스택 삭제
aws cloudformation delete-stack \
  --stack-name seoul-stack \
  --region ap-northeast-2

aws cloudformation delete-stack \
  --stack-name singapore-stack \
  --region ap-southeast-1
```

---

## 🔧 문제 해결 (Troubleshooting)

### **EKS 클러스터 생성 실패**
```bash
# 1. eksctl 버전 확인
eksctl version

# 2. IAM 권한 확인
aws iam list-attached-user-policies --user-name YOUR_USER

# 3. VPC/Subnet 가용성 확인
aws ec2 describe-subnets --subnet-ids subnet-xxxxx
```

### **DMS 마이그레이션 실패**
```bash
# 1. 엔드포인트 연결 테스트
aws dms test-connection \
  --replication-instance-arn arn:aws:dms:region:account:rep/replication-instance \
  --endpoint-arn arn:aws:dms:region:account:endpoint/endpoint-id

# 2. 마이그레이션 작업 로그
aws dms describe-replication-tasks \
  --filters "Name=replication-task-id,Values=seoul-to-sg-migration" \
  --query 'ReplicationTasks[0].ReplicationTaskStats'
```

### **Route53 DNS 해석 안 됨**
```bash
# 1. 레코드셋 확인
aws route53 list-resource-record-sets \
  --hosted-zone-id ZONE_ID \
  --query "ResourceRecordSets[?Name=='saintlee.life.']"

# 2. DNS 프로파게이션 확인 (온라인 도구)
# nslookup, dig, host 명령어 사용
```

---

## 📚 참고 자료

- [AWS CloudFormation 문서](https://docs.aws.amazon.com/cloudformation/)
- [AWS EKS 가이드](https://docs.aws.amazon.com/eks/)
- [AWS DMS 설명서](https://docs.aws.amazon.com/dms/)
- [AWS Route53 가이드](https://docs.aws.amazon.com/route53/)
- [eksctl 공식 문서](https://eksctl.io/)

---

## 📝 라이선스

MIT License

---

## 👤 프로젝트 정보

**목표**: AWS 다중 리전 아키텍처 및 마이크로서비스 마이그레이션 학습  
**클라우드**: AWS (Seoul, Singapore)  
**기술 스택**: 
- 인프라: CloudFormation, EKS, RDS, ALB, Route53
- 서비스: PHP, Apache, MySQL
- 자동화: AWS CLI, eksctl, Bash

---

**작성 시작일**: 2024년  
**최종 업데이트**: 2026년 11월 22일
