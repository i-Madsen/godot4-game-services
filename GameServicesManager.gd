extends Node

var is_authorized = false
var is_friends_authorized = false
var this_player: GSPlayer
var friend_players: Dictionary = {}
var avatarIcons: Dictionary = {}

var firstAuthorizationCheck: bool = true

signal authenticated_player(authenticated)
signal friends_authorized(authorized)
signal downloaded_avatar
signal downloaded_avatars

func _init():
	GameServices.authorization_complete.connect(_on_authorization_complete)
	GameServices.authorization_failed.connect(_on_authorization_failed)
	GameServices.get_friends_authorization_status_complete.connect(_on_get_friends_authorization_status_complete)
	GameServices.get_friends_authorization_status_failed.connect(_on_get_friends_authorization_status_failed)
	GameServices.load_friends_complete.connect(_on_load_friends_complete)
	GameServices.load_friends_failed.connect(_on_load_friends_failed)
	GameServices.fetch_friend_avatar_complete.connect(_on_fetch_friend_avatar_complete)
	GameServices.fetch_friend_avatar_failed.connect(_on_fetch_friend_avatar_failed)
	
func _ready():
	GameServices.initialize()

func _on_authorization_complete(authenticated: bool, player: GSPlayer):
	is_authorized = authenticated
	this_player = player
	print("Authenticated: " + str(authenticated) + " player: " + str(player))
	authenticated_player.emit(authenticated)
	
	GameServices.get_friends_authorization_status()

func _on_authorization_failed(error_message: String):
	is_authorized = false
	print("Failed to authenticate player, reason: " + error_message)

# authorization_enum:  notDetermined = 0, restricted = 1, denied = 2, authorized = 3
# Only calls load_friends() from first check, not second
func _on_get_friends_authorization_status_complete(authorization_enum: int):
	print("Got friend authorization status: " + str(authorization_enum))
	if authorization_enum == 0:
		if firstAuthorizationCheck:
			print("Friends list authorization undetermined, will try to load_friends() and recheck.")
			GameServices.load_friends()
		else:
			print("Friends list authorization still undetermined in second check.")
	else:
		if authorization_enum == 3:
			is_friends_authorized = true
			friends_authorized.emit(true)
			print("Friends list is authorized!")
			if firstAuthorizationCheck:
				GameServices.load_friends()
		else:
			friends_authorized.emit(false)
			print("Friends list is not authorized.")
	
	firstAuthorizationCheck = false

func _on_get_friends_authorization_status_failed(error_message: String):
	friends_authorized.emit(false)
	print("Failed to get friends authorization status reason: " + error_message)

# friends = Array<GSPlayer>
func _on_load_friends_complete(friends: Array):
	print("Got friends: " + str(friends))
	if friends.size() > 0:
		print("Getting friend avatars...")
		for friend in friends:
			friend_players[friend.id] = friend
			GameServices.fetch_friend_avatar(friend.id)
			await downloaded_avatar
	
	print("Getting own avatar...")
	GameServices.fetch_friend_avatar(this_player.id)
	await downloaded_avatar
	
	if !is_friends_authorized:
		GameServices.get_friends_authorization_status()
		await friends_authorized
		
	downloaded_avatars.emit()

func _on_load_friends_failed(error_message: String):
	print("Failed to fetch friend avatars reason: " + error_message)
	GameServices.get_friends_authorization_status()

func _on_fetch_friend_avatar_complete(friend_name, friend_img: Image):
	print("Got friend avatar: " + str(friend_img) + " id: " + str(friend_name))

	# Optionally resize the image if it is too large
	if friend_img.get_width() > 128:
		friend_img.resize(128, 128, Image.INTERPOLATE_LANCZOS)

	# Apply the image to a texture
	var avatar_texture: ImageTexture = ImageTexture.create_from_image(friend_img)
	
	# Add to friend icon dict
	avatarIcons[friend_name] = avatar_texture
	
	downloaded_avatar.emit()

func _on_fetch_friend_avatar_failed(error_message: String):
	print("Failed to fetch friend avatar reason: " + error_message)
