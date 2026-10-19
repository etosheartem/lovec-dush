extends Node
## Анонимный счётчик: случайный id установки, версия, суммарное время в игре, число душ.

const URL := "https://hgh09hcw39j.sn.mynetname.net:8444/lovec/ping"
const EVERY := 300.0  # пинг раз в 5 минут игры
# Свой сертификат приёмника (LXC 211, 20 лет): доверяем только ему, без публичных CA.
const CERT := """-----BEGIN CERTIFICATE-----
MIIBzTCCAXKgAwIBAgIURGzAITSQ5s6kUEj3qjFIYPI/SDowCgYIKoZIzj0EAwIw
JzElMCMGA1UEAwwcaGdoMDloY3czOWouc24ubXluZXRuYW1lLm5ldDAeFw0yNjEw
MTkxNDE3NDFaFw00NjEwMTQxNDE3NDFaMCcxJTAjBgNVBAMMHGhnaDA5aGN3Mzlq
LnNuLm15bmV0bmFtZS5uZXQwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAASNVn1R
vYZmAfrQCxVy2iSBHjnlHTklCu7fP+YVnM0vFX7gSuXcbOJ7xvs3UVXW33DwTCVw
TlWiMDQ6WDzPfW29o3wwejAdBgNVHQ4EFgQU4ZaKCQ4YrPw/c4ZjSxsBbm1L/icw
HwYDVR0jBBgwFoAU4ZaKCQ4YrPw/c4ZjSxsBbm1L/icwDwYDVR0TAQH/BAUwAwEB
/zAnBgNVHREEIDAeghxoZ2gwOWhjdzM5ai5zbi5teW5ldG5hbWUubmV0MAoGCCqG
SM49BAMCA0kAMEYCIQCXJErOLwP9HXwYvcAaLT+/LycCqcJtSYi9M+27dcSZSwIh
APz00iX6z/hig1xIO7XUbb90iPIx48TDzwsP5Qh0Nz+D
-----END CERTIFICATE-----"""

var settings_path := "user://settings.cfg"
var enabled := true
var id := ""
var play := 0.0
var since_ping := 0.0
var http: HTTPRequest


func setup(path: String, enabled_: bool) -> void:
	settings_path = path
	enabled = enabled_
	var config := ConfigFile.new()
	config.load(settings_path)
	id = str(config.get_value("stats", "id", ""))
	play = float(config.get_value("stats", "play", 0.0))
	if id.length() != 32:
		id = Crypto.new().generate_random_bytes(16).hex_encode()
		_store()
	http = HTTPRequest.new()
	http.timeout = 10
	var cert := X509Certificate.new()
	cert.load_from_string(CERT)
	http.set_tls_options(TLSOptions.client(cert))
	add_child(http)


func tick(dt: float, souls: int) -> void:
	play += dt
	since_ping += dt
	if since_ping >= EVERY:
		ping(souls)


func ping(souls: int) -> void:
	since_ping = 0
	_store()
	if not enabled or http == null or http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	var body := JSON.stringify({id = id, v = str(ProjectSettings.get_setting("application/config/version", "0")),
		t = int(play), s = clampi(souls, 0, 3)})
	http.request(URL, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)


func _store() -> void:
	if not enabled:
		return
	var config := ConfigFile.new()
	if config.load(settings_path) not in [OK, ERR_FILE_NOT_FOUND]:
		return
	config.set_value("stats", "id", id)
	config.set_value("stats", "play", play)
	config.save(settings_path)
