module LangSvg where
-- module LangSvg (valToHtml, valToIndexedTree, printIndexedTree) where

import Html
import Html.Attributes as HA
import Svg
import Svg.Attributes as A
import VirtualDom

-- in Svg.elm:
--   type alias Svg = VirtualDom.Node
--   type alias Attribute = VirtualDom.Property

-- in Html.elm:
--   type alias Html = VirtualDom.Node

import Debug
import Set
import String
import Char
import Dict exposing (Dict)
import Regex

import ColorNum

import Lang exposing (..)
import Utils
import Eval

------------------------------------------------------------------------------

attr = VirtualDom.attribute

-- TODO probably want to factor HTML attributes and SVG attributes into
-- records rather than lists of lists of ...

valToHtml : Int -> Int -> Val -> Html.Html
valToHtml w h v = case v.v_ of
  VList vs ->
    case List.map .v_ vs of
      [VBase (VString "svg"), VList vs1, VList vs2] ->
        let wh = [numAttrToVal "width" w, numAttrToVal "height" h] in
        let v' = vList [vStr "svg", vList (wh ++ vs1), vList vs2] in
        compileValToNode v'
          -- NOTE: not checking if width/height already in vs1
      _ ->
        Debug.crash "valToHtml"
  _ ->
    Debug.crash "valToHtml"

compileValToNode : Val -> VirtualDom.Node
compileValToNode v = case v.v_ of
  VList vs ->
    case List.map .v_ vs of
      [VBase (VString "TEXT"), VBase (VString s)] -> VirtualDom.text s
      [VBase (VString f), VList vs1, VList vs2] ->
        (Svg.node f) (compileAttrVals vs1) (compileNodeVals vs2)
      _ ->
        Debug.crash "compileValToNode"
  _ ->
    Debug.crash "compileValToNode"

compileNodeVals : List Val -> List Svg.Svg
compileNodeVals = List.map compileValToNode

compileAttrVals : List Val -> List Svg.Attribute
compileAttrVals = List.map (uncurry compileAttr << valToAttr)

compileAttrs    : List Attr -> List Svg.Attribute
compileAttrs    = List.map (uncurry compileAttr)

compileAttr : String -> AVal -> Svg.Attribute
compileAttr k v = (attr k) (strAVal v)

numAttrToVal a i =
  vList [vBase (VString a), vConst (toFloat i, dummyTrace)]

type alias AVal = { av_ : AVal_, vtrace : VTrace }

type AVal_
  = ANum NumTr
  | AString String
  | APoints (List Point)
  | ARgba Rgba
  | AColorNum (NumTr, Maybe NumTr) -- Utils.numToColor [0,500), and opacity
  | APath2 (List PathCmd, PathCounts)
  | ATransform (List TransformCmd)
  | ABounds (NumTr, NumTr, NumTr, NumTr)

-- these versions are for when the VTrace doesn't matter
aVal          = flip AVal [-1]
aNum          = aVal << ANum
aString       = aVal << AString
aTransform    = aVal << ATransform
aColorNum     = aVal << AColorNum
aPoints       = aVal << APoints
aPath2        = aVal << APath2

maxColorNum   = 500
clampColorNum = Utils.clamp 0 (maxColorNum - 1)

maxStrokeWidthNum = 20
clampStrokeWidthNum = toFloat << round << Utils.clamp 0 maxStrokeWidthNum

type alias Point = (NumTr, NumTr)
type alias Rgba  = (NumTr, NumTr, NumTr, NumTr)

type PathCmd
  = CmdZ   Cmd
  | CmdMLT Cmd IdPoint
  | CmdHV  Cmd NumTr
  | CmdC   Cmd IdPoint IdPoint IdPoint
  | CmdSQ  Cmd IdPoint IdPoint
  | CmdA   Cmd NumTr NumTr NumTr NumTr NumTr IdPoint

type TransformCmd
  = Rot NumTr NumTr NumTr
  | Scale NumTr NumTr
  | Trans NumTr NumTr

type alias PathCounts = {numPoints : Int}

type alias Cmd = String -- single uppercase/lowercase letter

type alias IdPoint = (Maybe Int, Point)

-- toNum    (ANum (i,_)) = i
-- toNumTr  (ANum (i,t)) = (i,t)

strValOfAVal = strVal << valOfAVal

expectedButGot x s = crashWithMsg <| "expected " ++ x ++", but got: " ++ s

-- temporary way to ignore numbers specified as strings (also see Sync)

toNum : AVal -> Num
toNum a = case a.av_ of
  ANum (n,_) -> n
  AString s  ->
    case String.toFloat s of
      Ok n -> n
      _    -> "a number" `expectedButGot` strValOfAVal a
  _        -> "a number" `expectedButGot` strValOfAVal a

toNumTr a = case a.av_ of
  ANum (n,t) -> (n,t)
  -- TODO add back in?
  -- AColorNum (n,t) -> (n,t)
  AString s  ->
    case String.toFloat s of
      Ok n -> (n, dummyTrace)
      _    -> "a number" `expectedButGot` strValOfAVal a
  _        -> "a number" `expectedButGot` strValOfAVal a

toPoints a = case a.av_ of
  APoints pts -> pts
  _           -> "a list of points" `expectedButGot` strValOfAVal a

toPath : AVal -> (List PathCmd, PathCounts)
toPath a = case a.av_ of
  APath2 p -> p
  _        -> "path commands" `expectedButGot` strValOfAVal a

toTransformRot a = case a.av_ of
  ATransform [Rot n1 n2 n3] -> (n1,n2,n3)
  _                         -> "a rotation transform" `expectedButGot` strValOfAVal a

-- TODO will need to change AVal also
--   and not insert dummy VTraces (using the v* functions)

