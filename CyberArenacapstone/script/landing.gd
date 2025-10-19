extends Control

# === UI References ===
@onready var username_input: Label = $VideoStreamPlayer/ProfilePanel/UserPanel/usernameInput
@onready var level_input: Label = $VideoStreamPlayer/ProfilePanel/UserPanel/levelInput
@onready var wins_input: Label = $VideoStreamPlayer/ProfilePanel/UserPanel/winsInput
@onready var losses_input: Label = $VideoStreamPlayer/ProfilePanel/UserPanel/losesInput
@onready var status_label: Label = $VideoStreamPlayer/ProfilePanel/UserPanel/StatusLabel
@onready var profile_pic: TextureRect = $VideoStreamPlayer/ProfilePanel/UserPanel/ProfilePic
@onready var change_btn: Button = $VideoStreamPlayer/ProfilePanel/UserPanel/ChangeAvatarButton
@onready var save_btn: Button = $VideoStreamPlayer/ProfilePanel/UserPanel/SaveProfile
@onready var avatar_picker: PopupPanel = $VideoStreamPlayer/ProfilePanel/UserPanel/AvatarPicker
@onready var avatar_grid: GridContainer = $VideoStreamPlayer/ProfilePanel/UserPanel/AvatarPicker/GridContainer

# === Avatars & User Data ===
var avatars: Dictionary = {}
var selected_avatar: String = ""
var last_avatar_change: int = 0
var avatar_cooldown: int = 2592000 # 30 days

# Firestore base
var firestore_base_url := "https://firestore.googleapis.com/v1/projects/capstone-823dc/databases/(default)/documents/users"

# Reusable HTTP node for requests
var http: HTTPRequest

# === Lifecycle ===
func _ready() -> void:
	#print("Setting fullscreen...")
	#DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	# Create reusable HTTPRequest node
	http = HTTPRequest.new()
	add_child(http)

	_load_avatars()
	change_btn.pressed.connect(_on_change_avatar_pressed)
	save_btn.pressed.connect(_on_save_profile_pressed)
	_load_user_data()

	# === Navigation setup ===
	_setup_navigation()


# === Load avatars from folder ===
func _load_avatars() -> void:
	var dir := DirAccess.open("res://asset/avatars")
	if dir == null:
		push_error("⚠️ Avatar folder not found: res://asset/avatars")
		return

	avatars.clear()
	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.get_extension() in ["png", "jpg", "jpeg", "webp"]:
			var tex := load("res://asset/avatars/" + file_name)
			if tex:
				avatars[file_name] = tex
				var btn := TextureButton.new()
				btn.texture_normal = tex
				btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
				btn.custom_minimum_size = Vector2(64, 64)
				# capture file_name at connection time
				var captured_name: String = file_name
				btn.pressed.connect(func(): _on_avatar_selected(captured_name))
				avatar_grid.add_child(btn)
		file_name = dir.get_next()
	dir.list_dir_end()


# === Change avatar button ===
func _on_change_avatar_pressed() -> void:
	var current_time = Time.get_unix_time_from_system()
	if current_time - last_avatar_change < avatar_cooldown:
		var remaining = int((avatar_cooldown - (current_time - last_avatar_change)) / 86400)
		status_label.text = "⏳ You can change avatar again in %d days." % remaining
		return
	avatar_picker.popup_centered()


# === User selects avatar ===
func _on_avatar_selected(file_name: String) -> void:
	if avatars.has(file_name):
		profile_pic.texture = avatars[file_name]
		selected_avatar = file_name
		status_label.text = "✅ Avatar selected (click SaveProfile to apply)"
		avatar_picker.hide()


# === SaveProfile button pressed ===
func _on_save_profile_pressed() -> void:
	var user_id = Auth.current_local_id
	var id_token = Auth.current_id_token
	if user_id == "" or id_token == "":
		push_error("⚠️ User not logged in, cannot save profile")
		return

	last_avatar_change = Time.get_unix_time_from_system()

	var url = "%s/%s" % [firestore_base_url, user_id]
	var body = {
		"fields": {
			"username": { "stringValue": username_input.text },
			"level": { "integerValue": level_input.text },
			"wins": { "integerValue": wins_input.text },
			"losses": { "integerValue": losses_input.text },
			"avatar": { "stringValue": selected_avatar },
			"last_avatar_change": { "integerValue": str(last_avatar_change) }
		}
	}
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer %s" % id_token
	]

	if http.request_completed.is_connected(_on_save_profile_response):
		http.request_completed.disconnect(_on_save_profile_response)
	http.request_completed.connect(_on_save_profile_response)

	http.request(url, headers, HTTPClient.METHOD_PATCH, JSON.stringify(body))


