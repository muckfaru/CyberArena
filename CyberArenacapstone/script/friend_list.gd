extends Panel

@onready var friend_container: VBoxContainer = $FriendListVBox
@onready var requests_container: VBoxContainer = $FriendRequestsVBox
@onready var add_input: LineEdit = $AddFriendHBox/FriendUIDInput
@onready var add_button: Button = $AddFriendHBox/AddFriendButton

# 🔹 Firebase Config
const PROJECT_ID: String = "capstone-823dc"
const BASE_URL: String = "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents" % PROJECT_ID

var refresh_timer := Timer.new()
var last_friend_list: Array = []
var last_request_list: Array = []

# ======================================================
# 🔸 READY
# ======================================================
func _ready():
	print("[FriendList] Ready.")
	refresh_timer.wait_time = 5.0
	refresh_timer.autostart = true
	refresh_timer.timeout.connect(func():
		load_friend_requests()
		load_friend_list()
	)
	add_child(refresh_timer)

	add_button.pressed.connect(func():
		var target = add_input.text.strip_edges()
		if target == "":
			return
		add_button.disabled = true
		send_friend_request(target)
		await get_tree().create_timer(1.0).timeout # prevent spam clicks
		add_button.disabled = false
	)

	load_friend_requests()
	load_friend_list()


# ======================================================
# 📥 LOAD FRIEND REQUESTS
# ======================================================
func load_friend_requests() -> void:
	var uid = Auth.current_local_id
	var token = Auth.current_id_token
	if uid == "" or token == "":
		push_warning("⚠️ Missing Auth info.")
		return

	var url = "%s/users/%s" % [BASE_URL, uid]
	var headers = ["Authorization: Bearer %s" % token]
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_r, code, _h, body):
		http.queue_free()
		if code != 200:
			return

		var data = JSON.parse_string(body.get_string_from_utf8())
		if not data.has("fields"):
			return

		var new_requests: Array = []
		if data["fields"].has("requests_received"):
			var arr = data["fields"]["requests_received"].get("arrayValue", {})
			if arr.has("values"):
				for v in arr["values"]:
					var sender = v.get("stringValue", "")
					if sender != "":
						new_requests.append(sender)

		if new_requests != last_request_list:
			last_request_list = new_requests.duplicate()
			print("[UI] 🔄 Friend requests changed → refreshing UI")
			_update_request_ui(new_requests)
	)
	http.request(url, headers, HTTPClient.METHOD_GET)


# ======================================================
# 📜 LOAD FRIEND LIST
# ======================================================
func load_friend_list() -> void:
	var uid = Auth.current_local_id
	var token = Auth.current_id_token
	if uid == "" or token == "":
		return

	var url = "%s/users/%s" % [BASE_URL, uid]
	var headers = ["Authorization: Bearer %s" % token]
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_r, code, _h, body):
		http.queue_free()
		if code != 200:
			return

		var data = JSON.parse_string(body.get_string_from_utf8())
		if not data.has("fields"):
			return

		var new_friends: Array = []
		if data["fields"].has("friends"):
			var arr = data["fields"]["friends"].get("arrayValue", {})
			if arr.has("values"):
				for v in arr["values"]:
					var friend_name = v.get("stringValue", "")
					if friend_name != "":
						new_friends.append(friend_name)

		if new_friends != last_friend_list:
			last_friend_list = new_friends.duplicate()
			print("[UI] 🔄 Friend list changed → refreshing UI")
			_update_friend_ui(new_friends)
	)
	http.request(url, headers, HTTPClient.METHOD_GET)


# ======================================================
# 🧾 UPDATE FRIEND REQUESTS UI (with fade-in)
# ======================================================
func _update_request_ui(requests: Array) -> void:
	for child in requests_container.get_children():
		child.queue_free()

	for sender in requests:
		var hbox = HBoxContainer.new()
		var lbl = Label.new()
		lbl.text = sender
		hbox.add_child(lbl)

		var accept_btn = Button.new()
		accept_btn.text = "✅"
		accept_btn.pressed.connect(func():
			accept_friend_request(sender)
			hbox.queue_free()
		)
		hbox.add_child(accept_btn)

		var decline_btn = Button.new()
		decline_btn.text = "❌"
		decline_btn.pressed.connect(func():
			decline_friend_request(sender)
			hbox.queue_free()
		)
		hbox.add_child(decline_btn)

		hbox.modulate.a = 0
		requests_container.add_child(hbox)
		var tween = create_tween()
		tween.tween_property(hbox, "modulate:a", 1.0, 0.25)


