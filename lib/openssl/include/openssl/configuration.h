// Bottom half was copied from a generated configuration.h
// Top half contains custom defines.
#ifndef OPENSSL_CONFIGURATION_H
# define OPENSSL_CONFIGURATION_H
# pragma once

# ifdef  __cplusplus
extern "C" {
# endif

//// Begin custom defines:

// Set empty for now.
#define OPENSSLDIR ""
#define ENGINESDIR ""
#define MODULESDIR ""

// Don't include deprecated.
#define OPENSSL_NO_DEPRECATED 1

// Engine api is deprecated in openssl v3.0
#define OPENSSL_NO_ENGINE 1

// SRP is deprecated in openssl v3.0
#define OPENSSL_NO_SRP 1

// Disable console related code.
#define OPENSSL_NO_UI_CONSOLE 1

// Legacy providers. See https://wiki.openssl.org/index.php/OpenSSL_3.0
#define OPENSSL_NO_BLAKE2 1
#define OPENSSL_NO_SM2 1
#define OPENSSL_NO_SM3 1
#define OPENSSL_NO_WHIRLPOOL 1
#define OPENSSL_NO_RMD160 1
#define OPENSSL_NO_MDC2 1
#define OPENSSL_NO_MD4 1
#define OPENSSL_NO_IDEA 1
#define OPENSSL_NO_RC2 1
#define OPENSSL_NO_RC4 1
#define OPENSSL_NO_DES 1
#define OPENSSL_NO_SEED 1
#define OPENSSL_NO_CMAC 1

//// End custom defines.

# ifdef OPENSSL_ALGORITHM_DEFINES
#  error OPENSSL_ALGORITHM_DEFINES no longer supported
# endif

/*
 * OpenSSL was configured with the following options:
 */

# define OPENSSL_CONFIGURED_API 30100
# ifndef OPENSSL_RAND_SEED_OS
#  define OPENSSL_RAND_SEED_OS
# endif
# ifndef OPENSSL_THREADS
#  define OPENSSL_THREADS
# endif
# ifndef OPENSSL_NO_ACVP_TESTS
#  define OPENSSL_NO_ACVP_TESTS
# endif
# ifndef OPENSSL_NO_ASAN
#  define OPENSSL_NO_ASAN
# endif
# ifndef OPENSSL_NO_CRYPTO_MDEBUG
#  define OPENSSL_NO_CRYPTO_MDEBUG
# endif
# ifndef OPENSSL_NO_CRYPTO_MDEBUG_BACKTRACE
#  define OPENSSL_NO_CRYPTO_MDEBUG_BACKTRACE
# endif
# ifndef OPENSSL_NO_DEVCRYPTOENG
#  define OPENSSL_NO_DEVCRYPTOENG
# endif
# ifndef OPENSSL_NO_EC_NISTP_64_GCC_128
#  define OPENSSL_NO_EC_NISTP_64_GCC_128
# endif
# ifndef OPENSSL_NO_EGD
#  define OPENSSL_NO_EGD
# endif
# ifndef OPENSSL_NO_EXTERNAL_TESTS
#  define OPENSSL_NO_EXTERNAL_TESTS
# endif
# ifndef OPENSSL_NO_FIPS_SECURITYCHECKS
#  define OPENSSL_NO_FIPS_SECURITYCHECKS
# endif
# ifndef OPENSSL_NO_FUZZ_AFL
#  define OPENSSL_NO_FUZZ_AFL
# endif
# ifndef OPENSSL_NO_FUZZ_LIBFUZZER
#  define OPENSSL_NO_FUZZ_LIBFUZZER
# endif
# ifndef OPENSSL_NO_KTLS
#  define OPENSSL_NO_KTLS
# endif
# ifndef OPENSSL_NO_MD2
#  define OPENSSL_NO_MD2
# endif
# ifndef OPENSSL_NO_MSAN
#  define OPENSSL_NO_MSAN
# endif
# ifndef OPENSSL_NO_RC5
#  define OPENSSL_NO_RC5
# endif
# ifndef OPENSSL_NO_SCTP
#  define OPENSSL_NO_SCTP
# endif
# ifndef OPENSSL_NO_SSL3
#  define OPENSSL_NO_SSL3
# endif
# ifndef OPENSSL_NO_SSL3_METHOD
#  define OPENSSL_NO_SSL3_METHOD
# endif
# ifndef OPENSSL_NO_TLS1
#  define OPENSSL_NO_TLS1
# endif
# ifndef OPENSSL_NO_TLS1_1
#  define OPENSSL_NO_TLS1_1
# endif
# ifndef OPENSSL_NO_TRACE
#  define OPENSSL_NO_TRACE
# endif
# ifndef OPENSSL_NO_UBSAN
#  define OPENSSL_NO_UBSAN
# endif
# ifndef OPENSSL_NO_UNIT_TEST
#  define OPENSSL_NO_UNIT_TEST
# endif
# ifndef OPENSSL_NO_UPLINK
#  define OPENSSL_NO_UPLINK
# endif
# ifndef OPENSSL_NO_WEAK_SSL_CIPHERS
#  define OPENSSL_NO_WEAK_SSL_CIPHERS
# endif
# ifndef OPENSSL_NO_STATIC_ENGINE
#  define OPENSSL_NO_STATIC_ENGINE
# endif

/* Generate 80386 code? */
# undef I386_ONLY

/*
 * The following are cipher-specific, but are part of the public API.
 */
# if !defined(OPENSSL_SYS_UEFI)
#  undef BN_LLONG
/* Only one for the following should be defined */
#  define SIXTY_FOUR_BIT_LONG
#  undef SIXTY_FOUR_BIT
#  undef THIRTY_TWO_BIT
# endif

# define RC4_INT unsigned int

# ifdef  __cplusplus
}
# endif

#endif                          /* OPENSSL_CONFIGURATION_H */