---@class discord.Gateway.Intents : number
local GatewayIntents = {
	Guilds = bit.lshift(1, 0),
	GuildMembers = bit.lshift(1, 1),
	GuildModeration = bit.lshift(1, 2),
	GuildExpressions = bit.lshift(1, 3),
	GuildIntegrations = bit.lshift(1, 4),
	GuildWebhooks = bit.lshift(1, 5),
	GuildInvites = bit.lshift(1, 6),
	GuildVoiceStates = bit.lshift(1, 7),
	GuildPresences = bit.lshift(1, 8),
	GuildMessages = bit.lshift(1, 9),
	GuildMessageReactions = bit.lshift(1, 10),
	GuildMessageMessageTyping = bit.lshift(1, 11),
	DirectMessages = bit.lshift(1, 12),
	DirectMessageReactions = bit.lshift(1, 13),
	DirectMessageTyping = bit.lshift(1, 14),
	MessageContent = bit.lshift(1, 15),
	GuildScheduledEvents = bit.lshift(1, 16),
	AutoModerationConfiguration = bit.lshift(1, 20),
	GuildMessagePolls = bit.lshift(1, 24),
	DirectMessagePolls = bit.lshift(1, 25)
}

return GatewayIntents