valToAttr v = case v.v_ of
  VList [v1,v2] -> case (v1.v_, v2.v_) of
    (VBase (VString k), v2_) ->
     -- NOTE: Elm bug? undefined error when shadowing k (instead of choosing k')
     let (k',av_) =
      case (k, v2_) of
        ("points", VList vs)    -> (k, APoints <| List.map valToPoint vs)

        ("fill"  , VList [v1,v2,v3,v4]) -> (k, ARgba <| valToRgba [v1,v2,v3,v4])
        ("stroke", VList [v1,v2,v3,v4]) -> (k, ARgba <| valToRgba [v1,v2,v3,v4])

        ("fill",   VConst it) -> (k, AColorNum (it, Nothing))
        ("stroke", VConst it) -> (k, AColorNum (it, Nothing))

        ("fill",   VList [v1,v2]) ->
          case (v1.v_, v2.v_) of
            (VConst it1, VConst it2) -> (k, AColorNum (it1, Just it2))
            _                        -> Debug.crash "valToAttr: fill"
        ("stroke", VList [v1,v2]) ->
          case (v1.v_, v2.v_) of
            (VConst it1, VConst it2) -> (k, AColorNum (it1, Just it2))
            _                        -> Debug.crash "valToAttr: stroke"

        ("d", VList vs)         -> (k, APath2 (valsToPath2 vs))

        ("transform", VList vs) -> (k, ATransform (valsToTransform vs))

        ("BOUNDS", VList vs)    -> (k, ABounds <| valToBounds vs)

        (_, VConst it)          -> (k, ANum it)
        (_, VBase (VString s))  -> (k, AString s)

        _                       -> Debug.crash "valToAttr"
     in
     (k', AVal av_ v2.vtrace)
    _ ->
      Debug.crash "valToAttr"
  _ ->
    Debug.crash "valToAttr"


valToPoint v = case v.v_ of
  VList vs -> case List.map .v_ vs of
    [VConst x, VConst y] -> (x,y)
    _                    -> "a point" `expectedButGot` strVal v
  _                      -> "a point" `expectedButGot` strVal v

pointToVal (x,y) = (vList [vConst x, vConst y])

valToRgba vs = case List.map .v_ vs of
  [VConst r, VConst g, VConst b, VConst a] -> (r,g,b,a)
  _                                        -> "rgba" `expectedButGot` strVal (vList vs)

rgbaToVal (r,g,b,a) = [vConst r, vConst g, vConst b, vConst a]

strPoint (x_,y_) =
  let (x,y) = Utils.unwrap2 <| List.map fst [x_,y_] in
  toString x ++ "," ++ toString y

strRgba (r_,g_,b_,a_) =
  strRgba_ (List.map fst [r_,g_,b_,a_])

strRgba_ rgba =
  "rgba" ++ Utils.parens (Utils.commas (List.map toString rgba))

strAVal : AVal -> String
strAVal a = case a.av_ of
  AString s -> s
  ANum it   -> toString (fst it)
  -- ANum it   -> toString (fst it) ++ Utils.parens (strTrace (snd it))
  APoints l -> Utils.spaces (List.map strPoint l)
  ARgba tup -> strRgba tup
  APath2 p  -> strAPath2 (fst p)
  ATransform l -> Utils.spaces (List.map strTransformCmd l)
  AColorNum (n, Nothing) ->
    -- slight optimization:
    strRgba_ (ColorNum.convert (fst n))
    -- let (r,g,b) = Utils.numToColor maxColorNum (fst n) in
    -- strRgba_ [r,g,b,1]
  AColorNum (n, Just (opacity, _)) ->
    let (r,g,b) = Utils.numToColor maxColorNum (fst n) in
    strRgba_ [toFloat r, toFloat g, toFloat b, opacity]
  ABounds bounds -> strBounds bounds

valOfAVal : AVal -> Val
valOfAVal a = flip Val a.vtrace <| case a.av_ of
  AString s    -> VBase (VString s)
  ANum it      -> VConst it
  APoints l    -> VList (List.map pointToVal l)
  ARgba tup    -> VList (rgbaToVal tup)
  APath2 p     -> VList (List.concatMap valsOfPathCmd (fst p))
  AColorNum (nt, Nothing)   -> VConst nt
  AColorNum (nt1, Just nt2) -> VList [vConst nt1, vConst nt2]
  _            -> Debug.crash "valOfAVal"

valsOfPathCmd c =
  Debug.crash "restore valsOfPathCmd"
{-
  let fooPt (_,(x,y)) = [vConst x, vConst y] in
  case c of
    CmdZ   s              -> vStr s :: []
    CmdMLT s pt           -> vStr s :: fooPt pt
    CmdHV  s n            -> vStr s :: [vConst n]
    CmdC   s pt1 pt2 pt3  -> vStr s :: List.concatMap fooPt [pt1,pt2,pt3]
    CmdSQ  s pt1 pt2      -> vStr s :: List.concatMap fooPt [pt1,pt2]
    CmdA   s a b c d e pt -> vStr s :: List.map vConst [a,b,c,d,e] ++ fooPt pt
-}

-- Return list of (i, pt).
-- (Includes control points.)
pathIndexPoints nodeAttrs =
  let cmds =
    Utils.find ("pathPoints nodeAttrs looking for \"d\" in " ++ (toString nodeAttrs)) nodeAttrs "d"
    |> toPath
    |> fst
  in
  let pts =
    cmds
    |> List.concatMap
        (\cmd -> case cmd of
          CmdZ   s              -> []
          CmdMLT s pt           -> [pt]
          CmdHV  s n            -> []
          CmdC   s pt1 pt2 pt3  -> [pt1, pt2, pt3]
          CmdSQ  s pt1 pt2      -> [pt1, pt2]
          CmdA   s a b c d e pt -> [pt]
        )
    |> List.filterMap
        (\(maybeIndex, pt) -> case maybeIndex of
          Nothing -> Nothing
          Just i  -> Just (i, pt)
        )
  in
  pts


valOfAttr (k,a) = vList [vBase (VString k), valOfAVal a]
  -- no VTrace to preserve...

-- https://developer.mozilla.org/en-US/docs/Web/SVG/Tutorial/Paths
-- http://www.w3schools.com/svg/svg_path.asp
--
-- NOTES:
--  . using different representation of points in d than in points
--    to make it less verbose and easier to copy-and-paste raw SVG examples
--  . looks like commas are optional

valsToPath2 = valsToPath2_ {numPoints = 0}

valsToPath2_ : PathCounts -> List Val -> (List PathCmd, PathCounts)
valsToPath2_ counts vs = case vs of
  []     -> ([], counts)
  v::vs' -> case v.v_ of
    VBase (VString cmd) ->
      if matchCmd cmd "Z" then
        CmdZ cmd +++ valsToPath2_ counts vs'
      else if matchCmd cmd "MLT" then
        let ((x,y),vs'') = Utils.mapFst Utils.unwrap2 <| projConsts 2 vs' in
        let (counts',pt) = Utils.mapSnd Utils.unwrap1 <| addIdPoints cmd counts [(x,y)] in
        CmdMLT cmd pt +++ valsToPath2_ counts' vs''
      else if matchCmd cmd "HV" then
        let (i,vs'') = Utils.mapFst Utils.unwrap1 <| projConsts 1 vs' in
        CmdHV cmd i +++ valsToPath2_ counts vs''
      else if matchCmd cmd "C" then
        let ((x1,y1,x2,y2,x,y),vs'') = Utils.mapFst Utils.unwrap6 <| projConsts 6 vs' in
        let (counts',(pt1,pt2,pt3)) = Utils.mapSnd Utils.unwrap3 <| addIdPoints cmd counts [(x1,y1),(x2,y2),(x,y)] in
        CmdC cmd pt1 pt2 pt3 +++ valsToPath2_ counts' vs''
      else if matchCmd cmd "SQ" then
        let ((x1,y1,x,y),vs'') = Utils.mapFst Utils.unwrap4 <| projConsts 4 vs' in
        let (counts',(pt1,pt2)) = Utils.mapSnd Utils.unwrap2 <| addIdPoints cmd counts [(x1,y1),(x,y)] in
        CmdSQ cmd pt1 pt2 +++ valsToPath2_ counts' vs''
      else if matchCmd cmd "A" then
        let ((rx,ry,axis,flag,sweep,x,y),vs'') = Utils.mapFst Utils.unwrap7 <| projConsts 7 vs' in
        let (counts',pt) = Utils.mapSnd Utils.unwrap1 <| addIdPoints cmd counts [(x,y)] in
        CmdA cmd rx ry axis flag sweep pt +++ valsToPath2_ counts' vs''
      else
        Debug.crash "valsToPath2_"
    _ ->
      Debug.crash "valsToPath2_"

(+++) x (xs,stuff) = (x::xs, stuff)

addIdPoints : Cmd -> PathCounts -> List Point -> (PathCounts, List IdPoint)
addIdPoints cmd counts pts =
  let c = Utils.unwrap1 <| String.toList cmd in
  if Char.isLower c then
    (counts, List.map ((,) Nothing) pts)
  else if Char.isUpper c then
    let (counts',l) =
      List.foldl (\pt (acc1,acc2) ->
        let nextId = 1 + acc1.numPoints in
        let acc1'  = {acc1 | numPoints = nextId} in
        let acc2'  = (Just nextId, pt) :: acc2 in
        (acc1', acc2')) (counts, []) pts
    in
    (counts', List.reverse l)
  else
    Debug.crash "addIdPoints"

strAPath2 =
  let strPt (_,(it,jt)) = toString (fst it) ++ " " ++ toString (fst jt) in
  -- TODO turn this into a debug mode for printing traces
  -- let strPt (_,(it,jt)) = strVal_ True (VConst it) ++ " " ++ strVal_ True (VConst jt) in
  let strNum (n,_) = toString n in

  let strPathCmd c = case c of
    CmdZ   s              -> s
    CmdMLT s pt           -> Utils.spaces [s, strPt pt]
    CmdHV  s n            -> Utils.spaces [s, strNum n]
    CmdC   s pt1 pt2 pt3  -> Utils.spaces (s :: List.map strPt [pt1,pt2,pt3])
    CmdSQ  s pt1 pt2      -> Utils.spaces (s :: List.map strPt [pt1,pt2])
    CmdA   s a b c d e pt ->
      Utils.spaces (s :: List.map strNum [a,b,c,d,e] ++ [strPt pt])
  in
  Utils.spaces << List.map strPathCmd

projConsts k vs =
  case (k == 0, vs) of
    (True, _)       -> ([], vs)
    (False, v::vs') ->
      case v.v_ of
        VConst it ->
          let (l1,l2) = projConsts (k-1) vs' in
          (it::l1, l2)
        _ ->
          Debug.crash "projConsts"
    _ ->
      Debug.crash "projConsts"

matchCmd cmd s =
  let c  = Utils.unwrap1 <| String.toList cmd in
  let cs = String.toList s in
  List.member c (cs ++ List.map Char.toLower cs)

-- transform commands

valsToTransform : List Val -> List TransformCmd
valsToTransform = List.map valToTransformCmd

valToTransformCmd v = case v.v_ of
  VList vs1 -> case List.map .v_ vs1 of
    (VBase (VString k) :: vs) ->
      case (k, vs) of
        ("rotate",    [VConst n1, VConst n2, VConst n3]) -> Rot n1 n2 n3
        ("scale",     [VConst n1, VConst n2])            -> Scale n1 n2
        ("translate", [VConst n1, VConst n2])            -> Trans n1 n2
        _ -> "a transform command" `expectedButGot` strVal v
    _     -> "a transform command" `expectedButGot` strVal v
  _       -> "a transform command" `expectedButGot` strVal v

strTransformCmd cmd = case cmd of
  Rot n1 n2 n3 ->
    let nums = List.map (toString << fst) [n1,n2,n3] in
    "rotate" ++ Utils.parens (Utils.spaces nums)
  Scale n1 n2 ->
    let nums = List.map (toString << fst) [n1,n2] in
    "scale" ++ Utils.parens (Utils.spaces nums)
  Trans n1 n2 ->
    let nums = List.map (toString << fst) [n1,n2] in
    "translate" ++ Utils.parens (Utils.spaces nums)

{- old way of doing things with APath...

valToPath = Utils.spaces << valToPath_

valToPath_ vs =
  let pt (i,_) (j,_) = toString i ++ " " ++ toString j in
  case vs of
    [] -> []
    VBase (VString cmd) :: vs' ->
      if | matchCmd cmd "Z" -> cmd :: valToPath_ vs'
         | matchCmd cmd "MLT" ->
             let ([sx,sy],vs'') = projConsts 2 vs' in
             cmd :: pt sx sy :: valToPath_ vs''
         | matchCmd cmd "HV" ->
             let ([i],vs'') = projConsts 1 vs' in
             cmd :: toString i :: valToPath_ vs''
         | matchCmd cmd "C" ->
             let ([x1,y1,x2,y2,x,y],vs'') = projConsts 6 vs' in
             let pts = String.join " , " [pt x1 y1, pt x2 y2, pt x y] in
             cmd :: pts :: valToPath_ vs''
         | matchCmd cmd "SQ" ->
             let ([x1,y1,x,y],vs'') = projConsts 4 vs' in
             let pts = String.join " , " [pt x1 y1, pt x y] in
             cmd :: pts :: valToPath_ vs''
         | matchCmd cmd "A" ->
             let (ns,vs'') = projConsts 7 vs' in
             let blah = Utils.spaces (List.map toString ns) in
             cmd :: blah :: valToPath_ vs'' -- not worrying about commas

-}

valToBounds vs = case List.map .v_ vs of
  [VConst a, VConst b, VConst c, VConst d] -> (a,b,c,d)
  _                                        -> "bounds" `expectedButGot` strVal (vList vs)

strBounds (left,top,right,bot) =
  Utils.spaces (List.map (toString << fst) [left,top,right,bot])

desugarKind shape =
  case shape of
    "BOX"  -> "rect"
    "OVAL" -> "ellipse"
    _      -> shape

desugarShapeAttrs shape0 attrs0 =
  let mkNum n = aNum (n, dummyTrace) in
  Maybe.withDefault (shape0, attrs0) <|
    case shape0 of
      "BOX" ->
        Utils.mapMaybe (\(left, top, right, bot, restOfAttrs) ->
          let newAttrs =
             [ ("x", mkNum left)
             , ("y", mkNum top)
             , ("width", mkNum (right - left))
             , ("height", mkNum (bot - top))
             ]
          in ("rect", newAttrs ++ restOfAttrs)
        ) (getBoundsAttrs attrs0)
      "OVAL" ->
        Utils.mapMaybe (\(left, top, right, bot, restOfAttrs) ->
          let newAttrs =
             [ ("cx", mkNum (left + (right - left) / 2))
             , ("cy", mkNum (top + (bot - top) / 2))
             , ("rx", mkNum ((right - left) / 2))
             , ("ry", mkNum ((bot - top) / 2))
             ]
          in ("ellipse", newAttrs ++ restOfAttrs)
        ) (getBoundsAttrs attrs0)
      _ ->
        Nothing

getBoundsAttrs attrs0 =
  Utils.maybeRemoveFirst "LEFT"  attrs0 `Maybe.andThen` \(vL,attrs1) ->
  Utils.maybeRemoveFirst "RIGHT" attrs1 `Maybe.andThen` \(vR,attrs2) ->
  Utils.maybeRemoveFirst "TOP"   attrs2 `Maybe.andThen` \(vT,attrs3) ->
  Utils.maybeRemoveFirst "BOT"   attrs3 `Maybe.andThen` \(vB,attrs4) ->
    case (vL.av_, vT.av_, vR.av_, vB.av_) of
      (ANum (left,_), ANum (top,_), ANum (right,_), ANum (bot,_)) ->
        Just (left, top, right, bot, attrs4)
      _ -> Nothing


------------------------------------------------------------------------------
-- Misc Attribute Helpers

maybeFindAttr_ id kind attr attrs =
  case Utils.maybeFind attr attrs of
    Just aval -> valOfAVal aval
    Nothing   -> Debug.crash <| toString ("RelateAttrs 2", id, kind, attr, attrs)


getPolyXYi attrs si fstOrSnd =
  let i = Utils.fromOk_ <| String.toInt si in
  case Utils.maybeFind "points" attrs of
    Just aval -> case aval.av_ of
      APoints pts -> valOfAVal <| aNum <| fstOrSnd <| Utils.geti i pts
      _           -> Debug.crash "getPolyXYi 2"
    _ -> Debug.crash "getPolyXYi 1"


getPathXYi attrs si fstOrSnd =
  let i = Utils.fromOk_ <| String.toInt si in
  let maybeIndexPoint =
    pathIndexPoints attrs
    |> Utils.maybeFind i
  in
  case maybeIndexPoint of
    Just pt -> valOfAVal <| aNum <| fstOrSnd pt
    Nothing -> Debug.crash "getPathXYi 3"


maybeFindAttr id kind attr attrs =
  case (kind, String.uncons attr) of
    ("polygon", Just ('x', si)) -> getPolyXYi attrs si fst
    ("polygon", Just ('y', si)) -> getPolyXYi attrs si snd
    ("path",    Just ('x', si)) -> getPathXYi attrs si fst
    ("path",    Just ('y', si)) -> getPathXYi attrs si snd
    _                           -> maybeFindAttr_ id kind attr attrs


getPtCount attrs =
  case Utils.maybeFind "points" attrs of
    Just aval -> case aval.av_ of
      APoints pts -> List.length pts
      _           -> Debug.crash "getPtCount 2"
    _ -> Debug.crash "getPtCount 1"


maybeFindBlobId l =
  case Utils.maybeFind "BLOB" l of
    Nothing -> Nothing
    Just av ->
      case av.av_ of
        AString sBlobId -> Just (Utils.parseInt sBlobId)
        _               -> Nothing


maybeFindBounds l =
  case Utils.maybeFind "BOUNDS" l of
    Nothing -> Nothing
    Just av ->
      let roundBounds = True in
      case (av.av_, roundBounds) of
        (ABounds bounds, False) -> Just bounds
        (ABounds (a,b,c,d), True) ->
          let f = Utils.mapFst (toFloat << round) in
          Just (f a, f b, f c, f d)
        _ ->
          Nothing


justGetSvgNode : String -> NodeId -> RootedIndexedTree -> (ShapeKind, List Attr)
justGetSvgNode cap nodeId (_, indexedTree) =
  case Utils.justGet_ cap nodeId indexedTree of
    SvgNode kind attrs _ -> (kind, attrs)
    TextNode _           -> Debug.crash (cap ++ ": TextNode ?")


------------------------------------------------------------------------------
-- Shape Features

type Feature
  = PointFeature PointFeature
  | DistanceFeature DistanceFeature
  | OtherFeature OtherFeature

type PointFeature
  = TopLeft | TopRight  | BotLeft | BotRight
  | TopEdge | RightEdge | BotEdge | LeftEdge
  | Center
  | Point Int
  | Midpoint Int

type DistanceFeature
  = Width | Height
  | Radius
  | RadiusX | RadiusY

type OtherFeature
  = FillColor | FillOpacity
  | StrokeColor | StrokeOpacity | StrokeWidth
  | Rotation

eightPointFeatures =
  List.map PointFeature
     [ TopLeft , TopRight  , BotLeft , BotRight
     , TopEdge , RightEdge , BotEdge , LeftEdge
     ]

ninePointFeatures =
  PointFeature Center :: eightPointFeatures

simpleKindFeatures : List (ShapeKind, List Feature)
simpleKindFeatures =
  [ ( "rect", ninePointFeatures ++ List.map DistanceFeature [Width, Height])
  , ( "BOX", ninePointFeatures ++ List.map DistanceFeature [Width, Height])
  , ( "circle", ninePointFeatures ++ List.map DistanceFeature [Radius])
  , ( "OVAL", ninePointFeatures ++ List.map DistanceFeature [RadiusX, RadiusY])
  , ( "ellipse", ninePointFeatures ++ List.map DistanceFeature [RadiusX, RadiusY])
  , ( "line", List.map PointFeature [Point 1, Point 2])
  ]

polyKindFeatures : ShapeKind -> List Attr -> List Feature
polyKindFeatures kind attrs =
  let cap = "polyKindFeatures" in
  let err s = Debug.crash <| Utils.spaces [cap, kind, ": ", s] in
  if kind == "polygon" then
    case (Utils.find cap attrs "points").av_ of
      APoints pts ->
        List.concatMap
          (\i -> [PointFeature (Point i), PointFeature (Midpoint i)])
          [1 .. List.length pts]
      _ ->
        err "bad points"
  else if kind == "path" then
    err "TODO"
  else
    err "bad shape kind"


------------------------------------------------------------------------------
-- FeatureNum (for selecting/relating individual values)

type FeatureNum
  = X PointFeature
  | Y PointFeature
  | D DistanceFeature
  | O OtherFeature


------------------------------------------------------------------------------
-- ShapeFeature ~= a comparable version of ShapeKind + FeatureNum

-- Must be a comparable to be put in a Set
-- Otherwise, this shouldn't be a string
-- For now, these are unnecessarily entangled with ShapeKinds.
-- See sanityChecks below for the output of getShapeFeature.
--
type alias ShapeFeature = String

getShapeFeature : Maybe ShapeKind -> FeatureNum -> ShapeFeature
getShapeFeature mKind featureNum =
  case mKind of
    Just kind -> String.toLower kind ++ strFeatureNum kind featureNum
    Nothing   -> strFeatureNum "XXX" featureNum

strFeatureNum : ShapeKind -> FeatureNum -> ShapeFeature
strFeatureNum kind featureNum =
  case (kind, featureNum) of
    ("line", X (Point 1)) -> "X1"
    ("line", X (Point 2)) -> "X2"
    ("line", Y (Point 1)) -> "Y1"
    ("line", Y (Point 2)) -> "Y2"
    (_,      X pf)        -> strPointFeature pf "X"
    (_,      Y pf)        -> strPointFeature pf "Y"
    (_,      D df)        -> strDistanceFeature df
    (_,      O f)         -> strOtherFeature f

strPointFeature pointFeature xy =
  case pointFeature of
    TopLeft    -> "TL" ++ xy
    TopRight   -> "TR" ++ xy
    BotLeft    -> "BL" ++ xy
    BotRight   -> "BR" ++ xy
    TopEdge    -> "TC" ++ xy
    RightEdge  -> "CR" ++ xy
    BotEdge    -> "BC" ++ xy
    LeftEdge   -> "CL" ++ xy
    Center     -> "C" ++ xy
    Point i    -> "Pt" ++ xy ++ toString i
    Midpoint i -> "Midpt" ++ xy ++ toString i

strDistanceFeature distanceFeature =
  case distanceFeature of
    Width         -> "Width"
    Height        -> "Height"
    Radius        -> "R"
    RadiusX       -> "RX"
    RadiusY       -> "RY"

strOtherFeature otherFeature =
  case otherFeature of
    FillColor     -> "fill"
    StrokeColor   -> "stroke"
    FillOpacity   -> "fillOpacity"
    StrokeOpacity -> "strokeOpacity"
    StrokeWidth   -> "strokeWidth"
    Rotation      -> "rotation"

xShapeFeatureRegex = Regex.regex "^(.*)X(\\d*)$"
yShapeFeatureRegex = Regex.regex "^(.*)Y(\\d*)$"

featureNumOf : ShapeFeature -> FeatureNum
featureNumOf shapeFeature =
  if Regex.contains xShapeFeatureRegex shapeFeature then
    Regex.find (Regex.AtMost 1) xShapeFeatureRegex shapeFeature
      |> Utils.head_
      |> (.submatches)
      |> parseShapeFeaturePoint
      |> X
  else if Regex.contains yShapeFeatureRegex shapeFeature then
    Regex.find (Regex.AtMost 1) yShapeFeatureRegex shapeFeature
      |> Utils.head_
      |> (.submatches)
      |> parseShapeFeaturePoint
      |> Y
  else
    case shapeFeature of

      "Width"  -> D Width
      "Height" -> D Height
      "R"      -> D Radius
      "RX"     -> D RadiusX
      "RY"     -> D RadiusY

      "fill"          -> O FillColor
      "stroke"        -> O StrokeColor
      "fillOpacity"   -> O FillOpacity
      "strokeOpacity" -> O StrokeOpacity
      "strokeWidth"   -> O StrokeWidth
      "rotation"      -> O Rotation

      _ -> Debug.crash <| "featureNumOf: " ++ shapeFeature

parseShapeFeaturePoint matches =
  case matches of

    [Just "TL", Just ""] -> TopLeft
    [Just "TR", Just ""] -> TopRight
    [Just "BL", Just ""] -> BotLeft
    [Just "BR", Just ""] -> BotRight
    [Just "TC", Just ""] -> TopEdge
    [Just "CR", Just ""] -> RightEdge
    [Just "BC", Just ""] -> BotEdge
    [Just "CL", Just ""] -> LeftEdge
    [Just "C" , Just ""] -> Center

    [Just "", Just "1"] -> Point 1
    [Just "", Just "2"] -> Point 2

    [Just "Pt", Just s] -> Point (Utils.parseInt s)

    [Just "MidPt", Just s] -> Midpoint (Utils.parseInt s)

    _ -> Debug.crash <| "parsePoint: " ++ toString matches


-- Keeping these Strings around to avoid pervasive changes to
-- ValueBasedTransform. Can remove them in favor of FeatureNums instead.

assertString string result =
  if result == string then string
  else Debug.crash <| Utils.spaces ["assertString:", result, "/= ", string]

sanityCheck string kind featureNum =
  assertString string (getShapeFeature (Just kind) featureNum)

sanityCheckOther string featureNum =
  assertString string (getShapeFeature Nothing featureNum)

shapeFill          = sanityCheckOther "fill" (O FillColor)
shapeStroke        = sanityCheckOther "stroke" (O StrokeColor)
shapeFillOpacity   = sanityCheckOther "fillOpacity" (O FillOpacity)
shapeStrokeOpacity = sanityCheckOther "strokeOpacity" (O StrokeOpacity)
shapeStrokeWidth   = sanityCheckOther "strokeWidth" (O StrokeWidth)
shapeRotation      = sanityCheckOther "rotation" (O Rotation)

rectTLX = sanityCheck "rectTLX" "rect" (X TopLeft)
rectTLY = sanityCheck "rectTLY" "rect" (Y TopLeft)
rectTRX = sanityCheck "rectTRX" "rect" (X TopRight)
rectTRY = sanityCheck "rectTRY" "rect" (Y TopRight)
rectBLX = sanityCheck "rectBLX" "rect" (X BotLeft)
rectBLY = sanityCheck "rectBLY" "rect" (Y BotLeft)
rectBRX = sanityCheck "rectBRX" "rect" (X BotRight)
rectBRY = sanityCheck "rectBRY" "rect" (Y BotRight)
rectTCX = sanityCheck "rectTCX" "rect" (X TopEdge)
rectTCY = sanityCheck "rectTCY" "rect" (Y TopEdge)
rectCRX = sanityCheck "rectCRX" "rect" (X RightEdge)
rectCRY = sanityCheck "rectCRY" "rect" (Y RightEdge)
rectBCX = sanityCheck "rectBCX" "rect" (X BotEdge)
rectBCY = sanityCheck "rectBCY" "rect" (Y BotEdge)
rectCLX = sanityCheck "rectCLX" "rect" (X LeftEdge)
rectCLY = sanityCheck "rectCLY" "rect" (Y LeftEdge)
rectCX  = sanityCheck "rectCX"  "rect" (X Center)
rectCY  = sanityCheck "rectCY"  "rect" (Y Center)

rectWidth  = sanityCheck "rectWidth"  "rect" (D Width)
rectHeight = sanityCheck "rectHeight" "rect" (D Height)

boxTLX = sanityCheck "boxTLX" "BOX" (X TopLeft)
boxTLY = sanityCheck "boxTLY" "BOX" (Y TopLeft)
boxTRX = sanityCheck "boxTRX" "BOX" (X TopRight)
boxTRY = sanityCheck "boxTRY" "BOX" (Y TopRight)
boxBLX = sanityCheck "boxBLX" "BOX" (X BotLeft)
boxBLY = sanityCheck "boxBLY" "BOX" (Y BotLeft)
boxBRX = sanityCheck "boxBRX" "BOX" (X BotRight)
boxBRY = sanityCheck "boxBRY" "BOX" (Y BotRight)
boxTCX = sanityCheck "boxTCX" "BOX" (X TopEdge)
boxTCY = sanityCheck "boxTCY" "BOX" (Y TopEdge)
boxCRX = sanityCheck "boxCRX" "BOX" (X RightEdge)
boxCRY = sanityCheck "boxCRY" "BOX" (Y RightEdge)
boxBCX = sanityCheck "boxBCX" "BOX" (X BotEdge)
boxBCY = sanityCheck "boxBCY" "BOX" (Y BotEdge)
boxCLX = sanityCheck "boxCLX" "BOX" (X LeftEdge)
boxCLY = sanityCheck "boxCLY" "BOX" (Y LeftEdge)
boxCX  = sanityCheck "boxCX"  "BOX" (X Center)
boxCY  = sanityCheck "boxCY"  "BOX" (Y Center)

boxWidth  = sanityCheck "boxWidth"  "BOX" (D Width)
boxHeight = sanityCheck "boxHeight" "BOX" (D Height)

ovalTLX = sanityCheck "ovalTLX" "OVAL" (X TopLeft)
ovalTLY = sanityCheck "ovalTLY" "OVAL" (Y TopLeft)
ovalTRX = sanityCheck "ovalTRX" "OVAL" (X TopRight)
ovalTRY = sanityCheck "ovalTRY" "OVAL" (Y TopRight)
ovalBLX = sanityCheck "ovalBLX" "OVAL" (X BotLeft)
ovalBLY = sanityCheck "ovalBLY" "OVAL" (Y BotLeft)
ovalBRX = sanityCheck "ovalBRX" "OVAL" (X BotRight)
ovalBRY = sanityCheck "ovalBRY" "OVAL" (Y BotRight)
ovalTCX = sanityCheck "ovalTCX" "OVAL" (X TopEdge)
ovalTCY = sanityCheck "ovalTCY" "OVAL" (Y TopEdge)
ovalCRX = sanityCheck "ovalCRX" "OVAL" (X RightEdge)
ovalCRY = sanityCheck "ovalCRY" "OVAL" (Y RightEdge)
ovalBCX = sanityCheck "ovalBCX" "OVAL" (X BotEdge)
ovalBCY = sanityCheck "ovalBCY" "OVAL" (Y BotEdge)
ovalCLX = sanityCheck "ovalCLX" "OVAL" (X LeftEdge)
ovalCLY = sanityCheck "ovalCLY" "OVAL" (Y LeftEdge)
ovalCX  = sanityCheck "ovalCX"  "OVAL" (X Center)
ovalCY  = sanityCheck "ovalCY"  "OVAL" (Y Center)

ovalRX = sanityCheck "ovalRX" "OVAL" (D RadiusX)
ovalRY = sanityCheck "ovalRY" "OVAL" (D RadiusY)

circleTCX = sanityCheck "circleTCX" "circle" (X TopEdge)
circleTCY = sanityCheck "circleTCY" "circle" (Y TopEdge)
circleCRX = sanityCheck "circleCRX" "circle" (X RightEdge)
circleCRY = sanityCheck "circleCRY" "circle" (Y RightEdge)
circleBCX = sanityCheck "circleBCX" "circle" (X BotEdge)
circleBCY = sanityCheck "circleBCY" "circle" (Y BotEdge)
circleCLX = sanityCheck "circleCLX" "circle" (X LeftEdge)
circleCLY = sanityCheck "circleCLY" "circle" (Y LeftEdge)
circleCX  = sanityCheck "circleCX"  "circle" (X Center)
circleCY  = sanityCheck "circleCY"  "circle" (Y Center)

circleR = sanityCheck "circleR" "circle" (D Radius)

ellipseTCX = sanityCheck "ellipseTCX" "ellipse" (X TopEdge)
ellipseTCY = sanityCheck "ellipseTCY" "ellipse" (Y TopEdge)
ellipseCRX = sanityCheck "ellipseCRX" "ellipse" (X RightEdge)
ellipseCRY = sanityCheck "ellipseCRY" "ellipse" (Y RightEdge)
ellipseBCX = sanityCheck "ellipseBCX" "ellipse" (X BotEdge)
ellipseBCY = sanityCheck "ellipseBCY" "ellipse" (Y BotEdge)
ellipseCLX = sanityCheck "ellipseCLX" "ellipse" (X LeftEdge)
ellipseCLY = sanityCheck "ellipseCLY" "ellipse" (Y LeftEdge)
ellipseCX  = sanityCheck "ellipseCX"  "ellipse" (X Center)
ellipseCY  = sanityCheck "ellipseCY"  "ellipse" (Y Center)

ellipseRX = sanityCheck "ellipseRX" "ellipse" (D RadiusX)
ellipseRY = sanityCheck "ellipseRY" "ellipse" (D RadiusY)

lineX1 = sanityCheck "lineX1" "line" (X (Point 1))
lineY1 = sanityCheck "lineY1" "line" (Y (Point 1))
lineX2 = sanityCheck "lineX2" "line" (X (Point 2))
lineY2 = sanityCheck "lineY2" "line" (Y (Point 2))
lineCX = sanityCheck "lineCX" "line" (X Center)
lineCY = sanityCheck "lineCY" "line" (Y Center)

pathPtX i    = sanityCheck (pathPtXPrefix ++ toString i) "path" (X (Point i))
pathPtY i    = sanityCheck (pathPtYPrefix ++ toString i) "path" (Y (Point i))
polyPtX i    = sanityCheck (polyPtXPrefix ++ toString i) "polygon" (X (Point i))
polyPtY i    = sanityCheck (polyPtYPrefix ++ toString i) "polygon" (Y (Point i))
polyMidptX i = sanityCheck (polyMidptXPrefix ++ toString i) "polygon" (X (Midpoint i))
polyMidptY i = sanityCheck (polyMidptYPrefix ++ toString i) "polygon" (Y (Midpoint i))

pathPtXPrefix = "pathPtX"
pathPtYPrefix = "pathPtY"
polyPtXPrefix = "polygonPtX"
polyPtYPrefix = "polygonPtY"
polyMidptXPrefix = "polygonMidptX"
polyMidptYPrefix = "polygonMidptY"


------------------------------------------------------------------------------
-- Feature Equations

-- Can't just use Trace because we need to introduce
-- constants not found in the program's Subst
type FeatureEquation
  = EqnVal Val
  | EqnOp Op_ (List FeatureEquation)

-- TODO refactor from ValueBasedTransform

featureEquationOf : ShapeKind -> List Attr -> FeatureNum -> FeatureEquation
featureEquationOf kind attrs featureNum =
  Debug.crash "aa"



------------------------------------------------------------------------------
-- ...

-- TODO redo when Zones are defined using Features

zoneToCrosshair : ShapeKind -> Zone -> Maybe (ShapeFeature, ShapeFeature)
zoneToCrosshair shape zone =
  pointCrosshair shape zone `Utils.plusMaybe`
  cardinalCrosshair shape zone

pointCrosshair shape zone =
  case (shape, realZoneOf zone) of
    ("line", ZPoint 1) -> Just ("lineX1", "lineY1")
    ("line", ZPoint 2) -> Just ("lineX2", "lineX2")
    ("polygon", ZPoint i) ->
      let f xy = "polyPt" ++ xy ++ toString i in Just (f "X", f "Y")
    ("path", ZPoint i) ->
      let f xy = "pathPt" ++ xy ++ toString i in Just (f "X", f "Y")
    _ -> Nothing

cardinalAbbreviation shape zone =
  let ifBoxy shape mx =
    if shape == "rect" || shape == "BOX" || shape == "OVAL"
      then mx
      else Nothing
  in
  case (shape, zone) of
    (_, "TopLeftCorner")  -> ifBoxy shape (Just "TL")
    (_, "TopRightCorner") -> ifBoxy shape (Just "TR")
    (_, "BotLeftCorner")  -> ifBoxy shape (Just "BL")
    (_, "BotRightCorner") -> ifBoxy shape (Just "BR")
    (_, "LeftEdge")       -> Just "CL"
    (_, "RightEdge")      -> Just "CR"
    (_, "TopEdge")        -> Just "TC"
    (_, "BotEdge")        -> Just "BC"
    _                     -> Nothing

cardinalCrosshair shape zone =
  Utils.bindMaybe
    (\abbrv ->
      let xFeatureName = String.toLower shape ++ abbrv ++ "X" in
      let yFeatureName = String.toLower shape ++ abbrv ++ "Y" in
      Just (xFeatureName, yFeatureName))
    (cardinalAbbreviation shape zone)

-- TODO want to generate some of the strings below from these helpers,
-- but wouldn't like so nice because top-level patterns aren't allowed

pointCrosshair_ : ShapeKind -> Zone -> (ShapeFeature, ShapeFeature)
pointCrosshair_ shape zone = Utils.fromJust (zoneToCrosshair shape zone)

cornerCrosshairs_ shape =
  ( pointCrosshair shape "TopLeftCorner"
  , pointCrosshair shape "TopRightCorner"
  , pointCrosshair shape "BotLeftCorner"
  , pointCrosshair shape "BotRightCorner"
  )

edgeCrosshairs_ shape =
  ( pointCrosshair shape "TopEdge"
  , pointCrosshair shape "RightEdge"
  , pointCrosshair shape "BotEdge"
  , pointCrosshair shape "LeftEdge"
  )


------------------------------------------------------------------------------
-- RootedIndexedTree (a.k.a. "Slate"): tree representation of SVG Canvas Value

type alias ShapeKind = String
type alias NodeId = Int
type alias IndexedTree = Dict NodeId IndexedTreeNode
type alias Attr = (String, AVal)
type IndexedTreeNode
  = TextNode String
  | SvgNode ShapeKind (List Attr) (List NodeId)
type alias RootedIndexedTree = (NodeId, IndexedTree)

-- TODO move this above shape point feature stuff

children n = case n of
  TextNode _    -> []
  SvgNode _ _ l -> l

emptyTree : RootedIndexedTree
emptyTree = valToIndexedTree <| vList [vBase (VString "svg"), vList [], vList []]

-- TODO reorder animation functions

-- TODO use options for better error messages

resolveToMovieCount : Int -> Val -> Result String Int
resolveToMovieCount slideNumber val =
  fetchSlideVal slideNumber val
  |> Result.map fetchMovieCount

resolveToMovieFrameVal : Int -> Int -> Float -> Val -> Result String Val
resolveToMovieFrameVal slideNumber movieNumber movieTime val =
  fetchEverything_ slideNumber movieNumber movieTime val
  |> Result.map (\(_, _, _, _, movieFrameVal) -> movieFrameVal)

resolveToIndexedTree : Int -> Int -> Float -> Val -> Result String RootedIndexedTree
resolveToIndexedTree slideNumber movieNumber movieTime val =
  fetchEverything slideNumber movieNumber movieTime val
  |> Result.map (\(_, _, _, _, indexedTree) -> indexedTree)

fetchEverything_ : Int -> Int -> Float -> Val -> Result String (Int, Int, Float, Bool, Val)
fetchEverything_ slideNumber movieNumber movieTime val =
  let slideCount = fetchSlideCount val in
  fetchSlideVal slideNumber val
  `Result.andThen` (\slideVal ->
    let movieCount = fetchMovieCount slideVal in
    fetchMovieVal movieNumber slideVal
    `Result.andThen` (\movieVal ->
      let (movieDuration, continue) = fetchMovieDurationAndContinueBool movieVal in
      fetchMovieFrameVal slideNumber movieNumber movieTime movieVal
      |> Result.map (\movieFrameVal ->
        (slideCount, movieCount, movieDuration, continue, movieFrameVal)
      )
    )
  )

fetchEverything : Int -> Int -> Float -> Val -> Result String (Int, Int, Float, Bool, RootedIndexedTree)
fetchEverything slideNumber movieNumber movieTime val =
  fetchEverything_ slideNumber movieNumber movieTime val
  |> Result.map (\(slideCount, movieCount, movieDuration, continue, movieVal) ->
                  (slideCount, movieCount, movieDuration, continue, valToIndexedTree movieVal))

fetchSlideCount : Val -> Int
fetchSlideCount val =
  case unwrapVList val of
    Just [VConst (slideCount, _), _] -> round slideCount
    _ -> 1 -- Program returned a plain SVG array structure...we hope.

fetchMovieCount : Val -> Int
fetchMovieCount slideVal =
  case unwrapVList slideVal of
    Just [VConst (movieCount, _), _] -> round movieCount
    _ -> 1 -- Program returned a plain SVG array structure...we hope.

fetchSlideVal : Int -> Val -> Result String Val
fetchSlideVal slideNumber val =
  case unwrapVList val of
    Just [VConst (slideCount, _), VClosure _ pat fexp fenv] ->
      -- Program returned the slide count and a
      -- function from slideNumber -> SVG array structure.
      case pat.val of -- Find that function's argument name
        PVar _ argumentName _ ->
          -- Bind the slide number to the function's argument.
          let fenv' = (argumentName, vConst (toFloat slideNumber, dummyTrace)) :: fenv in
          Eval.eval fenv' [] fexp
          |> Result.map (\((returnVal, _), _) -> returnVal)
        _ -> Err ("expected slide function to take a single argument, got " ++ (toString pat.val))
    _ -> Ok val -- Program returned a plain SVG array structure...we hope.

-- This is nasty b/c a two-arg function is really a function that returns a function...
fetchMovieVal : Int -> Val -> Result String Val
fetchMovieVal movieNumber slideVal =
  case unwrapVList slideVal of
    Just [VConst (movieCount, _), VClosure _ pat fexp fenv] ->
      case pat.val of -- Find the function's argument name
        PVar _ movieNumberArgumentName _ ->
          let fenv' = (movieNumberArgumentName, vConst (toFloat movieNumber, dummyTrace)) :: fenv in
          Eval.eval fenv' [] fexp
          |> Result.map (\((returnVal, _), _) -> returnVal)
        _ -> Err ("expected movie function to take a single argument, got " ++ (toString pat.val))
    _ -> Ok slideVal -- Program returned a plain SVG array structure...we hope.

fetchMovieDurationAndContinueBool : Val -> (Float, Bool)
fetchMovieDurationAndContinueBool movieVal =
  case unwrapVList movieVal of
    Just [VBase (VString "Static"), VClosure _ _ _ _] ->
      (0.0, False)
    Just [VBase (VString "Dynamic"), VConst (movieDuration, _), VClosure _ _ _ _, VBase (VBool continue)] ->
      (movieDuration, continue)
    _ ->
      (0.0, False) -- Program returned a plain SVG array structure...we hope.

-- This is nasty b/c a two-arg function is really a function that returns a function...
fetchMovieFrameVal : Int -> Int -> Float -> Val -> Result String Val
fetchMovieFrameVal slideNumber movieNumber movieTime movieVal =
  case unwrapVList movieVal of
    Just [VBase (VString "Static"), VClosure _ pat fexp fenv] ->
      case pat.val of -- Find the function's argument names
        PVar _ slideNumberArgumentName _ ->
          let fenv' = (slideNumberArgumentName, vConst (toFloat slideNumber, dummyTrace)) :: fenv in
          case Eval.eval fenv' [] fexp |> Result.map (\((innerVal, _), _) -> innerVal.v_) of
            Ok (VClosure _ patInner fexpInner fenvInner) ->
              case patInner.val of
                PVar _ movieNumberArgumentName _ ->
                  let fenvInner' = (movieNumberArgumentName, vConst (toFloat movieNumber, dummyTrace)) :: fenvInner in
                  Eval.eval fenvInner' [] fexpInner
                  |> Result.map (\((returnVal, _), _) -> returnVal)
                _ -> Err ("expected static movie frame function to take two arguments, got " ++ (toString patInner.val))
            Ok v_ -> Err ("expected static movie frame function to take two arguments, got " ++ (toString v_))
            Err s -> Err s
        _ -> Err ("expected static movie frame function to take two arguments, got " ++ (toString pat.val))
    Just [VBase (VString "Dynamic"), VConst (movieDuration, _), VClosure _ pat fexp fenv, VBase (VBool _)] ->
      case pat.val of -- Find the function's argument names
        PVar _ slideNumberArgumentName _ ->
          let fenv' = (slideNumberArgumentName, vConst (toFloat slideNumber, dummyTrace)) :: fenv in
          case Eval.eval fenv' [] fexp |> Result.map (\((innerVal1, _), _) -> innerVal1.v_) of
            Ok (VClosure _ patInner1 fexpInner1 fenvInner1) ->
              case patInner1.val of
                PVar _ movieNumberArgumentName _ ->
                  let fenvInner1' = (movieNumberArgumentName, vConst (toFloat movieNumber, dummyTrace)) :: fenvInner1 in
                  case Eval.eval fenvInner1' [] fexpInner1 |> Result.map (\((innerVal2, _), _) -> innerVal2.v_) of
                    Ok (VClosure _ patInner2 fexpInner2 fenvInner2) ->
                      case patInner2.val of
                        PVar _ movieSecondsArgumentName _ ->
                          let fenvInner2' = (movieSecondsArgumentName, vConst (movieTime, dummyTrace)) :: fenvInner2 in
                          Eval.eval fenvInner2' [] fexpInner2
                          |> Result.map (\((returnVal, _), _) -> returnVal)
                        _ -> Err ("expected dynamic movie frame function to take four arguments, got " ++ (toString patInner2.val))
                    Ok innerV2_ -> Err ("expected dynamic movie frame function to take four arguments, got " ++ (toString innerV2_))
                    Err s -> Err s
                _ -> Err ("expected dynamic movie frame function to take four arguments, got " ++ (toString patInner1.val))
            Ok innerV1_ -> Err ("expected dynamic movie frame function to take four arguments, got " ++ (toString innerV1_))
            Err s -> Err s
        _ -> Err ("expected dynamic movie frame function to take four arguments, got " ++ (toString pat.val))
    _ -> Ok movieVal -- Program returned a plain SVG array structure...we hope.


valToIndexedTree : Val -> RootedIndexedTree
valToIndexedTree v =
  let (nextId,tree) = valToIndexedTree_ v (1, Dict.empty) in
  let rootId = nextId - 1 in
  (rootId, tree)

valToIndexedTree_ v (nextId, d) = case v.v_ of

  VList vs -> case List.map .v_ vs of

    [VBase (VString "TEXT"), VBase (VString s)] ->
      (1 + nextId, Dict.insert nextId (TextNode s) d)

    [VBase (VString kind), VList vs1, VList vs2] ->
      let processChild vi (a_nextId, a_graph , a_children) =
        let (a_nextId',a_graph') = valToIndexedTree_ vi (a_nextId, a_graph) in
        let a_children'          = (a_nextId' - 1) :: a_children in
        (a_nextId', a_graph', a_children') in
      let (nextId',d',children) = List.foldl processChild (nextId,d,[]) vs2 in
      let node = SvgNode kind (List.map valToAttr vs1) (List.reverse children) in
      (1 + nextId', Dict.insert nextId' node d')

    _ ->
      "an SVG node" `expectedButGot` strVal v

  _ ->
    "an SVG node" `expectedButGot` strVal v

printIndexedTree : Val -> String
printIndexedTree = valToIndexedTree >> snd >> strEdges

strEdges : IndexedTree -> String
strEdges =
     Dict.toList
  >> List.map (\(i,n) ->
       let l = List.map toString (children n) in
       toString i ++ " " ++ Utils.braces (Utils.spaces l))
  >> Utils.lines


------------------------------------------------------------------------------
-- Printing to SVG format

printSvg : Bool -> RootedIndexedTree -> String
printSvg showGhosts (rootId, tree) =
  let s = printNode showGhosts 0 tree rootId in
  Regex.replace Regex.All (Regex.regex "[ ]+\\n") (\_ -> "") s

printNode showGhosts k slate i =
  case Utils.justGet i slate of
    TextNode s -> s
    SvgNode kind_ l1_ l2 ->
      let (kind,l1) = desugarShapeAttrs kind_ l1_ in
      case (showGhosts, Utils.maybeRemoveFirst "HIDDEN" l1) of
        (False, Just _) -> ""
        _ ->
          if l2 == [] then
            let l1' = addAttrs kind (removeSpecialAttrs l1) in
            Utils.delimit "<" ">" (kind ++ printAttrs l1') ++
            Utils.delimit "</" ">" kind
          else
            let l1' = addAttrs kind (removeSpecialAttrs l1) in
            Utils.delimit "<" ">" (kind ++ printAttrs l1') ++ "\n" ++
            printNodes showGhosts (k+1) slate l2 ++ "\n" ++
            tab k ++ Utils.delimit "</" ">" kind

printNodes showGhosts k slate =
  Utils.lines << List.map ((++) (tab k) << printNode showGhosts k slate)

printAttrs l = case l of
  [] -> ""
  _  -> " " ++ Utils.spaces (List.map printAttr l)

printAttr (k,v) =
  k ++ "=" ++ Utils.delimit "'" "'" (strAVal v)

addAttrs kind attrs =
  if kind == "svg"
    then ("xmlns", aString "http://www.w3.org/2000/svg") :: attrs
    else attrs

specialAttrs = ["HIDDEN", "ZONES"]
  -- not removing 'BLOB' and 'BOUNDS' since they are useful
  -- for understanding and debugging

removeSpecialAttrs =
  List.filter (\(s,_) -> not (List.member s specialAttrs))


------------------------------------------------------------------------------
-- Zones

-- TODO redefine zones using Features

type alias Zone = String

-- NOTE: would like to use only the following definition, but datatypes
-- aren't comparable... so using Strings for storing in dictionaries, but
-- using the following for pattern-matching purposes

type RealZone = Z String | ZPoint Int | ZEdge Int

addi s i = s ++ toString i

realZoneOf s =
  Maybe.withDefault (Z s) (toZPoint s `Utils.plusMaybe` toZEdge s)

toZPoint s =
  Utils.mapMaybe
    (\suffix ->
      if suffix == "" then Z "Point"
      else ZPoint (Utils.fromOk_ (String.toInt suffix)))
    (Utils.munchString "Point" s)

toZEdge s =
  Utils.mapMaybe
    (\suffix ->
      if suffix == "" then Z "Edge"
      else ZEdge (Utils.fromOk_ (String.toInt suffix)))
    (Utils.munchString "Edge" s)

-- TODO perhaps define Interface callbacks here

zones = [
    ("svg", [])
  , ("BOX",
      [ ("Interior", ["LEFT", "TOP", "RIGHT", "BOT"])
      , ("TopLeftCorner", ["LEFT", "TOP"])
      , ("TopRightCorner", ["TOP", "RIGHT"])
      , ("BotRightCorner", ["RIGHT", "BOT"])
      , ("BotLeftCorner", ["LEFT", "BOT"])
      , ("LeftEdge", ["LEFT"])
      , ("TopEdge", ["TOP"])
      , ("RightEdge", ["RIGHT"])
      , ("BotEdge", ["BOT"])
      ])
  , ("rect",
      [ ("Interior", ["x", "y"])
      , ("TopLeftCorner", ["x", "y", "width", "height"])
      , ("TopRightCorner", ["y", "width", "height"])
      , ("BotRightCorner", ["width", "height"])
      , ("BotLeftCorner", ["x", "width", "height"])
      , ("LeftEdge", ["x", "width"])
      , ("TopEdge", ["y", "height"])
      , ("RightEdge", ["width"])
      , ("BotEdge", ["height"])
      ])
  , ("line",
      [ ("Point1", ["x1", "y1"])
      , ("Point2", ["x2", "y2"])
      , ("Edge", ["x1", "y1", "x2", "y2"])
      ])
  , ("circle",
      [ ("Interior", ["cx", "cy"])
      , ("LeftEdge", ["cx", "r"])
      , ("RightEdge", ["cx", "r"])
      , ("TopEdge", ["cy", "r"])
      , ("BotEdge", ["cy", "r"])
      , ("TopLeftCorner", ["cx", "cy", "r"])
      , ("TopRightCorner", ["cx", "cy", "r"])
      , ("BotLeftCorner", ["cx", "cy", "r"])
      , ("BotRightCorner", ["cx", "cy", "r"])
      ])
  , ("ellipse",
      [ ("Interior", ["cx", "cy"])
      , ("LeftEdge", ["cx", "rx"])
      , ("RightEdge", ["cx", "rx"])
      , ("TopEdge", ["cy", "ry"])
      , ("BotEdge", ["cy", "ry"])
      , ("TopLeftCorner", ["cx", "cy", "rx", "ry"])
      , ("TopRightCorner", ["cx", "cy", "rx", "ry"])
      , ("BotLeftCorner", ["cx", "cy", "rx", "ry"])
      , ("BotRightCorner", ["cx", "cy", "rx", "ry"])
      ])
  , ("OVAL",
      [ ("Interior", ["LEFT", "TOP", "RIGHT", "BOT"])
      , ("TopLeftCorner", ["LEFT", "TOP"])
      , ("TopRightCorner", ["TOP", "RIGHT"])
      , ("BotRightCorner", ["RIGHT", "BOT"])
      , ("BotLeftCorner", ["LEFT", "BOT"])
      , ("LeftEdge", ["LEFT"])
      , ("TopEdge", ["TOP"])
      , ("RightEdge", ["RIGHT"])
      , ("BotEdge", ["BOT"])
      ])
  -- TODO
  , ("g", [])
  , ("text", [])
  , ("tspan", [])

  -- symptom of the Sync.Dict0 type. see Sync.nodeToAttrLocs_.
  , ("DUMMYTEXT", [])

  -- NOTE: these are computed in Sync.getZones
  -- , ("polygon", [])
  -- , ("polyline", [])
  -- , ("path", [])
  ]


------------------------------------------------------------------------------

dummySvgNode =
  let zero = aNum (0, dummyTrace) in
  SvgNode "circle" (List.map (\k -> (k, zero)) ["cx","cy","r"]) []

-- TODO break up and move slateToVal here
dummySvgVal =
  let zero = vConst (0, dummyTrace) in
  let attrs = vList <| List.map (\k -> vList [vStr k, zero]) ["cx","cy","r"] in
  let children = vList [] in
  vList [vStr "circle", attrs, children]
