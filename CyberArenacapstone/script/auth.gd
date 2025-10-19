extends Node

signal auth_response(response_code: int, response: Dictionary)

# 🔹 Firebase & Google OAuth config
const API_KEY: String = "AIzaSyAZvW_4HWndG-Spu5eUrxSf_yRKbpswm3Q"
const GOOGLE_OAUTH_CLIENT_ID: String = "1055956713490-tr6mh6pd994opb1hm2rmtmar1eilb3rm.apps.googleusercontent.com"
const GOOGLE_OAUTH_CLIENT_SECRET: String = "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"
const REDIRECT_URI: String = "http://127.0.0.1:8765"

@onready var http_request: HTTPRequest = $HTTPRequest

# 🔸 Auth Data (accessible globally)
var current_id_token: String = ""
var current_local_id: String = ""
var current_username: String = ""
var current_avatar: String = ""

func _ready() -> void:
	# Connect signal for request
	if not http_request.request_completed.is_connected(_on_request_completed):
		http_request.request_completed.connect(_on_request_completed)

	# Register as global singleton (para ma-access kahit saan)
	if not Engine.has_singleton("Auth"):
		Engine.register_singleton("Auth", self)
		print("[DEBUG] ✅ Auth singleton registered globally.")

	print("[DEBUG] Auth.gd ready!")

# -------------------------
# 🔐 SIGN UP
# -------------------------
func sign_up(email: String, password: String) -> void:
	print("[AUTH] Signing up:", email)
	_request(
		"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=%s" % API_KEY,
		{
			"email": email,
			"password": password,
			"returnSecureToken": true
		}
	)

# -------------------------
# 🔓 LOGIN (Email + Password)
# -------------------------
func login(email: String, password: String) -> void:
	print("[AUTH] Logging in:", email)
	_request(
		"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=%s" % API_KEY,
		{
			"email": email,
			"password": password,
			"returnSecureToken": true
		}
	)

# -------------------------
# 🌐 LOGIN WITH GOOGLE (Firebase)
# -------------------------
func login_with_google(id_token: String) -> void:
	print("[AUTH] Logging in with Google token...")
	_request(
		"https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=%s" % API_KEY,
		{
			"postBody": "id_token=%s&providerId=google.com" % id_token,
			"requestUri": "http://127.0.0.1",
			"returnIdpCredential": true,
			"returnSecureToken": true
		}
	)

# -------------------------
# 🔁 EXCHANGE GOOGLE AUTH CODE → ID_TOKEN
# -------------------------
func exchange_google_code(code: String) -> void:
	print("[OAUTH] Exchanging Google code → Firebase token...")

	var body_dict := {
		"code": code,
		"client_id": GOOGLE_OAUTH_CLIENT_ID,
		"client_secret": GOOGLE_OAUTH_CLIENT_SECRET,
		"redirect_uri": REDIRECT_URI,
		"grant_type": "authorization_code"
	}

	var pairs: Array = []
	for k in body_dict.keys():
		pairs.append("%s=%s" % [str(k).uri_encode(), str(body_dict[k]).uri_encode()])
	var body_str: String = "&".join(pairs)
	var headers := ["Content-Type: application/x-www-form-urlencoded"]

	var req := HTTPRequest.new()
	add_child(req)

	req.request_completed.connect(func(_r, response_code: int, _h: PackedStringArray, body: PackedByteArray):
		req.queue_free()

		var text := body.get_string_from_utf8()
		print("[OAUTH] Token exchange response:", response_code, text)

		if response_code == 200:
			var resp = JSON.parse_string(text)
			if resp is Dictionary and resp.has("id_token"):
				login_with_google(str(resp["id_token"]))
			else:
				push_warning("[OAUTH] Missing id_token in Google response.")
				emit_signal("auth_response", 0, {"error": "Missing id_token", "raw": resp})
		else:
			push_warning("[OAUTH] Token exchange failed (%s)" % response_code)
			emit_signal("auth_response", response_code, {"error": text})
	)

	var err := req.request("https://oauth2.googleapis.com/token", headers, HTTPClient.METHOD_POST, body_str)
	if err != OK:
		push_error("[OAUTH] ❌ Failed to start token exchange (code: %s)" % err)
		req.queue_free()

# -------------------------
# 📧 SEND EMAIL VERIFICATION
# -------------------------
func send_verification_email(id_token: String) -> void:
	print("[AUTH] Sending verification email...")
	_request(
		"https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=%s" % API_KEY,
		{
			"requestType": "VERIFY_EMAIL",
			"idToken": id_token
		}
	)

# -------------------------
# 🔍 CHECK EMAIL VERIFIED
# -------------------------
func check_email_verified(id_token: String) -> void:
	print("[AUTH] Checking email verification...")
	_request(
		"https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=%s" % API_KEY,
		{"idToken": id_token}
	)

# -------------------------
# 🧰 GENERIC REQUEST HANDLER
# -------------------------
func _request(url: String, body: Dictionary) -> void:
	var headers := ["Content-Type: application/json"]
	var body_str := JSON.stringify(body)
	print("[HTTP] Request →", url)

	var err := http_request.request(url, headers, HTTPClient.METHOD_POST, body_str)
	if err != OK:
		push_error("[AUTH] ❌ Failed to start request (%s)" % err)
		emit_signal("auth_response", 0, {"error": "Request failed: %s" % err})

# -------------------------
# 📬 RESPONSE HANDLER
# -------------------------
func _on_request_completed(result: int, response_code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	var response := {}
	if body.size() > 0:
		var text := body.get_string_from_utf8()
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary:
			response = parsed

	if response.has("idToken"):
		current_id_token = str(response["idToken"])
	if response.has("localId"):
		current_local_id = str(response["localId"])

	print("\n[AUTH RESPONSE]")
	print("Code:", response_code)
	print("Local ID:", current_local_id)
	print("ID Token:", current_id_token.left(25), "...\n")

	emit_signal("auth_response", response_code, response)
