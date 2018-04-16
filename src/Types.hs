{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}

--{-# LANGUAGE DuplicateRecordFields #-}
module Types where

import Data.Aeson.Types
import Data.IntMap.Lazy (IntMap)
import qualified Data.IntMap.Lazy as IntMap
import Data.Text (Text)
import GHC.Generics
import qualified Network.WebSockets as WS

type AuctionId = Int

--We represent a client by their username and a `WS.Connection`. We will see how we
--obtain this `WS.Connection` later on.
newtype Client =
  Client (Text, WS.Connection)

instance Show Client where
  show (Client (name, _)) = show name

data ServerState = ServerState
  { clients :: [Client]
  , auctions :: IntMap Auction
  } deriving (Show)

data Auction = Auction
  { auctionId :: AuctionId
  , createdBy :: String
  , initialValue :: Double
  , maxNumBids :: Int
  , auctionStartTimestamp :: String
  } deriving (Show, Generic, FromJSON, ToJSON)

data Bid = Bid
  { bidAuctionId :: AuctionId
  , bidValue :: String
  , bidder :: String
  , bidTimestamp :: String
  } deriving (Show, Generic, FromJSON, ToJSON)

-- Actions for synchronising client-server state
data AuctionAction
  = CreateAuctionAction Auction
  | BidAuctionAction Bid
  deriving (Show, Generic, FromJSON, ToJSON)

instance Eq Client where
  (Client (x, _)) == (Client (y, _)) = x == y

instance ToJSON Client where
  toJSON (Client (name, _)) = toJSON $ show (name, name)
