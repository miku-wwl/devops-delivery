# E11 (chapter 12): the governance of the configuration repository as code.
terraform {
  required_version = "~> 1.13.0"
  required_providers {
    gitlab = {
      source  = "gitlabhq/gitlab"
      version = "19.5.0"
    }
  }

  # The state in GitLab's OpenTofu state store (project root/platform-iac): GitLab refuses a second
  # lock with 409. The wrapper sets the addresses and the credentials (TF_HTTP_*).
  # First home, until E11's I2: Garage (bucket tofu-state) with use_lockfile - Garage v2.5.0 ignores
  # If-None-Match, so the "lock" excluded nobody (evidence/e11/i2-state.log).
  backend "http" {}

  # The state holds every attribute OpenTofu read - here GitLab settings, elsewhere passwords and
  # keys. Encrypted on the client before it leaves the machine; the passphrase is not in Git.
  encryption {
    key_provider "pbkdf2" "lab" {
      passphrase = var.state_passphrase
    }
    method "aes_gcm" "lab" {
      keys = key_provider.pbkdf2.lab
    }
    state {
      method   = method.aes_gcm.lab
      enforced = true
    }
    plan {
      method   = method.aes_gcm.lab
      enforced = true
    }
  }
}
