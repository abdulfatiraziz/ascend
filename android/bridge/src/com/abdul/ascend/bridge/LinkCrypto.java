package com.abdul.ascend.bridge;

import java.nio.charset.StandardCharsets;
import java.security.*;
import java.security.spec.X509EncodedKeySpec;
import java.util.Arrays;
import java.util.Base64;
import javax.crypto.Cipher;
import javax.crypto.KeyAgreement;
import javax.crypto.Mac;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/**
 * Mirrors PhoneLinkCrypto on the Mac: X25519 key agreement, HKDF-SHA256 (salt "ascend-link-v1",
 * info = mac key ‖ phone key) and AES-256-GCM sealed as nonce ‖ ciphertext ‖ tag.
 * Plain JDK APIs only, so the same class runs on Android and in the Mac interop check.
 */
public final class LinkCrypto {
    private LinkCrypto() {}
    private static final SecureRandom RANDOM = new SecureRandom();

    static KeyPairGenerator generator() throws GeneralSecurityException {
        try { return KeyPairGenerator.getInstance("X25519"); } catch (NoSuchAlgorithmException e) { return KeyPairGenerator.getInstance("XDH"); }
    }
    static KeyFactory factory() throws GeneralSecurityException {
        try { return KeyFactory.getInstance("X25519"); } catch (NoSuchAlgorithmException e) { return KeyFactory.getInstance("XDH"); }
    }
    static KeyAgreement agreement() throws GeneralSecurityException {
        try { return KeyAgreement.getInstance("X25519"); } catch (NoSuchAlgorithmException e) { return KeyAgreement.getInstance("XDH"); }
    }
    public static KeyPair newKeyPair() throws GeneralSecurityException { return generator().generateKeyPair(); }
    /** X.509 SubjectPublicKeyInfo, base64. */
    public static String encode(PublicKey key) { return Base64.getEncoder().encodeToString(key.getEncoded()); }
    static byte[] raw(byte[] x509) {
        if (x509.length != 44) throw new IllegalArgumentException("Unexpected X25519 key length");
        return Arrays.copyOfRange(x509, 12, 44);
    }
    public static PublicKey decode(String base64) throws GeneralSecurityException {
        return factory().generatePublic(new X509EncodedKeySpec(Base64.getDecoder().decode(base64)));
    }
    public static byte[] sessionKey(PrivateKey phonePrivate, PublicKey phonePublic, PublicKey macPublic) throws GeneralSecurityException {
        KeyAgreement agreement = agreement();
        agreement.init(phonePrivate);
        agreement.doPhase(macPublic, true);
        byte[] shared = agreement.generateSecret();
        return hkdf(shared, "ascend-link-v1".getBytes(StandardCharsets.UTF_8), concat(raw(macPublic.getEncoded()), raw(phonePublic.getEncoded())));
    }
    public static String pairingCode(PublicKey macPublic, PublicKey phonePublic) throws GeneralSecurityException {
        MessageDigest sha = MessageDigest.getInstance("SHA-256");
        sha.update("ascend-code-v1".getBytes(StandardCharsets.UTF_8));
        sha.update(raw(macPublic.getEncoded()));
        sha.update(raw(phonePublic.getEncoded()));
        byte[] d = sha.digest();
        long n = ((d[0] & 0xffL) << 24 | (d[1] & 0xffL) << 16 | (d[2] & 0xffL) << 8 | (d[3] & 0xffL)) % 1_000_000L;
        return String.format("%06d", n);
    }
    static byte[] hkdf(byte[] ikm, byte[] salt, byte[] info) throws GeneralSecurityException {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(salt, "HmacSHA256"));
        byte[] prk = mac.doFinal(ikm);
        mac.init(new SecretKeySpec(prk, "HmacSHA256"));
        mac.update(info);
        mac.update((byte) 1);
        return mac.doFinal();
    }
    public static byte[] seal(byte[] plain, byte[] key) throws GeneralSecurityException {
        byte[] nonce = new byte[12];
        RANDOM.nextBytes(nonce);
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(key, "AES"), new GCMParameterSpec(128, nonce));
        return concat(nonce, cipher.doFinal(plain));
    }
    public static byte[] open(byte[] sealed, byte[] key) throws GeneralSecurityException {
        if (sealed.length < 28) throw new GeneralSecurityException("Sealed data too short");
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, new SecretKeySpec(key, "AES"), new GCMParameterSpec(128, sealed, 0, 12));
        return cipher.doFinal(sealed, 12, sealed.length - 12);
    }
    static byte[] concat(byte[] a, byte[] b) {
        byte[] out = Arrays.copyOf(a, a.length + b.length);
        System.arraycopy(b, 0, out, a.length, b.length);
        return out;
    }
}
