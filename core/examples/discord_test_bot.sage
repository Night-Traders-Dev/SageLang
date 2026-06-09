import discord.client

proc on_ready(data):
    print("Bot is ready!")

proc on_message(data):
    print("Received message: " + data["content"])

let bot = discord.client.Client("YOUR_TOKEN", 32767) # Intents for all messages
bot.on("READY", on_ready)
bot.on("MESSAGE_CREATE", on_message)

bot.run()
