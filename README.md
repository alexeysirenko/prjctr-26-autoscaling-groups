# prjctr-26-autoscaling-groups

```
docker build -t test-dev:latest .
docker tag test-dev:latest 523717802721.dkr.ecr.eu-central-1.amazonaws.com/test-dev:latest
aws ecr get-login-password --region eu-central-1 | docker login --username AWS --password-stdin 523717802721.dkr.ecr.eu-central-1.amazonaws.com/test-dev
docker push 523717802721.dkr.ecr.eu-central-1.amazonaws.com/test-dev:latest
cd terraform
terraform init
terraform apply
```