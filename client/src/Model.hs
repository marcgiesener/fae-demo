{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ExtendedDefaultRules #-}

module Model where

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
import Data.UUID.V4

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
    , auctions = M.empty
    , received = S.ms ""
    , msg = Message $ S.ms ""
    , bidFieldValue = 0
    , genNumCoinsField = 1
    , maxBidCountField = 4
    , auctionStartValField = 1
    , username = S.ms ""
    , loggedIn = False
    , selectedAuctionTXID = Nothing
    , accountBalance = 0
    }

updateModel :: Action -> Model -> Effect Action Model
updateModel (AppAction action) m = handleAppAction action m
updateModel (ServerAction action) m = handleServerAction action m

handleAppAction :: AppAction -> Model -> Effect Action Model
handleAppAction (HandleURI u) m = m { uri = u } <# do
  pure $ AppAction Noop

handleAppAction (ChangeURI u) m = m <# do
  pushURI u
  pure $ AppAction Noop

handleAppAction (MintCoinsAndBid aucTXID coinCount) model = 
  mintCoinsAndBid coinCount aucTXID model

handleAppAction (SendServerAction action) model =
  model <# do
    send action
    pure (AppAction Noop)

handleAppAction (SelectAuction aucTXID) Model {..} =
  noEff Model {selectedAuctionTXID = Just aucTXID, ..}

handleAppAction (UpdateBidField maybeInt) Model {..} =
  Model {bidFieldValue = fromMaybe bidFieldValue maybeInt, ..} <# do
    pure (AppAction Noop)

handleAppAction (UpdateGenNumCoinsField maybeInt) Model {..} =
  Model {genNumCoinsField = fromMaybe 0 maybeInt, ..} <# do
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
  Model {loggedIn = True, ..} <# do send username >> pure (AppAction (goCreate))

handleAppAction (UpdateUserNameField newUsername) Model {..} =
  noEff Model {username = newUsername, ..}

handleAppAction (UpdateNewMaxBidCountField newMaxBidCount) Model {..} =
  noEff Model { maxBidCountField = newMaxBidCount, ..}

handleAppAction (UpdateNewStartingValField newAuctionStartVal) Model {..} =
  noEff Model {auctionStartValField = newAuctionStartVal, ..}

-- gets the auction start params from the fields, constructs the auction request msg and then sends
handleAppAction SendCreateAuctionRequest m@Model {..} = 
  m <# do send action >> pure (AppAction Noop)
  where action = CreateAuctionRequest $ AuctionOpts auctionStartValField maxBidCountField

handleAppAction Noop model = noEff model

handleAppAction _ model = noEff model

handleServerAction :: Msg -> Model -> Effect Action Model
handleServerAction a@(AuctionCreated aucTXID auction) Model {..} =
  Model {auctions = updatedAuctions, selectedAuctionTXID = Just aucTXID, ..} <# pure (AppAction goAuctionHome)
  where
    updatedAuctions = createAuction aucTXID auction auctions

handleServerAction a@(BidSubmitted aucTXID bid@Bid{..}) Model {..} =
  Model {
    auctions = updatedAuctions,
    accountBalance = accountBalance - bidValue, 
    bidFieldValue = 0,
    ..} <# pure (AppAction Noop)
  where
    updatedAuctions = bidOnAuction aucTXID bid auctions

handleServerAction a@(CoinsGenerated numCoins) Model {..} =
  noEff Model {accountBalance = newBalance, bidFieldValue = newBalance, ..} -- bidAmount == account balance for simplicity
  where newBalance = accountBalance + numCoins

handleServerAction _ model = noEff model

mintCoinsAndBid :: Int -> AucTXID -> Model -> Effect Action Model
mintCoinsAndBid coinCount aucTXID model = 
  updateModel mintCoinsMsg model >>= updateModel bidMsg
  where
    mintCoinsMsg = AppAction (SendServerAction (RequestCoins coinCount))
    bidMsg = AppAction (SendServerAction (BidRequest aucTXID coinCount)) 

getTXDescription :: Msg -> String
getTXDescription (AuctionCreated (AucTXID aucTXID) auction) = "Auction created"
getTXDescription (BidSubmitted (AucTXID aucTXID) coinCount) = Li.concat ["Raised bid to ", show coinCount, " coins"]
getTXDescription _ = "unknown msg"

addTXLogEntry :: String -> Msg -> IO TXLogEntry
addTXLogEntry entryUsername msg = do 
  entryTimestamp <- getCurrentTime
  uuid <- nextRandom
  let entryTXID = show uuid
  return TXLogEntry {..}
  where entryDescription = getTXDescription msg
