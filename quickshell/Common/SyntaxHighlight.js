.pragma library

const languageByExtension = {
    "c": "c", "h": "c", "cc": "cpp", "cpp": "cpp", "cxx": "cpp", "hpp": "cpp", "hh": "cpp",
    "go": "go", "js": "js", "jsx": "js", "mjs": "js", "cjs": "js", "ts": "js", "tsx": "js",
    "py": "python", "rs": "rust", "sh": "shell", "bash": "shell", "zsh": "shell",
    "json": "json", "jsonc": "json", "yaml": "yaml", "yml": "yaml", "toml": "toml", "xml": "xml"
};

const keywords = {
    c: "auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while bool true false NULL",
    cpp: "alignas alignof auto bool break case catch char class const constexpr continue decltype default delete do double else enum explicit export extern false float for friend goto if inline int long namespace new noexcept nullptr operator private protected public register return short signed sizeof static struct switch template this throw true try typedef typename union unsigned using virtual void volatile while",
    go: "break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr true false nil",
    js: "async await break case catch class const continue debugger default delete do else export extends false finally for from function get if import in instanceof let new of return set static super switch this throw try typeof undefined var void while with yield true null",
    python: "and as assert async await break class continue def del elif else except False finally for from global if import in is lambda nonlocal not or pass raise return True try while with yield None",
    rust: "as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while",
    shell: "case do done elif else esac fi for function if in select then until while",
    json: "true false null",
    yaml: "true false null yes no on off",
    toml: "true false"
};
const keywordSets = ({});
for (const language in keywords)
    keywordSets[language] = keywords[language].split(/\s+/);

function languageFor(path) {
    const name = String(path || "").split(/[\\/]/).pop() || "";
    const dot = name.lastIndexOf(".");
    return dot < 0 ? "" : languageByExtension[name.slice(dot + 1).toLowerCase()] || "";
}

function escaped(value) {
    return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function lineHtml(line, language, palette) {
    const keywordList = keywordSets[language] || [];
    const hashComments = ["python", "shell", "yaml", "toml"].includes(language);
    const literals = /"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`/;
    const comments = hashComments ? /#.*/ : /\/\/.*|\/\*.*?\*\//;
    const wordsAndNumbers = /[A-Za-z_$][\w$]*|\b\d+(?:\.\d+)?\b/;
    const tokenRegex = new RegExp([literals.source, comments.source, wordsAndNumbers.source].join("|"), "g");
    let output = "";
    let index = 0;
    let match;
    while ((match = tokenRegex.exec(line)) !== null) {
        const value = match[0];
        output += escaped(line.slice(index, match.index));
        let color = /^(?:\"|'|`)/.test(value) ? palette.string : "";
        if (/^(?:\/\/|\/\*|#)/.test(value))
            color = palette.comment;
        if (keywordList.indexOf(value) >= 0)
            color = palette.keyword;
        else if (/^\d/.test(value))
            color = palette.number;
        output += color ? `<span style="color:${color}">${escaped(value)}</span>` : escaped(value);
        index = tokenRegex.lastIndex;
    }
    return output + escaped(line.slice(index));
}

function highlight(source, language, palette) {
    if (!language)
        return "<pre style=\"margin:0; white-space:pre-wrap\">" + String(source).split("\n").map(escaped).join("<br/>") + "</pre>";
    const colors = {
        keyword: palette?.keyword || "#c678dd",
        number: palette?.number || "#d19a66",
        string: palette?.string || "#98c379",
        comment: palette?.comment || "#7f848e"
    };
    return "<pre style=\"margin:0; white-space:pre-wrap\">" + String(source).split("\n").map(line => lineHtml(line, language, colors)).join("<br/>") + "</pre>";
}
