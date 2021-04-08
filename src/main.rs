use dropshot::ApiDescription;
use dropshot::ConfigDropshot;
use dropshot::ConfigLogging;
use dropshot::ConfigLoggingLevel;
use dropshot::HttpServerStarter;
use tokio::sync::Mutex;
use tokio_postgres::NoTls;

pub mod db;
pub mod crypto;
pub mod context;
pub mod endpoints;

use context::ConjurContext;

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
        .to_logger("conjurer")
        .map_err(|e| e.to_string())?;

    // Describe the API.
    let mut api = ApiDescription::new();
    api.register(endpoints::authn::get_api_key).unwrap();
    api.register(endpoints::authn::get_access_token).unwrap();
    api.register(endpoints::secrets::get_secret).unwrap();

    let ctx = Mutex::new(ConjurContext::new(client, "g8zfk7UZkESkoCyOfqtC1Q82CQsynFoDKjIN3LF9De4="));

    // Output OpenAPI spec
    let spec = api.openapi("conjurer", "0.1.0").json().unwrap();
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