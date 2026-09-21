// JSON config test file
const config = require("./config.json");
const { Client, Events } = require("discord.js");

const token = config.token;
const clientId = config.clientId;

module.exports = { token, clientId, config };