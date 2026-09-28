# External Secrets logs in to Vault with its service-account token. Vault's
# kubernetes auth (what yojimbo uses) validates that by calling the cluster's
# TokenReview API, and Vault on the NAS cannot reach this cluster behind the
# laptop's NAT. JWT auth checks the token's signature against the cluster's
# service-account public key instead, so Vault never calls back.
#
# The key is regenerated with every rebuild, so it lives here and is
# rewritten on apply -- no hand steps after a rebuild.
resource "vault_jwt_auth_backend" "bahamut" {
  path                   = "jwt-bahamut"
  type                   = "jwt"
  description            = "bahamut service-account tokens (External Secrets)"
  jwt_validation_pubkeys = [trimspace(module.talos.service_account_public_key_pem)]
  bound_issuer           = module.talos.service_account_issuer
}

resource "vault_jwt_auth_backend_role" "external_secrets" {
  backend         = vault_jwt_auth_backend.bahamut.path
  role_name       = "external-secrets"
  role_type       = "jwt"
  user_claim      = "sub"
  bound_audiences = ["vault"]
  bound_subject   = "system:serviceaccount:external-secrets:external-secrets"
  token_policies  = ["eso-read"]
  token_ttl       = 3600
}
