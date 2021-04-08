use dropshot::endpoint;
use dropshot::HttpError;
use dropshot::HttpResponseOk;
use dropshot::RequestContext;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use tokio::sync::Mutex;
use std::sync::Arc;

use crate::context::ConjurContext;

/** Information about the client making the request */
#[allow(dead_code)]
#[derive(Deserialize, Serialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct WhoAmI {
    /** The account attribute of the client provided access token. */
    account: String,
    /** The username attribute of the provided access token. */
    username: String,
    // TODO: fill out with other fields
}

/** Provides information about the client making an API request. */
#[allow(unused_variables)]
#[endpoint {
    method = GET,
    path = "/whoami",
    tags = ["status"]
}]
pub async fn who_am_i(
    rqctx: Arc<RequestContext<Mutex<ConjurContext>>>,
) -> Result<HttpResponseOk<WhoAmI>, HttpError>
{
    let api_context = rqctx.context().lock().await;

    let bad_request_err = Err(HttpError::for_status(
        None,
        http::StatusCode::BAD_REQUEST,
    ));

    if api_context.user.is_none() || api_context.account.is_none() {
        // TODO: return correct error code
        return bad_request_err;
    }

    let username = api_context.user.clone().unwrap();
    let account = api_context.account.clone().unwrap();

    Ok(HttpResponseOk(WhoAmI {
        account,
        username,
    }))
}
