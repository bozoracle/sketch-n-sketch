module Types2 exposing
  ( typecheck
  , makeDeuceExpTool
  , makeDeucePatTool
  , AceTypeInfo
  , aceTypeInfo
  , dummyAceTypeInfo
  , typeChecks
  )

import Info exposing (WithInfo, withDummyInfo)
import Lang exposing (..)
import LangTools
import LangUtils
import LeoParser exposing (parse)
import LeoUnparser exposing (unparse, unparsePattern, unparseType)
import Ace
-- can't depend on Model, since ExamplesGenerated depends on Types2
import Utils

import Regex
import EditDistance

unparseMaybeType mt =
  case mt of
    Nothing -> "NO TYPE"
    Just t  -> unparseType t


--------------------------------------------------------------------------------

type alias AceTypeInfo =
  { annotations : List Ace.Annotation
  , highlights : List Ace.Highlight
  , tooltips : List Ace.Tooltip
  }

dummyAceTypeInfo =
  AceTypeInfo [] [] []

aceTypeInfo : Exp -> AceTypeInfo
aceTypeInfo exp =
  { highlights =
      []

  , annotations =
      let
        -- ept is "e" or "p" or "t"
        processThing ept thing toId thingToString =
          case (thing.val.typ, thing.val.typeError) of
            (Just _, Nothing) ->
              []
            _ ->
              addErrorAnnotation ept thing toId thingToString

        addErrorAnnotation ept thing toId thingToString =
          [ { row =
                thing.start.line - 1
            , type_ =
                "error"
            , text =
                String.concat
                  [ "Type error ["
                  , ept, "id: ", toString (toId thing.val), "; "
                  , "col: ", toString thing.start.col
                  , "]: ", "\n"
                  , String.trim (thingToString thing), "\n"
                  ]
            }
          ]

        processExp e =
          -- TODO for now, ignoring top-level prog and implicit main ---------------------------
          case ((unExpr e).start.line, (unExpr e).val.e__) of
            (1, _) -> []
            (_, EVar _ "main") -> []
            -- (_, ELet _ Let (Declarations [0] [] [] [(False, [LetExp _ _ p _ _ _])]) _ _) -> []
            _ ->
          --------------------------------------------------------------------------------------
          let
            result =
              annots1 ++ annots2

            annots1 =
              processThing "e" (unExpr e) .eid (Expr >> unparse)

            annots2 =
              case (unExpr e).val.e__ of
                EFun _ pats _ _->
                  pats
                    |> List.concatMap (\pat -> processThing "p" pat .pid unparsePattern)

                ELet _ _ (Declarations _ _ letAnnots _) _ _ ->
                  -- TODO: why aren't top-level pattern errors appearing in Ace annotations?
                  letAnnots
                    |> List.concatMap (\(LetAnnotation _ _ pat _ _ _) ->
                         processThing "p" pat .pid unparsePattern
                       )

                _ ->
                  []
          in
            result

        errorAnnotations =
          foldExp (\e acc -> processExp e ++ acc) [] exp

        summaryAnnotation =
          case errorAnnotations of
            [] ->
              { row = 0, type_ = "info", text= "No type errors!" }

            _ ->
              { row = 0, type_ = "warning", text="Type errors below..." }
      in
        summaryAnnotation :: errorAnnotations

  , tooltips =
      let addTooltip e =
        { row = (unExpr e).start.line - 1
        , col = (unExpr e).start.col - 1
        , text = "EId: " ++ toString (unExpr e).val.eid
        } 
      in
      -- Ace tooltips are token-based, so can't have them for expression
      -- forms that don't have an explicit start token
      --
      -- foldExp (\e acc -> addTooltip e :: acc) [] exp
      []
  }


--------------------------------------------------------------------------------

type alias TypeEnv = List TypeEnvElement

type TypeEnvElement
  = HasType Pat (Maybe Type)
  | TypeVar Ident
  -- | TypeAlias Pat Type


addHasMaybeType : (Pat, Maybe Type) -> TypeEnv -> TypeEnv
addHasMaybeType (p, mt) gamma =
  HasType p mt :: gamma


addHasType : (Pat, Type) -> TypeEnv -> TypeEnv
addHasType (p, t) gamma =
  addHasMaybeType (p, Just t) gamma


addTypeVar : Ident -> TypeEnv -> TypeEnv
addTypeVar typeVar gamma =
  TypeVar typeVar :: gamma


lookupVar : TypeEnv -> Ident -> Maybe (Maybe Type)
lookupVar gamma x =
  case gamma of
    HasType p mt :: gammaRest ->
      Utils.firstOrLazySecond
        (lookupVarInPat x p mt)
        (\_ -> lookupVar gammaRest x)

    _ :: gammaRest ->
      lookupVar gammaRest x

    [] ->
      Nothing


