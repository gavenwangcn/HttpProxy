```shell
openssl req -x509 -newkey rsa:4096 -sha256 -nodes -keyout private.key -out cert.pem -days 3650

## chrome不验证本地证书
chrome://flags/#allow-insecure-localhost
```