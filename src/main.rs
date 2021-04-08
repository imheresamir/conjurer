use dropshot::{ApiDescription, UntypedBody};
use dropshot::Path;
use dropshot::ConfigDropshot;
use dropshot::ConfigLogging;
use dropshot::ConfigLoggingLevel;
use dropshot::HttpServerStarter;
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
use tokio_postgres::{NoTls, Error};
use aes_gcm::Aes256Gcm; // Or `Aes128Gcm`
use aes_gcm::aead::{Aead, NewAead, generic_array::GenericArray, Payload};
use regex::bytes::Regex;

pub struct ConjurContext {
    current_user: Option<String>,
    db: tokio_postgres::Client
}

impl ConjurContext {
    /**
     * Return a new ConjurContext.
     */
    pub fn new(db: tokio_postgres::Client) -> ConjurContext {
        ConjurContext {
            current_user: None,
            db
        }
    }

    pub fn set_user(&mut self, new_user: String) {
        self.current_user.replace(new_user);
    }
}

#[allow(dead_code)]
#[derive(Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
struct AuthnPathParams {
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
async fn get_api_key(
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

    // TODO: prevent SQL injection
    let role_id = format!("myConjurAccount:user:{}", user);
    let rows = api_context.db
        .query("SELECT * FROM public.credentials WHERE role_id=$1;", &[&role_id]).await.unwrap();
    
    if rows.len() != 1 {
        // TODO: return not authorized?
        return bad_request_err;
    }

    let encrypted_api_key: &[u8] = rows[0].get("api_key");

    // decrypt api key
    // TODO: compile the server binary with hardware AES acceleration
    let master_key = base64::decode("g8zfk7UZkESkoCyOfqtC1Q82CQsynFoDKjIN3LF9De4=").unwrap();
    let master_key = GenericArray::from_slice(&master_key);
    let cipher = Aes256Gcm::new(master_key);
   
    // TODO: Pre-compile this
    let re = Regex::new(r"(?-u)(?P<version>[\s\S]{1})(?P<tag>[\s\S]{16})(?P<iv>[\s\S]{12})(?P<ctext>[\s\S]+)").unwrap();

    let caps = re.captures(encrypted_api_key).unwrap();
    let version = caps.name("version").unwrap().as_bytes();
    let tag = caps.name("tag").unwrap().as_bytes();
    let iv = caps.name("iv").unwrap().as_bytes();
    let ctext = caps.name("ctext").unwrap().as_bytes();

    let nonce = GenericArray::from_slice(iv); // 96-bits; unique per message

    let mut ciphertext = ctext.to_vec();
    ciphertext.extend_from_slice(tag);

    let payload = Payload {msg: ciphertext.as_ref(), aad: role_id.as_bytes()};

    let api_key = cipher.decrypt(nonce, payload)
        .expect("decryption failure!"); // NOTE: handle this error to avoid panics!

    let api_key = std::str::from_utf8(api_key.as_ref()).unwrap();

    // TODO: secure compare?
    if pass.ne(api_key) {
        // TODO: return not authorized?
        return bad_request_err;
    }

    api_context.set_user(String::from(user));

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
async fn get_access_token(
    rqctx: Arc<RequestContext<Mutex<ConjurContext>>>,
    path_params: Path<AuthnPathParams>,
    update: UntypedBody,
) -> Result<HttpResponseOk<()>, HttpError>
{
    let mut api_context = rqctx.context().lock().await;
    let login = path_params.into_inner().login;
    let body = update.as_str()?;

    let bad_request_err = Err(HttpError::for_status(
        None,
        http::StatusCode::BAD_REQUEST,
    ));
    
    let user = login;
    let pass = String::from(body);

    // TODO: prevent SQL injection
    let role_id = format!("myConjurAccount:user:{}", user);
    let rows = api_context.db
        .query("SELECT * FROM public.credentials WHERE role_id=$1;", &[&role_id]).await.unwrap();
    
    if rows.len() != 1 {
        // TODO: return not authorized?
        return bad_request_err;
    }

    let encrypted_api_key: &[u8] = rows[0].get("api_key");

    // decrypt api key
    // TODO: compile the server binary with hardware AES acceleration
    let master_key = base64::decode("g8zfk7UZkESkoCyOfqtC1Q82CQsynFoDKjIN3LF9De4=").unwrap();
    let master_key = GenericArray::from_slice(&master_key);
    let cipher = Aes256Gcm::new(master_key);
   
    // TODO: Pre-compile this
    let re = Regex::new(r"(?-u)(?P<version>[\s\S]{1})(?P<tag>[\s\S]{16})(?P<iv>[\s\S]{12})(?P<ctext>[\s\S]+)").unwrap();

    let caps = re.captures(encrypted_api_key).unwrap();
    let version = caps.name("version").unwrap().as_bytes();
    let tag = caps.name("tag").unwrap().as_bytes();
    let iv = caps.name("iv").unwrap().as_bytes();
    let ctext = caps.name("ctext").unwrap().as_bytes();

    let nonce = GenericArray::from_slice(iv); // 96-bits; unique per message

    let mut ciphertext = ctext.to_vec();
    ciphertext.extend_from_slice(tag);

    let payload = Payload {msg: ciphertext.as_ref(), aad: role_id.as_bytes()};

    let api_key = cipher.decrypt(nonce, payload)
        .expect("decryption failure!"); // NOTE: handle this error to avoid panics!

    let api_key = std::str::from_utf8(api_key.as_ref()).unwrap();

    // TODO: secure compare?
    if pass.ne(api_key) {
        // TODO: return not authorized?
        return bad_request_err;
    }

    api_context.set_user(String::from(user));

    Ok(HttpResponseOk(()))
}

#[allow(dead_code)]
#[derive(Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
struct SecretsPathParams {
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
async fn get_secret(
    rqctx: Arc<RequestContext<Mutex<ConjurContext>>>,
    path_params: Path<SecretsPathParams>,
    update: UntypedBody,
) -> Result<Response<Body>, HttpError>
{
    let request = rqctx.request.lock().await;
    let api_context = rqctx.context().lock().await;
    let headers = request.headers();

    let bad_request_err = Err(HttpError::for_status(
        None,
        http::StatusCode::BAD_REQUEST,
    ));

    if let None = api_context.current_user {
        return bad_request_err;
    }

    // TODO: account path param not verified
    let identifier = path_params.into_inner().identifier;
    let identifier: Vec<(String, String)> = form_urlencoded::parse(identifier.as_bytes()).into_owned().collect();
    let identifier = &identifier[0].0;

    // TODO: prevent SQL injection
    let resource_id = format!("myConjurAccount:variable:{}", identifier);
    let rows = api_context.db
        .query("SELECT * FROM public.secrets WHERE resource_id=$1;", &[&resource_id]).await.unwrap();
    
    if rows.len() != 1 {
        // TODO: return not authorized?
        println!("{:?}", identifier);
        return bad_request_err;
    }

    let encrypted_secret: &[u8] = rows[0].get("value");

    // decrypt secret
    // TODO: compile the server binary with hardware AES acceleration
    let master_key = base64::decode("g8zfk7UZkESkoCyOfqtC1Q82CQsynFoDKjIN3LF9De4=").unwrap();
    let master_key = GenericArray::from_slice(&master_key);
    let cipher = Aes256Gcm::new(master_key);
   
    // TODO: Pre-compile this
    let re = Regex::new(r"(?-u)(?P<version>[\s\S]{1})(?P<tag>[\s\S]{16})(?P<iv>[\s\S]{12})(?P<ctext>[\s\S]+)").unwrap();

    let caps = re.captures(encrypted_secret).unwrap();
    let version = caps.name("version").unwrap().as_bytes();
    let tag = caps.name("tag").unwrap().as_bytes();
    let iv = caps.name("iv").unwrap().as_bytes();
    let ctext = caps.name("ctext").unwrap().as_bytes();

    let nonce = GenericArray::from_slice(iv); // 96-bits; unique per message

    let mut ciphertext = ctext.to_vec();
    ciphertext.extend_from_slice(tag);

    let payload = Payload {msg: ciphertext.as_ref(), aad: resource_id.as_bytes()};

    let secret = cipher.decrypt(nonce, payload)
        .expect("decryption failure!"); // NOTE: handle this error to avoid panics!

    let secret = std::str::from_utf8(secret.as_ref()).unwrap();

    Ok(Response::builder()
        .header(http::header::CONTENT_TYPE, "text/plain")
        .status(StatusCode::OK)
        .body(String::from(secret).into())?)
}

#[tokio::main]
async fn main() -> Result<(), String> {
    // Connect to the database.
    let (client, connection) =
        tokio_postgres::connect("host=localhost user=postgres password=password", NoTls).await.unwrap();

    // The connection object performs the actual communication with the database,
    // so spawn it off to run on its own.
    tokio::spawn(async move {
        if let Err(e) = connection.await {
            eprintln!("connection error: {}", e);
        }
    });

    // Set up a logger.
    let log =
        ConfigLogging::StderrTerminal {
            level: ConfigLoggingLevel::Info,
        }
        .to_logger("conjur-rs")
        .map_err(|e| e.to_string())?;

    // Describe the API.
    let mut api = ApiDescription::new();
    api.register(get_api_key).unwrap();
    api.register(get_access_token).unwrap();
    api.register(get_secret).unwrap();

    let ctx = Mutex::new(ConjurContext::new(client));

    // Output OpenAPI spec
    let spec = api.openapi("conjur-rs", "0.1.0").json().unwrap();
    println!("{:#}", spec);

    // Start the server.
    let server =
        HttpServerStarter::new(
            &ConfigDropshot {
                bind_address: "127.0.0.1:8080".parse().unwrap(),
                request_body_max_bytes: 1024,
            },
            api,
            ctx,
            &log,
        )
        .map_err(|error| format!("failed to start server: {}", error))?
        .start();

    server.await
}