lookupVarInPat : Ident -> Pat -> Maybe Type -> Maybe (Maybe Type)
lookupVarInPat x p mt =
  case p.val.p__ of
    PConst _ _ -> Nothing
    PBase _ _ -> Nothing
    PWildcard _ -> Nothing

    PVar _ y _ ->
      if x == y then
        Just mt
      else
        Nothing

    -- TODO
{-
  | PList WS (List Pat) WS (Maybe Pat) WS -- TODO store WS before commas, like EList
  | PAs WS Pat WS Pat
  | PParens WS Pat WS
  | PRecord WS {- { -}  (List (Maybe WS {- , -}, WS, Ident, WS{-=-}, Pat)) WS{- } -}
  | PColonType WS Pat WS Type
-}

    _ ->
      Nothing


varsOfGamma gamma =
  case gamma of
    HasType p mt :: gammaRest ->
      varsOfPat p ++ varsOfGamma gammaRest

    _ :: gammaRest ->
      varsOfGamma gammaRest

    [] ->
      []


varsOfPat pat =
  Tuple.second <|
    mapFoldPatTopDown
        (\p acc ->
          case p.val.p__ of
            PVar _ y _ -> (p, y :: acc)
            _          -> (p, acc)
        )
        []
        pat


varNotFoundSuggestions x gamma =
  let
    result =
      List.concatMap maybeSuggestion (varsOfGamma gamma)

    maybeSuggestion y =
      let
        xLength =
          String.length x
        xSorted =
          List.sort (String.toList x)
        ySorted =
          List.sort (String.toList y)
        distance =
          EditDistance.levenshtein xSorted ySorted
            -- lowerBound: abs (xLength - yLength)
            -- upperBound: max xLength yLength
        closeEnough =
          if xLength <= 3 && distance <= xLength - 1 then
            True
          else if distance <= 3 then
            True
          else
            False
      in
        if closeEnough then
          [y]
        else
          []
  in
    result


findUnboundTypeVars : TypeEnv -> Type -> Maybe (List Ident)
findUnboundTypeVars gamma typ =
  let
    typeVarsInGamma =
      List.foldl (\binding acc ->
        case binding of
          TypeVar a -> a :: acc
          _         -> acc
      ) [] gamma

    freeTypeVarsInType =
      freeVarsType typeVarsInGamma typ
  in
    case Utils.listDiff freeTypeVarsInType typeVarsInGamma of
      [] ->
        Nothing

      unboundTypeVars ->
        Just unboundTypeVars


freeVarsType : List Ident -> Type -> List Ident
freeVarsType typeVarsInGamma typ =
  let
    result =
      helper typeVarsInGamma typ

    helper boundTypeVars typ =
      case typ.val.t__ of
        TVar _ a ->
          if a == "->" then
            []
          else if List.member a boundTypeVars then
            []
          else
            [a]

        TApp _ t0 typs _ ->
          let
            newBoundTypeVars =
              case matchArrow typ of
                Just (typeVars, _, _) ->
                  typeVars ++ boundTypeVars

                Nothing ->
                  boundTypeVars
          in
            List.concat (List.map (helper newBoundTypeVars) (t0::typs))

        TParens _ innerType _ ->
          helper boundTypeVars innerType

        _ ->
          let _ = Debug.log "TODO: implement freeVars for" (unparseType typ) in
          []
  in
    result


--------------------------------------------------------------------------------

typeEquiv t1 t2 =
  -- LangUtils.typeEqual is ws-sensitive.
  -- will need to do alpha-renaming too.
  -- TODO: this is temporary
  String.trim (unparseType t1) == String.trim (unparseType t2)


--------------------------------------------------------------------------------

type alias ArrowType = (List Ident, List Type, Type)


stripAllOuterTParens : Type -> Type
stripAllOuterTParens typ =
  case typ.val.t__ of
    TParens _ innerType _ ->
      stripAllOuterTParens innerType

    _ ->
      typ


-- This currently does not recurse into retType, so the argTypes list
-- always has length one.
--
-- This strips TParens off the outer type and off the arg and ret types.
--
matchArrow : Type -> Maybe ArrowType
matchArrow typ =
  let
    result =
      case (stripAllOuterTParens typ).val.t__ of
        TApp ws1 t0 typs InfixApp ->
          let
            typeVars =
              matchTypeVars ws1
          in
          case (t0.val.t__, typs) of
            (TVar _ "->", [argType, retType]) ->
              Just ( typeVars
                   , [stripAllOuterTParens argType]
                   , stripAllOuterTParens retType
                   )
            _ ->
              Nothing
        _ ->
          Nothing

    _ =
      result
        |> Maybe.map (\(typeVars, argTypes, retType) ->
             (typeVars, List.map unparseType argTypes, unparseType retType)
           )
        |> if False
           then Debug.log "matchArrowType"
           else Basics.identity
  in
    result


matchTypeVars : WS -> List Ident
matchTypeVars ws =
  let
    regex =
      -- Grouping all type var characters and spaces into a single
      -- string, then splitting below. Would be better to split/group
      -- words directly in the regex...
      --
      "^[ ]*{-[ ]*forall [ ]*([a-z ]+)[ ]*-}[ ]*$"
    matches =
      Regex.find Regex.All (Regex.regex regex) ws.val
    result =
      case matches of
        [{submatches}] ->
          case Utils.projJusts submatches of
            Just [string] ->
              string
                |> Utils.squish
                |> String.split " "
            _ ->
              []
        _ ->
          []

    _ =
      result
        |> if False
           then Debug.log "matchTypeVars"
           else Basics.identity
  in
    result


