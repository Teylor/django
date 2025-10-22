variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "image_uri" {
  type        = string
  description = "Docker image uri to deploy (ECR image with tag)"
  default     = ""
}
