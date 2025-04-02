# prjctr-26-autoscaling-groups

### Setup

```shell
docker build -t test-dev:latest .
docker tag test-dev:latest 523717802721.dkr.ecr.eu-central-1.amazonaws.com/test-dev:latest
aws ecr get-login-password --region eu-central-1 | docker login --username AWS --password-stdin 523717802721.dkr.ecr.eu-central-1.amazonaws.com/test-dev
docker push 523717802721.dkr.ecr.eu-central-1.amazonaws.com/test-dev:latest
cd terraform
terraform init
terraform apply
```

### Check auto-scaling

```shell
siege -c 50 -t 5M http://test-dev-alb-1632961615.eu-central-1.elb.amazonaws.com/
sleep 10
siege -c 100 -t 5M http://test-dev-alb-1632961615.eu-central-1.elb.amazonaws.com/
sleep 10
siege -c 200 -t 5M http://test-dev-alb-1632961615.eu-central-1.elb.amazonaws.com/
```

### Results

Initial setup:

![1.png](images/1.png)

Initial instances:

![3.png](images/3.png) 
![2.png](images/2.png)

Scaled setup:

![4.png](images/4.png)

Auto-scaling logs:

![5.png](images/5.png)

Scaling policies list:

![6.png](images/6.png)

