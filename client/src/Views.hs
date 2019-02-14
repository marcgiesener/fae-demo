{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ExtendedDefaultRules #-}

module Views where

import Auction
import LobbyView
import Data.Aeson as A
import Data.Bool
import qualified Data.ByteString.Lazy as L
import Data.ByteString.Lazy.Char8 as BL
import qualified Data.ByteString.Lazy.Char8 as C
import qualified Data.JSString as GJS
import qualified Data.List as Li
import qualified Data.Map as M
import Data.Map.Lazy (Map)
import Data.Maybe
import Data.Monoid
import qualified Data.Text.Lazy as W
import Data.Text.Lazy.Encoding as X
import Data.Time.Calendar
import Data.Time.Clock
import Data.Time.Format
import GHC.Generics
import Miso
import Miso.String (MisoString)
import qualified Miso.String as S
import Text.Read
import Types
import SharedTypes
import CreateAuctionView

import Data.Proxy
import Servant.API

import SharedViews


appView :: Model -> View Action
appView m = either (const the404) id $ runRoute (Proxy :: Proxy API) handlers uri m
  where
  handlers = login :<|> auctionHome :<|> create :<|> lobby
  auctionHome (_ :: Model) = div_ [] [
     biddingView m 
    ]
  login (_ :: Model) = div_ [] [
     loginView m
    ]
  create (_ :: Model) = div_ [] [
     createAuctionView m
    ]
  lobby (_ :: Model) = div_ [] [
     lobbyView m
    ]
  the404 = div_ [] [
      text "404 :("
    , button_ [ onClick (AppAction goLogin) ] [ text "Login" ]
    ]

loginView :: Model -> View Action
loginView m@Model {..} = div_ [] [
  h1_ [class_ "heading"] [ text "Fae Auction"]
  , loginForm m
  ]

biddingView :: Model -> View Action
biddingView m@Model {..} =
  div_ [] $
  [ div_
      [class_ "main-container"]
      [headerView m, mainView m ]
  ]

-- container for the main auction content
mainView :: Model -> View Action
mainView m@Model {..} =
  case selectedAuctionTXID of
    Nothing -> ""
    (Just aucTXID) ->
      case M.lookup aucTXID auctions of
        Nothing -> ""
        (Just auction) ->
          auctionView m maxBidCountField auctionStartValField aucTXID auction bidFieldValue

onEnter :: Action -> Attribute Action
onEnter action = onKeyDown $ bool (AppAction Noop) action . (== KeyCode 13)

viewAuction :: AucTXID -> Auction -> View Action
viewAuction aucTXID auction@Auction {..} =
  li_
    [class_ "auction-item", onClick $ AppAction (SelectAuction aucTXID)]
    [auctionText]
  where
    auctionText = p_ [] [text $ S.pack $ show auction]

getTableHeader :: [String] -> [View Action]
getTableHeader names =
  Prelude.map (\name -> th_ [] [p_ [] [text $ S.ms name]]) names


getTableRow :: TXLogEntry -> View Action
getTableRow TXLogEntry{..} =
  tr_
    [ --onClick $ AppAction (SelectAuction txid)
     --class_ $ do bool "auction-row" "auction-row-selected" isSelected
    ]
    [ td_ [class_ "hash-cell"] [text $ S.ms truncatedTXID]
    , td_ [class_ "timestamp-cell hash-cell"] [text $ S.ms $ format24hrTime entryTimestamp]
    , td_ [] [text $ S.ms entryUsername]
    , td_ [] [text $ S.ms $ entryDescription]
    ]
  where
    truncatedTXID = Li.take 6 entryTXID 

getTableRows :: [TXLogEntry] -> [View Action]
getTableRows txLogEntries = getTableRow <$> (Li.reverse txLogEntries)

   -- table m | not $ Li.null txLog
txLogTable :: [TXLogEntry] -> View Action
txLogTable txLogEntries = table
  where table =  div_
            [class_ "tx-log-table"]
            [ table_
                []
                [ thead_
                    [style_ $ M.fromList [(S.pack "text-align", S.pack "center")]]
                    [ 
                    ]
                , tbody_ [] $ getTableRows txLogEntries
                ]
            ]

auctionView :: Model -> Int -> Int -> AucTXID -> Auction -> Int ->  View Action
auctionView  m maxBidCountField startingVal aucTXID@(AucTXID txid) auction@Auction {..} bidFieldValue = 
  div_ [class_ "auction-container"] [ 
    auctionViewLeft m currentPrice auction, 
    auctionViewRight maxBidCountField aucTXID (bidFieldValue) auction]
  where currentPrice = if Li.null bids then S.ms startingVal else S.ms $ currentBidValue auction

auctionViewLeft m@Model{..} currentPrice auction@Auction{..} =
  div_
    [class_ "auction-container-left"]
      ([ div_
          [ class_ "auction-container-item no-margin-top"]
          [
            h3_ [] [text "Seller London Book House"]
          ]
      ,
      div_
        [class_ "auction-container-item no-margin-top"]
        [
            h3_ [] [text "Item 58113861094"]
        ]
      ,
       div_
          [ class_ "auction-container-item no-margin-top"]
          [
            h3_ [] [text $ "Current Price  $ " <> (currentPrice)]
          ]
      ,
      div_
          [ class_ "auction-container-item no-margin-top"]
          [
            h3_ [] [text "Description"]
          ]
      ,
      div_
          [ class_ "auction-container-item no-margin-top"]
          [
            p_ [] [text (S.ms description)]
          ]
      ,
      div_
          [ class_ "auction-container-item view-types", onClick (AppAction ToggleShowBidHistory)   ]
          [
             button_ [ class_ "segmented-btn l"] [text "Fae TX Log"], 
             button_ [ class_ "segmented-btn r"] [text "Bid History"] 
          ]
      ] ++ [ txLogTable txLog | not showBidHistory ]
        ++  [ bidHistoryTable auction | showBidHistory && Li.length bids /= 0 ]
        ++  [ text "No Bids Yet" | showBidHistory && Li.length bids == 0 ])

auctionViewRight maxBidCountField aucTXID bidFieldValue auction@Auction{..} =
  div_
    [class_ "auction-container-right"]
      [ div_
          [ class_ "auction-container-item"]
          [
            bookImg
          ]
      ,
      div_
        [class_ "bid-input-container auction-container-item"]
        [
            div_ 
              [class_ "bid-input-container"] 
              [ --h3_ [class_ "dollar"] [text "$"]
               -- , 
                input_
                [ class_ "bid-field-input"
                , type_ "text"
                , placeholder_ "Enter Bid"
                , value_ $ S.pack $ show bidFieldValue
                , name_ "bidValue"
                , onInput $
                  AppAction . UpdateBidField . readMaybe . S.unpack . S.toMisoString
                ]
              ] | not $ auctionEnded auction
        ]  
      ,
        div_
          [ class_ "auction-container-item"]
          [
            bidBtn | not $ auctionEnded auction
          ]
      ,
      div_
      [ class_ "auction-container-item"]
      [
        h3_ [] [text $ S.ms $ highestBidder auction <> " has won" | auctionEnded auction]
      ]
      ,
      div_
          [ class_ "bid-progress-container"]
          [
            h3_ [] [text $ ("Bids: " <> (S.ms $ show $ Li.length bids)) <> "/" <> (S.ms $ show aucMaxBidCount)]
          ]
      ]
      where 
        isBidDisabled = (auctionEnded auction) || (bidFieldValue <= currentBidValue auction)
        bidBtn = button_ [
              class_ "bid-field-btn",
              onClick (AppAction $ MintCoinsAndBid aucTXID (bidFieldValue)),
              disabled_ isBidDisabled
              ] 
              [
                text "Submit Bid"
              ]

--
       --     h3_ [] [text $ "Auction " <> (S.pack $ show truncatedAucTXID)],
       --     div_ [class_ "auction-info"] [ h3_ [class_ "book_title"] [
       --       text $ S.pack "An Inquiry into the Nature and Causes of the Wealth of Nations. Smith, Adam. 1776"], p_ [class_ "book-description"] [text description], bookImg]
       --   ]
      --]
  --     ++
  --    [ footer_ [] [placeBidView aucTXID auction bidFieldValue username]
  --    | not $ auctionEnded auction
  --    ]
  --  ]
  --where
  --  bidValue = currentBidValue auction
  --  truncatedAucTXID = Li.take 5 txid

