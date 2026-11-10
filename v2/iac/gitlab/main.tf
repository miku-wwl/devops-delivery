provider "gitlab" {
  base_url = "http://localhost:8929/api/v4/"
  token    = var.gitlab_token
}

data "gitlab_user" "alice" {
  username = "alice"
}

# root/platform-gitops: changes reach main only through a merge request whose pipeline succeeded
# (chapter 9). Adopted from platform/gitops/setup.sh, never recreated.
resource "gitlab_project" "gitops" {
  name                                  = "platform-gitops"
  path                                  = "platform-gitops"
  visibility_level                      = "private"
  default_branch                        = "main"
  only_allow_merge_if_pipeline_succeeds = true
  allow_merge_on_skipped_pipeline       = false
  remove_source_branch_after_merge      = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "gitlab_branch_protection" "main" {
  project            = gitlab_project.gitops.id
  branch             = "main"
  push_access_level  = "no one"
  merge_access_level = "maintainer"
  allow_force_push   = false
}

# alice (team shop) opens merge requests; she cannot merge them
resource "gitlab_project_membership" "alice" {
  project      = gitlab_project.gitops.id
  user_id      = data.gitlab_user.alice.id
  access_level = "developer"
}