# ======================================================
# 🧾 UPDATE FRIEND LIST UI (with fade-in)
# ======================================================
func _update_friend_ui(friends: Array) -> void:
	for child in friend_container.get_children():
		child.queue_free()

	for name in friends:
		var hbox = HBoxContainer.new()
		var lbl = Label.new()
		lbl.text = name
		hbox.add_child(lbl)

		var unfriend_btn = Button.new()
		unfriend_btn.text = "❌"
		unfriend_btn.tooltip_text = "Unfriend"
		unfriend_btn.pressed.connect(func():
			unfriend_user(name)
			hbox.queue_free()
		)
		hbox.add_child(unfriend_btn)

		hbox.modulate.a = 0
		friend_container.add_child(hbox)
		var tween = create_tween()
		tween.tween_property(hbox, "modulate:a", 1.0, 0.25)


# ======================================================
# 💔 UNFRIEND USER
# ======================================================
func unfriend_user(friend_name: String) -> void:
	var uid = Auth.current_local_id
	var token = Auth.current_id_token
	if uid == "" or token == "":
		return

	print("[FriendList] Unfriending:", friend_name)
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer %s" % token
	]

	var query_url = "%s:runQuery" % BASE_URL
	var query_body = {
		"structuredQuery": {
			"from": [{"collectionId": "users"}],
			"where": {
				"fieldFilter": {
					"field": {"fieldPath": "username"},
					"op": "EQUAL",
					"value": {"stringValue": friend_name}
				}
			},
			"limit": 1
		}
	}

	var http_query := HTTPRequest.new()
	add_child(http_query)
	http_query.request_completed.connect(func(_r, code, _h, body):
		http_query.queue_free()
		if code != 200:
			return

		var arr = JSON.parse_string(body.get_string_from_utf8())
		if typeof(arr) != TYPE_ARRAY or arr.size() == 0:
			return

		var friend_uid = arr[0]["document"]["name"].get_file()
		var my_name = Auth.current_username

		var commit_url = "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents:commit" % PROJECT_ID
		var commit_body = {
			"writes": [
				{
					"transform": {
						"document": "projects/%s/databases/(default)/documents/users/%s" % [PROJECT_ID, uid],
						"fieldTransforms": [{
							"fieldPath": "friends",
							"removeAllFromArray": {"values": [{"stringValue": friend_name}]}
						}]
					}
				},
				{
					"transform": {
						"document": "projects/%s/databases/(default)/documents/users/%s" % [PROJECT_ID, friend_uid],
						"fieldTransforms": [{
							"fieldPath": "friends",
							"removeAllFromArray": {"values": [{"stringValue": my_name}]}
						}]
					}
				}
			]
		}
		var http_commit := HTTPRequest.new()
		add_child(http_commit)
		http_commit.request_completed.connect(func(_r2, code2, _h2, _b2):
			http_commit.queue_free()
			if code2 == 200:
				print("💔 Unfriended:", friend_name)
				await get_tree().create_timer(0.4).timeout
				load_friend_list()
		)
		http_commit.request(commit_url, headers, HTTPClient.METHOD_POST, JSON.stringify(commit_body))
	)
	http_query.request(query_url, headers, HTTPClient.METHOD_POST, JSON.stringify(query_body))
# ======================================================
# ➕ SEND FRIEND REQUEST
# ======================================================
func send_friend_request(target_username: String) -> void:
	if target_username == "" or target_username == Auth.current_username:
		push_error("⚠️ Invalid target.")
		return

	var token = Auth.current_id_token
	var sender_uid = Auth.current_local_id
	if token == "" or sender_uid == "":
		return

	print("[FriendRequest] Sending to:", target_username)

	var query_url = "%s:runQuery" % BASE_URL
	var query_body = {
		"structuredQuery": {
			"from": [{"collectionId": "users"}],
			"where": {
				"fieldFilter": {
					"field": {"fieldPath": "username"},
					"op": "EQUAL",
					"value": {"stringValue": target_username}
				}
			},
			"limit": 1
		}
	}
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer %s" % token
	]

	var http_query := HTTPRequest.new()
	add_child(http_query)
	http_query.request_completed.connect(func(_r, code, _h, body):
		http_query.queue_free()
		if code != 200:
			push_warning("⚠️ Query failed.")
			return

		var arr = JSON.parse_string(body.get_string_from_utf8())
		if typeof(arr) != TYPE_ARRAY or arr.size() == 0:
			push_warning("⚠️ User not found.")
			return

		var target_uid = arr[0]["document"]["name"].get_file()
		var sender_url = "%s/users/%s" % [BASE_URL, sender_uid]
		var http_sender := HTTPRequest.new()
		add_child(http_sender)
		http_sender.request_completed.connect(func(_r2, code2, _h2, body2):
			http_sender.queue_free()
			if code2 != 200:
				return
			var data2 = JSON.parse_string(body2.get_string_from_utf8())
			var sender_name = data2["fields"]["username"]["stringValue"]

			var commit_url = "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents:commit" % PROJECT_ID
			var commit_body = {
				"writes": [{
					"transform": {
						"document": "projects/%s/databases/(default)/documents/users/%s" % [PROJECT_ID, target_uid],
						"fieldTransforms": [{
							"fieldPath": "requests_received",
							"appendMissingElements": {
								"values": [{"stringValue": sender_name}]
							}
						}]
					}
				}]
			}
			var http_commit := HTTPRequest.new()
			add_child(http_commit)
			http_commit.request_completed.connect(func(_r3, code3, _h3, _b3):
				http_commit.queue_free()
				if code3 == 200:
					print("✅ Friend request sent to:", target_username)
					add_input.text = ""
			)
			http_commit.request(commit_url, headers, HTTPClient.METHOD_POST, JSON.stringify(commit_body))
		)
		http_sender.request(sender_url, headers, HTTPClient.METHOD_GET)
	)
	http_query.request(query_url, headers, HTTPClient.METHOD_POST, JSON.stringify(query_body))


