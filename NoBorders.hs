module XMonadContrib.NoBorders ( noBorders, withBorder ) where

-- Make a given layout display without borders.  This is useful for
-- full-screen or tabbed layouts, where you don't really want to waste a
-- couple of pixels of real estate just to inform yourself that the visible
-- window has focus.

-- Usage:

-- import XMonadContrib.NoBorders

-- layouts = [ noBorders full, tall, ... ]

import Control.Monad.State ( gets )
import Graphics.X11.Xlib

import XMonad
import Operations ( UnDoLayout(UnDoLayout) )
import qualified StackSet as W
import {-# SOURCE #-} Config (borderWidth)

noBorders :: Layout -> Layout
noBorders = withBorder 0

withBorder :: Dimension -> Layout -> Layout
withBorder bd l = l { doLayout = \r x -> setborders bd >> doLayout l r x
                    , modifyLayout = ml }
    where ml m | Just UnDoLayout == fromMessage m
                   = do setborders borderWidth
                        fmap (withBorder bd) `fmap` (modifyLayout l) m
               | otherwise = fmap (withBorder bd) `fmap` (modifyLayout l) m

setborders :: Dimension -> X ()
setborders bw = withDisplay $ \d ->
                do ws <- gets (W.integrate' . W.stack . W.workspace . W.current . windowset)
                   mapM_ (\w -> io $ setWindowBorderWidth d w bw) ws
