// Discord.js bootstrap test (from plan section 4.1)
const { Client, GatewayIntentBits, Events } = require("discord.js");

const client = new Client({
  intents: [GatewayIntentBits.Guilds],
});

client.once(Events.ClientReady, c => {
  console.log(`Ready as ${c.user.tag}`);
});

client.login(process.env.DISCORD_TOKEN);