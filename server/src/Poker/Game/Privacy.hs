{-
  Functions for excluding sensitive game data from game state.
-}
{-# LANGUAGE RecordWildCards #-}

module Poker.Game.Privacy where

import Data.Text (Text)

import Data.Functor
import Data.List
import Data.Maybe
import Data.Monoid

import Debug.Trace

import Control.Lens

import Poker.Game.Game (isEveryoneAllIn)
import Poker.Game.Utils
import Poker.Types

-- For players that are sat in game
excludeOtherPlayerCards :: PlayerName -> Game -> Game
excludeOtherPlayerCards playerName = excludePrivateCards $ Just playerName

-- For spectators who aren't in game
excludeAllPlayerCards :: Game -> Game
excludeAllPlayerCards = excludePrivateCards Nothing

-- Exclude player cards and Deck so spectators can't see private cards.
--
-- Takes an optional playerName. If no playerName is given then all private
-- cards are excluded. However if playerName is given then their cards
-- will not be excluded.
--
-- So if a game update is going to be sent to a user then we pass in his playerName
-- so that information that is private to him is not excluded from the 
-- Game state (his pocket cards)
--
-- If everyone in the game is AllIn then their pocket cards should all be visible.
--
---- We show all active players cards in the case of every active player being all in
-- or during the final showdown stage of the game
--
-- If they are
-- then all the pocket cards held by players whose _playerState 
-- is set to In (active and) are public and therefore not removed.
excludePrivateCards :: Maybe PlayerName -> Game -> Game
excludePrivateCards maybePlayerName game =
  game & (players %~ (<$>) pocketCardsPrivacyModifier) . (deck .~ Deck [])
  where
    everyoneAllIn = isEveryoneAllIn game
    multiplayerShowdown =
      _street game == Showdown && isMultiPlayerShowdown (_winners game)
    showAllActivesCards = everyoneAllIn || multiplayerShowdown
    pocketCardsPrivacyModifier =
      maybe
        (updatePocketCardsForSpectator showAllActivesCards)
        (updatePocketCardsForPlayer showAllActivesCards)
        maybePlayerName

updatePocketCardsForSpectator :: Bool -> (Player -> Player)
updatePocketCardsForSpectator showAllActivesCards
  | showAllActivesCards =
    (\player@Player {..} ->
       if _playerState == In
         then player
         else Player {_pockets = PocketCards [], ..})
  | otherwise = (\Player {..} -> Player {_pockets = PocketCards [], ..})

updatePocketCardsForPlayer :: Bool -> PlayerName -> (Player -> Player)
updatePocketCardsForPlayer showAllActivesCards playerName
  | showAllActivesCards =
    (\player@Player {..} ->
       if _playerState == In
         then player
         else if _playerName == playerName
                then player
                else Player {_pockets = PocketCards [], ..})
  | otherwise =
    (\player@Player {..} ->
       if _playerName == playerName
         then player
         else Player {_pockets = PocketCards [], ..})
