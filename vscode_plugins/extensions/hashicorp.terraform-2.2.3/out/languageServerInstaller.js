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
exports.LanguageServerInstaller = void 0;
const vscode = require("vscode");
const cp = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const https = require("https");
const os = require("os");
const semver = require("semver");
const yauzl = require("yauzl");
const del = require("del");
const openpgp = require("openpgp");
const releasesUrl = "https://releases.hashicorp.com/terraform-ls";
const hashiPublicKey = `-----BEGIN PGP PUBLIC KEY BLOCK-----

mQENBFMORM0BCADBRyKO1MhCirazOSVwcfTr1xUxjPvfxD3hjUwHtjsOy/bT6p9f
W2mRPfwnq2JB5As+paL3UGDsSRDnK9KAxQb0NNF4+eVhr/EJ18s3wwXXDMjpIifq
fIm2WyH3G+aRLTLPIpscUNKDyxFOUbsmgXAmJ46Re1fn8uKxKRHbfa39aeuEYWFA
3drdL1WoUngvED7f+RnKBK2G6ZEpO+LDovQk19xGjiMTtPJrjMjZJ3QXqPvx5wca
KSZLr4lMTuoTI/ZXyZy5bD4tShiZz6KcyX27cD70q2iRcEZ0poLKHyEIDAi3TM5k
SwbbWBFd5RNPOR0qzrb/0p9ksKK48IIfH2FvABEBAAG0K0hhc2hpQ29ycCBTZWN1
cml0eSA8c2VjdXJpdHlAaGFzaGljb3JwLmNvbT6JAU4EEwEKADgWIQSRpuf4XQXG
VjC+8YlRhS2HNI/8TAUCXn0BIQIbAwULCQgHAgYVCgkICwIEFgIDAQIeAQIXgAAK
CRBRhS2HNI/8TJITCACT2Zu2l8Jo/YLQMs+iYsC3gn5qJE/qf60VWpOnP0LG24rj
k3j4ET5P2ow/o9lQNCM/fJrEB2CwhnlvbrLbNBbt2e35QVWvvxwFZwVcoBQXTXdT
+G2cKS2Snc0bhNF7jcPX1zau8gxLurxQBaRdoL38XQ41aKfdOjEico4ZxQYSrOoC
RbF6FODXj+ZL8CzJFa2Sd0rHAROHoF7WhKOvTrg1u8JvHrSgvLYGBHQZUV23cmXH
yvzITl5jFzORf9TUdSv8tnuAnNsOV4vOA6lj61Z3/0Vgor+ZByfiznonPHQtKYtY
kac1M/Dq2xZYiSf0tDFywgUDIF/IyS348wKmnDGjuQENBFMORM0BCADWj1GNOP4O
wJmJDjI2gmeok6fYQeUbI/+Hnv5Z/cAK80Tvft3noy1oedxaDdazvrLu7YlyQOWA
M1curbqJa6ozPAwc7T8XSwWxIuFfo9rStHQE3QUARxIdziQKTtlAbXI2mQU99c6x
vSueQ/gq3ICFRBwCmPAm+JCwZG+cDLJJ/g6wEilNATSFdakbMX4lHUB2X0qradNO
J66pdZWxTCxRLomPBWa5JEPanbosaJk0+n9+P6ImPiWpt8wiu0Qzfzo7loXiDxo/
0G8fSbjYsIF+skY+zhNbY1MenfIPctB9X5iyW291mWW7rhhZyuqqxN2xnmPPgFmi
QGd+8KVodadHABEBAAGJATwEGAECACYCGwwWIQSRpuf4XQXGVjC+8YlRhS2HNI/8
TAUCXn0BRAUJEvOKdwAKCRBRhS2HNI/8TEzUB/9pEHVwtTxL8+VRq559Q0tPOIOb
h3b+GroZRQGq/tcQDVbYOO6cyRMR9IohVJk0b9wnnUHoZpoA4H79UUfIB4sZngma
enL/9magP1uAHxPxEa5i/yYqR0MYfz4+PGdvqyj91NrkZm3WIpwzqW/KZp8YnD77
VzGVodT8xqAoHW+bHiza9Jmm9Rkf5/0i0JY7GXoJgk4QBG/Fcp0OR5NUWxN3PEM0
dpeiU4GI5wOz5RAIOvSv7u1h0ZxMnJG4B4MKniIAr4yD7WYYZh/VxEPeiS/E1CVx
qHV5VVCoEIoYVHIuFIyFu1lIcei53VD6V690rmn0bp4A5hs+kErhThvkok3c
=+mCN
-----END PGP PUBLIC KEY BLOCK-----`;
class LanguageServerInstaller {
    install(directory) {
        return __awaiter(this, void 0, void 0, function* () {
            const { version: extensionVersion } = require('../package.json');
            const lspCmd = `${directory}/terraform-ls --version`;
            const userAgent = `Terraform-VSCode/${extensionVersion} VSCode/${vscode.version}`;
            let isInstalled = true;
            try {
                var { stdout, stderr: installedVersion } = yield exec(lspCmd);
            }
            catch (err) {
                // TODO: verify error was in fact binary not found
                isInstalled = false;
            }
            const currentRelease = yield checkLatest(userAgent);
            if (isInstalled) {
                if (semver.gt(currentRelease.version, installedVersion, { includePrerelease: true })) {
                    const selected = yield vscode.window.showInformationMessage(`A new language server release is available: ${currentRelease.version}. Install now?`, 'Install', 'Cancel');
                    if (selected === 'Cancel') {
                        return;
                    }
                }
                else {
                    return;
                }
            }
            try {
                yield this.installPkg(directory, currentRelease, userAgent);
            }
            catch (err) {
                vscode.window.showErrorMessage('Unable to install terraform-ls');
                console.error(err);
                throw err;
            }
            // Do not wait on the showInformationMessage
            vscode.window.showInformationMessage(`Installed terraform-ls ${currentRelease.version}.`, "View Changelog")
                .then(selected => {
                if (selected === "View Changelog") {
                    return vscode.env.openExternal(vscode.Uri.parse(`https://github.com/hashicorp/terraform-ls/releases/tag/v${currentRelease.version}`));
                }
            });
        });
    }
    installPkg(installDir, release, userAgent) {
        return __awaiter(this, void 0, void 0, function* () {
            const destination = `${installDir}/terraform-ls_v${release.version}.zip`;
            fs.mkdirSync(installDir, { recursive: true }); // create install directory if missing
            let platform = os.platform().toString();
            if (platform === 'win32') {
                platform = 'windows';
            }
            let arch = os.arch();
            switch (arch) {
                case 'x64':
                    arch = 'amd64';
                    break;
                case 'x32':
                    arch = '386';
                    break;
            }
            const build = release.builds.find(b => b.os === platform && b.arch === arch);
            const downloadUrl = build.url;
            if (!downloadUrl) {
                throw new Error("Install error: no matching terraform-ls binary for platform");
            }
            try {
                this.removeOldBinary(installDir, platform);
            }
            catch (_a) {
                // ignore missing binary (new install)
            }
            return vscode.window.withProgress({
                cancellable: true,
                location: vscode.ProgressLocation.Notification,
                title: "Installing terraform-ls"
            }, (progress, token) => __awaiter(this, void 0, void 0, function* () {
                progress.report({ increment: 30 });
                yield this.download(downloadUrl, destination, userAgent);
                progress.report({ increment: 30 });
                yield this.verify(release, destination, build.filename);
                progress.report({ increment: 30 });
                return this.unpack(installDir, destination);
            }));
        });
    }
    removeOldBinary(directory, platform) {
        if (platform === "windows") {
            fs.unlinkSync(`${directory}/terraform-ls.exe`);
        }
        else {
            fs.unlinkSync(`${directory}/terraform-ls`);
        }
    }
    download(downloadUrl, installPath, identifier) {
        const headers = { 'User-Agent': identifier };
        return new Promise((resolve, reject) => {
            https.request(downloadUrl, { headers: headers }, (response) => {
                if (response.statusCode === 301 || response.statusCode === 302) { // redirect for CDN
                    const redirectUrl = response.headers.location;
                    return resolve(this.download(redirectUrl, installPath, identifier));
                }
                if (response.statusCode !== 200) {
                    return reject(response.statusMessage);
                }
                response
                    .on('error', reject)
                    .on('end', resolve)
                    .pipe(fs.createWriteStream(installPath))
                    .on('error', reject);
            })
                .on('error', reject)
                .end();
        });
    }
    verify(release, pkg, buildName) {
        return __awaiter(this, void 0, void 0, function* () {
            const [localSum, remoteSum] = yield Promise.all([
                this.calculateFileSha256Sum(pkg),
                this.downloadSha256Sum(release, buildName)
            ]);
            if (remoteSum !== localSum) {
                throw new Error(`Install error: SHA sum for ${buildName} does not match.\n` +
                    `(expected: ${remoteSum} calculated: ${localSum})`);
            }
        });
    }
    calculateFileSha256Sum(path) {
        return new Promise((resolve, reject) => {
            const hash = crypto.createHash('sha256');
            fs.createReadStream(path)
                .on('error', reject)
                .on('data', data => hash.update(data))
                .on('end', () => resolve(hash.digest('hex')));
        });
    }
    downloadSha256Sum(release, buildName) {
        return __awaiter(this, void 0, void 0, function* () {
            const [shasumResponse, signature] = yield Promise.all([
                httpsRequest(`${releasesUrl}/${release.version}/${release.shasums}`),
                httpsRequest(`${releasesUrl}/${release.version}/${release.shasums_signature}`, {}, 'hex'),
            ]);
            const verified = yield openpgp.verify({
                message: openpgp.message.fromText(shasumResponse),
                publicKeys: (yield openpgp.key.readArmored(hashiPublicKey)).keys,
                signature: yield openpgp.signature.read(Buffer.from(signature, 'hex'))
            });
            const { valid } = verified.signatures[0];
            if (!valid) {
                throw new Error('signature could not be verified');
            }
            const shasumLine = shasumResponse.split(`\n`).find(line => line.includes(buildName));
            if (!shasumLine) {
                throw new Error(`Install error: no matching SHA sum for ${buildName}`);
            }
            return shasumLine.split("  ")[0];
        });
    }
    unpack(directory, pkgName) {
        return new Promise((resolve, reject) => {
            let executable;
            yauzl.open(pkgName, { lazyEntries: true }, (err, zipfile) => {
                if (err) {
                    return reject(err);
                }
                zipfile.readEntry();
                zipfile.on('entry', (entry) => {
                    zipfile.openReadStream(entry, (err, readStream) => {
                        if (err) {
                            return reject(err);
                        }
                        readStream.on('end', () => {
                            zipfile.readEntry(); // Close it
                        });
                        executable = `${directory}/${entry.fileName}`;
                        const destination = fs.createWriteStream(executable);
                        readStream.pipe(destination);
                    });
                });
                zipfile.on('close', () => {
                    fs.chmodSync(executable, '755');
                    return resolve();
                });
            });
        });
    }
    cleanupZips(directory) {
        return __awaiter(this, void 0, void 0, function* () {
            return del(`${directory}/terraform-ls*.zip`, { force: true });
        });
    }
}
exports.LanguageServerInstaller = LanguageServerInstaller;
function exec(cmd) {
    return new Promise((resolve, reject) => {
        cp.exec(cmd, (err, stdout, stderr) => {
            if (err) {
                return reject(err);
            }
            return resolve({ stdout, stderr });
        });
    });
}
function httpsRequest(url, options = {}, encoding = 'utf8') {
    return new Promise((resolve, reject) => {
        https.request(url, options, res => {
            if (res.statusCode === 301 || res.statusCode === 302) { // follow redirects
                return resolve(httpsRequest(res.headers.location, options, encoding));
            }
            if (res.statusCode !== 200) {
                return reject(res.statusMessage);
            }
            let body = '';
            res.setEncoding(encoding)
                .on('data', data => body += data)
                .on('end', () => resolve(body));
        })
            .on('error', reject)
            .end();
    });
}
function checkLatest(userAgent) {
    return __awaiter(this, void 0, void 0, function* () {
        const indexUrl = `${releasesUrl}/index.json`;
        const headers = { 'User-Agent': userAgent };
        const body = yield httpsRequest(indexUrl, { headers });
        let releases = JSON.parse(body);
        const currentRelease = Object.keys(releases.versions).sort(semver.rcompare)[0];
        return releases.versions[currentRelease];
    });
}
//# sourceMappingURL=languageServerInstaller.js.map