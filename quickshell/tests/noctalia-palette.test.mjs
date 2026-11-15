import assert from "node:assert/strict";
import test from "node:test";
import vm from "node:vm";
import { source } from "./qml-script.mjs";

const ctx = vm.createContext({});
vm.runInContext(source("../Common/NoctaliaPalette.js").replace(/^\.pragma.*$/gm, ""), ctx);
const parse = vm.runInContext("parse", ctx);

test("Noctalia Qt palette maps colors and detects appearance", () => {
    const roles = Array(22).fill("#eeeeee");
    roles[10] = "#101010";
    roles[12] = "#aabbcc";
    roles[13] = "#000000";
    roles[21] = "#123456";
    const result = parse(`[ColorScheme]\nactive_colors=${roles.join(", ")}\n`);
    assert.equal(result.light, false);
    assert.equal(result.colors.primary, "#123456");
    assert.equal(result.colors.primaryText, "#000000");
    roles[10] = "#fafafa";
    assert.equal(parse(`active_colors=${roles.join(",")}`).light, true);
});

test("incomplete and invalid palettes are ignored", () => {
    assert.equal(parse(""), null);
    assert.equal(parse("active_colors=#ffffff"), null);
    assert.equal(parse(`active_colors=${Array(21).fill("red").join(",")}`), null);
});
