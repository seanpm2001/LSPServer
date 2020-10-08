BeginPackage["LSPServer`"]

StartServer::usage = "StartServer[] puts the kernel into a state ready for traffic from the client.\
 StartServer[logDir] logs traffic to logDir."



RegisterDidOpenNotification

RegisterDidCloseNotification

RegisterDidSaveNotification

RegisterDidChangeNotification


handleContent

$OpenFilesMap

Begin["`Private`"]

Needs["LSPServer`Color`"]
Needs["LSPServer`Definitions`"]
Needs["LSPServer`DocumentSymbol`"]
Needs["LSPServer`Library`"]
Needs["LSPServer`Hover`"]
Needs["LSPServer`Utils`"]
Needs["LSPServer`Workspace`"]

Needs["CodeFormatter`"]
Needs["CodeInspector`"]
Needs["CodeInspector`Format`"]
Needs["CodeInspector`ImplicitTokens`"]
Needs["CodeInspector`BracketMismatches`"]
Needs["CodeInspector`Utils`"]
Needs["CodeParser`"]
Needs["CodeParser`Utils`"]



(*
This uses func := func = def idiom and is fast
*)
loadAllFuncs[]



$ConfidenceLevel = 0.95

$ColorProvider = False

$CodeActionLiteralSupport = False

$ImplicitTokens = False

