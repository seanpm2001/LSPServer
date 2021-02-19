BeginPackage["LSPServer`Diagnostics`"]

Begin["`Private`"]

Needs["LSPServer`"]
Needs["LSPServer`Utils`"]
Needs["CodeInspector`"]
Needs["CodeInspector`Utils`"]
Needs["CodeParser`"]
Needs["CodeParser`Scoping`"] (* for scopingDataObject *)


expandContent[content:KeyValuePattern["method" -> "textDocument/runDiagnostics"], pos_] :=
  Catch[
  Module[{params, doc, uri},

    If[$Debug2,
      log["textDocument/runDiagnostics: enter expand"]
    ];
    
    params = content["params"];
    doc = params["textDocument"];
    uri = doc["uri"];

    If[isStale[$PreExpandContentQueue[[pos[[1]]+1;;]], uri],
    
      If[$Debug2,
        log["stale"]
      ];

      Throw[{}]
    ];

    <| "method" -> #, "params" -> params |>& /@ {
       "textDocument/concreteParse",
       "textDocument/runConcreteDiagnostics",
       "textDocument/aggregateParse",
       "textDocument/runAggregateDiagnostics",
       "textDocument/abstractParse",
       "textDocument/runAbstractDiagnostics",
       "textDocument/runScopingData", (* implemented in SemanticTokens.wl *)
       "textDocument/runScopingDiagnostics"
    }
  ]]

