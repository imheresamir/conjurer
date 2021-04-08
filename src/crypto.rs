use aes_gcm::Aes256Gcm;
use aes_gcm::aead::{Aead, NewAead, generic_array::GenericArray, Payload};
use regex::bytes::Regex;

pub fn decrypt(slosilo: &Slosilo, ciphertext: Vec<u8>, aad: &[u8]) -> String {
    String::from(slosilo.decrypt(&ciphertext, aad))
}

pub struct Slosilo {
    cipher: Aes256Gcm,
    re: Regex
}

impl Slosilo {
    pub fn new(data_key: &str) -> Slosilo {
        let master_key = base64::decode(data_key).unwrap();
        let master_key = GenericArray::from_slice(&master_key);

        Slosilo {
            cipher: Aes256Gcm::new(master_key),
            re: Regex::new(r"(?-u)(?P<version>[\s\S]{1})(?P<tag>[\s\S]{16})(?P<iv>[\s\S]{12})(?P<ctext>[\s\S]+)").unwrap()
        }
    }

    pub fn decrypt(&self, ciphertext: &[u8], aad: &[u8]) -> String {
        let caps = self.re.captures(ciphertext).unwrap();

        let _version = caps.name("version").unwrap().as_bytes();
        let tag = caps.name("tag").unwrap().as_bytes();
        let iv = caps.name("iv").unwrap().as_bytes();
        let ctext = caps.name("ctext").unwrap().as_bytes();

        let nonce = GenericArray::from_slice(iv); // 96-bits; unique per message

        let mut ciphertext = ctext.to_vec();
        ciphertext.extend_from_slice(tag);

        let payload = Payload { msg: ciphertext.as_ref(), aad };

        let plaintext = self.cipher.decrypt(nonce, payload)
            .expect("decryption failure!"); // NOTE: handle this error to avoid panics!

        String::from_utf8(plaintext).unwrap()
    }

    /*
    pub fn encrypt(&self, plaintext: &str, aad: &str) -> Vec<u8> {
    }
    */
}
