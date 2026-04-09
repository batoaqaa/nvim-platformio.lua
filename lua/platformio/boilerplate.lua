local pio = require('platformio.utils.pio')
local M = {}
local uv = vim.loop

local boilerplate = {}

--- stylua: ignore
boilerplate['arduino'] = {
  content = [[
#include <Arduino.h>

void setup() {

}

void loop() {

}
]],
}

boilerplate['platformio.ini'] = {
  template = [[
[platformio]
core_dir = %s
platforms_dir = ${platformio.core_dir}/platforms
packages_dir = ${platformio.core_dir}/packages

default_envs = 
;default_envs = uno, nodemcu

;--------------------------------------------------------------------------
[env]
upload_speed = 115200
monitor_speed = 9600

monitor_rts = 1	  ; 1 combination to reset esp32c6 (Table 32.3-2. CDC-ACM Settings with RTS and DTR)
monitor_dtr = 0   ; 0 // pio dev mon --rts=0 --dtr=0 then pio dev mon --rts=1 dtr=0

;extra_scripts =
;    pre:enable_toolchain.py ; enabled global env 'PLATFORMIO_SETTING_COMPILATIONDB_INCLUDE_TOOLCHAIN'

lib_ldf_mode = chain+   ;Library dependencies Finder ldf
]],
  content = function(self)
    return string.format(self.template, pio.get_pio_dir('core'))
  end,
}

boilerplate['enable_toolchain.py'] = {
  content = [[
from SCons.Script import DefaultEnvironment
env = DefaultEnvironment()
env.Replace(COMPILATIONDB_INCLUDE_TOOLCHAIN=True)

#Import("env")

# Safe retrieval with a default message
print(f"Toolchain Inclusion Status: {env.get('COMPILATIONDB_INCLUDE_TOOLCHAIN', 'Not Set')}")
print(">>> SUCCESS: Toolchain inclusion forced in Global Environment")
]],
}

boilerplate['.clangd_cmd'] = {
  template = [[
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
--query-driver=%s/toolchain-*/**/bin/*
]],
  content = function(self)
    return string.format(self.template, pio.get_pio_dir('packages') or '**')
  end,
  --query-driver=%s/.platformio/packages/*/bin/riscv32-esp-elf-*
  --query-driver=%s/.platformio/**/packages/toolchain-*/**/bin/*
  --query-driver = [[clangd --query-driver=]] .. vim.env.HOME .. [[/.platformio/packages/*]]
  --query-driver=**/*riscv32-esp-elf-*,**/*gcc*,**/*g++*
  --query-driver=**/.platformio/packages/toolchain*/**/bin/*gcc*
}

boilerplate['.clang-format'] = {
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

boilerplate['.clangd'] = {
  content = [[
CompileFlags:
  Add: [
    --target=riscv32-esp-elf,
  ]
  Remove: [
    -fno-fat-lto-objects
    -fno%-fat%-lto%-objects,
    -fno%-canonical%-system%-headers,
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

  -------------------------------------------------------------------------------------
  local fd = assert(uv.fs_open(file_path, 'w', 420))
  if not fd then
    print('failed to create file: ' .. file_path)
    return
  end

  -- local closeOnexit = type(exit_callback) == 'function'
  local text = type(entry.content) == 'function' and entry:content() or entry.content
  uv.fs_write(fd, text, 0)
  uv.fs_close(fd)

  -- uv.fs_open(file_path, 'w', 420, function(_, fd) -- crtete file if directory of the path exists
  --   if not fd then
  --     print('failed to create file: ' .. file_path .. '/' .. entry.filename)
  --     return
  --   end
  --   uv.fs_write(fd, entry.content, 0, function(werr, _)
  --     if werr then
  --       print('failed to write to file: ' .. file_path .. '/' .. entry.filename)
  --       return
  --     end
  --     uv.fs_close(fd, function(cerr)
  --       if cerr then
  --         print('failed to close file: ' .. file_path .. '/' .. entry.filename)
  --         return
  --       end
  --     end)
  --   end)
  -- end)
end
return M
