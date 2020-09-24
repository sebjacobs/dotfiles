"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.deactivate = exports.activate = void 0;
const vscode = require("vscode");
const vscode_languageclient_1 = require("vscode-languageclient");
const languageServerInstaller_1 = require("./languageServerInstaller");
let clients = new Map();
let extensionPath;
function activate(context) {
    return __awaiter(this, void 0, void 0, function* () {
        extensionPath = context.extensionPath;
        const commandOutput = vscode.window.createOutputChannel('Terraform');
        // get rid of pre-2.0.0 settings
        if (config('terraform').has('languageServer.enabled')) {
            try {
                yield config('terraform').update('languageServer', { enabled: undefined, external: true }, vscode.ConfigurationTarget.Global);
            }
            catch (err) {
                console.error(`Error trying to erase pre-2.0.0 settings: ${err.message}`);
            }
        }
        // Terraform Commands
        // TODO switch to using the workspace/execute_command API
        // https://microsoft.github.io/language-server-protocol/specifications/specification-current/#workspace_executeCommand
        // const rootPath = vscode.workspace.workspaceFolders[0].uri.path;
        // context.subscriptions.push(
        // 	vscode.commands.registerCommand('terraform.init', () => {
        // 		runCommand(rootPath, commandOutput, 'init');
        // 	}),
        // 	vscode.commands.registerCommand('terraform.plan', () => {
        // 		runCommand(rootPath, commandOutput, 'plan');
        // 	}),
        // 	vscode.commands.registerCommand('terraform.validate', () => {
        // 		runCommand(rootPath, commandOutput, 'validate');
        // 	})
        // );
        // Subscriptions
        context.subscriptions.push(vscode.commands.registerCommand('terraform.enableLanguageServer', () => __awaiter(this, void 0, void 0, function* () {
            if (!enabled()) {
                let current = config('terraform').get('languageServer');
                yield config('terraform').update('languageServer', Object.assign(current, { external: true }), vscode.ConfigurationTarget.Global);
            }
            return startClients();
        })), vscode.commands.registerCommand('terraform.disableLanguageServer', () => __awaiter(this, void 0, void 0, function* () {
            if (enabled()) {
                let current = config('terraform').get('languageServer');
                yield config('terraform').update('languageServer', Object.assign(current, { external: false }), vscode.ConfigurationTarget.Global);
            }
            return stopClients();
        })), vscode.workspace.onDidChangeConfiguration((event) => __awaiter(this, void 0, void 0, function* () {
            if (event.affectsConfiguration('terraform') || event.affectsConfiguration('terraform-ls')) {
                const reloadMsg = 'Reload VSCode window to apply language server changes';
                const selected = yield vscode.window.showInformationMessage(reloadMsg, 'Reload');
                if (selected === 'Reload') {
                    vscode.commands.executeCommand('workbench.action.reloadWindow');
                }
            }
        })), vscode.workspace.onDidChangeWorkspaceFolders((event) => __awaiter(this, void 0, void 0, function* () {
            if (event.removed.length > 0) {
                yield stopClients(folderNames(event.removed));
            }
            if (event.added.length > 0) {
                yield startClients(folderNames(event.added));
            }
        })));
        if (enabled()) {
            return vscode.commands.executeCommand('terraform.enableLanguageServer');
        }
    });
}
exports.activate = activate;
function deactivate() {
    return stopClients();
}
exports.deactivate = deactivate;
function startClients(folders = folderNames()) {
    return __awaiter(this, void 0, void 0, function* () {
        console.log('Starting:', folders);
        const command = yield pathToBinary();
        let disposables = [];
        for (const folder of folders) {
            if (!clients.has(folder)) {
                const client = newClient(command, folder);
                disposables.push(client.start());
                clients.set(folder, client);
            }
            else {
                console.log(`Client for folder: ${folder} already started`);
            }
        }
        return disposables;
    });
}
function newClient(cmd, folder) {
    const binaryName = cmd.split('/').pop();
    const channelName = `${binaryName}/${folder}`;
    const f = workspaceFolder(folder);
    const serverArgs = config('terraform').get('languageServer.args');
    const rootModulePaths = config('terraform-ls', f).get('rootModules');
    const excludeModulePaths = config('terraform-ls', f).get('excludeRootModules');
    if (rootModulePaths.length > 0 && excludeModulePaths.length > 0) {
        throw new Error('Only one of rootModules and excludeRootModules can be set at the same time, please remove the conflicting config and reload');
    }
    let initializationOptions = {};
    if (rootModulePaths.length > 0) {
        initializationOptions = { rootModulePaths };
    }
    if (excludeModulePaths.length > 0) {
        initializationOptions = { excludeModulePaths };
    }
    const setup = vscode.window.createOutputChannel(channelName);
    setup.appendLine(`Launching language server: ${cmd} ${serverArgs.join(' ')} for folder: ${folder}`);
    const executable = {
        command: cmd,
        args: serverArgs,
        options: {}
    };
    const serverOptions = {
        run: executable,
        debug: executable
    };
    const clientOptions = {
        documentSelector: [{ scheme: 'file', language: 'terraform', pattern: `${f.uri.fsPath}/**/*` }],
        workspaceFolder: f,
        initializationOptions: initializationOptions,
        outputChannel: setup,
        revealOutputChannelOn: 4 // hide always
    };
    return new vscode_languageclient_1.LanguageClient(`languageServer/${folder}`, `Language Server: ${folder}`, serverOptions, clientOptions);
}
function stopClients(folders = folderNames()) {
    return __awaiter(this, void 0, void 0, function* () {
        console.log('Stopping:', folders);
        let promises = [];
        for (const folder of folders) {
            if (clients.has(folder)) {
                promises.push(clients.get(folder).stop());
                clients.delete(folder);
            }
            else {
                console.log(`Attempted to stop a client for folder: ${folder} but no client exists`);
            }
        }
        return Promise.all(promises);
    });
}
let _pathToBinaryPromise;
function pathToBinary() {
    return __awaiter(this, void 0, void 0, function* () {
        if (!_pathToBinaryPromise) {
            let command = config('terraform').get('languageServer.pathToBinary');
            if (!command) { // Skip install/upgrade if user has set custom binary path
                const installDir = `${extensionPath}/lsp`;
                const installer = new languageServerInstaller_1.LanguageServerInstaller();
                try {
                    yield installer.install(installDir);
                }
                catch (err) {
                    vscode.window.showErrorMessage(err);
                    throw err;
                }
                finally {
                    yield installer.cleanupZips(installDir);
                }
                command = `${installDir}/terraform-ls`;
            }
            _pathToBinaryPromise = Promise.resolve(command);
        }
        return _pathToBinaryPromise;
    });
}
function config(section, scope) {
    return vscode.workspace.getConfiguration(section, scope);
}
function workspaceFolder(folder) {
    return vscode.workspace.getWorkspaceFolder(vscode.Uri.parse(folder));
}
function folderNames(folders = vscode.workspace.workspaceFolders) {
    if (!folders) {
        return [];
    }
    return folders.map(folder => {
        let result = folder.uri.toString();
        if (result.charAt(result.length - 1) !== '/') {
            result = result + '/';
        }
        return result;
    });
}
function enabled() {
    return config('terraform').get('languageServer.external');
}
//# sourceMappingURL=extension.js.map