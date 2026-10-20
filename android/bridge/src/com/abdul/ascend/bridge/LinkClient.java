package com.abdul.ascend.bridge;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.Map;

/** One-request HTTP/1.1 client over a plain socket, limited to local-network addresses. Plain JDK only. */
public final class LinkClient {
    private LinkClient() {}
    public static final class Response {
        public final int status;
        public final byte[] body;
        Response(int status, byte[] body) { this.status = status; this.body = body; }
        public String text() { return new String(body, StandardCharsets.UTF_8); }
    }
    public static boolean isLocal(InetAddress address) {
        return address.isSiteLocalAddress() || address.isLinkLocalAddress() || address.isLoopbackAddress()
            || (address instanceof Inet6Address && (address.getAddress()[0] & 0xfe) == 0xfc);
    }
    public static Response post(InetAddress host, int port, String path, Map<String, String> headers, byte[] body, int timeoutMs) throws IOException {
        if (!isLocal(host)) throw new IOException("Refusing to send to a non-local address");
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(host, port), timeoutMs);
            socket.setSoTimeout(timeoutMs);
            StringBuilder head = new StringBuilder("POST ").append(path).append(" HTTP/1.1\r\nHost: ")
                .append(host.getHostAddress()).append("\r\nConnection: close\r\nContent-Type: application/octet-stream\r\nContent-Length: ").append(body.length).append("\r\n");
            for (Map.Entry<String, String> h : headers.entrySet()) head.append(h.getKey()).append(": ").append(h.getValue()).append("\r\n");
            head.append("\r\n");
            OutputStream out = new BufferedOutputStream(socket.getOutputStream());
            out.write(head.toString().getBytes(StandardCharsets.UTF_8));
            out.write(body);
            out.flush();
            InputStream in = new BufferedInputStream(socket.getInputStream());
            ByteArrayOutputStream all = new ByteArrayOutputStream();
            byte[] buffer = new byte[16384];
            for (int n; (n = in.read(buffer)) != -1; ) {
                all.write(buffer, 0, n);
                if (all.size() > 2_000_000) throw new IOException("Response too large");
            }
            byte[] data = all.toByteArray();
            int split = -1;
            for (int i = 0; i + 3 < data.length; i++) if (data[i] == '\r' && data[i + 1] == '\n' && data[i + 2] == '\r' && data[i + 3] == '\n') { split = i; break; }
            if (split < 0) throw new IOException("Malformed response");
            String[] lines = new String(data, 0, split, StandardCharsets.ISO_8859_1).split("\r\n");
            String[] status = lines[0].split(" ");
            if (status.length < 2) throw new IOException("Malformed status");
            int code = Integer.parseInt(status[1]);
            byte[] payload = java.util.Arrays.copyOfRange(data, split + 4, data.length);
            return new Response(code, payload);
        }
    }
}
