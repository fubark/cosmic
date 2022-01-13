const std = @import("std");
const Builder = std.build.Builder;
const LibExeObjStep = std.build.LibExeObjStep;

const UsePrebuiltOpenSSL = false;

pub fn buildLinkCrypto(b: *Builder, step: *LibExeObjStep) !void {
    if (UsePrebuiltOpenSSL) {
        step.addAssemblyFile("/home/linuxbrew/.linuxbrew/Cellar/openssl@3/3.0.1/lib/libcrypto.a");
        return;
    }

    const target = step.target;
    const lib = b.addStaticLibrary("crypto", null);
    
    var c_flags = std.ArrayList([]const u8).init(b.allocator);
    defer c_flags.deinit();

    try c_flags.appendSlice(&.{
        // Set empty for now.
        "-DOPENSSLDIR=\"\"",
        "-DENGINESDIR=\"\"",
        "-DMODULESDIR=\"\"",

        // Don't include deprecated.
        "-DOPENSSL_NO_DEPRECATED",

        // Engine api is deprecated in openssl v3.0
        "-DOPENSSL_NO_ENGINE",

        // SRP is deprecated in openssl v3.0
        "-DOPENSSL_NO_SRP",

        // Disable console related code.
        "-DOPENSSL_NO_UI_CONSOLE",

        // Legacy providers. See https://wiki.openssl.org/index.php/OpenSSL_3.0
        "-DOPENSSL_NO_BLAKE2",
        "-DOPENSSL_NO_SM2",
        "-DOPENSSL_NO_SM3",
        "-DOPENSSL_NO_WHIRLPOOL",
        "-DOPENSSL_NO_RMD160",
        "-DOPENSSL_NO_MDC2",
        "-DOPENSSL_NO_MD4",
        "-DOPENSSL_NO_IDEA",
        "-DOPENSSL_NO_RC2",
        "-DOPENSSL_NO_RC4",
        "-DOPENSSL_NO_DES",
        "-DOPENSSL_NO_SEED",
        "-DOPENSSL_NO_CMAC",
    });

    const c_files = &[_][]const u8{
        // openssl/crypto/bio/build.info
        // base
        "bio/bio_lib.c",
        "bio/bio_cb.c",
        "bio/bio_err.c",
        "bio/bio_print.c",
        "bio/bio_dump.c",
        "bio/bio_addr.c",
        "bio/bio_sock.c",
        "bio/bio_sock2.c",
        "bio/bio_meth.c",
        "bio/ossl_core_bio.c",
        // source/sink
        "bio/bss_null.c",
        "bio/bss_mem.c",
        "bio/bss_bio.c",
        "bio/bss_fd.c",
        "bio/bss_file.c",
        "bio/bss_sock.c",
        "bio/bss_conn.c",
        "bio/bss_acpt.c",
        "bio/bss_dgram.c",
        "bio/bss_log.c",
        "bio/bss_core.c",
        // filters
        "bio/bf_null.c",
        "bio/bf_buff.c",
        "bio/bf_lbuf.c",
        "bio/bf_nbio.c",
        "bio/bf_prefix.c",
        "bio/bf_readbuff.c",

        // openssl/crypto/buffer/build.info
        "buffer/buffer.c",
        "buffer/buf_err.c",

        // openssl/crypto/err/build.info
        "err/err_blocks.c",
        "err/err.c",
        "err/err_all.c",
        "err/err_all_legacy.c",
        "err/err_prn.c",

        // openssl/crypto/encode_decode/build.info
        "encode_decode/encoder_meth.c",
        "encode_decode/encoder_lib.c",
        "encode_decode/encoder_pkey.c",
        "encode_decode/decoder_meth.c",
        "encode_decode/decoder_lib.c",
        "encode_decode/decoder_pkey.c",
        "encode_decode/encoder_err.c",
        "encode_decode/decoder_err.c",

        // openssl/crypto/property/build.info
        "property/property_string.c",
        "property/property_parse.c",
        "property/property_query.c",
        "property/property.c",
        "property/defn_cache.c",
        "property/property_err.c",

        // openssl/crypto/build.info
        // util common
        "cryptlib.c",
        "params.c",
        "params_from_text.c",
        "bsearch.c",
        "ex_data.c",
        "o_str.c",
        "threads_pthread.c",
        "threads_win.c",
        "threads_none.c",
        "initthread.c",
        "context.c",
        "sparse_array.c",
        "asn1_dsa.c",
        "packet.c",
        "param_build.c",
        "param_build_set.c",
        "der_writer.c",
        "threads_lib.c",
        "params_dup.c",
        // source
        "mem.c",
        "mem_sec.c",
        "cversion.c",
        "info.c",
        "cpt_err.c",
        "ebcdic.c",
        "uid.c",
        "o_time.c",
        "o_dir.c",
        "o_fopen.c",
        "getenv.c",
        "o_init.c",
        "init.c",
        "trace.c",
        "provider.c",
        "provider_child.c",
        "punycode.c",
        "passphrase.c",
        // core
        "provider_core.c",
        "provider_predefined.c",
        "core_fetch.c",
        "core_algorithm.c",
        "core_namemap.c",
        "self_test_core.c",
        "provider_conf.c",

        // openssl/crypto/lhash/build.info
        "lhash/lhash.c",
        "lhash/lh_stats.c",

        // openssl/crypto/objects/build.info
        "objects/o_names.c",
        "objects/obj_dat.c",
        "objects/obj_lib.c",
        "objects/obj_err.c",
        "objects/obj_xref.c",

        // openssl/crypto/evp/build.info
        // common
        "evp/digest.c",
        "evp/evp_enc.c",
        "evp/evp_lib.c",
        "evp/evp_fetch.c",
        "evp/evp_utils.c",
        "evp/mac_lib.c",
        "evp/mac_meth.c",
        "evp/keymgmt_meth.c",
        "evp/keymgmt_lib.c",
        "evp/kdf_lib.c",
        "evp/kdf_meth.c",
        "evp/m_sigver.c",
        "evp/pmeth_lib.c",
        "evp/signature.c",
        "evp/p_lib.c",
        "evp/pmeth_gn.c",
        "evp/exchange.c",
        "evp/evp_rand.c",
        "evp/asymcipher.c",
        "evp/kem.c",
        "evp/dh_support.c",
        "evp/ec_support.c",
        "evp/pmeth_check.c",
        // source
        "evp/encode.c",
        "evp/evp_key.c",
        "evp/evp_cnf.c",
        "evp/e_des.c",
        "evp/e_bf.c",
        "evp/e_idea.c",
        "evp/e_des3.c",
        "evp/e_rc4.c",
        "evp/e_aes.c",
        "evp/names.c",
        "evp/e_aria.c",
        "evp/e_sm4.c",
        "evp/e_xcbc_d.c",
        "evp/e_rc2.c",
        "evp/e_cast.c",
        "evp/e_rc5.c",
        "evp/m_null.c",
        "evp/p_seal.c",
        "evp/p_sign.c",
        "evp/p_verify.c",
        "evp/p_legacy.c",
        "evp/bio_md.c",
        "evp/bio_b64.c",
        "evp/bio_enc.c",
        "evp/evp_err.c",
        "evp/e_null.c",
        "evp/c_allc.c",
        "evp/c_alld.c",
        "evp/bio_ok.c",
        "evp/evp_pkey.c",
        "evp/evp_pbe.c",
        "evp/p5_crpt.c",
        "evp/p5_crpt2.c",
        "evp/pbe_scrypt.c",
        "evp/e_aes_cbc_hmac_sha1.c",
        "evp/e_aes_cbc_hmac_sha256.c",
        "evp/e_rc4_hmac_md5.c",
        "evp/e_chacha20_poly1305.c",
        "evp/legacy_sha.c",
        "evp/ctrl_params_translate.c",
        "evp/cmeth_lib.c",
        "evp/dh_ctrl.c",
        "evp/dsa_ctrl.c",
        "evp/ec_ctrl.c",
        "evp/legacy_md5.c",
        "evp/legacy_md5_sha1.c",
        "evp/e_camellia.c",

        // openssl/crypto/conf/build.info
        "conf/conf_err.c",
        "conf/conf_lib.c",
        "conf/conf_api.c",
        "conf/conf_def.c",
        "conf/conf_mod.c",
        "conf/conf_mall.c",
        "conf/conf_sap.c",
        "conf/conf_ssl.c",

        // openssl/crypto/x509/build.info
        "x509/x509_def.c",
        "x509/x509_d2.c",
        "x509/x509_r2x.c",
        "x509/x509_cmp.c",
        "x509/x509_obj.c",
        "x509/x509_req.c",
        "x509/x509spki.c",
        "x509/x509_vfy.c",
        "x509/x509_set.c",
        "x509/x509cset.c",
        "x509/x509rset.c",
        "x509/x509_err.c",
        "x509/x509name.c",
        "x509/x509_v3.c",
        "x509/x509_ext.c",
        "x509/x509_att.c",
        "x509/x509_meth.c",
        "x509/x509_lu.c",
        "x509/x_all.c",
        "x509/x509_txt.c",
        "x509/x509_trust.c",
        "x509/by_file.c",
        "x509/by_dir.c",
        "x509/by_store.c",
        "x509/x509_vpm.c",      
        "x509/x_crl.c",
        "x509/t_crl.c",
        "x509/x_req.c",
        "x509/t_req.c",
        "x509/x_x509.c",
        "x509/t_x509.c",      
        "x509/x_pubkey.c",
        "x509/x_x509a.c",
        "x509/x_attrib.c",
        "x509/x_exten.c",
        "x509/x_name.c",     
        "x509/v3_bcons.c",
        "x509/v3_bitst.c",
        "x509/v3_conf.c",
        "x509/v3_extku.c",
        "x509/v3_ia5.c",
        "x509/v3_utf8.c",
        "x509/v3_lib.c",     
        "x509/v3_prn.c",
        "x509/v3_utl.c",
        "x509/v3err.c",
        "x509/v3_genn.c",
        "x509/v3_san.c",
        "x509/v3_skid.c",
        "x509/v3_akid.c",       
        "x509/v3_pku.c",
        "x509/v3_int.c",
        "x509/v3_enum.c",
        "x509/v3_sxnet.c",
        "x509/v3_cpols.c",
        "x509/v3_crld.c",
        "x509/v3_purp.c",       
        "x509/v3_info.c",
        "x509/v3_akeya.c",
        "x509/v3_pmaps.c",
        "x509/v3_pcons.c",
        "x509/v3_ncons.c",       
        "x509/v3_pcia.c",
        "x509/v3_pci.c",
        "x509/v3_ist.c",    
        "x509/pcy_cache.c",
        "x509/pcy_node.c",
        "x509/pcy_data.c",
        "x509/pcy_map.c",
        "x509/pcy_tree.c",
        "x509/pcy_lib.c",       
        "x509/v3_asid.c",
        "x509/v3_addr.c",
        "x509/v3_tlsf.c",
        "x509/v3_admis.c",

        // openssl/crypto/store/build.info
        "store/store_err.c",
        "store/store_lib.c",
        "store/store_result.c",
        "store/store_strings.c",
        "store/store_meth.c",

        // openssl/crypto/pem/build.info
        "pem/pem_sign.c",
        "pem/pem_info.c",
        "pem/pem_lib.c",
        "pem/pem_all.c",
        "pem/pem_err.c",
        "pem/pem_x509.c",
        "pem/pem_xaux.c",
        "pem/pem_oth.c",
        "pem/pem_pk8.c",
        "pem/pem_pkey.c",
        "pem/pvkfmt.c",

        // openssl/crypto/asn1/build.info
        "asn1/a_object.c",
        "asn1/a_bitstr.c",
        "asn1/a_utctm.c",
        "asn1/a_gentm.c",
        "asn1/a_time.c",
        "asn1/a_int.c",
        "asn1/a_octet.c",
        "asn1/a_print.c",
        "asn1/a_type.c",
        "asn1/a_dup.c",
        "asn1/a_d2i_fp.c",
        "asn1/a_i2d_fp.c",      
        "asn1/a_utf8.c",
        "asn1/a_sign.c",
        "asn1/a_digest.c",
        "asn1/a_verify.c",
        "asn1/a_mbstr.c",
        "asn1/a_strex.c",
        "asn1/x_algor.c",
        "asn1/x_val.c",
        "asn1/x_sig.c",
        "asn1/x_bignum.c",
        "asn1/x_int64.c",
        "asn1/x_info.c",
        "asn1/x_spki.c",
        "asn1/nsseq.c",
        "asn1/d2i_pu.c",
        "asn1/d2i_pr.c",
        "asn1/i2d_evp.c",      
        "asn1/t_pkey.c",
        "asn1/t_spki.c",
        "asn1/t_bitst.c",       
        "asn1/tasn_new.c",
        "asn1/tasn_fre.c",
        "asn1/tasn_enc.c",
        "asn1/tasn_dec.c",
        "asn1/tasn_utl.c",
        "asn1/tasn_typ.c",      
        "asn1/tasn_prn.c",
        "asn1/tasn_scn.c",
        "asn1/ameth_lib.c",      
        "asn1/f_int.c",
        "asn1/f_string.c",
        "asn1/x_pkey.c",
        "asn1/bio_asn1.c",
        "asn1/bio_ndef.c",
        "asn1/asn_mime.c",
        "asn1/asn1_gen.c",
        "asn1/asn1_parse.c",
        "asn1/asn1_lib.c",
        "asn1/asn1_err.c",
        "asn1/a_strnid.c",     
        "asn1/evp_asn1.c",
        "asn1/asn_pack.c",
        "asn1/p5_pbe.c",
        "asn1/p5_pbev2.c",
        "asn1/p5_scrypt.c",
        "asn1/p8_pkey.c",        
        "asn1/asn_moid.c",
        "asn1/asn_mstbl.c",
        "asn1/asn1_item_list.c",
        "asn1/d2i_param.c",

        // openssl/crypto/hmac/build.info
        "hmac/hmac.c",

        // openssl/crypto/dh/build.info
        // common
        "dh/dh_lib.c",
        "dh/dh_key.c",
        "dh/dh_group_params.c",
        "dh/dh_check.c",
        "dh/dh_backend.c",
        "dh/dh_gen.c",
        "dh/dh_kdf.c",
        // source
        "dh/dh_asn1.c",
        "dh/dh_err.c",
        "dh/dh_ameth.c",
        "dh/dh_pmeth.c",
        "dh/dh_prn.c",
        "dh/dh_rfc5114.c",
        "dh/dh_meth.c",

        // openssl/crypto/ec/build.info
        // common
        "ec/ec_lib.c",
        "ec/ecp_smpl.c",
        "ec/ecp_mont.c",
        "ec/ecp_nist.c",
        "ec/ec_cvt.c",
        "ec/ec_mult.c", 
        "ec/ec_curve.c",
        "ec/ec_check.c", 
        "ec/ec_key.c",
        "ec/ec_kmeth.c",
        "ec/ecx_key.c",
        "ec/ec_asn1.c",        
        "ec/ec2_smpl.c",
        "ec/ecp_oct.c",
        "ec/ec2_oct.c",
        "ec/ec_oct.c",
        "ec/ecdh_ossl.c",        
        "ec/ecdsa_ossl.c",
        "ec/ecdsa_sign.c",
        "ec/ecdsa_vrf.c",
        "ec/curve25519.c",        
        "ec/curve448/f_generic.c",
        "ec/curve448/scalar.c",        
        "ec/curve448/curve448_tables.c",
        "ec/curve448/eddsa.c",
        "ec/curve448/curve448.c",        
        // $ECASM
        "ec/ec_backend.c",
        "ec/ecx_backend.c",
        "ec/ecdh_kdf.c",
        "ec/curve448/arch_64/f_impl64.c",        
        "ec/curve448/arch_32/f_impl32.c",
        // source
        "ec/ec_ameth.c",
        "ec/ec_pmeth.c",
        "ec/ecx_meth.c",
        "ec/ec_err.c",
        "ec/eck_prn.c",
        "ec/ec_deprecated.c",
        "ec/ec_print.c",

        // openssl/crypto/dsa/build.info
        // common
        "dsa/dsa_sign.c",
        "dsa/dsa_vrf.c",
        "dsa/dsa_lib.c",
        "dsa/dsa_ossl.c",
        "dsa/dsa_check.c",
        "dsa/dsa_key.c",
        "dsa/dsa_backend.c",
        "dsa/dsa_gen.c",
        // source
        "dsa/dsa_asn1.c",
        "dsa/dsa_err.c",
        "dsa/dsa_ameth.c",
        "dsa/dsa_pmeth.c",
        "dsa/dsa_prn.c",
        "dsa/dsa_meth.c",

        // openssl/crypto/rsa/build.info
        // common
        "rsa/rsa_ossl.c",
        "rsa/rsa_gen.c",
        "rsa/rsa_lib.c",
        "rsa/rsa_sign.c",
        "rsa/rsa_pk1.c",
        "rsa/rsa_none.c",
        "rsa/rsa_oaep.c",
        "rsa/rsa_chk.c",
        "rsa/rsa_pss.c",
        "rsa/rsa_x931.c",
        "rsa/rsa_crpt.c",
        "rsa/rsa_sp800_56b_gen.c",
        "rsa/rsa_sp800_56b_check.c",
        "rsa/rsa_backend.c",
        "rsa/rsa_mp_names.c",
        "rsa/rsa_schemes.c",
        // source
        "rsa/rsa_saos.c",
        "rsa/rsa_err.c",
        "rsa/rsa_asn1.c",
        "rsa/rsa_ameth.c",
        "rsa/rsa_prn.c",
        "rsa/rsa_pmeth.c",
        "rsa/rsa_meth.c",
        "rsa/rsa_mp.c",

        // openssl/crypto/pkcs7/build.info
        "pkcs7/pk7_asn1.c",
        "pkcs7/pk7_lib.c",
        "pkcs7/pkcs7err.c",
        "pkcs7/pk7_doit.c",
        "pkcs7/pk7_smime.c",
        "pkcs7/pk7_attr.c",
        "pkcs7/pk7_mime.c",
        "pkcs7/bio_pk7.c",

        // openssl/crypto/pkcs12/build.info
        "pkcs12/p12_add.c",
        "pkcs12/p12_asn.c",
        "pkcs12/p12_attr.c",
        "pkcs12/p12_crpt.c",
        "pkcs12/p12_crt.c",
        "pkcs12/p12_decr.c",
        "pkcs12/p12_init.c",
        "pkcs12/p12_key.c",
        "pkcs12/p12_kiss.c",
        "pkcs12/p12_mutl.c",
        "pkcs12/p12_sbag.c",
        "pkcs12/p12_utl.c",
        "pkcs12/p12_npas.c",
        "pkcs12/pk12err.c",
        "pkcs12/p12_p8d.c",
        "pkcs12/p12_p8e.c",

        // openssl/crypto/ocsp/build.info
        "ocsp/ocsp_asn.c",
        "ocsp/ocsp_ext.c",
        "ocsp/ocsp_http.c",
        "ocsp/ocsp_lib.c",
        "ocsp/ocsp_cl.c",
        "ocsp/ocsp_srv.c",
        "ocsp/ocsp_prn.c",
        "ocsp/ocsp_vfy.c",
        "ocsp/ocsp_err.c",
        "ocsp/v3_ocsp.c",

        // openssl/crypto/stack/build.info
        "stack/stack.c",

        // openssl/crypto/bn/build.info
        // common
        "bn/bn_add.c",
        "bn/bn_div.c",
        "bn/bn_exp.c",
        "bn/bn_lib.c",
        "bn/bn_ctx.c",
        "bn/bn_mul.c",
        "bn/bn_mod.c",
        "bn/bn_conv.c",
        "bn/bn_rand.c",
        "bn/bn_shift.c",
        "bn/bn_word.c",
        "bn/bn_blind.c",
        "bn/bn_kron.c",
        "bn/bn_sqrt.c",
        "bn/bn_gcd.c",
        "bn/bn_prime.c",
        "bn/bn_sqr.c",
        "bn/bn_recp.c",
        "bn/bn_mont.c",
        "bn/bn_mpi.c",
        "bn/bn_exp2.c",
        "bn/bn_gf2m.c",
        "bn/bn_nist.c",
        "bn/bn_intern.c",
        "bn/bn_dh.c",
        "bn/bn_rsa_fips186_4.c",
        "bn/bn_const.c",
        // $BNASM
        "bn/bn_asm.c",
        // source
        "bn/bn_print.c",
        "bn/bn_err.c",
        "bn/bn_srp.c", // SRP is deprecated in openssl v3.0

        // openssl/crypto/comp/build.info
        "comp/comp_lib.c",
        "comp/comp_err.c",
        "comp/c_zlib.c",

        // openssl/crypto/ct/build.info
        "ct/ct_b64.c",
        "ct/ct_err.c",
        "ct/ct_log.c",
        "ct/ct_oct.c",
        "ct/ct_policy.c",
        "ct/ct_prn.c",
        "ct/ct_sct.c",
        "ct/ct_sct_ctx.c",
        "ct/ct_vfy.c",
        "ct/ct_x509v3.c",

        // openssl/crypto/async/build.info
        "async/async.c",
        "async/async_wait.c",
        "async/async_err.c",
        "async/arch/async_posix.c",
        "async/arch/async_win.c",
        "async/arch/async_null.c",

        // openssl/crypto/rand/build.info
        // common
        "rand/rand_lib.c",
        // crypto
        "rand/randfile.c",
        "rand/rand_err.c",
        "rand/rand_deprecated.c",
        "rand/prov_seed.c",
        "rand/rand_pool.c",

        // openssl/crypto/md5/build.info
        // common
        "md5/md5_dgst.c",
        "md5/md5_one.c",
        "md5/md5_sha1.c",
        //$MD5ASM

        // openssl/crypto/poly1305/build.info
        "poly1305/poly1305.c",
        //$POLY1305ASM

        // openssl/crypto/chacha/build.info
        "chacha/chacha_enc.c",
        //$CHACHAASM

        // openssl/crypto/aria/build.info
        "aria/aria.c",

        // openssl/crypto/modes/build.info
        // common
        "modes/cbc128.c",
        "modes/ctr128.c",
        "modes/cfb128.c",
        "modes/ofb128.c",
        "modes/gcm128.c",
        "modes/ccm128.c",
        "modes/xts128.c",
        "modes/wrap128.c",
        // $MODESASM
        // source
        "modes/cts128.c",
        "modes/ocb128.c",
        "modes/siv128.c",

        // openssl/crypto/aes/build.info
        // AESASM
        "aes/aes_core.c",
        "aes/aes_cbc.c",
        // common
        "aes/aes_misc.c",
        "aes/aes_ecb.c",
        // source
        "aes/aes_cfb.c",
        "aes/aes_ofb.c",
        "aes/aes_wrap.c",

        // openssl/crypto/cast/build.info
        // CASTASM
        "cast/c_enc.c",
        // source
        "cast/c_skey.c",
        "cast/c_ecb.c",
        "cast/c_cfb64.c",
        "cast/c_ofb64.c",

        // openssl/crypto/bf/build.info
        // BFASM
        "bf/bf_enc.c",
        // source
        "bf/bf_skey.c",
        "bf/bf_ecb.c",
        "bf/bf_cfb64.c",
        "bf/bf_ofb64.c",

        // openssl/crypto/rc2/build.info
        // "rc2/rc2_ecb.c",
        // "rc2/rc2_skey.c",
        // "rc2/rc2_cbc.c",
        // "rc2/rc2cfb64.c",
        // "rc2/rc2ofb64.c",

        // openssl/crypto/sm4/build.info
        "sm4/sm4.c",

        // openssl/crypto/camellia/build.info
        // CMLLASM
        "camellia/camellia.c",
        "camellia/cmll_misc.c",
        "camellia/cmll_cbc.c",
        // source
        "camellia/cmll_ecb.c",
        "camellia/cmll_ofb.c",
        "camellia/cmll_cfb.c",
        "camellia/cmll_ctr.c",

        // openssl/crypto/ess/build.info
        "ess/ess_asn1.c",
        "ess/ess_err.c",
        "ess/ess_lib.c",

        // openssl/crypto/cmp/build.info
        "cmp/cmp_asn.c",
        "cmp/cmp_ctx.c",
        "cmp/cmp_err.c",
        "cmp/cmp_util.c",
        "cmp/cmp_status.c",
        "cmp/cmp_hdr.c",
        "cmp/cmp_protect.c",
        "cmp/cmp_msg.c",
        "cmp/cmp_vfy.c",
        "cmp/cmp_server.c",
        "cmp/cmp_client.c",
        "cmp/cmp_http.c",

        // openssl/crypto/crmf/build.info
        "crmf/crmf_asn.c",
        "crmf/crmf_err.c",
        "crmf/crmf_lib.c",
        "crmf/crmf_pbm.c",

        // openssl/crypto/cms/build.info
        "cms/cms_lib.c",
        "cms/cms_asn1.c",
        "cms/cms_att.c",
        "cms/cms_io.c",
        "cms/cms_smime.c",
        "cms/cms_err.c",
        "cms/cms_sd.c",
        "cms/cms_dd.c",
        "cms/cms_cd.c",
        "cms/cms_env.c",
        "cms/cms_enc.c",
        "cms/cms_ess.c",
        "cms/cms_pwri.c",
        "cms/cms_kari.c",
        "cms/cms_rsa.c",
        "cms/cms_dh.c",
        "cms/cms_ec.c",

        // openssl/crypto/ui/build.info
        "ui/ui_err.c",
        "ui/ui_lib.c",
        "ui/ui_openssl.c",
        "ui/ui_null.c",
        "ui/ui_util.c",

        // openssl/crypto/http/build.info
        "http/http_client.c",
        "http/http_err.c",
        "http/http_lib.c",

        // openssl/crypto/ts/build.info
        "ts/ts_err.c",
        "ts/ts_req_utils.c",
        "ts/ts_req_print.c",
        "ts/ts_rsp_utils.c",
        "ts/ts_rsp_print.c",
        "ts/ts_rsp_sign.c",
        "ts/ts_rsp_verify.c",
        "ts/ts_verify_ctx.c",
        "ts/ts_lib.c",
        "ts/ts_conf.c",
        "ts/ts_asn1.c",

        // openssl/crypto/dso/build.info
        "dso/dso_dl.c",
        "dso/dso_dlfcn.c",
        "dso/dso_err.c",
        "dso/dso_lib.c",
        "dso/dso_openssl.c",
        "dso/dso_win32.c",
        "dso/dso_vms.c",

        // openssl/crypto/ffc/build.info
        "ffc/ffc_params.c",
        "ffc/ffc_params_generate.c",
        "ffc/ffc_key_generate.c",
        "ffc/ffc_params_validate.c",
        "ffc/ffc_key_validate.c",
        "ffc/ffc_backend.c",
        "ffc/ffc_dh.c",

        // openssl/crypto/sha/build.info
        // KECCAK1600ASM
        "sha/keccak1600.c",
        // SHA1ASM
        // source
        "sha/sha1dgst.c",
        "sha/sha256.c",
        "sha/sha512.c",
        "sha/sha3.c",
        "sha/sha1_one.c",

        // openssl/crypto/siphash/build.info
        "siphash/siphash.c",
    };
    for (c_files) |file| {
        addCSourceFileFmt(b, lib, "./vendor/openssl/crypto/{s}", .{file}, c_flags.items);
    }

    // cpuid common (openssl/crypto/build.info)
    try c_flags.append("-DOPENSSL_CPUID_OBJ");
    if (target.getCpuArch() == .x86_64) {
        lib.addCSourceFile("./vendor/openssl/crypto/x86_64cpuid.s", c_flags.items);
    }
    lib.addCSourceFile("./vendor/openssl/crypto/cpuid.c", c_flags.items);
    lib.addCSourceFile("./vendor/openssl/crypto/ctype.c", c_flags.items);

    const digest_cfiles = &[_][]const u8{
        // openssl/providers/implementations/digests/build.info
        // common
        "implementations/digests/digestcommon.c",
        "implementations/digests/null_prov.c",
        "implementations/digests/sha2_prov.c",
        "implementations/digests/sha3_prov.c",
        "implementations/digests/md5_prov.c",
        "implementations/digests/md5_sha1_prov.c",

        // openssl/providers/implementations/kdfs/build.info
        "implementations/kdfs/tls1_prf.c",
        "implementations/kdfs/hkdf.c",
        "implementations/kdfs/kbkdf.c",
        "implementations/kdfs/krb5kdf.c",
        "implementations/kdfs/pbkdf1.c",
        "implementations/kdfs/pbkdf2.c",
        "implementations/kdfs/pbkdf2_fips.c",
        "implementations/kdfs/pkcs12kdf.c",
        "implementations/kdfs/sskdf.c",
        "implementations/kdfs/sshkdf.c",
        "implementations/kdfs/x942kdf.c",
        "implementations/kdfs/scrypt.c",

        // openssl/providers/implementations/macs/build.info
        "implementations/macs/gmac_prov.c",
        "implementations/macs/hmac_prov.c",
        "implementations/macs/kmac_prov.c",
        "implementations/macs/siphash_prov.c",
        "implementations/macs/poly1305_prov.c",

        // openssl/providers/implementations/rands/build.info
        "implementations/rands/drbg.c",
        "implementations/rands/test_rng.c",
        "implementations/rands/drbg_ctr.c",
        "implementations/rands/drbg_hash.c",
        "implementations/rands/drbg_hmac.c",
        "implementations/rands/crngt.c",
        "implementations/rands/seed_src.c",

        // openssl/providers/implementations/rands/seedings/build.info
        "implementations/rands/seeding/rand_unix.c",
        "implementations/rands/seeding/rand_win.c",
        "implementations/rands/seeding/rand_tsc.c",

        // openssl/providers/common/build.info
        "common/provider_util.c",
        "common/capabilities.c",
        "common/bio_prov.c",
        "common/digest_to_nid.c",
        "common/securitycheck.c",
        "common/provider_seeding.c",
        "common/provider_err.c",
        "common/provider_ctx.c",
        "common/securitycheck_fips.c",

        // openssl/providers/common/der/build.info
        // DER_RSA_COMMON
        "common/der/der_rsa_gen.c",
        "common/der/der_rsa_key.c",
        "common/der/der_rsa_sig.c",
        "common/der/der_ecx_gen.c",
        "common/der/der_ecx_key.c",
        "common/der/der_dsa_gen.c",
        "common/der/der_dsa_sig.c",
        "common/der/der_ec_gen.c",
        "common/der/der_ec_sig.c",
        "common/der/der_wrap_gen.c",

        // openssl/providers/implementations/exchange/build.info
        "implementations/exchange/dh_exch.c",
        "implementations/exchange/ecdh_exch.c",
        "implementations/exchange/ecx_exch.c",
        "implementations/exchange/kdf_exch.c",

        // openssl/providers/implementations/keymgmt/build.info
        "implementations/keymgmt/dh_kmgmt.c",
        "implementations/keymgmt/dsa_kmgmt.c",
        "implementations/keymgmt/ec_kmgmt.c",
        "implementations/keymgmt/ecx_kmgmt.c",
        "implementations/keymgmt/rsa_kmgmt.c",
        "implementations/keymgmt/kdf_legacy_kmgmt.c",
        "implementations/keymgmt/mac_legacy_kmgmt.c",

        // openssl/providers/implementations/encode_decode/build.info
        // encoder
        "implementations/encode_decode/endecoder_common.c",
        "implementations/encode_decode/encode_key2any.c",
        "implementations/encode_decode/encode_key2text.c",
        "implementations/encode_decode/encode_key2ms.c",
        "implementations/encode_decode/encode_key2blob.c",
        // decoder
        "implementations/encode_decode/decode_der2key.c",
        "implementations/encode_decode/decode_epki2pki.c",
        "implementations/encode_decode/decode_pem2der.c",
        "implementations/encode_decode/decode_msblob2key.c",
        "implementations/encode_decode/decode_pvk2key.c",
        "implementations/encode_decode/decode_spki2typespki.c",

        // openssl/providers/build.info
        "nullprov.c",
        "prov_running.c",
        "baseprov.c",
        "defltprov.c",

        // openssl/providers/implementations/ciphers/build.info
        // common
        "implementations/ciphers/ciphercommon.c",
        "implementations/ciphers/ciphercommon_hw.c",
        "implementations/ciphers/ciphercommon_block.c",
        "implementations/ciphers/ciphercommon_gcm.c",
        "implementations/ciphers/ciphercommon_gcm_hw.c",
        "implementations/ciphers/ciphercommon_ccm.c",
        "implementations/ciphers/ciphercommon_ccm_hw.c",
        "implementations/ciphers/cipher_null.c",
        // camellia
        "implementations/ciphers/cipher_camellia.c",
        "implementations/ciphers/cipher_camellia_hw.c",
        // aria
        "implementations/ciphers/cipher_aria.c",
        "implementations/ciphers/cipher_aria_hw.c",
        "implementations/ciphers/cipher_aria_gcm.c",
        "implementations/ciphers/cipher_aria_gcm_hw.c",
        "implementations/ciphers/cipher_aria_ccm.c",
        "implementations/ciphers/cipher_aria_ccm_hw.c",
        // chacha
        "implementations/ciphers/cipher_chacha20.c",
        "implementations/ciphers/cipher_chacha20_hw.c",
        "implementations/ciphers/cipher_chacha20_poly1305.c",
        "implementations/ciphers/cipher_chacha20_poly1305_hw.c",
        // sm4
        "implementations/ciphers/cipher_sm4.c",
        "implementations/ciphers/cipher_sm4_hw.c",
        "implementations/ciphers/cipher_sm4_gcm.c",
        "implementations/ciphers/cipher_sm4_gcm_hw.c",
        "implementations/ciphers/cipher_sm4_ccm.c",
        "implementations/ciphers/cipher_sm4_ccm_hw.c",
        // aes
        "implementations/ciphers/cipher_aes.c",
        "implementations/ciphers/cipher_aes_hw.c",
        "implementations/ciphers/cipher_aes_xts.c",
        "implementations/ciphers/cipher_aes_xts_hw.c",
        "implementations/ciphers/cipher_aes_gcm.c",
        "implementations/ciphers/cipher_aes_gcm_hw.c",
        "implementations/ciphers/cipher_aes_ccm.c",
        "implementations/ciphers/cipher_aes_ccm_hw.c",
        "implementations/ciphers/cipher_aes_wrp.c",
        "implementations/ciphers/cipher_aes_cbc_hmac_sha.c",
        "implementations/ciphers/cipher_aes_cbc_hmac_sha256_hw.c",
        "implementations/ciphers/cipher_aes_cbc_hmac_sha1_hw.c",
        "implementations/ciphers/cipher_cts.c",
        "implementations/ciphers/cipher_aes_xts_fips.c",
        "implementations/ciphers/cipher_aes_ocb.c",
        "implementations/ciphers/cipher_aes_ocb_hw.c",
        // siv
        "implementations/ciphers/cipher_aes_siv.c",
        "implementations/ciphers/cipher_aes_siv_hw.c",

        // openssl/providers/implementations/asymciphers/build.info
        "implementations/asymciphers/rsa_enc.c",

        // openssl/providers/implementations/kem/build.info
        "implementations/kem/rsa_kem.c",

        // openssl/providers/implementations/storemgmt/build.info
        "implementations/storemgmt/file_store.c",
        "implementations/storemgmt/file_store_any2obj.c",

        // openssl/providers/implementations/signature/build.info
        "implementations/signature/ecdsa_sig.c",
        "implementations/signature/dsa_sig.c",
        "implementations/signature/eddsa_sig.c",
        "implementations/signature/eddsa_sig.c",
        "implementations/signature/rsa_sig.c",
        "implementations/signature/mac_legacy_sig.c",
    };
    for (digest_cfiles) |file| {
        addCSourceFileFmt(b, lib, "./vendor/openssl/providers/{s}", .{file}, c_flags.items);
    }

    lib.disable_sanitize_c = true;

    lib.linkLibC();
    lib.addIncludeDir("./vendor/openssl/providers/implementations/include");
    lib.addIncludeDir("./vendor/openssl/providers/common/include");
    lib.addIncludeDir("./vendor/openssl/include");
    lib.addIncludeDir("./vendor/openssl");
    step.linkLibrary(lib);
}

