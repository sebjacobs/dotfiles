"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
/**
 * When the extension is activated by VS Code it activates its own helper to handle
 * the linting and then registers that helper as a code action provider.
 */
const vscode = require("vscode");
const credoProvider_1 = require("./credoProvider");
function activate(context) {
    const linter = new credoProvider_1.default(vscode);
    linter.activate(context.subscriptions, vscode);
}
exports.activate = activate;
//# sourceMappingURL=extension.js.map