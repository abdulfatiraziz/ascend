package com.abdul.ascend.bridge;

import java.awt.Color;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.net.InetAddress;
import java.nio.charset.StandardCharsets;
import java.security.KeyPair;
import java.security.PublicKey;
import java.util.*;
import javax.imageio.ImageIO;

/**
 * Plays the phone against the real Mac PhoneLinkServer (run by AscendChecks with ASCEND_JAVA_INTEROP).
 * Prints CODE, PAIRED, SYNC, MEAL, REPLAY and BADKEY lines that the Swift check verifies.
 */
public final class InteropMain {
    static final String KINDS = "\"heartRate\",\"steps\",\"sleep\",\"oxygen\",\"distance\",\"activeEnergy\",\"speed\",\"elevation\",\"workout\"";
    public static void main(String[] args) throws Exception {
        InetAddress host = InetAddress.getByName(args[0]);
        int port = Integer.parseInt(args[1]);
        String phoneID = UUID.randomUUID().toString();
        KeyPair pair = LinkCrypto.newKeyPair();
        String start = "{\"phoneID\":\"" + phoneID + "\",\"phoneName\":\"Interop Pixel\",\"phoneKey\":\"" + LinkCrypto.encode(pair.getPublic()) + "\"}";
        LinkClient.Response r = LinkClient.post(host, port, "/pair/start", Map.of(), start.getBytes(StandardCharsets.UTF_8), 5000);
        if (r.status != 200) throw new IllegalStateException("pair/start " + r.status + " " + r.text());
        String macKey = field(r.text(), "macKey");
        PublicKey mac = LinkCrypto.decode(macKey);
        byte[] key = LinkCrypto.sessionKey(pair.getPrivate(), pair.getPublic(), mac);
        System.out.println("CODE " + LinkCrypto.pairingCode(mac, pair.getPublic()));
        Map<String, String> headers = Map.of("X-Ascend-Phone", phoneID);
        for (int i = 0; ; i++) {
            if (i > 50) throw new IllegalStateException("pairing never confirmed");
            byte[] probe = LinkCrypto.seal(envelope("pair", "").getBytes(StandardCharsets.UTF_8), key);
            r = LinkClient.post(host, port, "/pair/confirm", headers, probe, 5000);
            if (r.status == 200) { System.out.println("PAIRED " + new String(LinkCrypto.open(r.body, key), StandardCharsets.UTF_8)); break; }
            if (r.status != 202) throw new IllegalStateException("pair/confirm " + r.status + " " + r.text());
            Thread.sleep(100);
        }
        long now = System.currentTimeMillis() / 1000;
        String snapshot = "\"snapshot\":{\"version\":1,\"requestID\":\"" + UUID.randomUUID() + "\",\"generatedAt\":" + now + ",\"rangeStart\":" + (now - 86400)
            + ",\"rangeEnd\":" + now + ",\"sourcePackage\":\"com.xiaomi.wearable\",\"permissions\":{" + KINDS.replace("\",", "\":true,") + ":true},\"errors\":{},"
            + "\"records\":[{\"id\":\"hr-interop:0\",\"metric\":\"heartRate\",\"start\":" + (now - 600) + ",\"end\":" + (now - 600) + ",\"value\":72,\"detail\":\"\",\"device\":\"\"}]}";
        System.out.println("SYNC " + send(host, port, "/v1/sync", headers, key, envelope("sync", "," + snapshot)));
        BufferedImage image = new BufferedImage(64, 64, BufferedImage.TYPE_INT_RGB);
        java.awt.Graphics2D g = image.createGraphics(); g.setColor(Color.RED); g.fillRect(0, 0, 64, 64); g.dispose();
        ByteArrayOutputStream jpeg = new ByteArrayOutputStream(); ImageIO.write(image, "jpg", jpeg);
        String meal = ",\"meal\":{\"id\":\"" + UUID.randomUUID() + "\",\"takenAt\":" + (now - 60) + ",\"note\":\"2 rotis, dal\",\"mediaType\":\"image/jpeg\",\"image\":\""
            + Base64.getEncoder().encodeToString(jpeg.toByteArray()) + "\"}";
        String mealEnvelope = envelope("meal", meal);
        System.out.println("MEAL " + send(host, port, "/v1/meal", headers, key, mealEnvelope));
        System.out.println("REPLAY " + send(host, port, "/v1/meal", headers, key, mealEnvelope));
        String urge = ",\"urge\":{\"id\":\"" + UUID.randomUUID() + "\",\"takenAt\":" + (now - 30) + ",\"outcome\":\"Acted on it\",\"intensity\":3,\"trigger\":\"Stress\",\"note\":\"late night\"}";
        String medPhoto = ",\"medPhoto\":{\"id\":\"" + UUID.randomUUID() + "\",\"batch\":\"" + UUID.randomUUID() + "\",\"batchSize\":2,\"takenAt\":" + (now - 40)
            + ",\"mediaType\":\"image/jpeg\",\"image\":\"" + Base64.getEncoder().encodeToString(jpeg.toByteArray()) + "\"}";
        System.out.println("MEDPHOTO " + send(host, port, "/v1/medphoto", headers, key, envelope("medphoto", medPhoto)));
        String dose = ",\"dose\":{\"id\":\"" + UUID.randomUUID() + "\",\"medID\":\"" + UUID.randomUUID() + "\",\"day\":\"2026-10-20\",\"minute\":540,\"takenAt\":" + (now - 5) + ".5,\"taken\":true}";
        System.out.println("DOSE " + send(host, port, "/v1/dose", headers, key, envelope("dose", dose)));
        System.out.println("URGE " + send(host, port, "/v1/urge", headers, key, envelope("urge", urge)));
        byte[] wrong = new byte[32];
        r = LinkClient.post(host, port, "/v1/sync", headers, LinkCrypto.seal(envelope("sync", "").getBytes(StandardCharsets.UTF_8), wrong), 5000);
        System.out.println("BADKEY " + r.status);
    }
    static int counter = 0;
    static final String FIXED = UUID.randomUUID().toString();
    static String envelope(String kind, String extra) {
        String id = kind.equals("meal") ? FIXED : UUID.randomUUID().toString();
        return "{\"id\":\"" + id + "\",\"sentAt\":" + (System.currentTimeMillis() / 1000.0) + ",\"kind\":\"" + kind + "\"" + extra + "}";
    }
    static String send(InetAddress host, int port, String path, Map<String, String> headers, byte[] key, String json) throws Exception {
        LinkClient.Response r = LinkClient.post(host, port, path, headers, LinkCrypto.seal(json.getBytes(StandardCharsets.UTF_8), key), 10000);
        if (r.status != 200) return "status=" + r.status + " " + r.text();
        return new String(LinkCrypto.open(r.body, key), StandardCharsets.UTF_8);
    }
    static String field(String json, String name) {
        int at = json.indexOf("\"" + name + "\"");
        int colon = json.indexOf(':', at), open = json.indexOf('"', colon + 1), close = json.indexOf('"', open + 1);
        return json.substring(open + 1, close).replace("\\/", "/");
    }
}
