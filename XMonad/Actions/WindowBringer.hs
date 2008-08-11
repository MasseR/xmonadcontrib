-----------------------------------------------------------------------------
-- |
-- Module      :  XMonad.Actions.WindowBringer
-- Copyright   :  Devin Mullins <me@twifkak.com>
-- License     :  BSD-style (see LICENSE)
--
-- Maintainer  :  Devin Mullins <me@twifkak.com>
-- Stability   :  unstable
-- Portability :  unportable
--
-- dmenu operations to bring windows to you, and bring you to windows.
-- That is to say, it pops up a dmenu with window names, in case you forgot
-- where you left your XChat.
--
-----------------------------------------------------------------------------

module XMonad.Actions.WindowBringer (
                                    -- * Usage
                                    -- $usage
                                    gotoMenu, bringMenu, windowMap,
                                    bringWindow
                                   ) where

import Data.Char (toLower)
import qualified Data.Map as M

import qualified XMonad.StackSet as W
import XMonad
import qualified XMonad as X
import XMonad.Util.Dmenu (dmenuMap)
import XMonad.Util.NamedWindows (getName)

-- $usage
--
-- Import the module into your @~\/.xmonad\/xmonad.hs@:
--
-- > import XMonad.Actions.WindowBringer
--
-- and define appropriate key bindings:
--
-- > , ((modMask x .|. shiftMask, xK_g     ), gotoMenu)
-- > , ((modMask x .|. shiftMask, xK_b     ), bringMenu)
--
-- For detailed instructions on editing your key bindings, see
-- "XMonad.Doc.Extending#Editing_key_bindings".


-- | Pops open a dmenu with window titles. Choose one, and you will be
--   taken to the corresponding workspace.
gotoMenu :: X ()
gotoMenu = actionMenu W.focusWindow

-- | Pops open a dmenu with window titles. Choose one, and it will be
--   dragged, kicking and screaming, into your current workspace.
bringMenu :: X ()
bringMenu = actionMenu bringWindow

-- | Brings the specified window into the current workspace.
bringWindow :: Window -> X.WindowSet -> X.WindowSet
bringWindow w ws = W.shiftWin (W.tag . W.workspace . W.current $ ws) w ws

-- | Calls dmenuMap to grab the appropriate Window, and hands it off to action
--   if found.
actionMenu :: (Window -> X.WindowSet -> X.WindowSet) -> X()
actionMenu action = windowMap >>= dmenuMap >>= flip X.whenJust (windows . action)

-- | A map from window names to Windows.
windowMap :: X (M.Map String Window)
windowMap = do
  ws <- gets X.windowset
  M.fromList `fmap` concat `fmap` mapM keyValuePairs (W.workspaces ws)
 where keyValuePairs ws = mapM (keyValuePair ws) $ W.integrate' (W.stack ws)
       keyValuePair ws w = flip (,) w `fmap` decorateName ws w

-- | Returns the window name as will be listed in dmenu.
--   Lowercased, for your convenience (since dmenu is case-sensitive).
--   Tagged with the workspace ID, to guarantee uniqueness, and to let the user
--   know where he's going.
decorateName :: X.WindowSpace -> Window -> X String
decorateName ws w = do
  name <- fmap (map toLower . show) $ getName w
  return $ name ++ " [" ++ W.tag ws ++ "]"
