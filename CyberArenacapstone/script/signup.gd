extends Control

@onready var email_input: LineEdit = $VideoStreamPlayer/EmailLineEdit
@onready var password_input: LineEdit = $VideoStreamPlayer/PasswordLineEdit
@onready var repeat_password_input: LineEdit = $VideoStreamPlayer/RepeatPasswordLineEdit
@onready var message_label: Label = $VideoStreamPlayer/status
@onready var signup_button: Button = $VideoStreamPlayer/SignUpButton
@onready var google_signup_btn: TextureButton = $VideoStreamPlayer/GoogleLoginButton

# daan papunta sa helper script mo (baguhin kung nasa ibang path)
@onready var oauth_helper = preload("res://script/auth_helper.gd").new()

var email_regex := RegEx.new()

func _ready():
	# panimulang setup
	add_child(oauth_helper)
	oauth_helper.token_received.connect(_on_google_code_received)
	Auth.auth_response.connect(_on_auth_response)

	signup_button.pressed.connect(_on_signup_pressed)
	google_signup_btn.pressed.connect(_on_google_signup_pressed)

	email_regex.compile(r"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$")
	email_input.text_changed.connect(_validate_inputs)
	password_input.text_changed.connect(_validate_inputs)
	repeat_password_input.text_changed.connect(_validate_inputs)


# ------------------------------------------------------
# 🔹 Google OAuth2 Sign Up Flow (sinisimulan ang local server + binubuksan ang browser)
# ------------------------------------------------------
func _on_google_signup_pressed():
	message_label.text = "⏳ Opening Google Sign-In..."
	oauth_helper.start_google_login()
	message_label.text = "🌐 Waiting for browser to redirect..."


# tinatawag kapag ang helper ay naglabas ng authorization code
func _on_google_code_received(code: String):
	message_label.text = "⏳ Exchanging code for tokens..."
	# Hinihingi sa Auth singleton na palitan ang code -> token (tatawagin nito ang login_with_google kapag nakuha na ang id_token)
	Auth.exchange_google_code(code)
	message_label.text = "⏳ Signing in with Google..."


# ------------------------------------------------------
# 🔹 Pag-validate at Pag-sign up
# ------------------------------------------------------
func _validate_inputs(_t: String = ""):
	var email = email_input.text.strip_edges()
	var password = password_input.text.strip_edges()
	var repeat = repeat_password_input.text.strip_edges()

	if email == "" or password == "" or repeat == "":
		message_label.text = "⚠️ Please fill all fields."
		return

	if not email_regex.search(email):
		message_label.text = "⚠️ Invalid email format."
		return

	message_label.text = ""


func _on_signup_pressed():
	var email = email_input.text.strip_edges()
	var password = password_input.text.strip_edges()
	var repeat = repeat_password_input.text.strip_edges()

	if email == "" or password == "" or repeat == "":
		message_label.text = "⚠️ Please enter credentials"
		return

	if not email_regex.search(email):
		message_label.text = "⚠️ Invalid email format"
		return

	if password != repeat:
		message_label.text = "❌ Passwords do not match!"
		return

	message_label.text = "⏳ Creating account..."
	Auth.sign_up(email, password)


# ------------------------------------------------------
# 🔹 Tugon mula sa Firebase Auth
# ------------------------------------------------------
func _on_auth_response(response_code: int, response: Dictionary):
	print("Auth response:", response_code, response)

	if response_code == 200:
		# Kung nagbalik ang Firebase ng idToken, ibig sabihin ay matagumpay ang sign-in o sign-up
		if response.has("idToken"):
			# Kung ang sign-in ay galing sa Google provider
			if response.has("providerId") and response["providerId"] == "google.com":
				message_label.text = "✅ Google Sign-In Success!"
				Auth.current_id_token = response["idToken"]
				if response.has("localId"):
					Auth.current_local_id = response["localId"]
				# Pagkatapos ng matagumpay na Firebase sign-in, i-check sa Firestore kung may document na
				_check_firestore_username_and_route()
				return

			# Kung hindi Google, ibig sabihin email signup → magpapadala ng email verification
			message_label.text = "✅ Account created! Please verify your email."
			Auth.send_verification_email(response["idToken"])
			var LoginScene = load("res://scene/login.tscn")
			get_tree().change_scene_to_packed(LoginScene)
		else:
			message_label.text = "❌ Unexpected response: " + str(response)
	else:
		message_label.text = "❌ Signup failed: " + str(response.get("error", {}).get("message", "Unknown error"))


func _check_firestore_username_and_route():
	# Pagkatapos ng matagumpay na sign-in, i-check kung may user document sa Firestore; kung meron, pupunta sa landing o create_user depende sa resulta
	if Auth.current_local_id == "" or Auth.current_id_token == "":
		push_error("Missing auth state after Google sign-in")
		return

	const PROJECT_ID := "capstone-823dc"
	var FIRESTORE_URL = "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents" % PROJECT_ID
	var url = "%s/users/%s" % [FIRESTORE_URL, Auth.current_local_id]
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer %s" % Auth.current_id_token
	]

	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result, response_code, headers_r, body_r, req=http):
		req.queue_free()
		var text = body_r.get_string_from_utf8()
		print("Firestore check: ", response_code, " | ", text)
		if response_code == 200:
			var resp = JSON.parse_string(text)
			if typeof(resp) == TYPE_DICTIONARY and resp.has("fields") and resp["fields"].has("username"):
				# Pupunta sa landing scene kapag may existing username
				var landing = load("res://scene/landing.tscn")
				get_tree().change_scene_to_packed(landing)
			else:
				var createuser = load("res://scene/create_users_panel.tscn")
				get_tree().change_scene_to_packed(createuser)
		else:
			# Kapag walang nahanap na dokumento o nagka-error → pupunta sa create user scene
			var createuser = load("res://scene/create_users_panel.tscn")
			get_tree().change_scene_to_packed(createuser)
	)
	http.request(url, headers, HTTPClient.METHOD_GET)


func _on_change_to_login_button_pressed() -> void:
	var loginScene = "res://scene/login.tscn"
	get_tree().change_scene_to_file(loginScene)
