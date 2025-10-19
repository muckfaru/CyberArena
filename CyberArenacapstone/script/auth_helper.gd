extends Node  # Gumagamit tayo ng Node bilang base script

signal token_received(code: String)  # Signal na maglalabas ng authorization code kapag nakuha na

# Gumagawa ng simpleng local TCP server para tanggapin ang redirect ni Google
var server: TCPServer = TCPServer.new()
var port: int = 8765                    # Port kung saan makikinig ang server (same sa redirect URI)
var is_listening: bool = false          # Flag kung active ang pakikinig

# Client ID mo sa Google Cloud / Firebase (Web type dapat)
const CLIENT_ID: String = "1055956713490-tr6mh6pd994opb1hm2rmtmar1eilb3rm.apps.googleusercontent.com"


# -------------------------
# START GOOGLE LOGIN
# -------------------------
func start_google_login() -> void:
	var err = server.listen(port)  # Subukang magbukas ng TCP server sa port 8765
	if err != OK:
		push_error("❌ Failed to start TCP server: %s" % err)
		return

	print("✅ Listening on http://127.0.0.1:%d" % port)
	set_process(true)       # I-activate ang _process() loop
	is_listening = true      # Mark na active ang pakikinig

	# Buoin ang Google OAuth URL (gamit ang response_type=code para ?code=... ang ibalik sa redirect)
	var redirect_uri: String = "http://127.0.0.1:%d" % port
	var scope: String = "openid%20email%20profile"  # Mga permissions na hinihingi

	# Gumamit ng random state (security measure para iwas CSRF attacks)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var state: String = str(rng.randi())

	# Ito ang full Google OAuth URL
	var oauth_url: String = (
		"https://accounts.google.com/o/oauth2/v2/auth?"
		+ "client_id=%s"
		+ "&redirect_uri=%s"
		+ "&response_type=code"
		+ "&scope=%s"
		+ "&access_type=offline"
		+ "&prompt=select_account"
		+ "&state=%s"
	) % [CLIENT_ID, redirect_uri.uri_encode(), scope, state]

	OS.shell_open(oauth_url)  # Bubuksan sa browser ang Google sign-in page
	# Kapag nakapag-sign in ang user, ire-redirect ito pabalik sa localhost:8765/?code=...


# -------------------------
# MAIN LOOP (tumatakbo habang nakikinig ang server)
# -------------------------
func _process(_delta: float) -> void:
	if not is_listening:  # Kung hindi naman nakikinig, wala tayong gagawin
		return

	if server.is_connection_available():  # Kapag may bagong connection (redirect mula sa Google)
		var peer = server.take_connection()
		if peer:
			# Basahin ang laman ng HTTP request na galing sa browser
			var bytes_avail := peer.get_available_bytes()
			if bytes_avail <= 0:
				return  # Wala pang laman, hintayin pa
			var raw: String = peer.get_utf8_string(bytes_avail)
			print("🌐 Raw redirect data:\n", raw)

			# Parse ang unang linya ng HTTP request
			# Halimbawa: "GET /?code=abcd1234&scope=email HTTP/1.1"
			var first_line: String = raw.split("\r\n")[0]
			var code: String = ""
			if first_line.begins_with("GET "):
				var parts := first_line.split(" ")
				if parts.size() >= 2:
					var path_and_q: String = parts[1]  # "/?code=abcd1234&state=..."
					if "?" in path_and_q:
						var q: String = path_and_q.split("?", false, 1)[1]
						for pair in q.split("&"):  # Hanapin ang bawat parameter
							if pair.begins_with("code="):
								# Kunin ang value ng code parameter
								code = pair.split("=", false, 1)[1].uri_decode()
								break

			# Gumawa ng simpleng HTTP response para ipakita sa browser
			var html: String = "<html><body><h2>✅ Successful! You can close this window.</h2></body></html>"
			var body_buf: PackedByteArray = html.to_utf8_buffer()

			# Header para ipahiwatig na OK ang response
			var header: String = "HTTP/1.1 200 OK\r\n"
			header += "Content-Type: text/html; charset=UTF-8\r\n"
			header += "Content-Length: %d\r\n" % body_buf.size()
			header += "Connection: close\r\n\r\n"

			# Ipadala sa browser ang header + HTML body
			peer.put_data(header.to_utf8_buffer())
			peer.put_data(body_buf)
			peer.disconnect_from_host()  # Isara ang koneksyon

			# Itigil na ang pakikinig (isa lang kasi ang kailangan nating request)
			server.stop()
			is_listening = false
			set_process(false)

			# Kung may nahanap na code, i-emit ito
			if code != "":
				print("✅ Got auth code:", code)
				emit_signal("token_received", code)  # Ipadala sa ibang script (ex: auth.gd)
			else:
				push_error("⚠️ No code found in redirect.")
				
func save_user_to_rtdb():
	if Auth.current_local_id == "" or Auth.current_username == "":
		push_warning("[AuthHelper] Missing UID or username, skipping RTDB save.")
		return

	var url = "https://capstone-823dc-default-rtdb.firebaseio.com/users/%s/username.json?auth=%s" % [
		Auth.current_local_id,
		Auth.current_id_token
	]

	var payload = JSON.stringify(Auth.current_username)
	var http = HTTPRequest.new()
	add_child(http)

	http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_PUT, payload)
	print("[AuthHelper] ✅ Username saved to RTDB:", Auth.current_username)
