// Google Cloud IAM REST API Client for GaiaOS
// Reference: https://cloud.google.com/iam/docs/reference/rest

use serde::{Deserialize, Serialize};
use reqwest::Client;
use anyhow::{Result, Context};
use std::collections::HashMap;

const IAM_API_BASE: &str = "https://iam.googleapis.com/v1";
const OAUTH2_TOKEN_URL: &str = "https://oauth2.googleapis.com/token";
const OAUTH2_USERINFO_URL: &str = "https://www.googleapis.com/oauth2/v2/userinfo";

/// Google Cloud IAM Client with full API access
pub struct GoogleIAMClient {
    client: Client,
    project_id: String,
    oauth_client_id: String,
    oauth_client_secret: String,
    api_key: Option<String>,
}

// ============================================================================
// OAUTH 2.0 AUTHENTICATION
// ============================================================================

#[derive(Debug, Serialize, Deserialize)]
pub struct OAuthTokenRequest {
    pub code: String,
    pub client_id: String,
    pub client_secret: String,
    pub redirect_uri: String,
    pub grant_type: String, // "authorization_code"
}

#[derive(Debug, Serialize, Deserialize)]
pub struct OAuthTokenResponse {
    pub access_token: String,
    pub expires_in: i64,
    pub refresh_token: Option<String>,
    pub scope: String,
    pub token_type: String,
    pub id_token: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct UserInfo {
    pub id: String,
    pub email: String,
    pub verified_email: bool,
    pub name: Option<String>,
    pub given_name: Option<String>,
    pub family_name: Option<String>,
    pub picture: Option<String>,
    pub locale: Option<String>,
}

// ============================================================================
// SERVICE ACCOUNTS
// https://cloud.google.com/iam/docs/reference/rest/v1/projects.serviceAccounts
// ============================================================================

#[derive(Debug, Serialize, Deserialize)]
pub struct ServiceAccount {
    pub name: String,
    pub project_id: String,
    pub unique_id: String,
    pub email: String,
    pub display_name: Option<String>,
    pub description: Option<String>,
    pub oauth2_client_id: Option<String>,
    pub disabled: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CreateServiceAccountRequest {
    pub account_id: String,
    pub service_account: ServiceAccountMetadata,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ServiceAccountMetadata {
    pub display_name: Option<String>,
    pub description: Option<String>,
}

// ============================================================================
// SERVICE ACCOUNT KEYS
// https://cloud.google.com/iam/docs/reference/rest/v1/projects.serviceAccounts.keys
// ============================================================================

#[derive(Debug, Serialize, Deserialize)]
pub struct ServiceAccountKey {
    pub name: String,
    pub private_key_type: String,
    pub key_algorithm: String,
    pub private_key_data: Option<String>,
    pub public_key_data: Option<String>,
    pub valid_after_time: Option<String>,
    pub valid_before_time: Option<String>,
    pub key_origin: String,
    pub key_type: String,
}

// ============================================================================
// WORKLOAD IDENTITY POOLS
// https://cloud.google.com/iam/docs/reference/rest/v1/projects.locations.workloadIdentityPools
// ============================================================================

#[derive(Debug, Serialize, Deserialize)]
pub struct WorkloadIdentityPool {
    pub name: String,
    pub display_name: Option<String>,
    pub description: Option<String>,
    pub state: String,
    pub disabled: bool,
}

// ============================================================================
// IAM POLICIES
// https://cloud.google.com/iam/docs/reference/rest/v1/projects.serviceAccounts/getIamPolicy
// ============================================================================

#[derive(Debug, Serialize, Deserialize)]
pub struct Policy {
    pub version: i32,
    pub bindings: Vec<Binding>,
    pub etag: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Binding {
    pub role: String,
    pub members: Vec<String>,
    pub condition: Option<Condition>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Condition {
    pub expression: String,
    pub title: Option<String>,
    pub description: Option<String>,
}

// ============================================================================
// ROLES
// https://cloud.google.com/iam/docs/reference/rest/v1/roles
// ============================================================================

#[derive(Debug, Serialize, Deserialize)]
pub struct Role {
    pub name: String,
    pub title: String,
    pub description: String,
    pub included_permissions: Vec<String>,
    pub stage: String,
    pub deleted: bool,
}

// ============================================================================
// IMPLEMENTATION
// ============================================================================

impl GoogleIAMClient {
    pub fn new(
        project_id: String,
        oauth_client_id: String,
        oauth_client_secret: String,
        api_key: Option<String>,
    ) -> Self {
        Self {
            client: Client::new(),
            project_id,
            oauth_client_id,
            oauth_client_secret,
            api_key,
        }
    }

    // ========================================================================
    // OAUTH 2.0 METHODS
    // ========================================================================

    /// Exchange authorization code for access token
    pub async fn exchange_code_for_token(
        &self,
        code: &str,
        redirect_uri: &str,
    ) -> Result<OAuthTokenResponse> {
        let request = OAuthTokenRequest {
            code: code.to_string(),
            client_id: self.oauth_client_id.clone(),
            client_secret: self.oauth_client_secret.clone(),
            redirect_uri: redirect_uri.to_string(),
            grant_type: "authorization_code".to_string(),
        };

        let response = self.client
            .post(OAUTH2_TOKEN_URL)
            .json(&request)
            .send()
            .await
            .context("Failed to exchange code for token")?;

        let token_response: OAuthTokenResponse = response
            .json()
            .await
            .context("Failed to parse token response")?;

        Ok(token_response)
    }

    /// Get user info from access token
    pub async fn get_user_info(&self, access_token: &str) -> Result<UserInfo> {
        let response = self.client
            .get(OAUTH2_USERINFO_URL)
            .bearer_auth(access_token)
            .send()
            .await
            .context("Failed to get user info")?;

        let user_info: UserInfo = response
            .json()
            .await
            .context("Failed to parse user info")?;

        Ok(user_info)
    }

    /// Refresh access token using refresh token
    pub async fn refresh_token(&self, refresh_token: &str) -> Result<OAuthTokenResponse> {
        let mut params = HashMap::new();
        params.insert("client_id", self.oauth_client_id.as_str());
        params.insert("client_secret", self.oauth_client_secret.as_str());
        params.insert("refresh_token", refresh_token);
        params.insert("grant_type", "refresh_token");

        let response = self.client
            .post(OAUTH2_TOKEN_URL)
            .form(&params)
            .send()
            .await
            .context("Failed to refresh token")?;

        let token_response: OAuthTokenResponse = response
            .json()
            .await
            .context("Failed to parse refresh token response")?;

        Ok(token_response)
    }

    // ========================================================================
    // SERVICE ACCOUNT METHODS
    // ========================================================================

    /// Create a service account
    pub async fn create_service_account(
        &self,
        account_id: &str,
        display_name: &str,
        description: &str,
        access_token: &str,
    ) -> Result<ServiceAccount> {
        let url = format!(
            "{}/projects/{}/serviceAccounts",
            IAM_API_BASE, self.project_id
        );

        let request = CreateServiceAccountRequest {
            account_id: account_id.to_string(),
            service_account: ServiceAccountMetadata {
                display_name: Some(display_name.to_string()),
                description: Some(description.to_string()),
            },
        };

        let response = self.client
            .post(&url)
            .bearer_auth(access_token)
            .json(&request)
            .send()
            .await
            .context("Failed to create service account")?;

        let service_account: ServiceAccount = response
            .json()
            .await
            .context("Failed to parse service account response")?;

        Ok(service_account)
    }

    /// List service accounts
    pub async fn list_service_accounts(&self, access_token: &str) -> Result<Vec<ServiceAccount>> {
        let url = format!(
            "{}/projects/{}/serviceAccounts",
            IAM_API_BASE, self.project_id
        );

        let response = self.client
            .get(&url)
            .bearer_auth(access_token)
            .send()
            .await
            .context("Failed to list service accounts")?;

        #[derive(Deserialize)]
        struct ListResponse {
            accounts: Vec<ServiceAccount>,
        }

        let list_response: ListResponse = response
            .json()
            .await
            .context("Failed to parse service accounts list")?;

        Ok(list_response.accounts)
    }

    /// Get service account
    pub async fn get_service_account(
        &self,
        account_email: &str,
        access_token: &str,
    ) -> Result<ServiceAccount> {
        let url = format!(
            "{}/projects/{}/serviceAccounts/{}",
            IAM_API_BASE, self.project_id, account_email
        );

        let response = self.client
            .get(&url)
            .bearer_auth(access_token)
            .send()
            .await
            .context("Failed to get service account")?;

        let service_account: ServiceAccount = response
            .json()
            .await
            .context("Failed to parse service account")?;

        Ok(service_account)
    }

    /// Delete service account
    pub async fn delete_service_account(
        &self,
        account_email: &str,
        access_token: &str,
    ) -> Result<()> {
        let url = format!(
            "{}/projects/{}/serviceAccounts/{}",
            IAM_API_BASE, self.project_id, account_email
        );

        self.client
            .delete(&url)
            .bearer_auth(access_token)
            .send()
            .await
            .context("Failed to delete service account")?;

        Ok(())
    }

    // ========================================================================
    // SERVICE ACCOUNT KEY METHODS
    // ========================================================================

    /// Create service account key
    pub async fn create_service_account_key(
        &self,
        account_email: &str,
        access_token: &str,
    ) -> Result<ServiceAccountKey> {
        let url = format!(
            "{}/projects/{}/serviceAccounts/{}/keys",
            IAM_API_BASE, self.project_id, account_email
        );

        let response = self.client
            .post(&url)
            .bearer_auth(access_token)
            .json(&serde_json::json!({
                "privateKeyType": "TYPE_GOOGLE_CREDENTIALS_FILE",
                "keyAlgorithm": "KEY_ALG_RSA_2048"
            }))
            .send()
            .await
            .context("Failed to create service account key")?;

        let key: ServiceAccountKey = response
            .json()
            .await
            .context("Failed to parse service account key")?;

        Ok(key)
    }

    /// List service account keys
    pub async fn list_service_account_keys(
        &self,
        account_email: &str,
        access_token: &str,
    ) -> Result<Vec<ServiceAccountKey>> {
        let url = format!(
            "{}/projects/{}/serviceAccounts/{}/keys",
            IAM_API_BASE, self.project_id, account_email
        );

        let response = self.client
            .get(&url)
            .bearer_auth(access_token)
            .send()
            .await
            .context("Failed to list service account keys")?;

        #[derive(Deserialize)]
        struct ListResponse {
            keys: Vec<ServiceAccountKey>,
        }

        let list_response: ListResponse = response
            .json()
            .await
            .context("Failed to parse service account keys list")?;

        Ok(list_response.keys)
    }

    // ========================================================================
    // IAM POLICY METHODS
    // ========================================================================

    /// Get IAM policy for service account
    pub async fn get_iam_policy(
        &self,
        account_email: &str,
        access_token: &str,
    ) -> Result<Policy> {
        let url = format!(
            "{}/projects/{}/serviceAccounts/{}:getIamPolicy",
            IAM_API_BASE, self.project_id, account_email
        );

        let response = self.client
            .post(&url)
            .bearer_auth(access_token)
            .send()
            .await
            .context("Failed to get IAM policy")?;

        let policy: Policy = response
            .json()
            .await
            .context("Failed to parse IAM policy")?;

        Ok(policy)
    }

    /// Set IAM policy for service account
    pub async fn set_iam_policy(
        &self,
        account_email: &str,
        policy: &Policy,
        access_token: &str,
    ) -> Result<Policy> {
        let url = format!(
            "{}/projects/{}/serviceAccounts/{}:setIamPolicy",
            IAM_API_BASE, self.project_id, account_email
        );

        let response = self.client
            .post(&url)
            .bearer_auth(access_token)
            .json(&serde_json::json!({ "policy": policy }))
            .send()
            .await
            .context("Failed to set IAM policy")?;

        let policy: Policy = response
            .json()
            .await
            .context("Failed to parse IAM policy")?;

        Ok(policy)
    }

    // ========================================================================
    // ROLES METHODS
    // ========================================================================

    /// List roles
    pub async fn list_roles(&self, access_token: &str) -> Result<Vec<Role>> {
        let url = format!("{}/roles", IAM_API_BASE);

        let response = self.client
            .get(&url)
            .bearer_auth(access_token)
            .send()
            .await
            .context("Failed to list roles")?;

        #[derive(Deserialize)]
        struct ListResponse {
            roles: Vec<Role>,
        }

        let list_response: ListResponse = response
            .json()
            .await
            .context("Failed to parse roles list")?;

        Ok(list_response.roles)
    }

    /// Query grantable roles for a resource
    pub async fn query_grantable_roles(
        &self,
        full_resource_name: &str,
        access_token: &str,
    ) -> Result<Vec<Role>> {
        let url = format!("{}/roles:queryGrantableRoles", IAM_API_BASE);

        let response = self.client
            .post(&url)
            .bearer_auth(access_token)
            .json(&serde_json::json!({
                "fullResourceName": full_resource_name
            }))
            .send()
            .await
            .context("Failed to query grantable roles")?;

        #[derive(Deserialize)]
        struct QueryResponse {
            roles: Vec<Role>,
        }

        let query_response: QueryResponse = response
            .json()
            .await
            .context("Failed to parse grantable roles")?;

        Ok(query_response.roles)
    }

    // ========================================================================
    // WORKLOAD IDENTITY POOL METHODS
    // ========================================================================

    /// Create workload identity pool
    pub async fn create_workload_identity_pool(
        &self,
        pool_id: &str,
        display_name: &str,
        description: &str,
        access_token: &str,
    ) -> Result<WorkloadIdentityPool> {
        let url = format!(
            "{}/projects/{}/locations/global/workloadIdentityPools",
            IAM_API_BASE, self.project_id
        );

        let response = self.client
            .post(&url)
            .bearer_auth(access_token)
            .json(&serde_json::json!({
                "workloadIdentityPoolId": pool_id,
                "workloadIdentityPool": {
                    "displayName": display_name,
                    "description": description
                }
            }))
            .send()
            .await
            .context("Failed to create workload identity pool")?;

        let pool: WorkloadIdentityPool = response
            .json()
            .await
            .context("Failed to parse workload identity pool")?;

        Ok(pool)
    }

    /// List workload identity pools
    pub async fn list_workload_identity_pools(
        &self,
        access_token: &str,
    ) -> Result<Vec<WorkloadIdentityPool>> {
        let url = format!(
            "{}/projects/{}/locations/global/workloadIdentityPools",
            IAM_API_BASE, self.project_id
        );

        let response = self.client
            .get(&url)
            .bearer_auth(access_token)
            .send()
            .await
            .context("Failed to list workload identity pools")?;

        #[derive(Deserialize)]
        struct ListResponse {
            #[serde(rename = "workloadIdentityPools")]
            workload_identity_pools: Vec<WorkloadIdentityPool>,
        }

        let list_response: ListResponse = response
            .json()
            .await
            .context("Failed to parse workload identity pools list")?;

        Ok(list_response.workload_identity_pools)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_google_iam_client_creation() {
        let client = GoogleIAMClient::new(
            "test-project".to_string(),
            "test-client-id".to_string(),
            "test-client-secret".to_string(),
            Some("test-api-key".to_string()),
        );

        assert_eq!(client.project_id, "test-project");
        assert_eq!(client.oauth_client_id, "test-client-id");
    }
}

