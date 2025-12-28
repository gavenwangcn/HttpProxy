package com.arloor.forwardproxy;

import com.arloor.forwardproxy.handler.HttpProxyServerInitializer;
import com.arloor.forwardproxy.handler.HttpsProxyServerInitializer;
import com.arloor.forwardproxy.util.OsUtils;
import com.arloor.forwardproxy.vo.Config;
import com.arloor.forwardproxy.vo.HttpConfig;
import com.arloor.forwardproxy.vo.SslConfig;
import io.netty.bootstrap.ServerBootstrap;
import io.netty.channel.Channel;
import io.netty.channel.ChannelOption;
import io.netty.channel.EventLoopGroup;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.File;
import java.io.FileReader;
import java.util.Properties;
import java.util.concurrent.TimeUnit;

public final class HttpProxyServer {

    private static final Logger log = LoggerFactory.getLogger(HttpProxyServer.class);

    public static void main(String[] args) {
        String propertiesPath = null;
        if (args.length == 2 && args[0].equals("-c")) {
            propertiesPath = args[1];
        }
        Properties properties = parseProperties(propertiesPath);

        Config config = Config.parse(properties);
        log.info("主动要求验证：" + Config.ask4Authcate);
        SslConfig sslConfig = config.ssl();
        HttpConfig httpConfig = config.http();
        
        log.info("配置检查 - SSL配置: {}, HTTP配置: {}", sslConfig != null ? "已创建" : "未创建", httpConfig != null ? "已创建" : "未创建");

        EventLoopGroup bossGroup = OsUtils.buildEventLoopGroup(1);
        EventLoopGroup workerGroup = OsUtils.buildEventLoopGroup(0);
        try {
            if (sslConfig != null && httpConfig != null) {
                log.info("同时启动HTTPS和HTTP代理服务");
                Channel sslChannel = startSSl(bossGroup, workerGroup, sslConfig);
                Channel httpChannel = startHttp(bossGroup, workerGroup, httpConfig);
                if (httpChannel != null) {
                    log.info("HTTP代理服务已启动，等待关闭...");
                    httpChannel.closeFuture().sync();
                } else {
                    log.warn("HTTP代理服务启动失败");
                }
                if (sslChannel != null) {
                    log.info("HTTPS代理服务已启动，等待关闭...");
                    sslChannel.closeFuture().sync();
                } else {
                    log.warn("HTTPS代理服务启动失败");
                }
            } else if (sslConfig != null) {
                log.info("仅启动HTTPS代理服务");
                Channel sslChannel = startSSl(bossGroup, workerGroup, sslConfig);
                if (sslChannel != null) {
                    log.info("HTTPS代理服务已启动，等待关闭...");
                    sslChannel.closeFuture().sync();
                } else {
                    log.warn("HTTPS代理服务启动失败");
                }
            } else if (httpConfig != null) {
                log.info("仅启动HTTP代理服务");
                Channel httpChannel = startHttp(bossGroup, workerGroup, httpConfig);
                if (httpChannel != null) {
                    log.info("HTTP代理服务已启动，等待关闭...");
                    httpChannel.closeFuture().sync();
                } else {
                    log.warn("HTTP代理服务启动失败");
                }
            } else {
                log.error("未配置任何代理服务（HTTP和HTTPS都未启用）");
            }
        } catch (InterruptedException e) {
            log.error("interrupt!", e);
        } finally {
            bossGroup.shutdownGracefully();
            workerGroup.shutdownGracefully();
        }
    }

    private static Properties parseProperties(String propertiesPath) {
        Properties properties = new Properties();
        try {
            if (propertiesPath != null) {
                log.info("从指定路径加载配置文件: {}", propertiesPath);
                File configFile = new File(propertiesPath);
                if (!configFile.exists()) {
                    log.error("配置文件不存在: {}", propertiesPath);
                } else {
                    log.info("配置文件存在，文件大小: {} bytes", configFile.length());
                }
                properties.load(new FileReader(configFile));
                log.info("配置文件加载成功，共 {} 个配置项", properties.size());
            } else {
                log.info("从classpath加载默认配置文件: proxy.properties");
                properties.load(HttpProxyServer.class.getClassLoader().getResourceAsStream("proxy.properties"));
                log.info("默认配置文件加载成功，共 {} 个配置项", properties.size());
            }
        } catch (Exception e) {
            log.error("加载配置文件失败 - 路径: {}", propertiesPath, e);
        }
        return properties;
    }


    public static Channel startHttp(EventLoopGroup bossGroup, EventLoopGroup workerGroup, HttpConfig httpConfig) {
        log.info("开始启动HTTP代理服务 - 端口: {}, 需要认证: {}", httpConfig.getPort(), httpConfig.needAuth());
        try {
            // Configure the server.
            ServerBootstrap b = new ServerBootstrap();
            b.option(ChannelOption.SO_BACKLOG, 10240);
            b.group(bossGroup, workerGroup)
                    .channel(OsUtils.serverSocketChannelClazz())
                    .childHandler(new HttpProxyServerInitializer(httpConfig));

            log.info("正在绑定HTTP代理端口: {}", httpConfig.getPort());
            Channel httpChannel = b.bind(httpConfig.getPort()).sync().channel();
            log.info("HTTP代理服务启动成功 - port={} auth={} url=http://localhost:{}", httpConfig.getPort(), httpConfig.needAuth(), httpConfig.getPort());
            return httpChannel;
        } catch (Exception e) {
            log.error("无法启动HTTP代理服务 - 端口: {}, 错误信息: {}", httpConfig.getPort(), e.getMessage(), e);
        }
        return null;
    }

    public static Channel startSSl(EventLoopGroup bossGroup, EventLoopGroup workerGroup, SslConfig sslConfig) {
        log.info("开始启动HTTPS代理服务 - 端口: {}, 需要认证: {}, 证书: {}, 私钥: {}", 
                sslConfig.getPort(), sslConfig.needAuth(), sslConfig.getFullchain(), sslConfig.getPrivkey());
        try {
            // Configure the server.
            ServerBootstrap b = new ServerBootstrap();
            b.option(ChannelOption.SO_BACKLOG, 10240);
            HttpsProxyServerInitializer initializer = new HttpsProxyServerInitializer(sslConfig);
            b.group(bossGroup, workerGroup)
                    .channel(OsUtils.serverSocketChannelClazz())
                    .childHandler(initializer);

            log.info("正在绑定HTTPS代理端口: {}", sslConfig.getPort());
            Channel sslChannel = b.bind(sslConfig.getPort()).sync().channel();
            // 每天更新一次ssl证书
            sslChannel.eventLoop().scheduleAtFixedRate(() -> {
                log.info("定时重加载ssl证书！");
                initializer.loadSslContext();
            }, 1, 1, TimeUnit.DAYS);
            log.info("HTTPS代理服务启动成功 - port={} auth={} url:https://localhost:{}", sslConfig.getPort(), sslConfig.needAuth(), sslConfig.getPort());
            return sslChannel;
        } catch (Exception e) {
            log.error("无法启动HTTPS代理服务 - 端口: {}, 错误信息: {}", sslConfig.getPort(), e.getMessage(), e);
        }
        return null;
    }
}