-- This is currently not taking prior whitespace into account.
--
rebuildArrow : ArrowType -> Type
rebuildArrow (typeVars, argTypes, retType) =
  withDummyTypeInfo <|
    TApp (rebuildTypeVars typeVars)
         (withDummyTypeInfo (TVar space1 "->"))
         (argTypes ++ [retType])
         InfixApp


-- This is currently not taking prior whitespace into account.
--
rebuildTypeVars : List Ident -> WS
rebuildTypeVars typeVars =
  case typeVars of
    [] ->
      space0
    _  ->
      withDummyInfo <|
        "{- forall " ++ String.join " " typeVars ++ " -} "


--------------------------------------------------------------------------------

matchLambda : Exp -> Int
matchLambda exp =
  case (unExpr exp).val.e__ of
    EFun _ pats body _ ->
      List.length pats + matchLambda body

    EParens _ innerExp _ _ ->
      matchLambda innerExp

    _ ->
      0


-- Don't feel like figuring out how to insert a LetAnnotation and update
-- BindingNums and PrintOrder correctly. So, just going through Strings.
--
insertStrAnnotation pat strType exp =
  let
    {line, col} =
      pat.start

    strAnnotation =
      indent ++ name ++ " : " ++ String.trim strType

    indent =
      String.repeat (col - 1) " "

    name =
      unparsePattern pat
  in
    exp
      |> unparse
      |> String.lines
      |> Utils.inserti line strAnnotation
      |> String.join "\n"
      |> parse
      |> Result.withDefault (eStr "Bad dummy annotation. Bad editor. Bad")


--------------------------------------------------------------------------------

copyTypeInfoFrom : Exp -> Exp -> Exp
copyTypeInfoFrom fromExp toExp =
  let
    copyTypeFrom : Exp -> Exp -> Exp
    copyTypeFrom fromExp toExp =
      toExp |> setType (unExpr fromExp).val.typ

    copyTypeErrorFrom : Exp -> Exp -> Exp
    copyTypeErrorFrom fromExp toExp =
      case (unExpr fromExp).val.typeError of
        Just typeError ->
          toExp |> setTypeError typeError
        Nothing ->
          toExp
  in
  toExp
    |> copyTypeFrom fromExp
    |> copyTypeErrorFrom fromExp


--------------------------------------------------------------------------------

typecheck : Exp -> Exp
typecheck e =
  let result = inferType [] { inputExp = e } e in
  result.newExp

-- extra stuff for typechecker
type alias Stuff =
  { inputExp : Exp  -- root expression (model.inputExp)
  }

inferType
    : TypeEnv
   -> Stuff
   -> Exp
   -> { newExp: Exp }
        -- the inferred Maybe Type is in newExp.val.typ

inferType gamma stuff thisExp =
  case (unExpr thisExp).val.e__ of
    EConst _ _ _ _ ->
      { newExp = thisExp |> setType (Just (withDummyTypeInfo (TNum space1))) }

    EBase _ (EBool _) ->
      { newExp = thisExp |> setType (Just (withDummyTypeInfo (TBool space1))) }

    EBase _ (EString _ _) ->
      { newExp = thisExp |> setType (Just (withDummyTypeInfo (TString space1))) }

    EVar ws x ->
      case lookupVar gamma x of
        Just mt ->
          { newExp = thisExp |> setType mt }

        Nothing ->
          let
            messages =
              [ deuceShow stuff.inputExp
                  "-- NAMING ERROR -------------------------------------------------------"
              , deuceShow stuff.inputExp <|
                  "Cannot find variable `" ++ x ++ "`"
              ]
            suggestions =
              List.map
                (\y -> (y, EVar ws y |> replaceE__ thisExp))
                (varNotFoundSuggestions x gamma)
            items =
              if List.length suggestions == 0 then
                messages
              else
                messages
                  ++ [ deuceShow stuff.inputExp "Maybe you want one of the following?" ]
                  ++ List.map
                       (\(y, ey) -> deuceTool y (replaceExpNode (unExpr thisExp).val.eid ey stuff.inputExp))
                       suggestions
          in
          { newExp = thisExp |> setTypeError (TypeError items) }

    EParens ws1 innerExp parensStyle ws2 ->
      let
        result =
          inferType gamma stuff innerExp

        newExp =
          EParens ws1 result.newExp parensStyle ws2
            |> replaceE__ thisExp
            |> setType (unExpr result.newExp).val.typ
      in
        { newExp = newExp }

    EColonType ws1 innerExp ws2 annotatedType ws3 ->
      case findUnboundTypeVars gamma annotatedType of
        Nothing ->
          let
            result =
              checkType gamma stuff innerExp annotatedType

            (newInnerExp, finishNewExp) =
              if result.okay then
                (result.newExp, Basics.identity)

              else
                -- the call to checkType calls:
                -- setTypeError (ExpectedButGot annotatedType typ)
                --
                -- here, adding extra breadcrumb about the solicitorExp.
                --
                (result.newExp, setExtraTypeInfo (HighlightWhenSelected (unExpr innerExp).val.eid))

            newExp =
              EColonType ws1 newInnerExp ws2 annotatedType ws3
                |> replaceE__ thisExp
                |> setType (Just annotatedType)
                |> finishNewExp
          in
            { newExp = newExp }

        Just unboundTypeVars ->
          -- TODO: Highlight occurrences of unbound variables with
          -- type polygons.
          --
          let
            newExp =
              thisExp
                |> setTypeError
                     (otherTypeError stuff.inputExp
                        [ "ill-formed type annotation"
                        , "unbound: " ++ String.join " " unboundTypeVars
                        ])
          in
            { newExp = newExp }

