#include <openssl/evp.h>
#include <openssl/rand.h>
#include <openssl/err.h>
#include <openssl/sha.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int http_client_crypto_random(unsigned char *out, size_t out_len) {
    if (out_len == 0) return 1;
    if (out == NULL) return 0;
    return RAND_bytes(out, (int)out_len) == 1 ? 1 : 0;
}

int http_client_crypto_aes256gcm_encrypt(
    const unsigned char *key, size_t key_len,
    const unsigned char *nonce, size_t nonce_len,
    const unsigned char *aad, size_t aad_len,
    const unsigned char *plaintext, size_t plaintext_len,
    unsigned char *ciphertext,
    unsigned char *tag, size_t tag_len) {
    EVP_CIPHER_CTX *ctx = NULL;
    int len = 0;
    int out_len = 0;
    unsigned char final_dummy[1];

    if (key == NULL || key_len != 32 || nonce == NULL || nonce_len != 12 || tag == NULL || tag_len != 16) return 0;
    if (plaintext_len > 0 && (plaintext == NULL || ciphertext == NULL)) return 0;
    if (aad_len > 0 && aad == NULL) return 0;

    ctx = EVP_CIPHER_CTX_new();
    if (ctx == NULL) return 0;
    if (EVP_EncryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL) != 1) goto fail;
    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, (int)nonce_len, NULL) != 1) goto fail;
    if (EVP_EncryptInit_ex(ctx, NULL, NULL, key, nonce) != 1) goto fail;
    if (aad_len > 0 && EVP_EncryptUpdate(ctx, NULL, &len, aad, (int)aad_len) != 1) goto fail;
    if (plaintext_len > 0) {
        if (EVP_EncryptUpdate(ctx, ciphertext, &len, plaintext, (int)plaintext_len) != 1) goto fail;
        out_len = len;
    }
    if (EVP_EncryptFinal_ex(ctx, plaintext_len > 0 ? ciphertext + out_len : final_dummy, &len) != 1) goto fail;
    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, (int)tag_len, tag) != 1) goto fail;
    EVP_CIPHER_CTX_free(ctx);
    return 1;
fail:
    EVP_CIPHER_CTX_free(ctx);
    return 0;
}

int http_client_crypto_aes256gcm_decrypt(
    const unsigned char *key, size_t key_len,
    const unsigned char *nonce, size_t nonce_len,
    const unsigned char *aad, size_t aad_len,
    const unsigned char *ciphertext, size_t ciphertext_len,
    const unsigned char *tag, size_t tag_len,
    unsigned char *plaintext) {
    EVP_CIPHER_CTX *ctx = NULL;
    int len = 0;
    int out_len = 0;
    int ok = 0;
    unsigned char final_dummy[1];

    if (key == NULL || key_len != 32 || nonce == NULL || nonce_len != 12 || tag == NULL || tag_len != 16) return 0;
    if (ciphertext_len > 0 && (ciphertext == NULL || plaintext == NULL)) return 0;
    if (aad_len > 0 && aad == NULL) return 0;

    ctx = EVP_CIPHER_CTX_new();
    if (ctx == NULL) return 0;
    if (EVP_DecryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL) != 1) goto done;
    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, (int)nonce_len, NULL) != 1) goto done;
    if (EVP_DecryptInit_ex(ctx, NULL, NULL, key, nonce) != 1) goto done;
    if (aad_len > 0 && EVP_DecryptUpdate(ctx, NULL, &len, aad, (int)aad_len) != 1) goto done;
    if (ciphertext_len > 0) {
        if (EVP_DecryptUpdate(ctx, plaintext, &len, ciphertext, (int)ciphertext_len) != 1) goto done;
        out_len = len;
    }
    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, (int)tag_len, (void *)tag) != 1) goto done;
    ok = EVP_DecryptFinal_ex(ctx, ciphertext_len > 0 ? plaintext + out_len : final_dummy, &len) == 1;
done:
    EVP_CIPHER_CTX_free(ctx);
    return ok ? 1 : 0;
}

