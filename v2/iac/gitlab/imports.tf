# Adoption (E11, I1): the objects exist; OpenTofu takes them over instead of creating them.
# Project 3 = root/platform-gitops, user 5 = alice.
import {
  to = gitlab_project.gitops
  id = "3"
}

import {
  to = gitlab_branch_protection.main
  id = "3:main"
}

import {
  to = gitlab_project_membership.alice
  id = "3:5"
}
