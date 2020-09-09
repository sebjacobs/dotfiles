"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getLines = (output) => {
    if (!output) {
        return [];
    }
    return output.split("\n")
        .filter((x) => {
        if (x.length) {
            return x;
        }
    });
};
exports.getFileInfo = (line, index = 0) => {
    const fileInfo = (line.split(" ")[2] || "").split(":");
    const found = fileInfo[index];
    return found || "";
};
exports.getLineInfoCheck = (info, line) => {
    const lintInfo = line.split(" ");
    const checkIndex = 0;
    info.check = (lintInfo[checkIndex] || [])[1];
    return info;
};
exports.getLineInfoColumn = (info, line) => {
    const column = exports.getFileInfo(line, 2);
    info.column = column ? parseInt(column, 10) : undefined;
    return info;
};
exports.getLineInfoMessage = (info, line) => {
    const lintInfo = line.split(" ");
    const messageIndex = 3;
    info.message = lintInfo.slice(messageIndex).join(" ") || undefined;
    return info;
};
exports.getLineInfoPosition = (info, line) => {
    const position = exports.getFileInfo(line, 1);
    info.position = position ? parseInt(position, 10) : undefined;
    return info;
};
exports.getLineInfo = (line) => {
    if (!line) {
        return;
    }
    const result = [{}].map((info) => {
        return exports.getLineInfoCheck(info, line);
    }).map((info) => {
        return exports.getLineInfoMessage(info, line);
    }).map((info) => {
        return exports.getLineInfoColumn(info, line);
    }).map((info) => {
        return exports.getLineInfoPosition(info, line);
    });
    return result[0];
};
//# sourceMappingURL=parse.js.map