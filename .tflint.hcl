plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Disabled for the customer workspaces: each customer directory intentionally
# declares only the backend and the module call, and inherits version
# constraints from modules/protect-baseline/main.tf.
rule "terraform_required_version" {
  enabled = false
}

rule "terraform_required_providers" {
  enabled = false
}
