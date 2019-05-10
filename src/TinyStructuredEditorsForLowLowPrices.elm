module TinyStructuredEditorsForLowLowPrices exposing (prepare, newLangValResult, selectPath, deselectPath, deselectAll)

import Dict
import Set

import Lang
import Utils

import TinyStructuredEditorsForLowLowPricesTypes exposing (..)
import TinyStructuredEditorsForLowLowPricesDesugaring
import TinyStructuredEditorsForLowLowPricesResugaring
import TinyStructuredEditorsForLowLowPricesEval
import TinyStructuredEditorsForLowLowPricesActions


----------- Controller -----------

-- Do all the computation after a program run.
--
-- I hate caching but if we instead perform the work on
-- demand in the view then the GUI slows to a crawl.
prepare : TinyStructuredEditorsForLowLowPricesTypes.ModelState -> Lang.Env -> Lang.Exp -> Maybe Lang.Type -> Lang.Val -> TinyStructuredEditorsForLowLowPricesTypes.ModelState
prepare oldModelState env program maybeValueOfInterestType valueOfInterest =
  let
    renderingFunctionNames =
      expToRenderingFunctionNames program

    maybeRenderingFunctionNameAndProgram =
      -- Use the previously selected function, if it's still available.
      oldModelState.maybeRenderingFunctionNameAndProgram
      |> Maybe.map (\{ renderingFunctionName } -> renderingFunctionName)
      |> Utils.filterMaybe (flip List.member renderingFunctionNames)
      |> Utils.plusMaybe (List.head renderingFunctionNames)
      |> Maybe.map
          (\renderingFunctionName ->
            { renderingFunctionName    = renderingFunctionName
            , desugaredToStringProgram = TinyStructuredEditorsForLowLowPricesDesugaring.makeDesugaredToStringProgram program renderingFunctionName
            }
          )

    valueOfInterestTagged =
      valueOfInterest
      |> TinyStructuredEditorsForLowLowPricesDesugaring.desugarVal
      |> TinyStructuredEditorsForLowLowPricesEval.tagVal []

    stringTaggedWithProjectionPathsResult =
      case maybeRenderingFunctionNameAndProgram of
        Just { renderingFunctionName, desugaredToStringProgram } ->
          TinyStructuredEditorsForLowLowPricesEval.evalToStringTaggedWithProjectionPaths
              desugaredToStringProgram
              valueOfInterestTagged

        Nothing ->
          Err "No rendering function chosen."

    stringProjectionPathToSpecificActions =
      stringTaggedWithProjectionPathsResult
      |> Result.toMaybe
      |> Maybe.map (TinyStructuredEditorsForLowLowPricesActions.generateActionsForValueAndAssociateWithStringLocations program maybeValueOfInterestType valueOfInterestTagged)
      |> Maybe.withDefault Dict.empty

  in
  { oldModelState
  | renderingFunctionNames                = renderingFunctionNames
  , maybeRenderingFunctionNameAndProgram  = maybeRenderingFunctionNameAndProgram
  , valueOfInterestTagged                 = valueOfInterestTagged
  , stringTaggedWithProjectionPathsResult = stringTaggedWithProjectionPathsResult
  , stringProjectionPathToSpecificActions = stringProjectionPathToSpecificActions
  }


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
  { oldModelState | selectedPaths = Set.empty }


expToRenderingFunctionNames : Lang.Exp -> List Ident
expToRenderingFunctionNames exp =
  ["intervalToString"]
