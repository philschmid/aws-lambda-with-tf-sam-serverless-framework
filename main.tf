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


