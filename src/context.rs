use crate::crypto::Slosilo;

pub struct ConjurContext {
    pub account: Option<String>,
    pub user: Option<String>,
    pub db: tokio_postgres::Client,
    pub slosilo: Slosilo,
}

impl ConjurContext {
    /**
     * Return a new ConjurContext.
     */
    pub fn new(db: tokio_postgres::Client, data_key: &str) -> ConjurContext {
        ConjurContext {
            account: None,
            user: None,
            db,
            slosilo: Slosilo::new(data_key),
        }
    }
}
