use dropshot::UntypedBody;
use dropshot::Path;
use dropshot::endpoint;
use dropshot::HttpError;
use dropshot::HttpResponseOk;
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
pub struct AuthnPathParams {
    /** Conjur account name */
    account: String,
    login: String,
}

/** Gets the API key of a user given the username and password via HTTP Basic Authentication. */
#[allow(unused_variables)]
#[endpoint {
    method = GET,
    path = "/authn/{account}/{login}",
    tags = ["authentication"]
}]
pub async fn get_api_key(
    rqctx: Arc<RequestContext<Mutex<ConjurContext>>>,
    path_params: Path<AuthnPathParams>,
    update: UntypedBody,
) -> Result<Response<Body>, HttpError>
{
    let request = rqctx.request.lock().await;
    let mut api_context = rqctx.context().lock().await;
    let headers = request.headers();
    let auth_header = headers.get(AUTHORIZATION);

    let bad_request_err = Err(HttpError::for_status(
        None,
        http::StatusCode::BAD_REQUEST,
    ));

    // TODO: path params not validated
    // TODO: in this handler verify {login} == "login"
    
    if let None = auth_header {
        return bad_request_err;
    }

    let auth_header_parts: Vec<&str> = auth_header.unwrap().to_str().unwrap().split_whitespace().collect();
    if auth_header_parts.len() != 2 || auth_header_parts[0] != "Basic" {
        return bad_request_err;
    }

    let user_pass = String::from_utf8(base64::decode(auth_header_parts[1]).unwrap()).unwrap();
    let user_pass: Vec<&str> = user_pass.split(':').collect();
    if user_pass.len() != 2 {
        return bad_request_err;
    }

    let user = user_pass[0];
    let pass = user_pass[1];
    let account = path_params.into_inner().account;

    // TODO: prevent SQL injection
    let role_id = format!("{}:user:{}", account, user);
    let encrypted_api_key = db::query(&api_context.db, "SELECT * FROM public.credentials WHERE role_id=$1;", &role_id, "api_key").await;
    if let None = encrypted_api_key {
        // TODO: return not authorized?
        return bad_request_err;
    }

    let api_key = crypto::decrypt(&api_context.slosilo, encrypted_api_key.unwrap(), role_id.as_bytes());

    // TODO: secure compare?
    if pass.ne(&api_key) {
        // TODO: return not authorized?
        return bad_request_err;
    }

    api_context.user.replace(String::from(user));
    api_context.account.replace(account);

    Ok(Response::builder()
        .header(http::header::CONTENT_TYPE, "text/plain")
        .status(StatusCode::OK)
        .body(String::from(api_key).into())?)
}


/**  */
#[allow(unused_variables)]
#[endpoint {
    method = POST,
    path = "/authn/{account}/{login}/authenticate",
    tags = ["authentication"]
}]
pub async fn get_access_token(
    rqctx: Arc<RequestContext<Mutex<ConjurContext>>>,
    path_params: Path<AuthnPathParams>,
    update: UntypedBody,
) -> Result<HttpResponseOk<()>, HttpError>
{
    let mut api_context = rqctx.context().lock().await;
    let path_params = path_params.into_inner();
    let body = update.as_str()?;

    let bad_request_err = Err(HttpError::for_status(
        None,
        http::StatusCode::BAD_REQUEST,
    ));
    
    let user  = path_params.login;
    let user: Vec<(String, String)> = form_urlencoded::parse(user.as_bytes()).into_owned().collect();
    let user = &user[0].0;

    let pass = String::from(body);
    let account = path_params.account;

    // TODO: prevent SQL injection
    let role_id = format!("{}:user:{}", account, user);
    println!("{:?}", role_id);
    let encrypted_api_key = db::query(&api_context.db, "SELECT * FROM public.credentials WHERE role_id=$1;", &role_id, "api_key").await;
    if let None = encrypted_api_key {
        // TODO: return correct error code
        return bad_request_err;
    }

    let api_key = crypto::decrypt(&api_context.slosilo, encrypted_api_key.unwrap(), role_id.as_bytes());

    // TODO: secure compare?
    if pass.ne(&api_key) {
        // TODO: return correct error code
        return bad_request_err;
    }

    api_context.user.replace(String::from(user));
    api_context.account.replace(account);

    Ok(HttpResponseOk(()))
}