pub fn buildLinkSsl(b: *Builder, step: *LibExeObjStep) void {
    if (UsePrebuiltOpenSSL) {
        step.addAssemblyFile("/home/linuxbrew/.linuxbrew/Cellar/openssl@3/3.0.1/lib/libssl.a");
        return;
    }

    // TODO: Don't build support for tls1.0 and tls1.1 https://github.com/openssl/openssl/issues/7048
    const lib = b.addStaticLibrary("ssl", null);
    
    const c_flags = &[_][]const u8{
        // Don't include deprecated.
        "-DOPENSSL_NO_DEPRECATED",

        // Engine api is deprecated in openssl v3.0
        "-DOPENSSL_NO_ENGINE",

        // SRP is deprecated in openssl v3.0
        "-DOPENSSL_NO_SRP",

        // Disable console related code.
        "-DOPENSSL_NO_UI_CONSOLE",
    };

    const c_files = &[_][]const u8{
        // Copied from openssl/ssl/build.info
        "pqueue.c",
        "statem/statem_srvr.c",
        "statem/statem_clnt.c",
        "s3_lib.c",
        "s3_enc.c",
        "record/rec_layer_s3.c",
        "statem/statem_lib.c",
        "statem/extensions.c",
        "statem/extensions_srvr.c",
        "statem/extensions_clnt.c",
        "statem/extensions_cust.c",
        "s3_msg.c",
        "methods.c",
        "t1_lib.c",
        "t1_enc.c",
        "tls13_enc.c",
        "d1_lib.c",
        "record/rec_layer_d1.c",
        "d1_msg.c",
        "statem/statem_dtls.c",
        "d1_srtp.c",
        "ssl_lib.c",
        "ssl_cert.c",
        "ssl_sess.c",
        "ssl_ciph.c",
        "ssl_stat.c",
        "ssl_rsa.c",
        "ssl_asn1.c",
        "ssl_txt.c",
        "ssl_init.c",
        "ssl_conf.c",
        "ssl_mcnf.c",
        "bio_ssl.c",
        "ssl_err.c",
        "ssl_err_legacy.c",
        "tls_srp.c",
        "t1_trce.c",
        "ssl_utst.c",
        "record/ssl3_buffer.c",
        "record/ssl3_record.c",
        "record/dtls1_bitmap.c",
        "statem/statem.c",
        "record/ssl3_record_tls13.c",
        "tls_depr.c",
        // shared
        "record/tls_pad.c",
        "s3_cbc.c",
    };
    for (c_files) |file| {
        addCSourceFileFmt(b, lib, "./vendor/openssl/ssl/{s}", .{file}, c_flags);
    }

    lib.disable_sanitize_c = true;

    lib.linkLibC();
    // openssl headers need to be generated with:
    // ./Configure 
    // make build_all_generated
    lib.addIncludeDir("./vendor/openssl/include");
    lib.addIncludeDir("./vendor/openssl");
    step.linkLibrary(lib);
}

fn addCSourceFileFmt(b: *Builder, lib: *LibExeObjStep, comptime format: []const u8, args: anytype, c_flags: []const []const u8) void {
    const path = std.fmt.allocPrint(b.allocator, format, args) catch unreachable;
    lib.addCSourceFile(b.pathFromRoot(path), c_flags);
}