placeBidView :: AucTXID -> Auction -> Int -> String -> View Action
placeBidView aucTXID auction@Auction {..} bidFieldValue username =
  div_
    [class_ "place-bid-container"]
    [ input_
        [ class_ "field-input"
        , type_ "text"
        , placeholder_ "Enter Bid"
        , value_ $ S.pack $ show bidFieldValue
        , name_ "bidValue"
        , onInput $
          AppAction . UpdateBidField . readMaybe . S.unpack . S.toMisoString
        , onEnter bidAction
        ]
    , button_ [class_ "bid-field-btn", onClick bidAction, disabled_ $ auctionEnded auction] [text "Submit Bid"]
    ]
  where
    title = S.pack $ "Current Bid" ++ show aucTXID
    bidAction = AppAction $ MintCoinsAndBid aucTXID bidFieldValue

loginForm :: Model -> View Action
loginForm Model {..} =
  div_
    [class_ "login-form"]
    [ header_
        [class_ "header"]
        [
         input_
            [ type_ "text"
            , class_ "login-form-input"
            , onInput (AppAction . UpdateUserNameField . S.toMisoString)
            , onEnter (AppAction (Login))
            ]
        , button_
            [class_ "login-form-btn", onClick (AppAction (Login))]
            [text "Login"]
        ]
    ]


bidHistoryTable Auction{..} = table
  where table =  div_
            [class_ "tx-log-table"]
            [ table_
                []
                [ thead_
                    [style_ $ M.fromList [(S.pack "text-align", S.pack "center")]]
                    [ 
                    ]
                , tbody_ [] (getBidHistTableRows bids)
                ]
            ]

getBidHistTableRow :: Bid -> View Action
getBidHistTableRow Bid{..} =
  tr_
    [ --onClick $ AppAction (SelectAuction txid)
     --class_ $ do bool "auction-row" "auction-row-selected" isSelected
    ]
    [ 
      td_ [class_ "timestamp-cell hash-cell"] [text $ S.ms $ format24hrTime bidTimestamp]
    , td_ [] [text $ S.ms bidder]
    , td_ [] [text $ S.ms $ bidValue]
    ]


getBidHistTableRows bids = getBidHistTableRow <$> bids