# The "terraform" ruleset ships inside tflint, so no plugin download is needed.
# Upgrade path: add the AWS ruleset plugin to catch AWS-specific mistakes.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}