{-
    EFun ws1 pats body ws2 ->
      let
        newGamma =
          -- TODO: just putting vars in env for now
          List.map (\pat -> HasType pat Nothing) pats ++ gamma
        result =
          inferType newGamma stuff body
        newExp =
          EFun ws1 pats result.newExp ws2
            |> replaceE__ thisExp
      in
      { newExp = newExp }
-}
    EFun ws1 pats body ws2 ->
      { newExp =
          thisExp
            |> setTypeError
                 (otherTypeError stuff.inputExp ["trying to synthesize unannotated..."])
      }

    EIf ws0 guardExp ws1 thenExp ws2 elseExp ws3 ->
      -- Not currently digging into nested EIfs
      let
        result1 =
          checkType gamma stuff guardExp (withDummyTypeInfo (TBool space1))

        result2 =
          inferType gamma stuff thenExp

        result3 =
          inferType gamma stuff elseExp

        -- (newThenExp, newElseExp, maybeBranchType) : (Exp, Exp, Maybe Type)
        (newThenExp, newElseExp, maybeBranchType) =
          case ( result1.okay
               , (unExpr result2.newExp).val.typ
               , (unExpr result3.newExp).val.typ
               ) of
            (True, Just thenType, Just elseType) ->
              if typeEquiv thenType elseType then
                (result2.newExp, result3.newExp, Just thenType)

              else
                let
                  addErrorAndInfo (eid1, type1) (eid2, type2) branchExp =
                    branchExp
                      |> setTypeError (otherTypeError stuff.inputExp
                           [ "-- TYPE MISMATCH ------------------------------------------------------"
                           , "The branches of this `if` produce different types of values."
                           , "This branch has type"
                           , unparseType type1
                           , "But the other branch has type"
                           , unparseType type2
                           , """Hint: These need to match so that no matter which
                                branch we take, we always get
                                back the same type of value."""
                           ])
                      |> setExtraTypeInfo (HighlightWhenSelected eid2)

                  (thenExpId, elseExpId) =
                     ((unExpr thenExp).val.eid, (unExpr elseExp).val.eid)

                  errorThenExp =
                    result2.newExp
                      |> addErrorAndInfo (thenExpId, thenType) (elseExpId, elseType)

                  errorElseExp =
                    result3.newExp
                      |> addErrorAndInfo (elseExpId, elseType) (thenExpId, thenType)
                in
                  (errorThenExp, errorElseExp, Nothing)

            _ ->
              (result2.newExp, result3.newExp, Nothing)

        finishNewExp =
          case maybeBranchType of
            Just branchType ->
              setType (Just branchType)
            Nothing ->
              Basics.identity

        newExp =
          EIf ws0 result1.newExp ws1 newThenExp ws2 newElseExp ws3
            |> replaceE__ thisExp
            |> finishNewExp
      in
        { newExp = newExp }

    ELet ws1 letKind (Declarations po [] letAnnots letExps) ws2 body ->
      let
        -- Process LetAnnotations ----------------------------------------------

        -- type alias AnnotationTable = List (Ident, Type)

        -- (newLetAnnots, annotTable) : (List LetAnnotation, AnnotationTable)
        (newLetAnnots, annotTable) =
          letAnnots
            |> List.foldl processLetAnnotation ([], [])
            |> Tuple.mapFirst List.reverse
            |> Tuple.mapFirst markUndefinedAnnotations

        _ =
          annotTable
            |> List.map (Tuple.mapSecond unparseType)
            |> if True
               then Debug.log "annotTable"
               else Basics.identity

        processLetAnnotation
            (LetAnnotation ws0 ws1 pat fas ws2 typ) (accLetAnnots, accTable) =
          let
            (newPat, newTable) =
              processPat accTable pat typ
            newLetAnnots =
              LetAnnotation ws0 ws1 newPat fas ws2 typ :: accLetAnnots
          in
            (newLetAnnots, newTable)

        -- Somewhat similar to lookupVarInPat.
        --
        processPat : List (Ident, Type) -> Pat -> Type -> (Pat, List (Ident, Type))
        processPat accTable pat typ =
          case (pat.val.p__, typ.val) of
            (PVar _ x _, _) ->
              let
                errors =
                  errors1 ++ errors2

                errors1 =
                  Utils.maybeFind x accTable
                    |> Maybe.map (\_ ->
                         [ "Can't have multiple annotations for same name."
                         -- Report locations of other annotations, if desired...
                         ]
                       )
                    |> Maybe.withDefault []

                errors2 =
                  findUnboundTypeVars gamma typ
                    |> Maybe.map (\unboundTypeVars ->
                         [ "ill-formed type annotation"
                         , "unbound: " ++ String.join " " unboundTypeVars
                         ]
                       )
                    |> Maybe.withDefault []

              in
                if List.length errors == 0 then
                  ( pat |> setPatType (Just typ)
                  , (x, typ) :: accTable
                  )

                else
                  ( pat |> setPatTypeError (otherTypeError stuff.inputExp errors)
                  , accTable
                  )

            _ ->
              ( pat |> setPatTypeError
                  (otherTypeError stuff.inputExp ["this kind of type annotation is currently unsupported"])
              , accTable
              )

        markUndefinedAnnotations : List LetAnnotation -> List LetAnnotation
        markUndefinedAnnotations =
          let
            varsDefinedInThisELet =
              letExps
                |> List.concatMap Tuple.second
                |> List.concatMap (\(LetExp _ _ pat _ _ _) -> varsOfPat pat)

            maybeMarkPat =
              mapPat
                (\p ->
                   case p.val.p__ of
                     PVar _ x _ ->
                       if List.member x varsDefinedInThisELet then
                         p
                       else
                         p |> setPatTypeError (otherTypeError stuff.inputExp ["this name is not defined"])
                     _ ->
                       p
                )
          in
            List.map (\(LetAnnotation ws0 ws1 pat fas ws2 typ) ->
              LetAnnotation ws0 ws1 (maybeMarkPat pat) fas ws2 typ
            )

        -- Process LetExps -----------------------------------------------------

        (newLetExps, newGamma) =
          letExps
            |> List.foldl processLetExp ([], gamma)
            |> Tuple.mapFirst List.reverse

        processLetExp (isRec, listLetExp) (accLetExpsRev, accGamma) =
          let
            listLetExpAndMaybeType : List (LetExp, Maybe Type)
            listLetExpAndMaybeType =
              listLetExp
                |> List.map (\letExp ->
                     let (LetExp ws0 ws1 pat fas ws2 expEquation) = letExp in
                     case pat.val.p__ of
                       PVar _ x _ ->
                         (letExp, Utils.maybeFind x annotTable)

                       -- To support other kinds of pats, will have to
                       -- walk expEquation as much as possible to push down
                       -- annotations. And any remaining annotations will
                       -- have to be treated as EColonTypes.
                       _ ->
                         let
                           newPat =
                             pat |> setPatTypeError
                               (otherTypeError stuff.inputExp ["pattern not yet supported by type checker"])
                         in
                           (LetExp ws0 ws1 newPat fas ws2 expEquation, Nothing)
                   )

            gammaForEquations =
              if isRec == False then
                accGamma

              else
                let
                  assumedRecPatTypes : List (Pat, Maybe Type)
                  assumedRecPatTypes =
                    listLetExpAndMaybeType
                      |> List.map (\((LetExp _ _ pat _ _ _), maybeAnnotatedType) ->
                           (pat, maybeAnnotatedType)
                         )
                in
                  List.foldl addHasMaybeType accGamma assumedRecPatTypes

            newListLetExp =
              listLetExpAndMaybeType
                |> List.map (\( (LetExp ws0 ws1 pat fas ws2 expEquation)
                              , maybeAnnotatedType
                              ) ->
                     case maybeAnnotatedType of
                       Nothing ->
                         let
                           result =
                             inferType gammaForEquations stuff expEquation

                           newPat =
                             case (unExpr result.newExp).val.typ of
                               Just inferredType ->
                                 pat |> setPatType (Just inferredType)
                                        -- TODO: Not an error, rename TypeError...
                                     |> setPatTypeError (TypeError
                                          [ deuceTool "Add inferred annotation"
                                              (insertStrAnnotation pat (unparseType inferredType) stuff.inputExp)
                                          ]
                                        )

                               Nothing ->
                                 case matchLambda expEquation of
                                   0 ->
                                     pat |> setPatTypeError (otherTypeError stuff.inputExp ["type error"])

                                   numArgs ->
                                     let
                                       wildcards =
                                         String.join " -> " (List.repeat (numArgs + 1) "_")
                                     in
                                     pat |> setPatTypeError (TypeError
                                       [ deuceShow stuff.inputExp
                                           "Currently, functions need annotations"
                                       , deuceTool "Add dummy type annotation"
                                           (insertStrAnnotation pat wildcards stuff.inputExp)
                                       ]
                                     )
                         in
                         LetExp ws0 ws1 newPat fas ws2 result.newExp

                       Just annotatedType ->
                         let
                           result =
                             checkType gammaForEquations stuff expEquation annotatedType

                           newPat =
                             if result.okay then
                               pat |> setPatType (Just annotatedType)
                             else
                               pat |> setPatTypeError (otherTypeError stuff.inputExp ["type error"])
                           -- TODO: add tool option to change annotation if result.okay == False
                           newExpEquation =
                             result.newExp
                         in
                         LetExp ws0 ws1 newPat fas ws2 newExpEquation
                   )

            newGamma =
              let
                maybePatTypes : Maybe (List (Pat, Type))
                maybePatTypes =
                  newListLetExp
                    |> List.map (\(LetExp _ _ newPat _ _ _) ->
                         newPat.val.typ |> Maybe.map ((,) newPat)
                       )
                    |> Utils.projJusts
              in
                -- Add bindings only if every LetExp type checked.
                case maybePatTypes of
                  Nothing ->
                    accGamma

                  Just patTypes ->
                    List.foldl addHasType accGamma patTypes
          in
            ((isRec, newListLetExp) :: accLetExpsRev, accGamma)

        -- Process Let-Body ----------------------------------------------------

        resultBody =
          inferType newGamma stuff body

        newBody =
          resultBody.newExp

        -- Rebuild -------------------------------------------------------------

        newExp =
          ELet ws1 letKind (Declarations po [] newLetAnnots newLetExps) ws2 newBody
            |> replaceE__ thisExp
            |> copyTypeInfoFrom newBody
      in
        { newExp = newExp }

    ELet ws1 letKind (Declarations po letTypes letAnnots letExps) ws2 body ->
      { newExp =
          thisExp
            |> setTypeError
                 (otherTypeError stuff.inputExp ["not yet supporting type definitions..."])
      }

    ERecord ws1 maybeExpWs (Declarations po letTypes letAnnots letExps) ws2 ->
      let
        eRecordError s =
          { newExp =
              thisExp
                |> setTypeError (otherTypeError stuff.inputExp ["not supported in records: " ++ s])
          }
      in
      case (maybeExpWs, letTypes, letAnnots, letExps) of
        (Just _, _, _, _) ->
          eRecordError "base expression"

        (Nothing, _::_, _, _) ->
          eRecordError "type definitions"

        (Nothing, _, _::_, _) ->
          eRecordError "type annotations"

        (Nothing, [], [], letExps) ->
          let
            maybeListLetExp =
              List.map (\(isRec, listLetExps) ->
                         case (isRec, listLetExps) of
                           (False, [letExp]) -> Just letExp
                           _                 -> Nothing
                       ) letExps
            rebuildLetExps =
              List.map (\newLetExp -> (False, [newLetExp]))
          in
          case Utils.projJusts maybeListLetExp of
            Nothing ->
              eRecordError "wasn't expecting these letExps..."

            Just listLetExp ->
              let
                (listLetExpMinusCtor, finishLetExpsAndFieldTypes) =
                  let
                    default =
                      ( listLetExp
                      , \(newListLetExp, maybeFieldTypes) -> (newListLetExp, maybeFieldTypes)
                      )
                  in
                  case listLetExp of
                    [] ->
                      default

                    firstLetExp :: restListLetExp ->
                      let (LetExp mbWs1 ws2 p funArgStyle ws3 e) = firstLetExp in
                      case (p.val.p__, (unExpr e).val.e__) of
                        (PVar _ pname _, EBase _ (EString _ ename)) ->
                          if String.startsWith "Tuple" ename then
                            ( restListLetExp
                            , \(newRestListLetExp, fieldMaybeTypes) ->
                                ( firstLetExp
                                    :: newRestListLetExp
                                , Just (Lang.ctor (withDummyTypeInfo << TVar space0) TupleCtor ename)
                                    :: fieldMaybeTypes
                                )
                            )

                          else
                            default

                        _ ->
                          default

                (newListLetExp, maybeFieldTypes) =

                  List.foldl
                    (\(LetExp mbWs1 ws2 p funArgStyle ws3 e) (acc1,acc2) ->
                      let
                        result =
                          inferType gamma stuff e
                        newLetExp =
                          LetExp mbWs1 ws2 p funArgStyle ws3 result.newExp
                        maybeFieldType =
                          case p.val.p__ of
                            PVar _ fieldName _ ->
                              (unExpr result.newExp).val.typ
                                |> Maybe.map (\t -> (Nothing, space1, fieldName, space1, t))
                            _ ->
                              Nothing -- TODO: report error around non-var field
                      in
                        ( newLetExp :: acc1 , maybeFieldType :: acc2 )
                    )
                    ([], [])
                    listLetExpMinusCtor

                  |> Utils.mapFirstSecond List.reverse List.reverse

                  |> finishLetExpsAndFieldTypes

                newLetExps =
                  rebuildLetExps newListLetExp

                newExp =
                  case Utils.projJusts maybeFieldTypes of
                    Just fieldTypes ->
                      ERecord ws1 maybeExpWs (Declarations po letTypes letAnnots newLetExps) ws2
                        |> replaceE__ thisExp
                        |> setType (Just (withDummyTypeInfo (TRecord space0 Nothing fieldTypes space1)))

                    Nothing ->
                      let
                        fieldError =
                          (Nothing, space1, "XXX", space1, withDummyTypeInfo (TVar space1 "XXX"))
                        fieldTypesWithXXXs =
                          List.map (Maybe.withDefault fieldError) maybeFieldTypes
                        recordTypeWithXXXs =
                          withDummyTypeInfo (TRecord space0 Nothing fieldTypesWithXXXs space1)
                        error =
                          otherTypeError stuff.inputExp
                            [ "Some fields are okay, but others are not: "
                            , unparseType recordTypeWithXXXs
                            ]
                      in
                        ERecord ws1 maybeExpWs (Declarations po letTypes letAnnots newLetExps) ws2
                          |> replaceE__ thisExp
                          |> setTypeError error
              in
                { newExp = newExp }

    _ ->
      { newExp = thisExp |> setType Nothing }


