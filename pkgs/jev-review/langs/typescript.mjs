// TypeScript (+ TSX): top-level and method functions, classes, types,
// non-function top-level consts.
const anyKind = (ks) => `{any: [${ks.map((k) => `{kind: ${k}}`).join(", ")}]}`;
const TOP = "{inside: {any: [{kind: program}, {kind: export_statement}]}}";
const FN_VALUE = "{has: {kind: variable_declarator, has: {field: value, any: [{kind: arrow_function}, {kind: function_expression}]}}}";

export const meta = {
  description: "TypeScript/TSX: fn, class, type (interface/alias/enum), const",
  display: "TypeScript",
  exts: [".ts", ".mts", ".cts", ".tsx"],
  grammar: ["typescript", "tsx"],
  kinds: {
    fn: `{any: [{kind: function_declaration}, {kind: generator_function_declaration}, {kind: method_definition}, {all: [{kind: lexical_declaration}, ${TOP}, ${FN_VALUE}]}]}`,
    class: anyKind(["class_declaration", "abstract_class_declaration"]),
    type: anyKind(["interface_declaration", "type_alias_declaration", "enum_declaration"]),
    const: `{all: [{kind: lexical_declaration}, ${TOP}, {not: ${FN_VALUE}}]}`,
  },
  trivial: /^\s*(import\s|export\s*\{|\/\/|[{}();,\]]*\s*$)/,
};
