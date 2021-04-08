# conjurer
Conjur server in Rust

Currently supported endpoints:
* /authn/{account}/login (GET)
* /authn/{account}/{login}/authenticate (POST)
* /whoami (GET)
* /secrets/{account}/variable/{identifier} (GET)

Currently endpoints return 400 Bad Request if something goes wrong, including auth failure.

The server authenticates a user login attempt by querying the Postgres database (using the unmodified Conjur schema) for the encrypted api key for the user, decrypting it (AES-256-GCM), and comparing the plaintext key with the user supplied key. The server responds with 200 OK if auth succeeds, and saves the logged in username and account in its internal context, otherwise returns 400 Bad Request. If auth is successful, the user can get a stored secret - the server similarly fetches the encrypted secret from the database, decrypts it, and returns the plaintext in the response body.

Tested with curl and conjur-cli. Server is hardcoded to look for Postgres at localhost:5432, configured with `username=postgres`, `password=password`. A test database can be setup using pg_restore with the backup at `test_data/schema/db_dump`, which is preconfigured with users (admin, Dave@BotApp) and a secret (BotApp/secretVar). Any authenticated user can fetch the secret at the moment.

The server is run by executing `cargo run` in the repo root. Clients should be instructed to look for a Conjur server at localhost:8080, and the account should be set to `myConjurAccount` in ~/.conjurrc in lieu of `conjur init` which isn't implemented.