handleContent[content:KeyValuePattern["method" -> "textDocument/runConcreteDiagnostics"]] :=
  Catch[
  Module[{params, doc, uri, entry, cst, cstLints},

    If[$Debug2,
      log["textDocument/runConcreteDiagnostics: enter"]
    ];

    params = content["params"];
    doc = params["textDocument"];
    uri = doc["uri"];

    If[isStale[$ContentQueue, uri],
      
      If[$Debug2,
        log["stale"]
      ];

      Throw[{}]
    ];

    entry = $OpenFilesMap[uri];

    cstLints = Lookup[entry, "CSTLints", Null];

    If[cstLints =!= Null,
      Throw[{}]
    ];
    
    cst = entry["CST"];

    If[$Debug2,
      log["before CodeInspectCST"]
    ];

    cstLints = CodeInspectCST[cst, "AggregateRules" -> <||>, "AbstractRules" -> <||>];

    If[$Debug2,
      log["after CodeInspectCST"]
    ];

    If[$Debug2,
      log["cstLints: ", #["Tag"]& /@ cstLints]
    ];

    entry["CSTLints"] = cstLints;

    $OpenFilesMap[uri] = entry;

    {}
  ]]

handleContent[content:KeyValuePattern["method" -> "textDocument/runAggregateDiagnostics"]] :=
  Catch[
  Module[{params, doc, uri, entry, agg, aggLints},

    If[$Debug2,
      log["textDocument/runAggregateDiagnostics: enter"]
    ];

    params = content["params"];
    doc = params["textDocument"];
    uri = doc["uri"];

    If[isStale[$ContentQueue, uri],
      
      If[$Debug2,
        log["stale"]
      ];

      Throw[{}]
    ];

    entry = $OpenFilesMap[uri];

    aggLints = Lookup[entry, "AggLints", Null];

    If[aggLints =!= Null,
      Throw[{}]
    ];

    agg = entry["Agg"];

    If[$Debug2,
      log["before CodeInspectAgg"]
    ];

    aggLints = CodeInspectAgg[agg, "AbstractRules" -> <||>];

    If[$Debug2,
      log["after CodeInspectAgg"]
    ];

    If[$Debug2,
      log["aggLints: ", #["Tag"]& /@ aggLints]
    ];

    entry["AggLints"] = aggLints;

    $OpenFilesMap[uri] = entry;

    {}
  ]]

handleContent[content:KeyValuePattern["method" -> "textDocument/runAbstractDiagnostics"]] :=
  Catch[
  Module[{params, doc, uri, entry, ast, astLints},

    If[$Debug2,
      log["textDocument/runAbstractDiagnostics: enter"]
    ];

    params = content["params"];
    doc = params["textDocument"];
    uri = doc["uri"];

    If[isStale[$ContentQueue, uri],
      
      If[$Debug2,
        log["stale"]
      ];

      Throw[{}]
    ];

    entry = $OpenFilesMap[uri];

    astLints = Lookup[entry, "ASTLints", Null];

    If[astLints =!= Null,
      Throw[{}]
    ];

    ast = entry["AST"];

    If[$Debug2,
      log["before CodeInspectAST"]
    ];

    astLints = CodeInspectAST[ast];

    If[$Debug2,
      log["after CodeInspectAST"]
    ];

    If[$Debug2,
      log["astLints: ", #["Tag"]& /@ astLints]
    ];

    entry["ASTLints"] = astLints;

    $OpenFilesMap[uri] = entry;

    {}
  ]]

handleContent[content:KeyValuePattern["method" -> "textDocument/runScopingDiagnostics"]] :=
  Catch[
  Module[{params, doc, uri, entry, scopingLints, scopingData, filtered},

    If[$Debug2,
      log["textDocument/runScopingDiagnostics: enter"]
    ];

    (*
    If $SemanticTokens, then do not also create scoping diagnostics
    *)
    If[$SemanticTokens,
      Throw[{}]
    ];

    params = content["params"];
    doc = params["textDocument"];
    uri = doc["uri"];

    If[isStale[$ContentQueue, uri],
      
      If[$Debug2,
        log["stale"]
      ];

      Throw[{}]
    ];

    entry = $OpenFilesMap[uri];

    scopingLints = Lookup[entry, "ScopingLints", Null];

    If[scopingLints =!= Null,
      Throw[{}]
    ];

    scopingData = entry["ScopingData"];

    If[$Debug2,
      log["scopingData: ", scopingData]
    ];

    (*
    Filter those that have non-empty modifiers
    *)
    filtered = Cases[scopingData, scopingDataObject[_, _, {_, ___}]];

    scopingLints = scopingDataObjectToLints /@ filtered;

    scopingLints = Flatten[scopingLints];

    If[$Debug2,
      log["scopingLints: ", #["Tag"]& /@ scopingLints]
    ];

    entry["ScopingLints"] = scopingLints;

    $OpenFilesMap[uri] = entry;

    {}
  ]]


handleContent[content:KeyValuePattern["method" -> "textDocument/clearDiagnostics"]] :=
  Catch[
  Module[{params, doc, uri, entry},

    If[$Debug2,
      log["textDocument/clearDiagnostics: enter"]
    ];

    params = content["params"];
    doc = params["textDocument"];
    uri = doc["uri"];

    If[isStale[$ContentQueue, uri],
      
      If[$Debug2,
        log["stale"]
      ];

      Throw[{}]
    ];

    entry = $OpenFilesMap[uri];

    entry["CSTLints"] =.;

    entry["AggLints"] =.;
    
    entry["ASTLints"] =.;

    entry["ScopingLints"] =.;

    $OpenFilesMap[uri] = entry;

    {}
  ]]


handleContent[content:KeyValuePattern["method" -> "textDocument/publishDiagnostics"]] :=
  Catch[
  Module[{params, doc, uri, entry, lints, lintsWithConfidence, cstLints, aggLints, astLints, scopingLints, diagnostics},

    If[$Debug2,
      log["textDocument/publishDiagnostics: enter"]
    ];

    params = content["params"];
    doc = params["textDocument"];
    uri = doc["uri"];

    If[isStale[$ContentQueue, uri],
      
      If[$Debug2,
        log["stale"]
      ];

      Throw[{}]
    ];
    
    entry = Lookup[$OpenFilesMap, uri, Null];

    (*
    Possibly cleared
    *)
    If[entry === Null,
      Throw[{<| "jsonrpc" -> "2.0",
                "method" -> "textDocument/publishDiagnostics",
                "params" -> <| "uri" -> uri,
                               "diagnostics" -> {} |> |>}]
    ];

    (*
    Possibly cleared
    *)
    cstLints = Lookup[entry, "CSTLints", {}];

    (*
    Possibly cleared
    *)
    aggLints = Lookup[entry, "AggLints", {}];

    (*
    Possibly cleared
    *)
    astLints = Lookup[entry, "ASTLints", {}];

    (*
    Possibly cleared
    *)
    scopingLints = Lookup[entry, "ScopingLints", {}];

    lints = cstLints ~Join~ aggLints ~Join~ astLints ~Join~ scopingLints;

    If[$Debug2,
      log["lints: ", #["Tag"]& /@ lints]
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
      log["lints: ", #["Tag"]& /@ lints]
    ];

    diagnostics = lintToDiagnostics /@ lints;

    diagnostics = Flatten[diagnostics];

    {<| "jsonrpc" -> "2.0",
        "method" -> "textDocument/publishDiagnostics",
        "params" -> <| "uri" -> uri,
                       "diagnostics" -> diagnostics |> |>}
  ]]


End[]

EndPackage[]
