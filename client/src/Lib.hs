{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ExtendedDefaultRules #-}

module Lib where

import Auction
import Data.Aeson as A
import Data.Bool
import qualified Data.ByteString.Lazy as L
import Data.ByteString.Lazy.Char8 as BL
import qualified Data.ByteString.Lazy.Char8 as C
import Data.IntMap.Lazy (IntMap)
import qualified Data.IntMap.Lazy as IntMap
import qualified Data.JSString as GJS
import qualified Data.List as Li
import qualified Data.Map as M
import qualified Data.Map as M
import Data.Maybe
import Data.Monoid
import qualified Data.Text.Lazy as W
import Data.Text.Lazy.Encoding as X
import Data.Time.Calendar
import Data.Time.Clock
import GHC.Generics
import Miso
import Miso.String (MisoString)
import qualified Miso.String as S
import Text.Read
import SharedTypes
import Data.Proxy
import Servant.API
import Servant.Utils.Links
import Types
import Views

parseServerAction :: MisoString -> Action
parseServerAction m =
  case parsedServerAction of
    Just msg -> ServerAction msg
    Nothing -> AppAction Noop
  where
    parsedServerAction = decode (C.pack $ GJS.unpack m) :: Maybe Msg

getInitialModel currentURI =
  Model
    { 
      uri = currentURI
    ,  auctions = M.empty
    , received = S.ms ""
    , msg = Message $ S.ms ""
    , bidFieldValue = 0
    , username = S.ms ""
    , loggedIn = False
    , selectedAuctionTXID = Nothing
    , accountBalance = 0
    }

runApp :: IO ()
runApp = do
  startApp App {model=getInitialModel initialURI, initialAction = AppAction goLogin, ..}
  where
    initialURI = linkURI $ safeLink (Proxy :: Proxy API) (Proxy :: Proxy Login)
    events = defaultEvents
    subs = [websocketSub uri protocols (AppAction . HandleWebSocket), uriSub (AppAction . HandleURI) ]
    update = updateModel
    view = appView
    uri = URL "ws://localhost:9160"
    protocols = Protocols []
    mountPoint = Nothing

updateModel :: Action -> Model -> Effect Action Model
updateModel (AppAction action) m = handleAppAction action m
updateModel (ServerAction action) m = handleServerAction action m

handleAppAction :: AppAction -> Model -> Effect Action Model
handleAppAction (HandleURI u) m = m { uri = u } <# do
  pure $ AppAction Noop
handleAppAction (ChangeURI u) m = m <# do
  pushURI u
  pure $ AppAction Noop
handleAppAction (SendServerAction action) model =
  model <# do
    send action
    pure (AppAction Noop)
handleAppAction (SelectAuction aucTXID) Model {..} =
  noEff Model {selectedAuctionTXID = Just aucTXID, ..}
handleAppAction (UpdateBidField maybeInt) Model {..} =
  Model {bidFieldValue = fromMaybe bidFieldValue maybeInt, ..} <# do
    pure (AppAction Noop)
handleAppAction (SendMessage msg) model =
  model <# do send msg >> pure (AppAction Noop)
handleAppAction (HandleWebSocket (WebSocketMessage msg@(Message m))) model =
  model {received = m} <# do
    pure parsedServerAction
  where
    parsedServerAction = parseServerAction m
handleAppAction (UpdateMessage m) model = noEff model {msg = Message m}
handleAppAction Login Model {..} =
  Model {loggedIn = True, ..} <# do send msg >> pure (AppAction (goHome))
handleAppAction (UpdateUserNameField newUsername) Model {..} =
  noEff Model {username = newUsername, ..}
handleAppAction Noop model = noEff model
handleAppAction _ model = noEff model

handleServerAction :: Msg -> Model -> Effect Action Model
handleServerAction a@(AuctionCreated aucTXID auction) Model {..} =
  noEff Model {auctions = updatedAuctions, ..}
  where
    updatedAuctions = createAuction aucTXID auction auctions
handleServerAction a@(BidSubmitted aucTXID bid) Model {..} =
  noEff Model {auctions = updatedAuctions, accountBalance = 0, bidFieldValue = 0, ..}
  where
    updatedAuctions = bidOnAuction aucTXID bid auctions
handleServerAction a@(CoinsGenerated numCoins) Model {..} =
  noEff Model {accountBalance = newBalance, bidFieldValue = newBalance, ..} -- bidAmount == account balance for simplicity
  where newBalance = accountBalance + 1
handleServerAction _ model = noEff model