inferTypes
    : TypeEnv
   -> Stuff
   -> List Exp
   -> { newExps: List Exp }
inferTypes gamma stuff exps =
  let (newExps, _) =
    List.foldl (\exp (newExpsAcc,stuffAcc) ->
                 let result = inferType gamma stuffAcc exp in
                 (result.newExp :: newExpsAcc, stuffAcc)
               )
               ([], stuff)
               exps
  in
  { newExps = List.reverse newExps }


checkType
    : TypeEnv
   -> Stuff
   -> Exp
   -> Type
   -> { okay: Bool, newExp: Exp }
checkType gamma stuff thisExp expectedType =
  case ( (unExpr thisExp).val.e__
       , expectedType.val.t__
       , matchArrow expectedType
       ) of

    (_, TParens _ innerExpectedType _, _) ->
      let
        result =
          checkType gamma stuff thisExp innerExpectedType
        newExp =
          thisExp
            |> copyTypeInfoFrom result.newExp
      in
      { okay = result.okay, newExp = newExp }

    (EParens ws1 innerExp parensStyle ws2, _, _) ->
      let
        result =
          checkType gamma stuff innerExp expectedType
        newExp =
          EParens ws1 result.newExp parensStyle ws2
            |> replaceE__ thisExp
            |> copyTypeInfoFrom result.newExp
      in
      { okay = result.okay, newExp = newExp }

    -- Not recursing into function body or retType because of the
    -- EParens and TParens cases, above.
    --
    (EFun ws1 pats body ws2, _, Just (typeVars, argTypes, retType)) ->
      if List.length pats < List.length argTypes then
        { okay = False
        , newExp =
            thisExp
              |> setTypeError
                   (otherTypeError stuff.inputExp <|
                      "TODO List.length pats < List.length argTypes"
                        :: List.map unparsePattern pats
                        ++ List.map unparseType argTypes)
        }

      else if List.length pats > List.length argTypes then
        let
          -- Break up thisExp EFun into two nested EFuns, and check that.
          --
          result =
            checkType gamma stuff rewrittenThisExp expectedType

          (prefixPats, suffixPats) =
            Utils.split (List.length argTypes) pats

          rewrittenBody =
            -- TODO: Probably need to do something better with ids/breadcrumbs...
            Expr (withDummyInfo (exp_ (EFun space0 suffixPats body space0)))

          rewrittenThisExp =
            -- TODO: Probably need to do something better with ids/breadcrumbs...
            Expr (withDummyInfo (exp_ (EFun space0 prefixPats rewrittenBody space0)))

          (newPrefixPats, newSuffixPats, newBody) =
            case (unExpr result.newExp).val.e__ of
              EFun _ newPrefixPats innerFunc _ ->
                case (unExpr innerFunc).val.e__ of
                  EFun _ newSuffixPats newCheckedBody _ ->
                    (newPrefixPats, newSuffixPats, newCheckedBody)
                  _ ->
                    Debug.crash "the structure of the rewritten EFun has changed..."
              _ ->
                Debug.crash "the structure of the rewritten EFun has changed..."

          newExp =
            -- Keeping the structure of the original EFun in tact, not
            -- the rewrittenThisExp version. May need to track some
            -- breadcrumbs for stuffing type info into selection polygons...
            --
            EFun ws1 (newPrefixPats ++ newSuffixPats) newBody ws2
              |> replaceE__ thisExp
              |> copyTypeInfoFrom result.newExp
        in
        { okay = result.okay, newExp = newExp }

      else {- List.length pats == List.length argTypes -}
        let
          patTypes =
            Utils.zip pats argTypes
          newGamma_ =
            List.foldl addTypeVar gamma typeVars
          newGamma =
            List.foldl addHasType newGamma_ patTypes
          newPats =
            List.map (\(p,t) -> p |> setPatType (Just t)) patTypes
          result =
            checkType newGamma stuff body retType
        in
          if result.okay then
            { okay = True
            , newExp =
                EFun ws1 newPats result.newExp ws2
                  |> replaceE__ thisExp
                  |> setType (Just expectedType)
            }

          else
            let
              maybeActualType =
                (unExpr result.newExp).val.typ
                  |> Maybe.map (\actualRetType ->
                       rebuildArrow (typeVars, argTypes, actualRetType)
                     )
            in
            { okay = False
            , newExp =
                EFun ws1 newPats result.newExp ws2
                  |> replaceE__ thisExp
                  |> setTypeError (expectedButGot stuff.inputExp expectedType maybeActualType)
            }

    (EIf ws0 guardExp ws1 thenExp ws2 elseExp ws3, _, _) ->
      let
        result1 =
          checkType gamma stuff guardExp (withDummyTypeInfo (TBool space1))

        result2 =
          checkType gamma stuff thenExp expectedType

        result3 =
          checkType gamma stuff elseExp expectedType

        okay =
          result1.okay && result2.okay && result3.okay

        finishNewExp =
          if okay then
            setType (Just expectedType)
          else
            Basics.identity

        newExp =
          EIf ws0 result1.newExp ws1 result2.newExp ws2 result3.newExp ws3
            |> replaceE__ thisExp
            |> finishNewExp
      in
        { okay = okay, newExp = newExp }

    _ ->
      let
        result =
          inferType gamma stuff thisExp
        _ =
          (unparse thisExp, unparseType expectedType, expectedType)
            |> if False
               then Debug.log "catch-all synthesis rule"
               else Basics.identity
      in
        case (unExpr result.newExp).val.typ of
          Nothing ->
            { okay = False
            , newExp =
                result.newExp
                -- Don't want to overwrite existing error...
                --
                -- |> setTypeError (ExpectedButGot expectedType
                --                                 (unExpr result.newExp).val.typ)
            }

          Just inferredType ->
            if typeEquiv inferredType expectedType then
              { okay = True
              , newExp = result.newExp
              }

            else
              { okay = False
              , newExp =
                  result.newExp
                    |> setTypeError (expectedButGot stuff.inputExp expectedType (Just inferredType))
              }


