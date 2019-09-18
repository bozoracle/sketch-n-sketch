module TinyStructuredEditorsForLowLowPrices exposing (prepare, newLangValResult, showNewValueOptions, selectPath, deselectPath, deselectAll, startTextEditing, updateTextBox, newLangValResultForTextEdit, cancelTextEditing)

import Dict
import Set

import Lang
import Sync
import Utils

import TinyStructuredEditorsForLowLowPricesTypes exposing (..)
import TinyStructuredEditorsForLowLowPricesDesugaring
import TinyStructuredEditorsForLowLowPricesResugaring
import TinyStructuredEditorsForLowLowPricesEval
import TinyStructuredEditorsForLowLowPricesActions
import TinyStructuredEditorsForLowLowPricesScrub


----------- Controller -----------

-- Do all the computation after a program run.
--
-- I hate caching but if we instead perform the work on
-- demand in the view then the GUI slows to a crawl.
prepare : TinyStructuredEditorsForLowLowPricesTypes.ModelState -> Sync.Options -> Lang.Env -> Lang.Exp -> Maybe Lang.Type -> Lang.Val -> TinyStructuredEditorsForLowLowPricesTypes.ModelState
prepare oldModelState syncOptions env program maybeValueOfInterestTypeFromLeo valueOfInterest =
  let
    renderingFunctionNames =
      expToRenderingFunctionNames program

    dataTypeDefs =
      TinyStructuredEditorsForLowLowPricesDesugaring.dataTypeDefsWithoutTBoolsTLists program

    maybeRenderingFunctionNameAndProgram =
      -- Use the previously selected function, if it's still available.
      oldModelState.maybeRenderingFunctionNameAndProgram
      |> Maybe.map (\{ renderingFunctionName } -> renderingFunctionName)
      |> Utils.filterMaybe (flip List.member renderingFunctionNames)
      |> Utils.plusMaybe (List.head renderingFunctionNames)
      |> Maybe.map
          (\renderingFunctionName ->
            let (multipleDispatchFunctions, desugaredToStringProgram) =
              TinyStructuredEditorsForLowLowPricesDesugaring.makeDesugaredToStringProgram program renderingFunctionName
            in
            { renderingFunctionName     = renderingFunctionName
            , multipleDispatchFunctions = multipleDispatchFunctions
            , desugaredToStringProgram  = desugaredToStringProgram
            }
          )

    valueOfInterestTagged =
      valueOfInterest
      |> TinyStructuredEditorsForLowLowPricesDesugaring.desugarVal
      |> TinyStructuredEditorsForLowLowPricesEval.tagVal []

    stringTaggedWithProjectionPathsResult =
      case maybeRenderingFunctionNameAndProgram of
        Just { renderingFunctionName, multipleDispatchFunctions, desugaredToStringProgram } ->
          TinyStructuredEditorsForLowLowPricesEval.evalToStringTaggedWithProjectionPaths
              dataTypeDefs
              multipleDispatchFunctions
              desugaredToStringProgram
              valueOfInterestTagged

        Nothing ->
          Err "No rendering function chosen."

    maybeValueOfInterestType =
      maybeValueOfInterestTypeFromLeo
      |> Maybe.map TinyStructuredEditorsForLowLowPricesDesugaring.replaceTBoolTListWithTVarTApp

    stringProjectionPathToSpecificActions =
      stringTaggedWithProjectionPathsResult
      |> Result.toMaybe
      |> Maybe.map (TinyStructuredEditorsForLowLowPricesActions.generateActionsForValueAndAssociateWithStringLocations dataTypeDefs maybeValueOfInterestType valueOfInterestTagged)
      |> Maybe.withDefault Dict.empty

  in
  { oldModelState
  | renderingFunctionNames                = renderingFunctionNames
  , dataTypeDefs                          = dataTypeDefs
  , maybeRenderingFunctionNameAndProgram  = maybeRenderingFunctionNameAndProgram
  , valueOfInterestTagged                 = valueOfInterestTagged
  , stringTaggedWithProjectionPathsResult = stringTaggedWithProjectionPathsResult
  , stringProjectionPathToSpecificActions = stringProjectionPathToSpecificActions
  , maybeNewValueOptions                  = Nothing
  , liveSyncInfo                          = TinyStructuredEditorsForLowLowPricesScrub.prepareLiveUpdates syncOptions program valueOfInterest
  }


showNewValueOptions : TinyStructuredEditorsForLowLowPricesTypes.ModelState -> List TaggedValue -> TinyStructuredEditorsForLowLowPricesTypes.ModelState
showNewValueOptions oldModelState newValueOptions =
  { oldModelState | maybeNewValueOptions = Just newValueOptions }


newLangValResult : TaggedValue -> Result String Lang.Val
newLangValResult = TinyStructuredEditorsForLowLowPricesResugaring.taggedValToLangValResult


selectPath : TinyStructuredEditorsForLowLowPricesTypes.ModelState -> ProjectionPath -> TinyStructuredEditorsForLowLowPricesTypes.ModelState
selectPath oldModelState projectionPath =
  { oldModelState | selectedPaths = Set.insert projectionPath oldModelState.selectedPaths }


deselectPath : TinyStructuredEditorsForLowLowPricesTypes.ModelState -> ProjectionPath -> TinyStructuredEditorsForLowLowPricesTypes.ModelState
deselectPath oldModelState projectionPath =
  { oldModelState | selectedPaths = Set.remove projectionPath oldModelState.selectedPaths }


deselectAll : TinyStructuredEditorsForLowLowPricesTypes.ModelState -> TinyStructuredEditorsForLowLowPricesTypes.ModelState
deselectAll oldModelState =
  { oldModelState | selectedPaths = Set.empty, maybeNewValueOptions = Nothing }


startTextEditing : TinyStructuredEditorsForLowLowPricesTypes.ModelState -> (ProjectionPath, String) -> TinyStructuredEditorsForLowLowPricesTypes.ModelState
startTextEditing oldModelState (projectionPath, text) =
  -- Only set if not already text editing
  { oldModelState | maybeTextEditingPathAndText = oldModelState.maybeTextEditingPathAndText |> Maybe.withDefault (projectionPath, text) |> Just }


updateTextBox : TinyStructuredEditorsForLowLowPricesTypes.ModelState -> String -> TinyStructuredEditorsForLowLowPricesTypes.ModelState
updateTextBox oldModelState newText =
  { oldModelState | maybeTextEditingPathAndText = oldModelState.maybeTextEditingPathAndText |> Maybe.map (\(path, _) -> (path, newText)) }


newLangValResultForTextEdit : TinyStructuredEditorsForLowLowPricesTypes.ModelState -> Result String Lang.Val
newLangValResultForTextEdit modelState =
  case modelState.maybeTextEditingPathAndText of
    Just (path, newText) ->
      modelState.valueOfInterestTagged
      |> TinyStructuredEditorsForLowLowPricesActions.replaceAtPath path (noTag <| VString newText)
      |> TinyStructuredEditorsForLowLowPricesResugaring.taggedValToLangValResult

    Nothing ->
      Err "Not text editing right now!"


cancelTextEditing : TinyStructuredEditorsForLowLowPricesTypes.ModelState -> TinyStructuredEditorsForLowLowPricesTypes.ModelState
cancelTextEditing oldModelState =
  { oldModelState | maybeTextEditingPathAndText = Nothing }


expToRenderingFunctionNames : Lang.Exp -> List Ident
expToRenderingFunctionNames exp =
  ["toString"]