int http_client_crypto_pbkdf2_sha256(
    const unsigned char *password, size_t password_len,
    const unsigned char *salt, size_t salt_len,
    int iterations,
    unsigned char *out, size_t out_len) {
    if (out == NULL || out_len == 0 || iterations < 1) return 0;
    if (password_len > 0 && password == NULL) return 0;
    if (salt_len > 0 && salt == NULL) return 0;
    return PKCS5_PBKDF2_HMAC((const char *)password, (int)password_len,
                             salt, (int)salt_len, iterations,
                             EVP_sha256(), (int)out_len, out) == 1 ? 1 : 0;
}

int http_client_crypto_digest_hex(
    int algorithm,
    const unsigned char *input, size_t input_len,
    char *output, size_t output_len) {
    const EVP_MD *md = NULL;
    EVP_MD_CTX *ctx = NULL;
    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned int digest_len = 0;
    static const char hex[] = "0123456789abcdef";
    size_t i;

    if (output == NULL) return 0;
    if (input_len > 0 && input == NULL) return 0;
    if (algorithm == 1) md = EVP_md5();
    else if (algorithm == 2) md = EVP_sha256();
    else return 0;
    if (md == NULL) return 0;
    if (output_len < (size_t)(EVP_MD_size(md) * 2)) return 0;

    ctx = EVP_MD_CTX_new();
    if (ctx == NULL) return 0;
    if (EVP_DigestInit_ex(ctx, md, NULL) != 1) goto fail;
    if (input_len > 0 && EVP_DigestUpdate(ctx, input, input_len) != 1) goto fail;
    if (EVP_DigestFinal_ex(ctx, digest, &digest_len) != 1) goto fail;
    EVP_MD_CTX_free(ctx);

    for (i = 0; i < digest_len; ++i) {
        output[i * 2] = hex[(digest[i] >> 4) & 0x0f];
        output[i * 2 + 1] = hex[digest[i] & 0x0f];
    }
    return 1;
fail:
    EVP_MD_CTX_free(ctx);
    return 0;
}

int http_client_crypto_digest_file_hex(
    int algorithm,
    const char *path, size_t path_len,
    char *output, size_t output_len) {
    const EVP_MD *md = NULL;
    EVP_MD_CTX *ctx = NULL;
    unsigned char buffer[65536];
    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned int digest_len = 0;
    static const char hex[] = "0123456789abcdef";
    char *c_path = NULL;
    FILE *file = NULL;
    size_t n;
    size_t i;

    if (path == NULL || path_len == 0 || output == NULL) return 0;
    if (algorithm == 1) md = EVP_md5();
    else if (algorithm == 2) md = EVP_sha256();
    else return 0;
    if (md == NULL) return 0;
    if (output_len < (size_t)(EVP_MD_size(md) * 2)) return 0;

    c_path = (char *)malloc(path_len + 1);
    if (c_path == NULL) return 0;
    memcpy(c_path, path, path_len);
    c_path[path_len] = '\0';

    file = fopen(c_path, "rb");
    free(c_path);
    if (file == NULL) return 0;

    ctx = EVP_MD_CTX_new();
    if (ctx == NULL) goto fail;
    if (EVP_DigestInit_ex(ctx, md, NULL) != 1) goto fail;

    while ((n = fread(buffer, 1, sizeof(buffer), file)) > 0) {
        if (EVP_DigestUpdate(ctx, buffer, n) != 1) goto fail;
    }
    if (ferror(file)) goto fail;
    if (EVP_DigestFinal_ex(ctx, digest, &digest_len) != 1) goto fail;

    EVP_MD_CTX_free(ctx);
    fclose(file);

    for (i = 0; i < digest_len; ++i) {
        output[i * 2] = hex[(digest[i] >> 4) & 0x0f];
        output[i * 2 + 1] = hex[digest[i] & 0x0f];
    }
    return 1;
fail:
    EVP_MD_CTX_free(ctx);
    fclose(file);
    return 0;
}