--------------------------------------------------------------------------------

-- Currently shoving entire type error message and suggested fixes into Deuce.
-- So every line is a DeuceTypeInfoItem === SynthesisResult.

deuceShow : Exp -> String -> TransformationResult
deuceShow inputExp s =
  -- TODO: everything is a SynthesisResult, so pass in inputExp as dummy...
  basicTransformationResult s inputExp


deuceTool : String -> Exp -> TransformationResult
deuceTool =
  basicTransformationResult


-- TODO: remove inputExp when TypeError interface is worked out
otherTypeError : Exp -> List String -> TypeError
otherTypeError inputExp strings =
  TypeError
    (List.map (deuceShow inputExp) strings)


-- TODO: remove inputExp when TypeError interface is worked out
expectedButGot inputExp expectedType maybeActualType =
  TypeError
    [ deuceShow inputExp
        "-- TYPE MISMATCH ------------------------------------------------------"
    , deuceShow inputExp <|
        "The expected type is"
    , deuceShow inputExp <|
        unparseType expectedType
    , deuceShow inputExp <|
        "But this is a"
    , deuceShow inputExp <|
        Maybe.withDefault "Nothing" (Maybe.map unparseType maybeActualType)
    , deuceTool
        ("TODO-Ravi Maybe an option to change expected type if it's annotation...")
        inputExp
    ]


