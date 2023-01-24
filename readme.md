# Application Infrastructure as Code

This repository contains the code to provision the application once the application has been pushed into the ECR defined inside the envirnonment code.
The application listens on port `8080` .

## Accessing the application

The application has a DNS name that you may use to access the health data listening on the `/healthcheck` endpoint. To access the application, point your browser to:

```
http://dns-name:8080/healthcheck
```

## Usage

Similar to the environment side, you may provision the application using this repository as the source:

```hcl
module "heath_chcker_app" {
  source       = "../app"
  project_name = "healthchecker"
  image_tag    = "latest"
  vpc_id       = "vpc-xxxxxxx"
  subnet_ids = [
    "subnet-xxxxx",
    "subnet-xxxx",
  ]
  container_count = 1
}
```

The logs are piped to CloudWatch under the log group `project-name-applogs` and certain metrics from the websites being queried are also piped to CloudWatch metrics for monitoring under the `health_stats` namespace.

## Updating

When you update a new image into ECR, you can update the service inside ECS and select `Force New Deployment`. This will update the service and create a new deployment with the newly updated application.