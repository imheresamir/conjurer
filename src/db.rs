pub async fn query(
    db: &tokio_postgres::Client,
    query_statement: &str,
    query_params: &str,
    column_name: &str) -> Option<Vec<u8>> {
        let rows = db.query(query_statement, &[&query_params]).await.unwrap();
        if rows.len() != 1 {
            return None;
        }

        let result: &[u8] = rows[0].get(column_name);

        Some(Vec::from(result))
}