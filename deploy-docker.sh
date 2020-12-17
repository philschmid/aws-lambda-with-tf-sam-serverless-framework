#!/bin/bash

docker_name=docker-lambda
aws_region=eu-central-1
aws_account_id=891511646143
aws_profile=serverless-bert


docker build -t $docker_name .

aws ecr create-repository --repository-name $docker_name --profile $aws_profile > /dev/null

aws ecr get-login-password \
    --region $aws_region \
    --profile $aws_profile \
| docker login \
    --username AWS \
    --password-stdin $aws_account_id.dkr.ecr.$aws_region.amazonaws.com


docker tag $docker_name $aws_account_id.dkr.ecr.$aws_region.amazonaws.com/$docker_name

docker push $aws_account_id.dkr.ecr.$aws_region.amazonaws.com/$docker_name