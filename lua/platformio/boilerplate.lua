local M = {}
local uv = vim.loop

local boilerplate = {}

boilerplate['arduino'] = {
  -- filename = 'main.cpp',
  content = [[
#include <Arduino.h>

void setup() {

}

void loop() {

}
]],
}

boilerplate['extra_script.py'] = {
  -- filename = 'main.cpp',
  content = [[
Import("env")

def set_compilation_db_toolchain(env):
    # This runs after the environment is fully initialized
    env.Replace(COMPILATIONDB_INCLUDE_TOOLCHAIN=True)

# Add the function as a callback for the environment
env.AddMethod(set_compilation_db_toolchain)
set_compilation_db_toolchain(env)

]],
}
--[[
from SCons.Script import DefaultEnvironment
env = DefaultEnvironment()
env.Replace(COMPILATIONDB_INCLUDE_TOOLCHAIN=True)

# Optional: ensure it saves to the root of your project
#env.Replace(COMPILATIONDB_PATH="compile_commands.json")
]]

boilerplate['.clangd_cmd'] = {
  -- filename = '.clangd_cmd',
  content = [[
clangd
--all-scopes-completion
--background-index
--clang-tidy
--compile_args_from=filesystem
--compile-commands-dir=.
--enable-config
--completion-parse=always
--completion-style=detailed
--header-insertion=iwyu
--header-insertion-decorators
-j=12
--log=verbose
--offset-encoding=utf-8
--pch-storage=memory
--pretty
--ranking-model=decision_forest
--query-driver=]] .. vim.env.HOME .. [[/.platformio/packages/toolchain-*/bin/*]],
}

--query-driver = [[clangd --query-driver=]] .. vim.env.HOME .. [[/.platformio/packages/*]]
--query-driver=**

boilerplate['.clang-format'] = {
  -- filename = '.clang-format',
  content = [[
---
Language:        Cpp
# BasedOnStyle:  LLVM
AccessModifierOffset: -2
AlignAfterOpenBracket: Align
AlignArrayOfStructures: None
AlignConsecutiveAssignments:
  Enabled:         false
  AcrossEmptyLines: false
  AcrossComments:  false
  AlignCompound:   false
  AlignFunctionPointers: false
  PadOperators:    true
AlignConsecutiveBitFields:
  Enabled:         false
  AcrossEmptyLines: false
  AcrossComments:  false
  AlignCompound:   false
  AlignFunctionPointers: false
  PadOperators:    false
AlignConsecutiveDeclarations:
  Enabled:         false
  AcrossEmptyLines: false
  AcrossComments:  false
  AlignCompound:   false
  AlignFunctionPointers: false
  PadOperators:    false
AlignConsecutiveMacros:
  Enabled:         false
  AcrossEmptyLines: false
  AcrossComments:  false
  AlignCompound:   false
  AlignFunctionPointers: false
  PadOperators:    false
AlignConsecutiveShortCaseStatements:
  Enabled:         false
  AcrossEmptyLines: false
  AcrossComments:  false
  AlignCaseColons: false
AlignEscapedNewlines: Right
AlignOperands:   Align
AlignTrailingComments:
  Kind:            Always
  OverEmptyLines:  0
AllowAllArgumentsOnNextLine: true
AllowAllParametersOfDeclarationOnNextLine: true
AllowBreakBeforeNoexceptSpecifier: Never
AllowShortBlocksOnASingleLine: Never
AllowShortCaseLabelsOnASingleLine: false
AllowShortCompoundRequirementOnASingleLine: true
AllowShortEnumsOnASingleLine: true
AllowShortFunctionsOnASingleLine: All
AllowShortIfStatementsOnASingleLine: Never
AllowShortLambdasOnASingleLine: All
AllowShortLoopsOnASingleLine: false
AlwaysBreakAfterDefinitionReturnType: None
AlwaysBreakAfterReturnType: None
AlwaysBreakBeforeMultilineStrings: false
AlwaysBreakTemplateDeclarations: MultiLine
AttributeMacros:
  - __capability
BinPackArguments: true
BinPackParameters: true
BitFieldColonSpacing: Both
BraceWrapping:
  AfterCaseLabel:  false
  AfterClass:      false
  AfterControlStatement: Never
  AfterEnum:       false
  AfterExternBlock: false
  AfterFunction:   false
  AfterNamespace:  false
  AfterObjCDeclaration: false
  AfterStruct:     false
  AfterUnion:      false
  BeforeCatch:     false
  BeforeElse:      false
  BeforeLambdaBody: false
  BeforeWhile:     false
  IndentBraces:    false
  SplitEmptyFunction: true
  SplitEmptyRecord: true
  SplitEmptyNamespace: true
BreakAdjacentStringLiterals: true
BreakAfterAttributes: Leave
BreakAfterJavaFieldAnnotations: false
BreakArrays:     true
BreakBeforeBinaryOperators: None
BreakBeforeConceptDeclarations: Always
BreakBeforeBraces: Attach
BreakBeforeInlineASMColon: OnlyMultiline
BreakBeforeTernaryOperators: true
BreakConstructorInitializers: BeforeColon
BreakInheritanceList: BeforeColon
BreakStringLiterals: true
ColumnLimit:     80
CommentPragmas:  '^ IWYU pragma:'
CompactNamespaces: false
ConstructorInitializerIndentWidth: 4
ContinuationIndentWidth: 4
Cpp11BracedListStyle: true
DerivePointerAlignment: false
DisableFormat:   false
EmptyLineAfterAccessModifier: Never
EmptyLineBeforeAccessModifier: LogicalBlock
ExperimentalAutoDetectBinPacking: false
FixNamespaceComments: true
ForEachMacros:
  - foreach
  - Q_FOREACH
  - BOOST_FOREACH
IfMacros:
  - KJ_IF_MAYBE
IncludeBlocks:   Preserve
IncludeCategories:
  - Regex:           '^"(llvm|llvm-c|clang|clang-c)/'
    Priority:        2
    SortPriority:    0
    CaseSensitive:   false
  - Regex:           '^(<|"(gtest|gmock|isl|json)/)'
    Priority:        3
    SortPriority:    0
    CaseSensitive:   false
  - Regex:           '.*'
    Priority:        1
    SortPriority:    0
    CaseSensitive:   false
IncludeIsMainRegex: '(Test)?$'
IncludeIsMainSourceRegex: ''
IndentAccessModifiers: false
IndentCaseBlocks: false
IndentCaseLabels: false
IndentExternBlock: AfterExternBlock
IndentGotoLabels: true
IndentPPDirectives: None
IndentRequiresClause: true
IndentWidth:     2
IndentWrappedFunctionNames: false
InsertBraces:    false
InsertNewlineAtEOF: false
InsertTrailingCommas: None
IntegerLiteralSeparator:
  Binary:          0
  BinaryMinDigits: 0
  Decimal:         0
  DecimalMinDigits: 0
  Hex:             0
  HexMinDigits:    0
JavaScriptQuotes: Leave
JavaScriptWrapImports: true
KeepEmptyLinesAtTheStartOfBlocks: true
KeepEmptyLinesAtEOF: false
LambdaBodyIndentation: Signature
LineEnding:      DeriveLF
MacroBlockBegin: ''
MacroBlockEnd:   ''
MaxEmptyLinesToKeep: 1
NamespaceIndentation: None
ObjCBinPackProtocolList: Auto
ObjCBlockIndentWidth: 2
ObjCBreakBeforeNestedBlockParam: true
ObjCSpaceAfterProperty: false
ObjCSpaceBeforeProtocolList: true
PackConstructorInitializers: BinPack
PenaltyBreakAssignment: 2
PenaltyBreakBeforeFirstCallParameter: 19
PenaltyBreakComment: 300
PenaltyBreakFirstLessLess: 120
PenaltyBreakOpenParenthesis: 0
PenaltyBreakScopeResolution: 500
PenaltyBreakString: 1000
PenaltyBreakTemplateDeclaration: 10
PenaltyExcessCharacter: 1000000
PenaltyIndentedWhitespace: 0
PenaltyReturnTypeOnItsOwnLine: 60
PointerAlignment: Right
PPIndentWidth:   -1
QualifierAlignment: Leave
ReferenceAlignment: Pointer
ReflowComments:  true
RemoveBracesLLVM: false
RemoveParentheses: Leave
RemoveSemicolon: false
RequiresClausePosition: OwnLine
RequiresExpressionIndentation: OuterScope
SeparateDefinitionBlocks: Leave
ShortNamespaceLines: 1
SkipMacroDefinitionBody: false
SortIncludes:    CaseSensitive
SortJavaStaticImport: Before
SortUsingDeclarations: LexicographicNumeric
SpaceAfterCStyleCast: false
SpaceAfterLogicalNot: false
SpaceAfterTemplateKeyword: true
SpaceAroundPointerQualifiers: Default
SpaceBeforeAssignmentOperators: true
SpaceBeforeCaseColon: false
SpaceBeforeCpp11BracedList: false
SpaceBeforeCtorInitializerColon: true
SpaceBeforeInheritanceColon: true
SpaceBeforeJsonColon: false
SpaceBeforeParens: ControlStatements
SpaceBeforeParensOptions:
  AfterControlStatements: true
  AfterForeachMacros: true
  AfterFunctionDefinitionName: false
  AfterFunctionDeclarationName: false
  AfterIfMacros:   true
  AfterOverloadedOperator: false
  AfterPlacementOperator: true
  AfterRequiresInClause: false
  AfterRequiresInExpression: false
  BeforeNonEmptyParentheses: false
SpaceBeforeRangeBasedForLoopColon: true
SpaceBeforeSquareBrackets: false
SpaceInEmptyBlock: false
SpacesBeforeTrailingComments: 1
SpacesInAngles:  Never
SpacesInContainerLiterals: true
SpacesInLineCommentPrefix:
  Minimum:         1
  Maximum:         -1
SpacesInParens:  Never
SpacesInParensOptions:
  InCStyleCasts:   false
  InConditionalStatements: false
  InEmptyParentheses: false
  Other:           false
SpacesInSquareBrackets: false
Standard:        Latest
StatementAttributeLikeMacros:
  - Q_EMIT
StatementMacros:
  - Q_UNUSED
  - QT_REQUIRE_VERSION
TabWidth:        8
UseTab:          Never
VerilogBreakBetweenInstancePorts: true
WhitespaceSensitiveMacros:
  - BOOST_PP_STRINGIZE
  - CF_SWIFT_NAME
  - NS_SWIFT_NAME
  - PP_STRINGIZE
  - STRINGIZE
...

]],
}

-- local home = vim.env.HOME
-- print(home)
boilerplate['.clangd'] = {
  -- filename = '.clangd',
  content = [[
CompileFlags:
  Remove: [
      -misc-definitions-in-headers,
      -fno-tree-switch-conversion,
      -mtext-section-literals,
      -mlong-calls,
      -mlongcalls,
      -fstrict-volatile-bitfields,
      -free*,
      -fipa-pta*,
      -march=*,
      -mabi=*,
      -mcpu=*,
    ]
Diagnostics:
  Suppress: [
      "misc-definitions-in-headers",
      "pp_including_mainfile_in_preamble",
      "misc-unused-using-decls",
      "unused-includes",
    ]
  ClangTidy:
    Remove: [
        readability-*,
        cert-err58-cpp,
        llvmlibc-*,
        fuchsia-*,
        hicpp-avoid-c-arrays,
        cppcoreguidelines-*,
        llvm-*,
        google-*,
        bugprone-*,
        hicpp-vararg,
        modernize-*,
      ]

]],
}
boilerplate['.stylua.toml'] = {
  -- filename = '.stylua.toml',
  content = [[
syntax = "All"
column_width = 132
line_endings = "Unix"
indent_type = "Spaces"
indent_width = 2
quote_style = "AutoPreferSingle"
call_parentheses = "Always"
collapse_simple_statement = "Never"
space_after_function_names = "Never"

[sort_requires]
enabled = false
]],
}

function M.boilerplate_gen(framework, src_path, filename)
  filename = filename or framework
  -- print(src_path .. '/0' .. framework)
  local entry = boilerplate[framework]
  if not entry then
    return
  end
  --
  local file_path = src_path .. '/' .. filename
  if vim.uv.fs_stat(file_path) then
    return -- return if file exists
  end

  if vim.fn.isdirectory(src_path) == 0 then
    vim.fn.mkdir(src_path, 'p')
  end

  --
  uv.fs_open(file_path, 'w', 420, function(_, fd) -- crtete file if directory of the path exists
    if not fd then
      print('failed to create file: ' .. file_path .. '/' .. entry.filename)
      return
    end
    -- uv.fs_write(fd, entry.content, 0, function(werr, _)
    --   if werr then
    --     print('failed to write to file: ' .. file_path .. '/' .. entry.filename)
    --     return
    --   end
    --   uv.fs_close(fd, function(cerr)
    --     if cerr then
    --       print('failed to close file: ' .. file_path .. '/' .. entry.filename)
    --       return
    --     end
    --   end)
    -- end)
    uv.fs_write(fd, entry.content, 0)
    uv.fs_close(fd)
  end)
end
return M
