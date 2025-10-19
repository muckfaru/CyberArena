extends Control

@onready var email_input: LineEdit = $VideoStreamPlayer/EmailLineEdit
@onready var password_input: LineEdit = $VideoStreamPlayer/PasswordLineEdit
@onready var message_label: Label = $VideoStreamPlayer/MessageLabel
@onready var login_button: Button = $VideoStreamPlayer/LoginButton
@onready var google_login_btn: TextureButton = $VideoStreamPlayer/GoogleLoginButton

# (helper) para sa OAuth2 / Google Login
@onready var oauth_helper = preload("res://script/auth_helper.gd").new()

var email_regex := RegEx.new()

func _ready():

	add_child(oauth_helper)
	oauth_helper.token_received.connect(_on_google_code_received)
	Auth.auth_response.connect(_on_auth_response)

	login_button.pressed.connect(_on_login_pressed)
	google_login_btn.pressed.connect(_on_google_login_pressed)

	email_regex.compile(r"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$")


# ------------------------------------------------------
# 🔹 Email/Password Login (Pag-login gamit ang email at password)
# ------------------------------------------------------
func _on_login_pressed():
	var email = email_input.text.strip_edges()
	var password = password_input.text.strip_edges()

	if email == "" or password == "":
		message_label.text = "⚠️ Pakilagay ang email at password."
		return

	if not email_regex.search(email):
		message_label.text = "⚠️ Mali ang format ng email."
		return

	message_label.text = "⏳ Nagla-login..."
	Auth.login(email, password)


# ------------------------------------------------------
# 🔹 Google OAuth Login Flow (pareho lang sa signup)
# ------------------------------------------------------
func _on_google_login_pressed():
	message_label.text = "⏳ Binubuksan ang Google Sign-In..."
	oauth_helper.start_google_login()
	message_label.text = "🌐 Naghihintay sa pag-redirect ng browser..."


func _on_google_code_received(code: String):
	message_label.text = "⏳ Pinapalit ang code para maging token..."
	Auth.exchange_google_code(code)
	message_label.text = "⏳ Nagla-login gamit ang Google..."


# ------------------------------------------------------
# 🔹 Tugon mula sa Firebase Authentication
# ------------------------------------------------------
func _on_auth_response(response_code: int, response: Dictionary):
	print("Auth Response:", response_code, response)

	if response_code == 200:
		if response.has("idToken"):
			message_label.text = "✅ Matagumpay na naka-login!"
			Auth.current_id_token = response["idToken"]
			if response.has("localId"):
				Auth.current_local_id = response["localId"]

			_check_firestore_username_and_route()
			return


# ------------------------------------------------------
# 🔹 Pag-check sa Firestore (katulad din ng sa signup)
# ------------------------------------------------------
func _check_firestore_username_and_route():
	if Auth.current_local_id == "" or Auth.current_id_token == "":
		push_error("Walang auth data pagkatapos mag-sign in")
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
				var landing = load("res://scene/landing.tscn")
				get_tree().change_scene_to_packed(landing)
			else:
				var createuser = load("res://scene/create_users_panel.tscn")
				get_tree().change_scene_to_packed(createuser)
		else:
			var createuser = load("res://scene/create_users_panel.tscn")
			get_tree().change_scene_to_packed(createuser)
	)
	http.request(url, headers, HTTPClient.METHOD_GET)
	
	
# ------------------------------------------------------
# 🔹 Button para lumipat sa Signup scene
# ------------------------------------------------------
func _on_sign_up_button_pressed() -> void:
	var signupScene = "res://scene/signup.tscn"
	get_tree().change_scene_to_file(signupScene)
