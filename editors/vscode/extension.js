/*
 * Sage Language VSCode Extension
 *
 * Starts the Sage LSP server (sage --lsp) and connects the
 * vscode-languageclient to it for diagnostics, completion,
 * hover, and formatting support.
 */

const { workspace } = require("vscode");
const {
    LanguageClient,
    TransportKind,
} = require("vscode-languageclient/node");

let client;

function activate(context) {
    const config = workspace.getConfiguration("sage.lsp");
    const enabled = config.get("enabled", true);

    if (!enabled) {
        return;
    }

    const sagePath = config.get("path", "sage");

    /* Determine command and args based on the configured path */
    let command, args;
    if (sagePath.endsWith("sage-lsp")) {
        command = sagePath;
        args = [];
    } else {
        command = sagePath;
        args = ["--lsp"];
    }

    const serverOptions = {
        run: {
            command: command,
            args: args,
            transport: TransportKind.stdio,
        },
        debug: {
            command: command,
            args: args,
            transport: TransportKind.stdio,
        },
    };

    const clientOptions = {
        documentSelector: [{ scheme: "file", language: "sage" }],
        synchronize: {
            fileEvents: workspace.createFileSystemWatcher("**/*.sage"),
        },
    };

    client = new LanguageClient(
        "sageLSP",
        "Sage Language Server",
        serverOptions,
        clientOptions
    );

    client.start();
}

function deactivate() {
    if (client) {
        return client.stop();
    }
}

module.exports = { activate, deactivate };
