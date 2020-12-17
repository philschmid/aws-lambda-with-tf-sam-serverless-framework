# Deploy docker in multiple ways

# Initial steps "Create Docker image and upload it to ecr"

1. create docker images

```bash
docker build -t docker-lambda .
```

2. test it locally

```bash
docker run -d -p 8080:8080 docker-lambda
```

```bash
curl -XPOST "http://localhost:8080/2015-03-31/functions/function/invocations" -d '{}'
```

3. create ecr repository

```bash
aws ecr create-repository --repository-name docker-lambda --profile serverless-bert
```

4. login into ecr

```bash
aws_region=eu-central-1
aws_account_id=891511646143
aws_profile=serverless-bert

aws ecr get-login-password \
    --region $aws_region \
    --profile $aws_profile \
| docker login \
    --username AWS \
    --password-stdin $aws_account_id.dkr.ecr.$aws_region.amazonaws.com
```

5. tag docker image

```bash
docker tag bert-lambda $aws_account_id.dkr.ecr.$aws_region.amazonaws.com/bert-lambda
```

6. push docker image

```bash
docker push $aws_account_id.dkr.ecr.$aws_region.amazonaws.com/bert-lambda
```

# SAM ()

1. add ecr url to `template.yaml`

For an ECR image, the URL should look like this `{AccountID}.dkr.ecr.{region}.amazonaws.com/{repository-name}:latest`

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Description: serverless-aws-lambda-custom-docker

# More info about Globals: https://github.com/awslabs/serverless-application-model/blob/master/docs/globals.rst
Globals:
  Function:
    Timeout: 3

Resources:
  MyCustomDocker:
    Type: AWS::Serverless::Function # More info about Function Resource: https://github.com/awslabs/serverless-application-model/blob/master/versions/2016-10-31.md#awsserverlessfunction
    Properties:
      FunctionName: MyCustomDocker
      ImageUri: 891511646143.dkr.ecr.eu-central-1.amazonaws.com/docker-lambda:latest
      PackageType: Image
      Events:
        HelloWorld:
          Type: Api # More info about API Event Source: https://github.com/awslabs/serverless-application-model/blob/master/versions/2016-10-31.md#api
          Properties:
            Path: /hello
            Method: get

Outputs:
  # ServerlessRestApi is an implicit API created out of Events key under Serverless::Function
  # Find out more about other implicit resources you can reference within SAM
  # https://github.com/awslabs/serverless-application-model/blob/master/docs/internals/generated_resources.rst#api
  MyCustomDockerApi:
    Description: 'API Gateway endpoint URL for Prod stage for Hello World function'
    Value: !Sub 'https://${ServerlessRestApi}.execute-api.${AWS::Region}.amazonaws.com/Prod/hello/'
```

2. deploy your lambda function

```bash
sam deploy --guided
```

# Serverless Framework

1. add ecr url to `serverless.yaml`

For an ECR image, the URL should look like this {AccountID}.dkr.ecr.{region}.amazonaws.com/{repository-name}@{digest}

```yaml
service: serverless-bert-lambda-docker

provider:
  name: aws # provider
  region: eu-central-1 # aws region
  memorySize: 5120 # optional, in MB, default is 1024
  timeout: 30 # optional, in seconds, default is 6

functions:
  questionanswering:
    image: #ecr url
    events:
      - http:
          path: qa # http path
          method: post # http method
```

2. deploy your lambda function

```Bash
serverless deploy --aws-profile serverless-bert
```

# Terraform

Difference between terraform and SAM or Serveless, we have to create ressource for an API Gateway, IAM Permission ... too.

```yaml
# provider
provider "aws" {
  region                  = "eu-central-1"
  shared_credentials_file = "~/.aws/credentials"
  profile                 = "serverless-bert"
  version                 = "~> 3.19.0"

  # Make it faster by skipping something
  skip_get_ec2_platforms      = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_credentials_validation = true
  skip_requesting_account_id  = true
}



resource "aws_iam_role" "iam_for_lambda" {
  name = "docker_lambda_iam"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_lambda_function" "lambda" {
  # depends_on       = [module.ecr_docker_build]
  # image_uri        = aws_ecr_repository.test_service.repository_url
  function_name    = "docker-lambda"
  role             = aws_iam_role.iam_for_lambda.arn
  image_uri        = "891511646143.dkr.ecr.eu-central-1.amazonaws.com/docker-lambda:latest"
  package_type     = "Image"
  memory_size      = 128
  timeout          = 30
}



# API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name = "docker-lambda"
}

resource "aws_api_gateway_resource" "resource" {
  path_part   = "joke"
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.api.id
}

resource "aws_api_gateway_method" "method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "integration" {
  depends_on              = [aws_api_gateway_method.method,aws_lambda_function.lambda]
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.resource.id
  http_method             = aws_api_gateway_method.method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda.invoke_arn
}


resource "aws_lambda_permission" "apigw_lambda" {
  depends_on    = [aws_lambda_function.lambda,aws_api_gateway_rest_api.api]
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn = "arn:aws:execute-api:eu-central-1:891511646143:${aws_api_gateway_rest_api.api.id}/*/${aws_api_gateway_method.method.http_method}${aws_api_gateway_resource.resource.path}"
}

resource "aws_api_gateway_deployment" "base_deployment" {
  depends_on    = [aws_lambda_permission.apigw_lambda]
  rest_api_id       = aws_api_gateway_rest_api.api.id
  stage_name        = "test"
  stage_description = "Deployed from infrastruktur"
  description       = "Deployed from infrastruktur"
}

```
