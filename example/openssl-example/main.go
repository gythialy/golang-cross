// Command openssl-example verifies cgo + OpenSSL cross-compilation
// through the zig-based toolchain (Dockerfile.zig).
//
// It links OpenSSL's libcrypto via cgo and computes a SHA-256 digest,
// which exercises the full cgo path: C headers, compile, and static link.
//
// Build matrix (see example/openssl-example/.goreleaser.zig-openssl.yml):
//   - darwin amd64/arm64 (zig cc + macOS SDK)
//   - linux amd64 (zig cc, static libcrypto)
//   - windows amd64 (zig cc)
package main

/*
#include <openssl/evp.h>
#include <openssl/err.h>
#include <stdlib.h>
#include <string.h>

static int sha256_hex(const char* input, char* out, size_t outlen) {
    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned int digest_len = 0;
    EVP_MD_CTX* ctx = EVP_MD_CTX_new();
    if (ctx == NULL) return -1;
    if (EVP_DigestInit_ex(ctx, EVP_sha256(), NULL) != 1) { EVP_MD_CTX_free(ctx); return -1; }
    if (EVP_DigestUpdate(ctx, input, strlen(input)) != 1) { EVP_MD_CTX_free(ctx); return -1; }
    if (EVP_DigestFinal_ex(ctx, digest, &digest_len) != 1) { EVP_MD_CTX_free(ctx); return -1; }
    EVP_MD_CTX_free(ctx);

    if (outlen < (size_t)(digest_len * 2 + 1)) return -1;
    for (unsigned int i = 0; i < digest_len; i++) {
        snprintf(out + i * 2, 3, "%02x", digest[i]);
    }
    return 0;
}
*/
import "C"

import (
	"fmt"
	"os"
	"unsafe"
)

func sha256Hex(input string) (string, error) {
	cInput := C.CString(input)
	defer C.free(unsafe.Pointer(cInput))

	out := make([]byte, 65)
	rc := C.sha256_hex(cInput, (*C.char)(unsafe.Pointer(&out[0])), C.size_t(len(out)))
	if rc != 0 {
		return "", fmt.Errorf("openssl sha256 failed (rc=%d)", rc)
	}
	return string(out[:64]), nil
}

func main() {
	input := "golang-cross zig openssl example"
	if len(os.Args) > 1 {
		input = os.Args[1]
	}
	hex, err := sha256Hex(input)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Printf("sha256(%q) = %s\n", input, hex)
}