makeDeuceExpTool : Exp -> Exp -> (() -> List TransformationResult)
makeDeuceExpTool = makeDeuceToolForThing Expr unExpr


makeDeucePatTool : Exp -> Pat -> (() -> List TransformationResult)
makeDeucePatTool = makeDeuceToolForThing Basics.identity Basics.identity


makeDeuceToolForThing
   : (WithInfo (WithTypeInfo b) -> a)
  -> (a -> WithInfo (WithTypeInfo b))
  -> Exp
  -> a -- thing is a Thing (Exp or Pat or Type)
  -> (() -> List TransformationResult)
makeDeuceToolForThing wrap unwrap inputExp thing = \() ->
  let
    -- exp =
    --   LangTools.justFindExpByEId inputExp eId

    -- posInfo =
    --   [ show <| "Start: " ++ toString exp.start ++ " End: " ++ toString exp.end
    --   ]

    deuceTypeInfo =
      case ((unwrap thing).val.typ, (unwrap thing).val.typeError) of
        (Nothing, Nothing) ->
          [ deuceShow inputExp <|
              "This expression wasn't processed by the typechecker..."
          , deuceShow inputExp <|
              "Or there's a type error inside..."
          ]

        (Just t, Nothing) ->
          [ deuceShow inputExp <| "Type: " ++ unparseType t ]

        (_, Just (TypeError items)) ->
          items

{-
    insertAnnotationTool =
      case (unExpr exp).val.typ of
        Just typ ->
          let e__ =
            EParens space1
                    (withDummyExpInfo (EColonType space0 exp space1 typ space0))
                    Parens
                    space0
          in
          [ deuceTool "Insert Annotation" (replaceExpNodeE__ByEId eId e__ inputExp) ]

        Nothing ->
          []
-}
  in
    List.concat <|
      [ deuceTypeInfo
      -- , insertAnnotationTool
      ]

typeChecks : Exp -> Bool
typeChecks =
  foldExp
    ( \e acc ->
        acc && (unExpr e).val.typeError == Nothing
    )
    True