extends Control

@onready var username_input: LineEdit = $NinePatchRect/UsernameLineEdit
@onready var save_button: Button = $NinePatchRect/ConfirmButton
@onready var message_label: Label = $NinePatchRect/MessageLabel

const PROJECT_ID := "capstone-823dc"
const FIRESTORE_URL := "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents" % PROJECT_ID

func _ready() -> void:
	save_button.pressed.connect(_on_save_pressed)
	message_label.text = ""


# -------------------------
# MAIN SAVE LOGIC (Entry point)
# -------------------------
func _on_save_pressed() -> void:
	var username: String = username_input.text.strip_edges()
	if username == "":
		message_label.text = "⚠️ Please enter a username."
		return
	if Auth.current_local_id == "" or Auth.current_id_token == "":
		message_label.text = "⚠️ Missing Auth info. Please log in again."
		return

	message_label.text = "⏳ Checking existing profile..."

	# Step 1: Check kung existing user doc
	var url: String = "%s/users/%s" % [FIRESTORE_URL, Auth.current_local_id]
	var headers: Array = ["Authorization: Bearer %s" % Auth.current_id_token]

	var req := HTTPRequest.new()
	add_child(req)

	req.request_completed.connect(func(_r, code, _h, body):
		req.queue_free()

		if code == 200:
			print("✅ Existing user found, redirecting to landing.tscn...")
			get_tree().change_scene_to_packed(load("res://scene/landing.tscn"))
			return

		print("🆕 No existing user found, creating new Firestore doc...")
		_create_new_user(username)
	)

	var err := req.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		push_error("Failed to start user check request: %s" % err)
		req.queue_free()


# -------------------------
# CREATE NEW USER DOC (Only called if not found)
# -------------------------
func _create_new_user(username: String) -> void:
	message_label.text = "⏳ Creating new profile..."

	var body := {
		"fields": {
			"username": {"stringValue": username},
			"avatar": {"stringValue": "default.png"},
			"wins": {"integerValue": 0},
			"losses": {"integerValue": 0},
			"level": {"integerValue": 1},
			"friends": {"arrayValue": {"values": []}},
			"requests_received": {"arrayValue": {"values": []}},
			"status": {"stringValue": "offline"}
		}
	}

	var url: String = "%s/users?documentId=%s" % [FIRESTORE_URL, Auth.current_local_id]
	var headers: Array = [
		"Content-Type: application/json",
		"Authorization: Bearer %s" % Auth.current_id_token
	]

	var http := HTTPRequest.new()
	add_child(http)

	http.request_completed.connect(func(_r, code, _h, body):
		http.queue_free()

		var text: String = body.get_string_from_utf8()
		print("Firestore Response:", code, text)

		if code == 200 or code == 201:
			message_label.text = "✅ Profile created successfully!"
			get_tree().change_scene_to_packed(load("res://scene/landing.tscn"))
		else:
			message_label.text = "❌ Failed to create profile (%s)" % code
			push_warning(text)
	)

	var err := http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		push_error("Failed to start Firestore POST request: %s" % err)
		http.queue_free()
