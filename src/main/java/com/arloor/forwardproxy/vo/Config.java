package com.arloor.forwardproxy.vo;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.stream.Collectors;

public class Config {
    private static final Logger log = LoggerFactory.getLogger(Config.class);
    private static final String TRUE = "true";

    public static boolean ask4Authcate = false;
    private static final String POUND_SIGN = "\u00A3";  // £

    private SslConfig sslConfig;
    private HttpConfig httpConfig;

    public SslConfig ssl() {
        return sslConfig;
    }

    public HttpConfig http() {
        return httpConfig;
    }

    /**
     * 安全地获取配置值，自动trim前后空格
     */
    private static String getProperty(Properties properties, String key) {
        String value = properties.getProperty(key);
        return value != null ? value.trim() : null;
    }

    public static Config parse(Properties properties) {

        Config config = new Config();
        String ask4AuthcateValue = getProperty(properties, "ask4Authcate");
        ask4Authcate = TRUE.equals(ask4AuthcateValue);
        log.info("解析配置 - ask4Authcate: {} (原始值: {})", ask4Authcate, ask4AuthcateValue);

        String httpsEnable = getProperty(properties, "https.enable");
        log.info("解析配置 - https.enable: {} (原始值: {})", httpsEnable, properties.getProperty("https.enable"));
        if (TRUE.equals(httpsEnable)) {
            try {
                String httpsPortStr = getProperty(properties, "https.port");
                log.info("解析配置 - https.port: {}", httpsPortStr);
                Integer port = Integer.parseInt(httpsPortStr);
                String auth = getProperty(properties, "https.auth");
                log.info("解析配置 - https.auth: {}", auth != null ? "已配置" : "未配置");
                Map<String, String> users = new HashMap<>();
                if (auth != null && auth.length() != 0) {
                    for (String user : auth.split(",")) {
                        String trimmedUser = user.trim();
                        if (trimmedUser.length() > 0) {
                            users.computeIfAbsent(genBasicAuth(trimmedUser), (cell) -> trimmedUser);
                            users.computeIfAbsent(genBasicAuthWithOut£(trimmedUser), (cell) -> trimmedUser);
                        }
                    }
                }
                String fullchain = getProperty(properties, "https.fullchain.pem");
                String privkey = getProperty(properties, "https.privkey.pem");
                log.info("解析配置 - https.fullchain.pem: {}, https.privkey.pem: {}", fullchain, privkey);
                SslConfig sslConfig = new SslConfig(port, users, fullchain, privkey);
                config.sslConfig = sslConfig;
                log.info("HTTPS配置解析成功 - 端口: {}, 需要认证: {}", port, sslConfig.needAuth());
            } catch (Exception e) {
                log.error("解析HTTPS配置失败", e);
            }
        } else {
            log.info("HTTPS代理未启用 - 原因: http.enable的值不是'true' (实际值: '{}')", httpsEnable);
        }

        String httpEnable = getProperty(properties, "http.enable");
        log.info("解析配置 - http.enable: {} (原始值: '{}')", httpEnable, properties.getProperty("http.enable"));
        if (TRUE.equals(httpEnable)) {
            try {
                String httpPortStr = getProperty(properties, "http.port");
                log.info("解析配置 - http.port: {}", httpPortStr);
                Integer port = Integer.parseInt(httpPortStr);
                String auth = getProperty(properties, "http.auth");
                log.info("解析配置 - http.auth: {}", auth != null ? "已配置" : "未配置");
                Map<String, String> users = new HashMap<>();
                if (auth != null && auth.length() != 0) {
                    for (String user : auth.split(",")) {
                        String trimmedUser = user.trim();
                        if (trimmedUser.length() > 0) {
                            users.computeIfAbsent(genBasicAuth(trimmedUser), (cell) -> trimmedUser);
                            users.computeIfAbsent(genBasicAuthWithOut£(trimmedUser), (cell) -> trimmedUser);
                        }
                    }
                }
                String whiteDomains = getProperty(properties, "http.proxy.white.domain");
                if (whiteDomains == null) {
                    whiteDomains = "";
                }
                log.info("解析配置 - http.proxy.white.domain: {}", whiteDomains);
                config.httpConfig = new HttpConfig(port, users, Arrays.stream(whiteDomains.split(",")).filter(s -> s != null && s.trim().length() != 0).map(String::trim).collect(Collectors.toSet()));
                log.info("HTTP配置解析成功 - 端口: {}, 需要认证: {}", port, config.httpConfig.needAuth());
            } catch (Exception e) {
                log.error("解析HTTP配置失败", e);
            }
        } else {
            log.info("HTTP代理未启用 - 原因: http.enable的值不是'true' (实际值: '{}')", httpEnable);
        }

        log.info("配置解析完成 - HTTP配置: {}, HTTPS配置: {}", config.httpConfig != null ? "已创建" : "未创建", config.sslConfig != null ? "已创建" : "未创建");
        return config;
    }

    /**
     * https://datatracker.ietf.org/doc/html/rfc7617
     * The user's name is "test", and the password is the string "123"
     * followed by the Unicode character U+00A3 (POUND SIGN).  Using the
     * character encoding scheme UTF-8, the user-pass becomes:
     * <p>
     * 't' 'e' 's' 't' ':' '1' '2' '3' pound
     * 74  65  73  74  3A  31  32  33  C2  A3
     * <p>
     * Encoding this octet sequence in Base64 ([RFC4648], Section 4) yields:
     * <p>
     * dGVzdDoxMjPCow==
     *
     * @param user
     * @return
     */
    private static String genBasicAuth(String user) {
        user += POUND_SIGN;
        return "Basic " + Base64.getEncoder().encodeToString(user.getBytes(StandardCharsets.UTF_8));
    }


    private static String genBasicAuthWithOut£(String user) {
        return "Basic " + Base64.getEncoder().encodeToString(user.getBytes(StandardCharsets.UTF_8));
    }


}