# ======================================================
# 🤝 ACCEPT FRIEND REQUEST
# ======================================================
func accept_friend_request(sender_name: String) -> void:
	var uid = Auth.current_local_id
	var token = Auth.current_id_token
	if uid == "" or token == "":
		return

	print("[FriendRequest] Accepting:", sender_name)
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer %s" % token
	]

	var query_url = "%s:runQuery" % BASE_URL
	var query_body = {
		"structuredQuery": {
			"from": [{"collectionId": "users"}],
			"where": {
				"fieldFilter": {
					"field": {"fieldPath": "username"},
					"op": "EQUAL",
					"value": {"stringValue": sender_name}
				}
			},
			"limit": 1
		}
	}
	var http_query := HTTPRequest.new()
	add_child(http_query)
	http_query.request_completed.connect(func(_r, code, _h, body):
		http_query.queue_free()
		if code != 200:
			return

		var arr = JSON.parse_string(body.get_string_from_utf8())
		if typeof(arr) != TYPE_ARRAY or arr.size() == 0:
			return

		var sender_uid = arr[0]["document"]["name"].get_file()
		var my_name = Auth.current_username

		var commit_url = "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents:commit" % PROJECT_ID
		var commit_body = {
			"writes": [
				{
					"transform": {
						"document": "projects/%s/databases/(default)/documents/users/%s" % [PROJECT_ID, uid],
						"fieldTransforms": [
							{
								"fieldPath": "friends",
								"appendMissingElements": {"values": [{"stringValue": sender_name}]}
							},
							{
								"fieldPath": "requests_received",
								"removeAllFromArray": {"values": [{"stringValue": sender_name}]}
							}
						]
					}
				},
				{
					"transform": {
						"document": "projects/%s/databases/(default)/documents/users/%s" % [PROJECT_ID, sender_uid],
						"fieldTransforms": [
							{
								"fieldPath": "friends",
								"appendMissingElements": {"values": [{"stringValue": my_name}]}
							}
						]
					}
				}
			]
		}
		var http_commit := HTTPRequest.new()
		add_child(http_commit)
		http_commit.request_completed.connect(func(_r2, code2, _h2, _b2):
			http_commit.queue_free()
			if code2 == 200:
				print("✅ Accepted:", sender_name)
				await get_tree().create_timer(0.5).timeout
				load_friend_requests()
				load_friend_list()
		)
		http_commit.request(commit_url, headers, HTTPClient.METHOD_POST, JSON.stringify(commit_body))
	)
	http_query.request(query_url, headers, HTTPClient.METHOD_POST, JSON.stringify(query_body))


# ======================================================
# 🚫 DECLINE FRIEND REQUEST
# ======================================================
func decline_friend_request(sender_name: String) -> void:
	var uid = Auth.current_local_id
	var token = Auth.current_id_token
	if uid == "" or token == "":
		return

	print("[FriendRequest] Declining:", sender_name)
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer %s" % token
	]
	var commit_url = "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents:commit" % PROJECT_ID
	var commit_body = {
		"writes": [ {
			"transform": {
				"document": "projects/%s/databases/(default)/documents/users/%s" % [PROJECT_ID, uid],
				"fieldTransforms": [ {
					"fieldPath": "requests_received",
					"removeAllFromArray": {"values": [{"stringValue": sender_name}]}
				} ]
			}
		} ]
	}

	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_r, code, _h, _b):
		http.queue_free()
		if code == 200:
			print("🚫 Declined friend request from:", sender_name)
			load_friend_requests()
	)
	http.request(commit_url, headers, HTTPClient.METHOD_POST, JSON.stringify(commit_body))
