// JavaScript (+ JSX): same unit shapes as typescript.mjs, minus the type
// kinds the javascript grammar doesn't have (an unknown kind fails the scan).
const anyKind = (ks) => `{any: [${ks.map((k) => `{kind: ${k}}`).join(", ")}]}`;
const TOP = "{inside: {any: [{kind: program}, {kind: export_statement}]}}";
const FN_VALUE = "{has: {kind: variable_declarator, has: {field: value, any: [{kind: arrow_function}, {kind: function_expression}]}}}";

export const meta = {
  description: "JavaScript/JSX: fn, class, const",
  display: "JavaScript",
  exts: [".js", ".mjs", ".cjs", ".jsx"],
  grammar: "javascript",
  kinds: {
    fn: `{any: [{kind: function_declaration}, {kind: generator_function_declaration}, {kind: method_definition}, {all: [{kind: lexical_declaration}, ${TOP}, ${FN_VALUE}]}]}`,
    class: anyKind(["class_declaration"]),
    const: `{all: [{kind: lexical_declaration}, ${TOP}, {not: ${FN_VALUE}}]}`,
  },
  trivial: /^\s*(import\s|export\s*\{|\/\/|[{}();,\]]*\s*$)/,
};
