use dropshot::UntypedBody;
use dropshot::Path;
use dropshot::endpoint;
use dropshot::HttpError;
use dropshot::RequestContext;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use hyper::Body;
use hyper::Response;
use tokio::sync::Mutex;
use std::sync::Arc;
use http::{StatusCode, header::AUTHORIZATION};

use crate::{context::ConjurContext, db, crypto};

#[allow(dead_code)]
#[derive(Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct SecretsPathParams {
    /** Organization account name */
    account: String,
    /** URL-encoded variable ID */
    identifier: String,
}

/** Fetches the value of a secret from the specified Secret. */
#[allow(unused_variables)]
#[endpoint {
    method = GET,
    path = "/secrets/{account}/variable/{identifier}",
    tags = ["secrets"]
}]
pub async fn get_secret(
    rqctx: Arc<RequestContext<Mutex<ConjurContext>>>,
    path_params: Path<SecretsPathParams>,
    update: UntypedBody,
) -> Result<Response<Body>, HttpError>
{
    let api_context = rqctx.context().lock().await;

    let bad_request_err = Err(HttpError::for_status(
        None,
        http::StatusCode::BAD_REQUEST,
    ));

    if let None = api_context.user {
        return bad_request_err;
    }

    let path_params = path_params.into_inner();
    let account = path_params.account;
    let identifier = path_params.identifier;
    let identifier: Vec<(String, String)> = form_urlencoded::parse(identifier.as_bytes()).into_owned().collect();
    let identifier = &identifier[0].0;

    // TODO: prevent SQL injection
    let resource_id = format!("{}:variable:{}", account, identifier);
    let encrypted_secret = db::query(&api_context.db, "SELECT * FROM public.secrets WHERE resource_id=$1;", &resource_id, "value").await;
    if let None = encrypted_secret {
        // TODO: return correct error code
        return bad_request_err;
    }

    let secret = crypto::decrypt(&api_context.slosilo, encrypted_secret.unwrap(), resource_id.as_bytes());

    Ok(Response::builder()
        .header(http::header::CONTENT_TYPE, "text/plain")
        .status(StatusCode::OK)
        .body(String::from(secret).into())?)
}

/* TODO
/** Creates a secret value within the specified variable. */
#[allow(unused_variables)]
#[endpoint {
    method = POST,
    path = "/secrets/{account}/variable/{identifier}",
    tags = ["secrets"]
}]
pub async fn create_secret(
    rqctx: Arc<RequestContext<Mutex<ConjurContext>>>,
    path_params: Path<SecretsPathParams>,
    update: UntypedBody,
) -> Result<Response<Body>, HttpError>
{
}
*/