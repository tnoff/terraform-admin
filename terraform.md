<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_github"></a> [github](#requirement\_github) | ~> 6.0 |
| <a name="requirement_gitlab"></a> [gitlab](#requirement\_gitlab) | ~> 19.0 |
| <a name="requirement_local"></a> [local](#requirement\_local) | ~> 2.0 |
| <a name="requirement_oci"></a> [oci](#requirement\_oci) | ~> 9.0 |
| <a name="requirement_time"></a> [time](#requirement\_time) | ~> 0.14 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_github"></a> [github](#provider\_github) | ~> 6.0 |
| <a name="provider_gitlab"></a> [gitlab](#provider\_gitlab) | ~> 19.0 |
| <a name="provider_local"></a> [local](#provider\_local) | ~> 2.0 |
| <a name="provider_oci"></a> [oci](#provider\_oci) | ~> 9.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |
| <a name="provider_time"></a> [time](#provider\_time) | ~> 0.14 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | ~> 4.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_terraform_gitlab"></a> [terraform\_gitlab](#module\_terraform\_gitlab) | git::https://github.com/tnoff/terraform-modules.git//gitlab/repo | 4cbebdd95c017db8b3a55e461adac21733000ecd |
| <a name="module_terraform_repo"></a> [terraform\_repo](#module\_terraform\_repo) | git::https://github.com/tnoff/terraform-modules.git//github/repo | 32e1dd5de326da36423006bfcffeb47a097e9d8b |
| <a name="module_terraform_state_buckets"></a> [terraform\_state\_buckets](#module\_terraform\_state\_buckets) | git::https://github.com/tnoff/terraform-modules.git//oci/object-storage-bucket | 4cbebdd95c017db8b3a55e461adac21733000ecd |
| <a name="module_terraform_state_vault"></a> [terraform\_state\_vault](#module\_terraform\_state\_vault) | git::https://github.com/tnoff/terraform-modules.git//oci/secret-vault | 4cbebdd95c017db8b3a55e461adac21733000ecd |

## Resources

| Name | Type |
|------|------|
| [github_actions_secret.terraform](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_secret) | resource |
| [github_actions_variable.terraform](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_variable) | resource |
| [local_sensitive_file.envrc](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/sensitive_file) | resource |
| [local_sensitive_file.mcp_readonly_oci_config](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/sensitive_file) | resource |
| [local_sensitive_file.mcp_readonly_private_key](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/sensitive_file) | resource |
| [local_sensitive_file.terraform_admin_private_key](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/sensitive_file) | resource |
| [oci_identity_api_key.mcp_readonly](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_api_key) | resource |
| [oci_identity_api_key.terraform_admin](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_api_key) | resource |
| [oci_identity_group.mcp_readonly](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_group) | resource |
| [oci_identity_group.terraform_admin](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_group) | resource |
| [oci_identity_policy.admin_kms_object_storage](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_policy) | resource |
| [oci_identity_policy.mcp_readonly](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_policy) | resource |
| [oci_identity_policy.terraform_admin](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_policy) | resource |
| [oci_identity_user.mcp_readonly](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_user) | resource |
| [oci_identity_user.terraform_admin](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_user) | resource |
| [oci_identity_user_group_membership.mcp_readonly](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_user_group_membership) | resource |
| [oci_identity_user_group_membership.terraform_admin](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_user_group_membership) | resource |
| [terraform_data.backstage_app_private_key_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.ci_app_private_key_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.cloudflare_api_token_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.discord_token_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.flux_app_private_key_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.gitlab_api_key_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.gitlab_bot_api_key_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.secret_age_tracker_gitlab_token_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.ssh_public_key_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [time_static.backstage_app_private_key_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.ci_app_private_key_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.cloudflare_api_token_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.discord_token_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.flux_app_private_key_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.gitlab_api_key_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.gitlab_bot_api_key_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.secret_age_tracker_gitlab_token_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.ssh_public_key_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [tls_private_key.mcp_readonly](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [tls_private_key.terraform_admin](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [gitlab_group.personal](https://registry.terraform.io/providers/gitlabhq/gitlab/latest/docs/data-sources/group) | data source |
| [oci_identity_tenancy.current](https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/identity_tenancy) | data source |
| [oci_objectstorage_namespace.this](https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/objectstorage_namespace) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alarm_email"></a> [alarm\_email](#input\_alarm\_email) | Email address for OCI alarm notifications | `string` | n/a | yes |
| <a name="input_backstage_app_client_id"></a> [backstage\_app\_client\_id](#input\_backstage\_app\_client\_id) | Client ID of the tnoff-backstage GitHub App (Iv23li... form). Not a secret, and shown on the App settings page without generating anything. Backstage requires the key to be PRESENT (readGithubIntegrationConfig uses getString, not getOptionalString) but never uses it: SingleInstanceGithubCredentialsProvider builds its auth config from appId + privateKey alone. Supplied so config parsing succeeds. | `string` | n/a | yes |
| <a name="input_backstage_app_id"></a> [backstage\_app\_id](#input\_backstage\_app\_id) | App ID of the tnoff-backstage GitHub App. Not a secret. From https://github.com/settings/apps/tnoff-backstage. | `number` | n/a | yes |
| <a name="input_backstage_app_private_key_b64"></a> [backstage\_app\_private\_key\_b64](#input\_backstage\_app\_private\_key\_b64) | Base64 of the tnoff-backstage App private key PEM, single line. Base64 for the same reason ci\_app\_private\_key\_b64 is: a multi-line PEM does not survive a shell round-trip cleanly. Produce with `base64 -w0 tnoff-backstage.*.private-key.pem`. Set in admin/terraform.tfvars (gitignored); apps/ base64decodes it into the Secret the pod mounts. | `string` | n/a | yes |
| <a name="input_ci_app_client_id"></a> [ci\_app\_client\_id](#input\_ci\_app\_client\_id) | Client ID of the tnoff-ci GitHub App (Iv23li... form). Distinct from ci\_app\_id: actions/create-github-app-token deprecated its `app-id` input in favour of `client-id`, while the ruleset bypass actor still keys on the numeric App ID. Both are needed. Not a secret. | `string` | n/a | yes |
| <a name="input_ci_app_id"></a> [ci\_app\_id](#input\_ci\_app\_id) | App ID of the tnoff-ci GitHub App. Exported so terraform/infra can name it as a ruleset bypass actor (actor\_type Integration) and mint installation tokens in CI, replacing the human admin PAT that assemble-changelog needs to push to a protected default branch. Not a secret. | `number` | n/a | yes |
| <a name="input_ci_app_private_key_b64"></a> [ci\_app\_private\_key\_b64](#input\_ci\_app\_private\_key\_b64) | Base64 of the tnoff-ci GitHub App private key PEM, single line. Base64 rather than the raw PEM for the same reason OCI\_API\_KEY\_B64 is: GitLab can only mask a single-line value, so a multi-line PEM would have to travel through CI unmasked. Produce with `base64 -w0 tnoff-ci.private-key.pem`; terraform/infra base64decodes it when writing the Actions secret. | `string` | n/a | yes |
| <a name="input_cloudflare_account_id"></a> [cloudflare\_account\_id](#input\_cloudflare\_account\_id) | Cloudflare account identifier (not secret) | `string` | n/a | yes |
| <a name="input_cloudflare_api_token"></a> [cloudflare\_api\_token](#input\_cloudflare\_api\_token) | Cloudflare account API token | `string` | n/a | yes |
| <a name="input_config_file_profile"></a> [config\_file\_profile](#input\_config\_file\_profile) | Profile name in ~/.oci/config file | `string` | `"DEFAULT"` | no |
| <a name="input_discord_token"></a> [discord\_token](#input\_discord\_token) | Discord bot token | `string` | n/a | yes |
| <a name="input_flux_app_id"></a> [flux\_app\_id](#input\_flux\_app\_id) | App ID of the tnoff-flux GitHub App. Not a secret. From https://github.com/settings/apps/tnoff-flux. | `number` | n/a | yes |
| <a name="input_flux_app_installation_id"></a> [flux\_app\_installation\_id](#input\_flux\_app\_installation\_id) | Installation ID of the tnoff-flux App on tnoff/docker-apps -- the trailing number in https://github.com/settings/installations/<id>. Not a secret. Flux accepts githubAppInstallationOwner instead, but the ID has been supported since 2.5 and the owner form is newer, so the ID is the safer pin. | `number` | n/a | yes |
| <a name="input_flux_app_private_key_b64"></a> [flux\_app\_private\_key\_b64](#input\_flux\_app\_private\_key\_b64) | Base64 of the tnoff-flux App private key PEM, single line. Base64 for the same reason ci\_app\_private\_key\_b64 is: a multi-line PEM does not survive a shell round-trip cleanly. Produce with `base64 -w0 tnoff-flux.*.private-key.pem`. Set in admin/terraform.tfvars (gitignored); bootstrap base64decodes it into the Secret. | `string` | n/a | yes |
| <a name="input_gitlab_api_key"></a> [gitlab\_api\_key](#input\_gitlab\_api\_key) | GitLab personal access token for admin user | `string` | n/a | yes |
| <a name="input_gitlab_bot_api_key"></a> [gitlab\_bot\_api\_key](#input\_gitlab\_bot\_api\_key) | GitLab personal access token for bot user | `string` | n/a | yes |
| <a name="input_mcp_readonly_group_name"></a> [mcp\_readonly\_group\_name](#input\_mcp\_readonly\_group\_name) | Name of the tenancy-wide read-only group backing the local OCI MCP server | `string` | `"mcp-readonly-bot"` | no |
| <a name="input_mcp_readonly_private_key_path"></a> [mcp\_readonly\_private\_key\_path](#input\_mcp\_readonly\_private\_key\_path) | Path where the MCP read-only user's API key PEM will be written | `string` | `"generated-output/mcp_readonly_api_key.pem"` | no |
| <a name="input_mcp_readonly_user_name"></a> [mcp\_readonly\_user\_name](#input\_mcp\_readonly\_user\_name) | Name of the tenancy-wide read-only user backing the local OCI MCP server | `string` | `"mcp-readonly-bot"` | no |
| <a name="input_oci_region"></a> [oci\_region](#input\_oci\_region) | OCI region | `string` | `"us-ashburn-1"` | no |
| <a name="input_oci_tenancy_ocid"></a> [oci\_tenancy\_ocid](#input\_oci\_tenancy\_ocid) | OCID of the tenancy (all resources created in root compartment) | `string` | n/a | yes |
| <a name="input_sealed_secrets_tls_crt_b64"></a> [sealed\_secrets\_tls\_crt\_b64](#input\_sealed\_secrets\_tls\_crt\_b64) | Base64 (as stored in the Secret .data) of the sealed-secrets controller key certificate (tls.crt). Source: kubectl -n sealed-secrets get secret sealed-secrets-keyptkzt -o jsonpath='{.data.tls\.crt}' | `string` | n/a | yes |
| <a name="input_sealed_secrets_tls_key_b64"></a> [sealed\_secrets\_tls\_key\_b64](#input\_sealed\_secrets\_tls\_key\_b64) | Base64 (as stored in the Secret .data) of the sealed-secrets controller private key (tls.key). Source: kubectl -n sealed-secrets get secret sealed-secrets-keyptkzt -o jsonpath='{.data.tls\.key}' | `string` | n/a | yes |
| <a name="input_secret_age_tracker_gitlab_token"></a> [secret\_age\_tracker\_gitlab\_token](#input\_secret\_age\_tracker\_gitlab\_token) | GitLab personal access token consumed by the secret-age-tracker CronJob (read\_api scope). Used to blame docker-apps SealedSecret YAMLs and list PAT expiries. Folded into the oke-security-scanner image per docs/projects/secret-age-tracker.md. | `string` | n/a | yes |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | SSH public key for OKE worker nodes | `string` | n/a | yes |
| <a name="input_state_bucket_prefix"></a> [state\_bucket\_prefix](#input\_state\_bucket\_prefix) | Prefix for state bucket names | `string` | `"terraform-state"` | no |
| <a name="input_terraform_admin_group_name"></a> [terraform\_admin\_group\_name](#input\_terraform\_admin\_group\_name) | Name of the Terraform admin group | `string` | `"terraform-administrators"` | no |
| <a name="input_terraform_admin_private_key_path"></a> [terraform\_admin\_private\_key\_path](#input\_terraform\_admin\_private\_key\_path) | Path where the Terraform admin private key will be saved | `string` | `"generated-output/terraform_admin_private_key.pem"` | no |
| <a name="input_terraform_admin_user_name"></a> [terraform\_admin\_user\_name](#input\_terraform\_admin\_user\_name) | Name of the Terraform admin user for infrastructure management | `string` | `"terraform-admin"` | no |
| <a name="input_terraform_app_id"></a> [terraform\_app\_id](#input\_terraform\_app\_id) | App ID of the tnoff-terraform GitHub App. Not a secret. From https://github.com/settings/apps/tnoff-terraform. | `number` | n/a | yes |
| <a name="input_terraform_app_installation_id"></a> [terraform\_app\_installation\_id](#input\_terraform\_app\_installation\_id) | Installation ID of the tnoff-terraform App on this account -- the trailing number in https://github.com/settings/installations/<id>. Not a secret. | `number` | n/a | yes |
| <a name="input_terraform_app_private_key_b64"></a> [terraform\_app\_private\_key\_b64](#input\_terraform\_app\_private\_key\_b64) | Base64 of the tnoff-terraform App private key PEM, single line. Produce with `base64 -w0 tnoff-terraform.*.private-key.pem`. Set in admin/terraform.tfvars (gitignored); terraform/infra base64decodes it for the provider's app\_auth block. | `string` | n/a | yes |
| <a name="input_vault_name"></a> [vault\_name](#input\_vault\_name) | Name prefix for the vault and KMS key | `string` | `"terraform-state"` | no |
| <a name="input_workspaces"></a> [workspaces](#input\_workspaces) | List of workspace names to create state buckets for (admin state stays local) | `list(string)` | <pre>[<br/>  "discord",<br/>  "infra",<br/>  "oci",<br/>  "oci-alarms",<br/>  "bootstrap",<br/>  "apps",<br/>  "dns"<br/>]</pre> | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->