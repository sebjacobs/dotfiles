"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.runCommand = void 0;
const child_process_1 = require("child_process");
function runCommand(rootPath, outputChannel, command) {
    if (rootPath) {
        outputChannel.show(true);
        outputChannel.appendLine(`Running terraform ${command}`);
        console.log(rootPath);
        child_process_1.exec(`terraform ${command} -no-color ${rootPath}`, (err, stdout, stderr) => {
            if (err) {
                outputChannel.appendLine(err.message);
            }
            if (stdout) {
                outputChannel.appendLine(stdout);
            }
            if (stderr) {
                outputChannel.appendLine(stderr);
            }
        });
    }
}
exports.runCommand = runCommand;
//# sourceMappingURL=terraformCommand.js.map