func _on_save_profile_response(result, response_code, _headers, body) -> void:
	if response_code == 200:
		status_label.text = "✅ Profile saved!"
		Auth.current_avatar = selected_avatar
		Auth.current_username = username_input.text
		_load_user_data()
	else:
		var msg = body.get_string_from_utf8() if body.size() > 0 else "Unknown error"
		status_label.text = "❌ Failed to save profile"
		push_error("Firestore error: %s" % msg)


# === Load user data from Firestore ===
func _load_user_data() -> void:
	var user_id = Auth.current_local_id
	var id_token = Auth.current_id_token
	if user_id == "" or id_token == "":
		return

	var url = "%s/%s" % [firestore_base_url, user_id]
	var headers = ["Authorization: Bearer %s" % id_token]

	if http.request_completed.is_connected(_on_user_data_response):
		http.request_completed.disconnect(_on_user_data_response)
	http.request_completed.connect(_on_user_data_response)

	http.request(url, headers, HTTPClient.METHOD_GET)


func _on_user_data_response(result, response_code, _headers, body) -> void:
	if response_code != 200:
		push_error("⚠️ Failed to load user data: %s" % response_code)
		return

	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data.has("fields"):
		return

	var f = data["fields"]

	if f.has("avatar"):
		selected_avatar = f["avatar"]["stringValue"]
		if avatars.has(selected_avatar):
			profile_pic.texture = avatars[selected_avatar]
			Auth.current_avatar = selected_avatar

	if f.has("last_avatar_change"):
		last_avatar_change = int(f["last_avatar_change"]["integerValue"])

	if f.has("username"):
		Auth.current_username = f["username"]["stringValue"]
		username_input.text = Auth.current_username

	if f.has("level"):
		level_input.text = str(f["level"]["integerValue"])

	if f.has("wins"):
		wins_input.text = str(f["wins"]["integerValue"])

	if f.has("losses"):
		losses_input.text = str(f["losses"]["integerValue"])


# === Navigation Logic ===
func _setup_navigation() -> void:
	var panel_paths := {
		"home": "HomePanel",
		"game": "GameSelectPanel",
		"ranking": "RankingPanel",
		"profile": "ProfilePanel",
	}

	$NavigationPanel/HBoxContainer/HomeNavigate.pressed.connect(func(): _show_panel(panel_paths, "home"))
	$NavigationPanel/HBoxContainer/GameNavigate.pressed.connect(func(): _show_panel(panel_paths, "game"))
	$NavigationPanel/HBoxContainer/RankingNavigate.pressed.connect(func(): _show_panel(panel_paths, "ranking"))
	$NavigationPanel/HBoxContainer/ProfileNavigate.pressed.connect(func(): _show_panel(panel_paths, "profile"))
	$NavigationPanel/HBoxContainer/LogoButton.pressed.connect(func(): _show_panel(panel_paths, "home"))
	$NavigationPanel/HBoxContainer/LogoutButton.pressed.connect(_on_logout_pressed)

	_show_panel(panel_paths, "home")


func _show_panel(panel_paths: Dictionary, panel_name: String) -> void:
	# Hide all panels
	for key in panel_paths.keys():
		var node = $VideoStreamPlayer.get_node_or_null(panel_paths[key])
		if node:
			node.visible = false
		else:
			push_warning("Panel node missing (hide): %s" % panel_paths[key])

	# Show target panel
	var node_to_show = $VideoStreamPlayer.get_node_or_null(panel_paths.get(panel_name, ""))
	if node_to_show:
		node_to_show.visible = true
	else:
		push_warning("Panel node not found to show: %s" % panel_name)

	# Friend list visibility
	var friend_list = $VideoStreamPlayer.get_node_or_null("FriendListPanel")
	if friend_list:
		friend_list.visible = (panel_name != "game")


# === Logout Logic ===
func _on_logout_pressed() -> void:
	print("Logging out...")
	Auth.set_user_offline()  # 🔴 mark offline before exit
	get_tree().change_scene_to_file("res://scene/login.tscn")
