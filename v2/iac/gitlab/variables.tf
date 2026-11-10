variable "gitlab_token" {
  description = "API token (from the wrapper's environment, never in a file of the repository)"
  type        = string
  sensitive   = true
}

variable "state_passphrase" {
  description = "Passphrase of the state encryption (~/.lab-secrets/v2/tofu/passphrase)"
  type        = string
  sensitive   = true
}

variable "s3_endpoint" {
  description = "Garage's S3 endpoint"
  type        = string
}
