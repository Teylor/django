#!/bin/bash
echo ECS_CLUSTER=${cluster_name} >> /etc/ecs/ecs.config
yum update -y
amazon-linux-extras install -y docker
service docker start
usermod -a -G docker ec2-user
docker --version