(*
if $BracketMatcher, then load ML4Code` and use ML bracket matching tech
*)
$BracketMatcher = False

$BracketMatcherUseDesignColors = True

$BracketMatcherDisplayInsertionText = False

(*
Bracket suggestions from ML4Code can take O(n^2) time in the size of the chunk, so make sure to
have a time limit 
*)
$ML4CodeTimeLimit = 0.4


$ExecuteCommandProvider = <|
  "commands" -> {
    "enable_bracket_matcher_debug_mode",
    "disable_bracket_matcher_debug_mode",
    "enable_bracket_matcher_design_colors",
    "disable_bracket_matcher_design_colors",
    "enable_bracket_matcher_display_insertion_text",
    "disable_bracket_matcher_display_insertion_text"
  } |>

$HTMLSnippets = False




(*
lint objects may be printed to log files and we do not want to include ANSI control codes
*)
CodeInspector`Format`Private`$UseANSI = False


(*
The counter that is used for creating unique hrefs
*)
$hrefIdCounter = 0



$ErrorCodes = <|
  (*
  Defined by JSON RPC
  *)
  "ParseError" -> -32700,
  "InvalidRequest" -> -32600,
  "MethodNotFound" -> -32601,
  "InvalidParams" -> -32602,
  "InternalError" -> -32603,
  "serverErrorStart" -> -32099,
  "serverErrorEnd" -> -32000,
  "ServerNotInitialized" -> -32002,
  "UnknownErrorCode" -> -32001,

  (*
  Defined by the protocol.
  *)
  "RequestCancelled" -> -32800,
  "ContentModified" -> -32801
|>

$DiagnosticSeverity = <|
  "Error" -> 1,
  "Warning" -> 2,
  "Information" -> 3,
  "Hint" -> 4
|>


$TextDocumentSyncKind = <|
  "None" -> 0,
  "Full" -> 1,
  "Incremental" -> 2
|>



StartBackgroundReaderThread[] :=
Module[{res},
  res = libraryFunctionWrapper[startBackgroundReaderThreadFunc];
  res
]

LockQueue[] :=
Module[{res},
  res = libraryFunctionWrapper[lockQueueFunc];
  res
]

UnlockQueue[] :=
Module[{res},
  res = libraryFunctionWrapper[unlockQueueFunc];
  res
]

GetQueueSize[] :=
Module[{res},
  res = libraryFunctionWrapper[getQueueSizeFunc];
  res
]

GetFrontMessageSize[] :=
Module[{res},
  res = libraryFunctionWrapper[getFrontMessageSizeFunc];
  res
]

PopQueue[numBytes_Integer] :=
Module[{bytes},
  bytes = ByteArray[Developer`AllocateNumericArray["UnsignedInteger8", {numBytes}]];
  libraryFunctionWrapper[popQueueFunc, bytes];
  bytes
]

GetBackgroundReaderThreadError[] :=
Module[{res},
  res = libraryFunctionWrapper[getBackgroundReaderThreadError];
  res
]

GetStdInFEOF[] :=
Module[{res},
  res = libraryFunctionWrapper[getStdInFEOF];
  res
]

GetStdInFError[] :=
Module[{res},
  res = libraryFunctionWrapper[getStdInFError];
  res
]

GetStdOutFEOF[] :=
Module[{res},
  res = libraryFunctionWrapper[getStdOutFEOF];
  res
]

GetStdOutFError[] :=
Module[{res},
  res = libraryFunctionWrapper[getStdOutFError];
  res
]

WriteLineToStdOut[line_String] :=
Module[{res},
  res = libraryFunctionWrapper[writeLineToStdOutFunc, line];
  res
]

WriteBytesToStdOut[bytes_ByteArray] :=
Module[{res},
  res = libraryFunctionWrapper[writeBytesToStdOutFunc, bytes];
  res
]



$Debug

$Debug2

$DebugBracketMatcher



$OpenFilesMap = <||>



(*
setup the REPL to handle traffic from client
*)
StartServer[logDir_String:""] :=
Catch[
Catch[
Module[{logFile, res, bytes, bytess, logFileStream,
  logFileName, logFileCounter,
  queueSize, frontMessageSize,
  lspServerVersion, codeParserVersion, codeInspectorVersion, codeFormatterVersion,
  content, contents,
  bytessIn, contentsIn,
  backgroundReaderThreadError, errStr, feof, ferror},

  (*
  Ensure that no messages are printed to stdout
  *)
  $Messages = Streams["stderr"];

  (*
  Ensure that no Print output is printed to stdout

  There may have been messages printed from doing Needs["LSPServer`"], and we can't do anything about those
  But they will be detected when doing RunDiagnostic[] 
  *)
  $Output = Streams["stderr"];

  (*
  res = RunDiagnostic[];
  If[!TrueQ[res],
    Write[$Messages, "\n\n" //OutputForm];
    Write[$Messages, "RunDiagnostic[] did not return True: " //OutputForm, res //OutputForm];
    Write[$Messages, "KERNEL IS EXITING" //OutputForm];
    Write[$Messages, "\n\n" //OutputForm];
    Pause[1];Exit[1]
  ];
  *)

  $Debug = (logDir != "");

  If[$Debug,

    Quiet[CreateDirectory[logDir], {CreateDirectory::filex}];

    logFileName = "kernelLogFile";

    logFile = FileNameJoin[{logDir, logFileName <> ".txt"}];
    If[FileExistsQ[logFile],
      logFileCounter = 1;
      logFile = FileNameJoin[{logDir, logFileName <> ToString[logFileCounter] <> ".txt"}];
      While[True,
        If[FileExistsQ[logFile],
          logFileCounter++;
          logFile = FileNameJoin[{logDir, logFileName <> ToString[logFileCounter] <> ".txt"}];
          ,
          Break[]
        ]
      ]
    ];

    logFileStream = OpenWrite[logFile, CharacterEncoding -> "UTF8"];

    $Messages = $Messages ~Join~ { logFileStream }
  ];

  SetOptions[$Messages, PageWidth -> Infinity];

  (*
  There may be messages that we want to see

  TODO: investigate resetting the General::stop counter at the start of each loop
  *)
  Off[General::stop];


  log["$CommandLine: ", $CommandLine];
  log["\n\n"];

  log["$ProcessID: ", $ProcessID];
  log["\n\n"];

  If[!StringStartsQ[ToLowerCase[FileBaseName[$CommandLine[[1]]]], "wolframkernel"],
    log["WARNING: Command for Wolfram Language Server does not start with 'WolframKernel': ", $CommandLine[[1]]];
    log["\n\n"];
  ];
  If[!MemberQ[$CommandLine, "-noinit"],
    log["WARNING: -noinit is not in $CommandLine"];
    log["\n\n"];
  ];
  If[!MemberQ[$CommandLine, "-noprompt"],
    log["WARNING: -noprompt is not in $CommandLine"];
    log["\n\n"];
  ];
  If[!MemberQ[$CommandLine, "-nopaclet"],
    log["WARNING: -nopaclet is not in $CommandLine"];
    log["\n\n"];
  ];
  If[!MemberQ[$CommandLine, "-noicon"],
    log["WARNING: -noicon is not in $CommandLine"];
    log["\n\n"];
  ];


  lspServerVersion = Information[PacletObject["LSPServer"], "Version"];

  codeParserVersion = Information[PacletObject["CodeParser"], "Version"];

  codeInspectorVersion = Information[PacletObject["CodeInspector"], "Version"];

  codeFormatterVersion = Information[PacletObject["CodeFormatter"], "Version"];

  If[lspServerVersion =!= codeParserVersion,
    log["WARNING: LSPServer and CodeParser do not have the same version."];
    log["WARNING: LSPServer version: ", lspServerVersion];
    log["WARNING: CodeParser version: ", codeParserVersion];
    log["\n\n"];
  ];
  If[lspServerVersion =!= codeInspectorVersion,
    log["WARNING: LSPServer and CodeInspector do not have the same version."];
    log["WARNING: LSPServer version: ", lspServerVersion];
    log["WARNING: CodeInspector version: ", codeInspectorVersion];
    log["\n\n"];
  ];
  If[lspServerVersion =!= codeFormatterVersion,
    log["WARNING: LSPServer and CodeFormatter do not have the same version."];
    log["WARNING: LSPServer version: ", lspServerVersion];
    log["WARNING: CodeFormatter version: ", codeFormatterVersion];
    log["\n\n"];
  ];


  (*
  Some simple thing to warm-up
  *)
  CodeParse["1+1"];


  log["Starting server... (If this is the last line you see, then there may be a problem and the server is hanging.)"];
  log["\n\n"];


  StartBackgroundReaderThread[];


  (*
  loop over:
    read content
    evaluate
    write content
  *)
  While[True,


    backgroundReaderThreadError = GetBackgroundReaderThreadError[];

    If[backgroundReaderThreadError != 0,

      Switch[backgroundReaderThreadError,
        (*FREAD_FAILED*)
        1,
          Which[
            (feof = GetStdInFEOF[]) != 0,
              errStr = "fread EOF"
            ,
            (ferror = GetStdInFError[]) != 0,
              errStr = "fread error: " <> ToString[ferror]
            ,
            True,
              errStr = "fread unknown error"
          ]
        ,
        (*UNEXPECTED_LINEFEED*)
        2,
          errStr = "unexpected linefeed"
        ,
        (*EXPECTED_LINEFEED*)
        3,
          errStr = "expected linefeed"
        ,
        (*UNRECOGNIZED_HEADER*)
        4,
          errStr = "unrecognized header"
        ,
        _,
          errStr = "UNKNOWN ERROR: " <> ToString[backgroundReaderThreadError]
      ];

      log["\n\n"];
      log["Background Reader Thread Error: ", errStr];
      log["\n\n"];

      exitHard[]
    ];

    LockQueue[];

    queueSize = GetQueueSize[];

    If[queueSize == 0,
      
      UnlockQueue[];

      Pause[0.1];

      Continue[];
    ];

    If[$Debug2,
      log["queueSize: ", queueSize];
    ];

    bytessIn = {};
    Do[
      
      frontMessageSize = GetFrontMessageSize[];

      bytes = PopQueue[frontMessageSize];

      AppendTo[bytessIn, bytes]
      ,
      queueSize
    ];

    UnlockQueue[];


    contentsIn = {};
    Do[
      If[FailureQ[bytesIn],
        log["\n\n"];
        log["invalid bytes from stdin: ", bytesIn];
        log["\n\n"];

        exitHard[]
      ];

      If[$Debug2,
        log["C-->S " <> ToString[Length[bytesIn]] <> " bytes "];
        log["C-->S " <> stringLineTake[FromCharacterCode[Normal[Take[bytesIn, UpTo[1000]]]], UpTo[20]]];
        log["...\n"];
      ];

      content = ImportByteArray[bytesIn, "RawJSON"];

      AppendTo[contentsIn, content]
      ,
      {bytesIn, bytessIn}
    ];

    bytessIn = {};

    (*
    Remove cancellations and redundant requests
    *)
    contentsIn = filterContents[contentsIn];


    Do[

      contents = LSPEvaluate[content];

      Check[
        bytess = ExportByteArray[#, "JSON"]& /@ contents;

        ,
        log["\n\n"];
        log["message generated by contents: ", contents];
        log["\n\n"];
        ,
        {Export::jsonstrictencoding}
      ];

      (*
      write out each byte array in bytess
      *)
      Do[
      
        If[!ByteArrayQ[bytes],
          
          log["\n\n"];
          log["invalid bytes from stdin: ", bytes];
          log["\n\n"];

          exitHard[]
        ];

        (*
        Write the headers
        *)
        Do[
          If[$Debug2,
            log[""];
            log["C<--S  ", line];
          ];

          res = WriteLineToStdOut[line];
          If[res =!= 0,

            Switch[res,
              (*FWRITE_FAILED | FFLUSH_FAILED*)
              5 | 6,
                Which[
                  (feof = GetStdOutFEOF[]) != 0,
                    errStr = "fwrite EOF"
                  ,
                  (ferror = GetStdOutFError[]) != 0,
                    errStr = "fwrite error: " <> ToString[ferror]
                  ,
                  True,
                    errStr = "fwrite unknown error"
                ]
              ,
              _,
                errStr = "UNKNOWN ERROR: " <> ToString[res]
            ];

            log["\n\n"];
            log["StdOut error: ", errStr];
            log["\n\n"];

            exitHard[]
          ];
          ,
          {line, {"Content-Length: " <> ToString[Length[bytes]], ""}}
        ];

        (*
        Write the body
        *)
        If[$Debug2,
          log["C<--S  ", stringLineTake[FromCharacterCode[Normal[Take[bytes, UpTo[1000]]]], UpTo[20]]];
          log["...\n"];
        ];

        res = WriteBytesToStdOut[bytes];
        If[res =!= 0,

          Switch[res,
            (*FWRITE_FAILED | FFLUSH_FAILED*)
            5 | 6,
              Which[
                (feof = GetStdOutFEOF[]) != 0,
                  errStr = "fwrite EOF"
                ,
                (ferror = GetStdOutFError[]) != 0,
                  errStr = "fwrite error: " <> ToString[ferror]
                ,
                True,
                  errStr = "fwrite unknown error"
              ]
            ,
            _,
              errStr = "UNKNOWN ERROR: " <> ToString[res]
          ];

          log["\n\n"];
          log["StdOut error: ", errStr];
          log["\n\n"];

          exitHard[]
        ];
        ,
        {bytes, bytess}
      ](*Do bytess*)
      ,
      {content, contentsIn}
    ];(*Do contentsIn*)

    contentsIn = {};

  ](*While*)
]],(*Module*)
_,
(
  log["\n\n"];
  log["uncaught Throw: ", #1];
  log["\n\n"];
  
  exitHard[]

  )&
]


(*
Remove cancelable requests (and the cancel requests themselves)

Remove all redundant requests: in a group of batchable requests, remove everything before last didChange request
*)
filterContents[contentsIn_] :=
  Catch[
  Module[{contents, cancels, toCancel, contentsss},

    contents = contentsIn;

    (*
    TODO: is 0 possible here?
    *)
    If[empty[contents],
      Throw[contents]
    ];

    If[Length[contents] == 1,
      
      Switch[contents[[1]],
        KeyValuePattern["method" -> "textDocument/didChange"],
          (*
          Clear diagnostics and snippets first
          *)
          Throw[clearBeforeChange[uri[contents[[1]]]] ~Join~ contents]
        ,
        _,
          Throw[contents]
      ]

    ];

    If[$Debug2,
      log["\n"];
      log["contents > 1. Here are the methods: ", #["method"]& /@ contents];
      log["\n"];
    ];

    (*
    First handle cancellations
    *)
    cancels = Cases[contents, KeyValuePattern["method" -> "$/cancelRequest"]];

    toCancel = Flatten[handleCancelRequest[#, contents]& /@ cancels];

    If[$Debug2,
      log["cancels: ", cancels];
      log["toCancel: ", toCancel];
    ];

    (*
    Must preserve ordering, so do not use Complement
    *)
    contents = DeleteCases[contents, Alternatives @@ cancels];
    
    contents = DeleteCases[contents, Alternatives @@ toCancel];

    If[$Debug2,
      log["\n"];
      log["Here are the NEW methods: ", #["method"]& /@ contents];
      log["\n"];
    ];

    (*
    Now remove redundant requests

    First group together based on the same document

    Then remove everything before the last didChange
    *)
    contentsss = SplitBy[contents, {uri, batchable}];

    contentsss =
      Map[
        Function[{contentss1},
          Map[
            Function[{contents1},
              Function[{contents2},
                If[$Debug2,
                  log["\n"];
                  log["Here is the OLD contents: ", {#["method"], uri[#], batchable[#]}& /@ contents1];
                  log["Here is the NEW contents: ", {#["method"], uri[#], batchable[#]}& /@ contents2];
                  log["\n"];
                ];
                contents2
              ][Function[{pos},
                  If[pos == {},
                    contents1
                    ,
                    (*
                    If there is a didChange, then drop everything up to the last textDocument/didChange, but keeping the last textDocument/didChange
                    Also clear diagnostics and snippets first
                    *)
                    clearBeforeChange[uri[contents1[[1]]]] ~Join~ Drop[contents1, Last[pos][[1]] - 1]
                  ]
                ][Position[contents1, KeyValuePattern["method" -> "textDocument/didChange"]]]
              ]
            ]
            ,
            contentss1
          ]
        ]
        ,
        contentsss
      ];

    contents = Flatten[contentsss];

    If[$Debug2,
      log["\n"];
      log["Here are the NEW NEW methods: ", #["method"]& /@ contents];
      log["\n"];
    ];

    contents
  ]]


(*
HACK: rely on implementation detail of SplitBy calling SameQ internally

provide a sentinal value that cannot be compared with itself
*)
incomparableSentinel /: SameQ[incomparableSentinel, incomparableSentinel] := False

uri[KeyValuePattern["params" -> KeyValuePattern["textDocument" -> KeyValuePattern["uri" -> uri_]]]] := uri

(*
no uri, so always separate
*)
uri[_] := incomparableSentinel

(*
These are either:
didChange, which is the source of changes, or
other requests that depend on didChange and have no side-effects
*)
batchable[KeyValuePattern["method" -> "textDocument/definition"]] := True
batchable[KeyValuePattern["method" -> "textDocument/didChange"]] := True
batchable[KeyValuePattern["method" -> "textDocument/documentColor"]] := True
batchable[KeyValuePattern["method" -> "textDocument/hover"]] := True
batchable[KeyValuePattern["method" -> "textDocument/references"]] := True

batchable[_] := incomparableSentinel


clearBeforeChange[uri_] :=
  Join[
    publishDiagnosticsNotificationWithLints[uri, {}],
    publishImplicitTokensNotificationWithLines[uri, {}],
    publishHTMLSnippetWithLines[uri, {}]
  ]



(*
Forward these to the client
*)
handleContent[content:KeyValuePattern["method" -> "textDocument/publishDiagnostics"]] :=
  {content}

handleContent[content:KeyValuePattern["method" -> "textDocument/publishImplicitTokens"]] :=
  {content}

handleContent[content:KeyValuePattern["method" -> "textDocument/publishHTMLSnippet"]] :=
  {content}





RunDiagnostic[command:{_String...}] :=
  Module[{},
    (*
    launch a child kernel with same command args that a client has
    this kernel will be the client
    scheduled task for 3 seconds to kill child kernel if no response
    send traffic to kernel, read response
    read stderr also
    then shutdown child kernel
    *)
    True
  ]



(*
input: JSON RPC assoc

returns: a list of JSON RPC assocs
*)
LSPEvaluate[content_(*no Association here, allow everything*)] :=
Catch[
Module[{contents},

  (*
  (*  
  Figuring out what to with UTF-16 surrogates...

  Related bugs: 382744
  *)

  (*
  Coming in as JSON, so non-ASCII characters are using \uXXXX escaping
  So safe to treat bytes as ASCII
  *)
  str = FromCharacterCode[Normal[bytes], "ASCII"];

  escapes = StringCases[str, "\\u" ~~ ds : (_ ~~ _ ~~ _ ~~ _) :> ds];
  If[escapes != {},
    surrogates = Select[escapes, (
        (* high and low surrogates *)
        16^^d800 <= FromDigits[#, 16] <= 16^^dfff
      )&];
    If[surrogates != {},
      (*
      surrogates have been detected
      *)
      Null
    ]
  ];

  content = ImportString[str, "RawJSON"];
  *)

  Which[
    TrueQ[$ServerState == "shutdown"],
      contents = handleContentShutdown[content]
    ,
    True,
      contents = handleContent[content];
  ];

  If[!MatchQ[contents, {_Association...}],
    log["\n\n"];
    log["invalid contents result (should match {_Association...}): ", contents];
    log["\n\n"];

    exitHard[]
  ];

  contents
]]





(*
Functions in this list are called as:

func[uri]

*)
$didOpenNotifications = {publishDiagnosticsNotification, publishBracketMismatchesNotification}

(*
Functions in this list are called as:

func[uri]

clear lints and lines on file close

NOTE: may want to be able to control this behavior
*)
$didCloseNotifications = {publishDiagnosticsNotificationWithLints[#1, {}]&, publishHTMLSnippetWithLines[#, {}]&}

(*
Functions in this list are called as:

func[uri]

*)
$didSaveNotifications = {publishDiagnosticsNotification, publishBracketMismatchesNotification}

(*
Functions in this list are called as:

func[uri]

*)
$didChangeNotifications = {publishDiagnosticsNotification, publishBracketMismatchesNotification}


RegisterDidOpenNotification[func_] := AppendTo[$didOpenNotifications, func]

RegisterDidCloseNotification[func_] := AppendTo[$didCloseNotifications, func]

RegisterDidSaveNotification[func_] := AppendTo[$didSaveNotifications, func]

RegisterDidChangeNotification[func_] := AppendTo[$didChangeNotifications, func]







(*
content: JSON-RPC Association

returns: a list of associations (possibly empty), each association represents JSON-RPC
*)
handleContent[content:KeyValuePattern["method" -> "initialize"]] :=
Module[{id, params, capabilities, textDocument, codeAction, codeActionLiteralSupport, codeActionKind, valueSet,
  codeActionProviderValue, initializationOptions, confidenceLevel, colorProvider, implicitTokens,
  bracketMatcher, debugBracketMatcher, htmlSnippets},

  id = content["id"];
  params = content["params"];
  
  If[KeyExistsQ[params, "initializationOptions"],
    initializationOptions = params["initializationOptions"];

    If[KeyExistsQ[initializationOptions, "confidenceLevel"],
      confidenceLevel = initializationOptions["confidenceLevel"];

      $ConfidenceLevel = confidenceLevel;
    ];
    If[KeyExistsQ[initializationOptions, "colorProvider"],
      colorProvider = initializationOptions["colorProvider"];

      $ColorProvider = colorProvider;
    ];

    If[KeyExistsQ[initializationOptions, "implicitTokens"],
      implicitTokens = initializationOptions["implicitTokens"];

      $ImplicitTokens = implicitTokens;
    ];
    If[KeyExistsQ[initializationOptions, "bracketMatcher"],
      bracketMatcher = initializationOptions["bracketMatcher"];

      $BracketMatcher = bracketMatcher;
    ];
    If[KeyExistsQ[initializationOptions, "debugBracketMatcher"],
      debugBracketMatcher = initializationOptions["debugBracketMatcher"];

      $DebugBracketMatcher = debugBracketMatcher;
    ];
    If[KeyExistsQ[initializationOptions, "htmlSnippets"],
      htmlSnippets = initializationOptions["htmlSnippets"];

      $HTMLSnippets = htmlSnippets;
    ];
  ];

  capabilities = params["capabilities"];
  textDocument = capabilities["textDocument"];
  codeAction = textDocument["codeAction"];

  If[KeyExistsQ[codeAction, "codeActionLiteralSupport"],
    $CodeActionLiteralSupport = True;
    codeActionLiteralSupport = codeAction["codeActionLiteralSupport"];
    codeActionKind = codeActionLiteralSupport["codeActionKind"];
    valueSet = codeActionKind["valueSet"];
  ];

  If[$CodeActionLiteralSupport,
    codeActionProviderValue = <| "codeActionKinds" -> {"quickfix"} |>
    ,
    codeActionProviderValue = True
  ];

  If[$ImplicitTokens,
    RegisterDidOpenNotification[publishImplicitTokensNotification];
    RegisterDidCloseNotification[publishImplicitTokensNotificationWithLines[#, {}]&];
    RegisterDidSaveNotification[publishImplicitTokensNotification];
    RegisterDidChangeNotification[publishImplicitTokensNotification];
  ];

  If[$BracketMatcher,

    Needs["ML4Code`"];

    (*
    Some simple thing to warm-up
    *)
    ML4Code`SuggestBracketEdits["f["]

  ];

  {<| "jsonrpc" -> "2.0", "id" -> id,
     "result" -> <| "capabilities"-> <| "referencesProvider" -> True,
                                        "textDocumentSync" -> <| "openClose" -> True,
                                                                 "save" -> <| "includeText" -> False |>,
                                                                 "change" -> $TextDocumentSyncKind["Full"]
                                                              |>,
                                         "codeActionProvider" -> codeActionProviderValue,
                                         "colorProvider" -> $ColorProvider,
                                         "hoverProvider" -> True,
                                         "definitionProvider" -> True,
                                         "documentFormattingProvider" -> True,
                                         "documentRangeFormattingProvider" -> True,
                                         "executeCommandProvider" -> $ExecuteCommandProvider,
                                         "documentSymbolProvider" -> True
                                     |>
                 |>
  |>}
]


handleContent[content:KeyValuePattern["method" -> "initialized"]] :=
  {}

handleContent[content:KeyValuePattern["method" -> "shutdown"]] :=
Module[{id},
  id = content["id"];

  $ServerState = "shutdown";

  {<| "jsonrpc" -> "2.0", "id" -> id, "result" -> Null |>}
]

(*
Unexpected call to exit
*)
handleContent[content:KeyValuePattern["method" -> "exit"]] := (

  exitSemiGracefully[]
)


handleCancelRequest[content:KeyValuePattern["method" -> "$/cancelRequest"], contents_] :=
Module[{params, id},

  params = content["params"];

  id = params["id"];

  Cases[contents, KeyValuePattern["id" -> id]]
]

(*
$ Notifications and Requests

Notification and requests whose methods start with "$/" are messages which are protocol
implementation dependent and might not be implementable in all clients or servers.
For example if the server implementation uses a single threaded synchronous programming
language then there is little a server can do to react to a "$/cancelRequest" notification.
If a server or client receives notifications starting with "$/" it is free to ignore the
notification.
If a server or client receives a requests starting with "$/" it must error the request with
error code MethodNotFound (e.g. -32601).
*)
handleContent[content:KeyValuePattern["method" -> meth_ /; StringMatchQ[meth, "$/" ~~ __]]] :=
Module[{params, id},

  params = content["params"];

  If[KeyExistsQ[params, "id"],
    (*
    has id, so this is a request
    *)
    id = params["id"];
    {<| "jsonrpc" -> "2.0", "id" -> id,
      "error" -> <|
        "code" -> $ErrorCodes["MethodNotFound"],
        "message"->"Method Not Found" |> |>}
    ,
    (*
    does not have id, so this is a notification
    just ignore
    *)
    {}
  ]
]



handleContentShutdown[content:KeyValuePattern["method" -> "exit"]] := (

  exitGracefully[]
)

(*
Called if any requests or notifications come in after shutdown
*)
handleContentShutdown[content_] :=
  Module[{params, id},

    params = content["params"];

    If[KeyExistsQ[params, "id"],
      (*
      has id, so this is a request
      *)
      id = params["id"];
      {<| "jsonrpc" -> "2.0", "id" -> id,
        "error" -> <|
          "code" -> $ErrorCodes["InvalidRequest"],
          "message"->"Invalid request" |> |>}
      ,
      (*
      does not have id, so this is a notification
      just ignore
      *)
      {}
    ]
  ]



handleContent[content:KeyValuePattern["method" -> "textDocument/references"]] :=
Catch[
Module[{id, params, doc, uri, cst, pos, line, char, cases, sym, name, srcs},

  id = content["id"];
  params = content["params"];
  doc = params["textDocument"];
  uri = doc["uri"];
  pos = params["position"];
  line = pos["line"];
  char = pos["character"];

  (*
  convert from 0-based to 1-based
  *)
  line+=1;
  char+=1;

  entry = $OpenFilesMap[uri];

  cst = entry[[2]];

  If[FailureQ[cst],
    Throw[cst]
  ];

  (*
  Find the name of the symbol at the position
  *)
  cases = Cases[cst, LeafNode[Symbol, _, KeyValuePattern[Source -> src_ /; SourceMemberQ[src, {line, char}]]], Infinity];

  If[cases == {},
    Throw[{<|"jsonrpc" -> "2.0", "id" -> id, "result" -> {} |>}]
  ];

  sym = cases[[1]];

  name = sym["String"];

  cases = Cases[cst, LeafNode[Symbol, name, _], Infinity];

  srcs = #[[3, Key[Source] ]]& /@ cases;

  locations = (<|   "uri" -> uri,
                  "range" -> <| "start" -> <| "line" -> #[[1, 1]], "character" -> #[[1, 2]] |>,
                                  "end" -> <| "line" -> #[[2, 1]], "character" -> #[[2, 2]] |> |>
               |>&[Map[Max[#, 0]&, #-1, {2}]])& /@ srcs;

  {<|"jsonrpc" -> "2.0", "id" -> id, "result" -> locations |>}
]]



(*
textDocument/didOpen is a notification (so no response), but take this chance to do linting and send textDocument/publishDiagnostics
*)
handleContent[content:KeyValuePattern["method" -> "textDocument/didOpen"]] :=
Catch[
Module[{params, doc, uri, cst, text},

  params = content["params"];
  doc = params["textDocument"];
  uri = doc["uri"];
  text = doc["text"];

  If[$Debug2,
    log["text: ", stringLineTake[StringTake[ToString[text, InputForm], UpTo[1000]], UpTo[20]]];
    log["...\n"];
  ];

  cst = CodeConcreteParse[text, "TabWidth" -> 1];

  If[FailureQ[cst],

    (*
    It is possible that a file is open in an editor, the actual file system contents get deleted,
    but the editor still has a stale window open.
    Focusing on that window could trigger a textDocument/didOpen notification, but the file does not exist!
    TODO: is this a bug in Sublime / LSP package?
    *)
    If[MatchQ[cst, Failure["FindFileFailed", _]],
      Throw[{}]
    ];

    Throw[cst]
  ];

  If[$Debug2,
    log["Calling didOpenNotifications: ", $didOpenNotifications];
    log["with these args: ", {uri}];
  ];

  (*
  This is a File, not a String
  *)
  cst[[1]] = File;

  (*
  Structure of entries is:

  { text, cst, cstTabs, ast, lints from CodeInspectCST }

  text: String that is the text of the file
  
  cst: cst of the file, with "TabWidth" -> 1
    Usually all that you need

  cstTabs: cst of the file, with "TabWidth" -> tab width of editor
    FIXME: needs to get tab width of editor
    this is used when doing something such as:
      rendering down to HTML and cannot rely on \t characters displaying properly, need to convert to spaces
    this is parsed lazily, on demand
  *)
  $OpenFilesMap[uri] = {text, cst, Null, Null, Null};

  (*
  save time if the file has no tabs
  *)
  If[!StringContainsQ[text, "\t"],
    $OpenFilesMap[[Key[uri], 3]] = cst
  ];

  Flatten[#[uri]& /@ $didOpenNotifications, 1]
]]

handleContent[content:KeyValuePattern["method" -> "textDocument/didClose"]] :=
Module[{params, doc, uri, res},

  params = content["params"];
  doc = params["textDocument"];
  uri = doc["uri"];

  If[$Debug2,
    log["Calling didCloseNotifications: ", $didCloseNotifications];
    log["with these args: ", {uri}];
  ];

  res = Flatten[#[uri]& /@ $didCloseNotifications, 1];

  $OpenFilesMap[uri] =.;

  res
]

handleContent[content:KeyValuePattern["method" -> "textDocument/didSave"]] :=
  {}

handleContent[content:KeyValuePattern["method" -> "textDocument/didChange"]] :=
Catch[
Module[{params, doc, uri, cst, text, lastChange},
  
  params = content["params"];
  doc = params["textDocument"];
  uri = doc["uri"];
  
  changes = params["contentChanges"];

  (*
  Currently only supporting full text, so always only apply the last change
  *)
  lastChange = changes[[-1]];

  text = lastChange["text"];

  cst = CodeConcreteParse[text, "TabWidth" -> 1];

  If[FailureQ[cst],
    Throw[cst]
  ];

  (*
  This is a File, not a String
  *)
  cst[[1]] = File;

  (*
  entries are: {text, cst, cstTabs, ast, lints from CodeInspectCST}

  Null represents a stale value
  *)
  $OpenFilesMap[uri] = {text, cst, Null, Null, Null};

  (*
  save time if the file has no tabs
  *)
  If[!StringContainsQ[text, "\t"],
    $OpenFilesMap[[Key[uri], 3]] = cst
  ];

  If[$Debug2,
    log["Calling didChangeNotifications: ", $didChangeNotifications];
    log["with these args: ", {uri}];
  ];

  Flatten[#[uri]& /@ $didChangeNotifications, 1]
]]



(*
convert from CodeTools Lint severities to LSP severities
*)
lintSeverityToLSPSeverity[severity_String] :=
Switch[severity,
  "Formatting" | "ImplicitTimes", $DiagnosticSeverity["Hint"],
  "Remark", $DiagnosticSeverity["Information"],
  "Warning", $DiagnosticSeverity["Warning"],
  "Error" | "Fatal", $DiagnosticSeverity["Error"]
]


publishDiagnosticsNotification[uri_String] :=
Module[{lints, lintsWithConfidence, shadowing, cst, entry},

  If[$Debug2,
    log["enter publishDiagnosticsNotification"];
  ];

  entry = $OpenFilesMap[uri];

  lints = entry[[5]];

  If[lints === Null,

    cst = entry[[2]];
    
    If[$Debug2,
      log["before CodeInspectCST"];
    ];

    lints = CodeInspectCST[cst];

    If[$Debug2,
      log["after CodeInspectCST"];
    ];

    $OpenFilesMap[[Key[uri], 5]] = lints;
  ];

  (*
  Might get something like FileTooLarge
  Still want to update
  *)
  If[FailureQ[lints],
    lints = {}
  ];

  lintsWithConfidence = Cases[lints, InspectionObject[_, _, _, KeyValuePattern[ConfidenceLevel -> _]]];

  lints = Cases[lintsWithConfidence, InspectionObject[_, _, _, KeyValuePattern[ConfidenceLevel -> _?(GreaterEqualThan[$ConfidenceLevel])]]];

  

  (*

  Disable shadow filtering for now

  Below is quadratic time

  shadowing = Select[lints, Function[lint, AnyTrue[lints, shadows[lint, #]&]]];

  lints = Complement[lints, shadowing];
  *)

  
  (*
  Make sure to sort lints before taking

  Sort by severity, then sort by Source

  severityToInteger maps "Remark" -> 1 and "Fatal" -> 4, so make sure to negate that
  *)
  lints = SortBy[lints, {-severityToInteger[#[[3]]]&, #[[4, Key[Source]]]&}];

  lints = Take[lints, UpTo[CodeInspector`Summarize`$LintLimit]];

  If[$Debug2,
    log["lints: ", stringLineTake[StringTake[ToString[lints, InputForm], UpTo[1000]], UpTo[20]]];
    log["...\n"];
  ];

  If[$Debug2,
    log["exit publishDiagnosticsNotification"];
  ];

  publishDiagnosticsNotificationWithLints[uri, lints]
]


publishDiagnosticsNotificationWithLints[uri_String, lints_List] :=
Module[{diagnostics},

  (*
  
  if no lints, must still publish in order to update client

  If[lints == {},
    Throw[Null]
  ];
  *)

  diagnostics = lintToDiagnostics /@ lints;

  diagnostics = Flatten[diagnostics];

  {<| "jsonrpc" -> "2.0",
      "method" -> "textDocument/publishDiagnostics",
      "params" -> <|         "uri" -> uri,
                     "diagnostics" -> diagnostics |> |>}
]



publishImplicitTokensNotification[uri_String] :=
Catch[
Module[{inspectedFileObj, lines, cst, entry},

  entry = $OpenFilesMap[uri];

  cst = entry[[2]];

  If[!CodeStructuralSyntaxCSTQ[cst],
    Throw[publishImplicitTokensNotificationWithLines[uri, {}]]
  ];

  inspectedFileObj = CodeInspectImplicitTokensCSTSummarize[cst, "TabWidth" -> 1];

  (*
  Might get something like FileTooLarge
  Still want to update
  *)
  If[FailureQ[inspectedFileObj],
    Throw[publishImplicitTokensNotificationWithLines[uri, {}]]
  ];

  (*
  Even though we have:
  Format[LintTimesCharacter, StandardForm] := "\[Times]"

  we cannot evaluate Format[LintTimesCharacter, StandardForm] to get "\[Times]"
  *)
  
  lines = <|
    "line" -> #[[2]],
    "characters" -> ((# /. {
      (*
      convert characters to the little markup language described in notes.md

      Openers and closers are dropped here
      *)
      LintAllCharacter -> "A",
      LintNullCharacter -> "N",
      LintOneCharacter -> "1",
      LintTimesCharacter -> "x",
      LintExpectedOperandCharacter -> "e",
      LintAllCloseCharacter -> "A",
      LintAllTimesCharacter -> "B",
      LintCloseCloseCharacter -> " ",
      LintCloseTimesCharacter -> "x",
      LintOpenOneCharacter -> "1",
      LintOpenOpenCharacter -> " ",
      LintTimesOneCharacter -> "y",
      LintExpectedOperandTimesCharacter -> "f",
      LintExpectedOperandCloseCharacter -> "e",
      LintOpenExpectedOperandCharacter -> "e",
      LintAllTimesOneCharacter -> "C",
      LintCloseTimesOneCharacter -> "y"
    })& /@ ((# /. LintMarkup[content_, ___] :> content)& /@ #[[3, 2, 2;;]]))
  |>& /@ inspectedFileObj[[2]];

  publishImplicitTokensNotificationWithLines[uri, lines]
]]


publishImplicitTokensNotificationWithLines[uri_String, lines_List] :=
Module[{},

  {<| "jsonrpc" -> "2.0",
      "method" -> "textDocument/publishImplicitTokens",
      "params" -> <|   "uri" -> uri,
                     "lines" -> lines |> |>}
]



publishBracketMismatchesNotification[uri_String] :=
Catch[
Module[{lines, entry, cst, text, mismatches, actions, textLines, action, suggestions, confidenceMap, badChunkLineNums,
  badChunkLines, badChunk, originalColumnCount, rank, chunkOffset, line1, line2, line3, line4,
  line1Map, line2Map, line3Map, line4Map, cstTabs},
  
  If[$Debug2,
    log["enter publishBracketMismatchesNotification"];
  ];

  If[!$BracketMatcher,
    Throw[publishHTMLSnippetWithLinesAndActions[uri, {}, {}]]
  ];

  entry = $OpenFilesMap[uri];

  text = entry[[1]];
  cstTabs = entry[[3]];

  If[cstTabs === Null,
    (*
    Using "TabWidth" -> 4 here because the notification is rendered down to HTML and tabs need to be expanded in HTML
    FIXME: Must use the tab width from the editor
    *)
    cstTabs = CodeConcreteParse[text, "TabWidth" -> 4];
    
    $OpenFilesMap[[Key[uri], 3]] = cstTabs;
  ];

  (*
  Using $BracketMatcher here
  *)

  mismatches = CodeInspectBracketMismatchesCST[cstTabs];

  If[$Debug2,
    log["mismatches: ", stringLineTake[StringTake[ToString[mismatches], UpTo[1000]], UpTo[20]]];
    log["...\n"];
  ];

  lines = {};
  actions = {};

  textLines = StringSplit[text, {"\r\n", "\n", "\r"}, All];

  line1Map = <||>;
  line2Map = <||>;
  line3Map = <||>;
  line4Map = <||>;
  Function[{mismatch},


    badChunkLineNums = mismatch[[3, Key[Source], All, 1]];
    badChunkLines = Take[textLines, badChunkLineNums];
    badChunk = StringJoin[Riffle[badChunkLines, "\n"]];

    suggestions = TimeConstrained[ML4Code`SuggestBracketEdits[badChunk], $ML4CodeTimeLimit, {}] /. $Failed -> {};
    suggestions = convertSuggestionToLineColumn[#, badChunkLines]& /@ suggestions;
    If[AnyTrue[suggestions, FailureQ],
      (*
      If any of the suggestions are malformed, then just give up. There is something wrong with ML4Code
      *)
      suggestions = {}
    ];

    If[$Debug2,
      log["badChunkLineNums: ", badChunkLineNums];
      log["badChunk: ", stringLineTake[StringTake[ToString[badChunk], UpTo[1000]], UpTo[20]]];
      log["...\n"];

      log["suggestions: ", suggestions];
    ];
    confidenceMap = Association[MapIndexed[#1 -> #2[[1]] &, Reverse[Union[suggestions[[All, 3]]]]]];
    Function[{suggestion},
      rank = confidenceMap[suggestion[[3]]];

      (*
      offset to add to relative line numbers inside suggestions to obtain line numbers of text
      *)
      chunkOffset = badChunkLineNums[[1]] - 1;
      originalColumnCount = StringLength[textLines[[suggestion[[1, 3, 1]] + chunkOffset]]];

      If[$Debug2,
        log["rank: ", rank];
        log["chunkOffset: ", chunkOffset];
        log["originalColumnCount: ", originalColumnCount];
      ];

      {line1, line2, line3, line4, action} = suggestionToLinesAndAction[suggestion, chunkOffset, originalColumnCount, rank];
      If[TrueQ[$DebugBracketMatcher],
        (*
        if debug, then keep all lines separated
        *)
        AppendTo[lines, line1]
        ,
        (*
        if not debug, then merge lines together
        *)
        If[KeyExistsQ[line1Map, line1["line"]],
          line1Map[line1["line"]] = merge[line1Map[line1["line"]], line1]
          ,
          line1Map[line1["line"]] = line1
        ];
        If[KeyExistsQ[line2Map, line2["line"]],
          line2Map[line2["line"]] = merge[line2Map[line2["line"]], line2]
          ,
          line2Map[line2["line"]] = line2
        ];
        If[KeyExistsQ[line3Map, line3["line"]],
          line3Map[line3["line"]] = merge[line3Map[line3["line"]], line3]
          ,
          line3Map[line3["line"]] = line3
        ];
        If[KeyExistsQ[line4Map, line4["line"]],
          line4Map[line4["line"]] = merge[line4Map[line4["line"]], line4]
          ,
          line4Map[line4["line"]] = line4
        ];
      ];

      AppendTo[actions, action];

    ] /@ suggestions;
  ] /@ mismatches;

  If[TrueQ[$DebugBracketMatcher],

    lines = <|#, "content" -> StringJoin[#["characters"]], "characterCount" -> Length[#["characters"]]|>& /@ lines
    ,

    lines = Values[line1Map] ~Join~ Values[line2Map] ~Join~ Values[line3Map] ~Join~ Values[line4Map];

    lines = <|#, "content" -> StringJoin[#["characters"]], "characterCount" -> Length[#["characters"]]|>& /@ lines;

    lines = Merge[<|#["line"] -> #|>& /@ lines, ({StringJoin["<div style=\"" <> "margin: 0;border: 0;padding: 0;\">", Riffle[(#["content"])& /@ #, "<br>"], "</div>"], #[[1]]["characterCount"]})&];
    
    lines = KeyValueMap[<|"line" -> #1, "content" -> #2[[1]], "characterCount" -> #2[[2]]|> &, lines]
  ];

  If[$Debug2,
    log["exit publishBracketMismatchesNotification"];
  ];

  publishHTMLSnippetWithLinesAndActions[uri, lines, actions]
]]


convertSuggestionToLineColumn[{{command_Symbol, text_String, index_Integer}, completed_String, prob_}, badChunkLines_] :=
  Module[{line, column},
    {line, column} = indexToLineColumn[index, badChunkLines];
    {{command, text, {line, column}}, completed, prob}
  ]

(*
ML4Code`SuggestBracketEdits may be broken and return crazy unevaluated stuff

Make sure to filter this out
*)
convertSuggestionToLineColumn[___] :=
  $Failed


indexToLineColumn[index_, badChunkLines_] :=
  Module[{indexs, line, taken, lineStartIndex, column},
    indexs = FoldList[#1 + StringLength[#2] + 1 &, 1, badChunkLines];
    taken = TakeWhile[indexs, (# <= index) &];
    line = Length[taken];
    lineStartIndex = Last[taken];
    column = index - lineStartIndex + 1;
    {line, column}
  ]


suggestionToLinesAndAction[{{Insert, insertionText_String, {line_Integer, column_Integer}}, completed_String, confidence_}, chunkOffset_Integer, originalColumnCount_Integer, rank_Integer] :=
  Module[{escaped, confidenceStr},
    escaped = StringReplace[Characters[insertionText], {"<" -> "&lt;", ">" -> "&gt;"}];
    confidenceStr = " confidence: " <> ToString[PercentForm[confidence]];

    $hrefIdCounter++;
    
    {
      (*
      top most line
      *)
      <|
        "line" -> line + chunkOffset,
        "characters" -> ReplacePart[Table["&nbsp;", {originalColumnCount + 1}], {column -> makeHTML[Switch[rank, 1|2|3, blueRank[rank], _, gray[]], $upArrow, ToString[$hrefIdCounter], "Insert " <> escaped <> " " <> confidenceStr]}]
      |>
      ,
      <|
        "line" -> line + chunkOffset,
        "characters" -> ReplacePart[Table["&nbsp;", {originalColumnCount + 1}], {column -> makeHTML[Switch[rank, 1|2, blueRank[rank], _, gray[]], $upArrow, ToString[$hrefIdCounter], "Insert " <> escaped <> " " <> confidenceStr]}]
      |>
      ,
      <|
        "line" -> line + chunkOffset,
        "characters" -> ReplacePart[Table["&nbsp;", {originalColumnCount + 1}], {column -> makeHTML[Switch[rank, 1, blueRank[rank], _, gray[]], $upArrow, ToString[$hrefIdCounter], "Insert " <> escaped <> " " <> confidenceStr]}]
      |>
      ,
      (*
      bottom most line
      *)
      <|
        "line" -> line + chunkOffset,
        "characters" ->
          If[$BracketMatcherDisplayInsertionText,
            ReplacePart[Table["&nbsp;", {originalColumnCount + 1}], {
              column -> makeHTML[blueRank[rank], escaped[[1]], ToString[$hrefIdCounter], ""],
              column + 1 -> If[Length[escaped] == 2, makeHTML[blueRank[rank], escaped[[2]], ToString[$hrefIdCounter], ""], "&nbsp;"]
            }]
            ,
            Table["&nbsp;", {originalColumnCount + 1}]
          ]
      |>
      ,
      (*
      action
      *)
      <|"command" -> "insert",
        "insertionText" -> insertionText,
        "line" -> line + chunkOffset,
        "column" -> column,
        "href" -> ToString[$hrefIdCounter]
      |>
    }
  ]

suggestionToLinesAndAction[{{Delete, deletionText_String, {line_Integer, column_Integer}}, completed_String, probability_}, chunkOffset_Integer, originalColumnCount_Integer, rank_Integer] :=
  Module[{escaped},
    escaped = StringReplace[deletionText, {"<" -> "&lt;", ">" -> "&gt;"}];

    $hrefIdCounter++;
    
    {
      (*
      top most line
      *)
      <|
        "line" -> line + chunkOffset,
        "characters" -> ReplacePart[Table["&nbsp;", {originalColumnCount + 1}], column -> makeHTML[Switch[rank, 1|2|3, redRank[rank], _, gray[]], $downArrow, ToString[$hrefIdCounter], "Delete " <> escaped <> " prob: " <> ToString[PercentForm[probability]]]]
      |>
      ,
      <|
        "line" -> line + chunkOffset,
        "characters" -> ReplacePart[Table["&nbsp;", {originalColumnCount + 1}], column -> makeHTML[Switch[rank, 1|2, redRank[rank], _, gray[]], $downArrow, ToString[$hrefIdCounter], "Delete " <> escaped <> " prob: " <> ToString[PercentForm[probability]]]]
      |>
      ,
      <|
        "line" -> line + chunkOffset,
        "characters" -> ReplacePart[Table["&nbsp;", {originalColumnCount + 1}], column -> makeHTML[Switch[rank, 1, redRank[rank], _, gray[]], $downArrow, ToString[$hrefIdCounter], "Delete " <> escaped <> " prob: " <> ToString[PercentForm[probability]]]]
      |>
      ,
      (*
      bottom most line
      *)
      <|
        "line" -> line + chunkOffset,
        "characters" -> Table["&nbsp;", {originalColumnCount + 1}]
      |>
      ,
      (*
      action
      *)
      <|
        "command" -> "delete",
        "deletionText" -> deletionText,
        "line" -> line + chunkOffset,
        "column" -> column,
        "href" -> ToString[$hrefIdCounter]
      |>
    }
  ]



gray[] :=
  RGBColor[0.74902, 0.74902, 0.74902]

redRank[rank_] /; TrueQ[$BracketMatcherUseDesignColors] :=
  RGBColor[0.984314, 0.0509804, 0.105882]

blueRank[rank_] /; TrueQ[$BracketMatcherUseDesignColors] :=
  RGBColor[0.27451, 0.662745, 0.988235]

(*
FIXME: designed for a white background color scheme, need to get current background from client
*)
redRank[rank_] /; !TrueQ[$BracketMatcherUseDesignColors] :=
  If[TrueQ[$DebugBracketMatcher],
    RGBColor[1, 0, 0]
    ,
    Switch[rank,
      1,
        RGBColor[1, 0, 0]
      ,
      2,
        RGBColor[1, 0.55, 0.55]
      ,
      3,
        RGBColor[1, 0.75, 0.75]
    ]
  ]

(*
FIXME: designed for a white background color scheme, need to get current background from client
*)
blueRank[rank_] /; !TrueQ[$BracketMatcherUseDesignColors] :=
  If[TrueQ[$DebugBracketMatcher],
    RGBColor[0, 0, 1]
    ,
    Switch[rank,
      1,
        RGBColor[0, 0, 1]
      ,
      2,
        RGBColor[0.55, 0.55, 1]
      ,
      3,
        RGBColor[0.75, 0.75, 1]
    ]
  ]



publishHTMLSnippetWithLines[uri_String, lines_List] :=
Catch[
Module[{},

  If[!$HTMLSnippets,
    Throw[{}]
  ];

  {<| "jsonrpc" -> "2.0",
      "method" -> "textDocument/publishHTMLSnippet",
      "params" -> <|   "uri" -> uri,
                     "lines" -> lines,
                     "actions" -> {} |> |>}
]]

publishHTMLSnippetWithLinesAndActions[uri_String, lines_List, actions_List] :=
Catch[
Module[{},

  If[!$HTMLSnippets,
    Throw[{}]
  ];

  {<| "jsonrpc" -> "2.0",
      "method" -> "textDocument/publishHTMLSnippet",
      "params" -> <|   "uri" -> uri,
                     "lines" -> lines,
                     "actions" -> actions |> |>}
]]




lintToDiagnostics[InspectionObject[tag_, message_, severity_, data_]] :=
Catch[
Module[{srcs},

  If[!KeyExistsQ[data, Source],
    (*
    It is possible that abstracted problems may not have Source

    An example would be  a < b > c  being abstracted as an Inequality expression

    Inequality is an undocumented symbol, but it does not actually show up in the source code

    So it would be wrong to report "Inequality is an undocumented symbol" for  a < b > c
    *)
    Throw[{}]
  ];

  srcs = { data[Source] } ~Join~ Lookup[data, "AdditionalSources", {}];

  ((<|     "code" -> tag,
        "message" -> plainify[message],
       "severity" -> lintSeverityToLSPSeverity[severity],
          "range" -> <| "start" -> <| "line" -> #[[1, 1]], "character" -> #[[1, 2]] |>,
                          "end" -> <| "line" -> #[[2, 1]], "character" -> #[[2, 2]] |> |>,
         "source" -> "wolfram lint" |>)&[Map[Max[#, 0]&, #-1, {2}]])& /@ srcs
]]



handleContent[content:KeyValuePattern["method" -> "textDocument/codeAction"]] :=
Catch[
Module[{id, params, doc, uri, actions, range, lints, lspAction, lspActions, edit, diagnostics,
  command, label, actionData, actionSrc, replacementNode, insertionNode, replacementText, lintsWithConfidence,
  shadowing, insertionText, cursor, entry, text, cst},
  
  id = content["id"];
  params = content["params"];
  doc = params["textDocument"];
  uri = doc["uri"];
  range = params["range"];

  cursor = { { range["start"]["line"], range["start"]["character"] },
             {   range["end"]["line"],   range["end"]["character"] } };

  (* convert from 0-based to 1-based *)
  cursor+=1;

  If[$Debug2,
    log["cursor: ", ToString[cursor]];
  ];

  entry = $OpenFilesMap[uri];

  lints = entry[[5]];

  If[lints === Null,

    cst = entry[[2]];
    
    lints = CodeInspectCST[cst];
    
    $OpenFilesMap[[Key[uri], 5]] = lints;
  ];

  If[$Debug2,
    log["lints: ", stringLineTake[StringTake[ToString[lints, InputForm], UpTo[1000]], UpTo[20]]];
    log["...\n"];
  ];

  (*
  Might get something like FileTooLarge
  *)
  If[FailureQ[lints],
    Throw[{<|"jsonrpc" -> "2.0", "id" -> id, "result" -> {} |>}]
  ];

  lintsWithConfidence = Cases[lints, InspectionObject[_, _, _, KeyValuePattern[ConfidenceLevel -> _]]];

  lints = Cases[lintsWithConfidence, InspectionObject[_, _, _, KeyValuePattern[ConfidenceLevel -> _?(GreaterEqualThan[$ConfidenceLevel])]]];


  (*

  Disable shadow filtering for now

  Below is quadratic time

  shadowing = Select[lints, Function[lint, AnyTrue[lints, shadows[lint, #]&]]];

  If[$Debug2,
   Write[$Messages, "shadowing: " //OutputForm, ToString[shadowing, InputForm] //OutputForm];
  ];

  lints = Complement[lints, shadowing];
  *)
  
  (*
  Make sure to sort lints before taking

  Sort by severity, then sort by Source

  severityToInteger maps "Remark" -> 1 and "Fatal" -> 4, so make sure to negate that
  *)
  lints = SortBy[lints, {-severityToInteger[#[[3]]]&, #[[4, Key[Source]]]&}];

  lints = Take[lints, UpTo[CodeInspector`Summarize`$LintLimit]];

  
  lspActions = {};

  Do[

    diagnostics = lintToDiagnostics[lint];

    If[$Debug2,
      log["diagnostics: ", ToString[diagnostics]];
    ];

    (*
    Need to filter the actions that match the cursor
    *)
    actions = Cases[lint, CodeAction[_, _, KeyValuePattern[Source -> src_ /; SourceMemberIntersectingQ[src, cursor]]], Infinity];

    If[$Debug2,
      log["actions: ", ToString[actions]];
    ];

    Do[

      label = action[[1]];

      label = plainify[label];

      command = action[[2]];
      actionData = action[[3]];

      actionSrc = actionData[Source];

      Switch[command,

        InsertNode,

        insertionNode = actionData["InsertionNode"];

        If[$Debug2,
          log["insertionNode: ", ToString[insertionNode]];
        ];

        (*
        For inserting, don't use the [start, end) range, only use [start, start)
        *)
        edit = (<| "changes"-> <| uri -> { <| "range" -> <| "start" -> <| "line" -> #[[1, 1]], "character" -> #[[1, 2]] |>,
                                                              "end" -> <| "line" -> #[[1, 1]], "character" -> #[[1, 2]] |> |>,
                                            "newText" -> ToSourceCharacterString[insertionNode]|> } |> |>)&[Map[Max[#, 0]&, actionSrc-1, {2}]];

        lspAction = <|      "title"  -> label,
                             "kind"  -> "quickfix",
                             "edit"  -> edit,
                       "diagnostics" -> diagnostics |>;

        AppendTo[lspActions, lspAction];

        ,

        InsertText,

        insertionText = actionData["InsertionText"];

        If[$Debug2,
          log["insertionText: ", ToString[insertionText]];
        ];

        (*
        For inserting, don't use the [start, end) range, only use [start, start)
        *)
        edit = (<| "changes" -> <| uri -> { <| "range" -> <| "start" -> <| "line" -> #[[1, 1]], "character" -> #[[1, 2]] |>,
                                                               "end" -> <| "line" -> #[[1, 1]], "character" -> #[[1, 2]] |> |>,
                                             "newText" -> insertionText|> } |> |>)&[Map[Max[#, 0]&, actionSrc-1, {2}]];

        lspAction = <|       "title" -> label,
                              "kind" -> "quickfix",
                              "edit" -> edit,
                       "diagnostics" -> diagnostics |>;

        AppendTo[lspActions, lspAction];

        ,

        DeleteNode,

        edit = (<| "changes"-> <| uri -> { <| "range" -> <| "start" -> <| "line" -> #[[1, 1]], "character" -> #[[1, 2]] |>,
                                                              "end" -> <| "line" -> #[[2, 1]], "character" -> #[[2, 2]] |> |>,
                                            "newText" -> "" |> } |> |>)&[Map[Max[#, 0]&, actionSrc-1, {2}]];

        lspAction = <|       "title" -> label,
                              "kind" -> "quickfix",
                              "edit" -> edit,
                       "diagnostics" -> diagnostics |>;

        AppendTo[lspActions, lspAction];

        ,

        ReplaceNode,

        replacementNode = actionData["ReplacementNode"];

        If[$Debug2,
          log["replacementNode: ", ToString[replacementNode]];
        ];

        edit = (<| "changes"-> <| uri -> { <| "range" -> <| "start" -> <| "line" -> #[[1, 1]], "character" -> #[[1, 2]] |>,
                                                              "end" -> <| "line" -> #[[2, 1]], "character" -> #[[2, 2]] |> |>,
                                            "newText" -> ToSourceCharacterString[replacementNode] |> } |> |>)&[Map[Max[#, 0]&, actionSrc-1, {2}]];

        lspAction = <|        "title" -> label,
                               "kind" -> "quickfix",
                               "edit" -> edit,
                        "diagnostics" -> diagnostics |>;

        AppendTo[lspActions, lspAction];

        ,

        ReplaceText,

        replacementText = actionData["ReplacementText"];

        If[$Debug2,
          log["replacementText: ", ToString[replacementText]];
        ];

        edit = (<| "changes"-> <| uri -> { <| "range" -> <| "start" -> <| "line" -> #[[1, 1]], "character" -> #[[1, 2]] |>,
                                                              "end" -> <| "line" -> #[[2, 1]], "character" -> #[[2, 2]] |> |>,
                                            "newText" -> replacementText|> } |> |>)&[Map[Max[#, 0]&, actionSrc-1, {2}]];

        lspAction = <|       "title" -> label,
                              "kind" -> "quickfix",
                              "edit" -> edit,
                       "diagnostics" -> diagnostics |>;

        AppendTo[lspActions, lspAction];

        ,

        _,

        If[$Debug,
          log["UNSUPPORTED COMMAND: ", command];
        ];

      ]

      ,
      {action, actions}
    ]

    ,
    {lint, lints}
  ];

  {<|"jsonrpc" -> "2.0", "id" -> id, "result" -> lspActions |>}
]]



handleContent[content:KeyValuePattern["method" -> "textDocument/formatting"]] :=
Catch[
Module[{params, doc, uri, id, cst, formatted, startLineCol, endLineCol, textEdit, options, tabSize, insertSpaces,
  indentationString, entry, text},

  id = content["id"];

  params = content["params"];
  doc = params["textDocument"];
  uri = doc["uri"];

  options = params["options"];
  tabSize = options["tabSize"];
  insertSpaces = options["insertSpaces"];

  entry = $OpenFilesMap[uri];

  text = entry[[1]];

  cst = CodeConcreteParse[text, "TabWidth" -> tabSize];

  startLineCol = cst[[2, 1, 3, Key[Source], 1]];
  endLineCol = cst[[2, -1, 3, Key[Source], 2]];

  (*
  convert from 1-based to 0-based
  *)
  startLineCol--;
  endLineCol--;

  If[insertSpaces,
    indentationString = StringJoin[Table[" ", {tabSize}]]
    ,
    indentationString = "\t"
  ];

  formatted = CodeFormatCST[cst, "TabWidth" -> tabSize, "IndentationString" -> indentationString];

  If[FailureQ[formatted],
    Throw[formatted]
  ];

  textEdit = <| "range" -> <| "start" -> <| "line" -> startLineCol[[1]], "character" -> startLineCol[[2]] |>,
                              "end" ->   <| "line" -> endLineCol[[1]], "character" -> endLineCol[[2]] |> |>,
                "newText" -> formatted|>;

  {<|"jsonrpc" -> "2.0", "id" -> id, "result" -> { textEdit } |>}
]]

handleContent[content:KeyValuePattern["method" -> "textDocument/rangeFormatting"]] :=
Catch[
Module[{params, doc, uri, id, formatted, textEdit, entry, text, options, tabSize,
  insertSpaces, rangeSource, lines},

  id = content["id"];

  params = content["params"];
  doc = params["textDocument"];
  uri = doc["uri"];

  range = params["range"];
  
  rangeSource = { { range["start"]["line"], range["start"]["character"] },
                  { range["end"]["line"],   range["end"]["character"] } };

  (* convert from 0-based to 1-based *)
  rangeSource+=1;

  options = params["options"];
  tabSize = options["tabSize"];
  insertSpaces = options["insertSpaces"];

  entry = $OpenFilesMap[uri];

  text = entry[[1]];

  lines = StringSplit[text, {"\r\n", "\n", "\r"}, All];
  lines = lines[[rangeSource[[1, 1]];;rangeSource[[2, 1]]]];
  If[rangeSource[[1, 1]] == rangeSource[[2, 1]],
    (*
    single line selection
    *)
    text = StringTake[lines[[1]], {rangeSource[[1, 2]], rangeSource[[2, 2]] - 1}]
    ,
    (*
    multiple line selection
    *)
    lines[[1]] = StringDrop[lines[[1]], rangeSource[[1, 2]] - 1];
    lines[[-1]] = StringTake[lines[[-1]], rangeSource[[2, 2]] - 1];
    (*
    FIXME: use the correct newline
    *)
    text = StringJoin[Riffle[lines, "\n"]];
  ];

  If[insertSpaces,
    indentationString = StringJoin[Table[" ", {tabSize}]]
    ,
    indentationString = "\t"
  ];

  formatted = CodeFormat[text, "TabWidth" -> tabSize, "IndentationString" -> indentationString];

  If[FailureQ[formatted],
    Throw[formatted]
  ];

  textEdit = <| "range" -> range,
                "newText" -> formatted|>;

  {<|"jsonrpc" -> "2.0", "id" -> id, "result" -> { textEdit } |>}
]]


handleContent[content:KeyValuePattern["method" -> "workspace/executeCommand"]] :=
Catch[
Module[{params, id, command},

  id = content["id"];

  params = content["params"];

  command = params["command"];

  Switch[command,
    "enable_bracket_matcher_debug_mode",
      $DebugBracketMatcher = True;
    ,
    "disable_bracket_matcher_debug_mode",
      $DebugBracketMatcher = False;
    ,
    "enable_bracket_matcher_design_colors",
      $BracketMatcherUseDesignColors = True;
    ,
    "disable_bracket_matcher_design_colors",
      $BracketMatcherUseDesignColors = False;
    ,
    "enable_bracket_matcher_display_insertion_text",
      $BracketMatcherDisplayInsertionText = True;
    ,
    "disable_bracket_matcher_display_insertion_text",
      $BracketMatcherDisplayInsertionText = False;
    ,
    _,
      If[$Debug,
        log["UNSUPPORTED COMMAND: ", command];
      ];
  ];

  {<|"jsonrpc" -> "2.0", "id" -> id, "result" -> { } |>}
]]



$upArrow = "\:25b2"

$downArrow = "\:25bc"

(*
FIXME: Use the same font as the editor
*)
$fontFamily = "Fira Code"


makeHTML[color_RGBColor, arrow_String, href_String, debugStr_String] /; TrueQ[$DebugBracketMatcher] :=
  Module[{colorHex},
    colorHex = StringJoin[IntegerString[Round[255 List @@ color], 16, 2]];
"\
<span style=\"" <> "margin: 0;border: 0;padding: 0;" <> "\">\
<a style=\"" <> "margin: 0;border: 0;padding: 0;text-decoration: none;" <> "font-family:" <> $fontFamily <> ";color:#" <> colorHex <> ";" <> "\" href=" <> "\"" <> href <> "\"" <> ">" <> arrow <> "</a><br>\
<a style=\"" <> "margin: 0;border: 0;padding: 0;text-decoration: none;" <> "font-family:" <> $fontFamily <> ";color:#" <> colorHex <> ";" <> "\" href=" <> "\"" <> href <> "\"" <> ">" <> debugStr <> "</a>\
</span>\
"
  ]

makeHTML[color_RGBColor, arrow_String, href_String, debugStr_String] /; !TrueQ[$DebugBracketMatcher] :=
  Module[{colorHex},
    colorHex = StringJoin[IntegerString[Round[255 List @@ color], 16, 2]];
"\
<span style=\"" <> "margin: 0;border: 0;padding: 0;" <> "\">\
<a style=\"" <> "margin: 0;border: 0;padding: 0;text-decoration: none;" <> "font-family:" <> $fontFamily <> ";color:#" <> colorHex <> ";" <> "\" href=" <> "\"" <> href <> "\"" <> ">" <> arrow <> "</a>\
</span>\
"
  ]



exitGracefully[] := (
  log["\n\n"];
  log["KERNEL IS EXITING GRACEFULLY"];
  log["\n\n"];
  Pause[1];Exit[0]
)

exitSemiGracefully[] := (
  log["\n\n"];
  log["KERNEL IS EXITING SEMI-GRACEFULLY"];
  log["\n\n"];
  Pause[1];Exit[1]
)

exitHard[] := (
  log["\n\n"];
  log["KERNEL IS EXITING HARD"];
  log["\n\n"];
  Pause[1];Exit[1]
)


End[]

EndPackage[]
